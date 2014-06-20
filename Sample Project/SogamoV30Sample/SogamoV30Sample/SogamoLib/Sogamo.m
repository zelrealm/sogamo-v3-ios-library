#if ! __has_feature(objc_arc)
#error This file must be compiled with ARC. Either turn on ARC for the project or use -fobjc-arc flag on this file.
#endif

#include <arpa/inet.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <sys/socket.h>
#include <sys/sysctl.h>

#import <CommonCrypto/CommonDigest.h>
#import <CoreTelephony/CTCarrier.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <UIKit/UIDevice.h>

#import "Sogamo.h"
#import "NSData+MPBase64.h"

#define VERSION @"2.3.6"

#ifdef Sogamo_LOG
#define SogamoLog(...) NSLog(__VA_ARGS__)
#else
#define SogamoLog(...)
#endif

#ifdef Sogamo_DEBUG
#define SogamoDebug(...) NSLog(__VA_ARGS__)
#else
#define SogamoDebug(...)
#endif

@interface Sogamo () {
    NSUInteger _flushInterval;
}

// re-declare internally as readwrite
@property (atomic, strong) SogamoPeople *people;
@property (atomic, copy) NSString *distinctId;

@property (nonatomic, copy) NSString *apiToken;
@property (atomic, strong) NSDictionary *superProperties;
@property (atomic, strong) NSDictionary *automaticProperties;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) NSMutableArray *eventsQueue;
@property (nonatomic, strong) NSMutableArray *peopleQueue;
@property (nonatomic, assign) UIBackgroundTaskIdentifier taskId;
@property (nonatomic, strong) dispatch_queue_t serialQueue;
@property (nonatomic, assign) SCNetworkReachabilityRef reachability;
@property (nonatomic, strong) CTTelephonyNetworkInfo *telephonyInfo;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;

@property (nonatomic, strong) NSArray *surveys;
@property (nonatomic, strong) NSMutableSet *shownSurveyCollections;

@property (nonatomic, strong) NSArray *notifications;
@property (nonatomic, strong) NSMutableSet *shownNotifications;

@end

@interface SogamoPeople ()

@property (nonatomic, weak) Sogamo *Sogamo;
@property (nonatomic, strong) NSMutableArray *unidentifiedQueue;
@property (nonatomic, copy) NSString *distinctId;
@property (nonatomic, strong) NSDictionary *automaticPeopleProperties;

- (id)initWithSogamo:(Sogamo *)Sogamo;

@end

static NSString *MPURLEncode(NSString *s)
{
    return (NSString *)CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, (CFStringRef)s, NULL, CFSTR("!*'();:@&=+$,/?%#[]"), kCFStringEncodingUTF8));
}

@implementation Sogamo

static void SogamoReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void *info)
{
    if (info != NULL && [(__bridge NSObject*)info isKindOfClass:[Sogamo class]]) {
        @autoreleasepool {
            Sogamo *s = (__bridge Sogamo *)info;
            [s reachabilityChanged:flags];
        }
    } else {
        NSLog(@"Sogamo reachability callback received unexpected info object");
    }
}

static Sogamo *sharedInstance = nil;

+ (Sogamo *)sharedInstanceWithToken:(NSString *)apiToken
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[super alloc] initWithToken:apiToken andFlushInterval:60];
    });
    return sharedInstance;
}

+ (Sogamo *)sharedInstance
{
    if (sharedInstance == nil) {
        NSLog(@"%@ warning sharedInstance called before sharedInstanceWithToken:", self);
    }
    return sharedInstance;
}

- (instancetype)initWithToken:(NSString *)apiToken andFlushInterval:(NSUInteger)flushInterval
{
    if (apiToken == nil) {
        apiToken = @"";
    }
    if ([apiToken length] == 0) {
        NSLog(@"%@ warning empty api token", self);
    }
    if (self = [self init]) {
        self.people = [[SogamoPeople alloc] initWithSogamo:self];
        self.apiToken = apiToken;
        _flushInterval = flushInterval;
        self.flushOnBackground = YES;
        self.showNetworkActivityIndicator = YES;
        self.serverURL = @"http://sogamo-data-collector-chadin.herokuapp.com";

        self.showNotificationOnActive = YES;
        self.checkForNotificationsOnActive = YES;

        self.distinctId = [self defaultDistinctId];
        self.superProperties = [NSMutableDictionary dictionary];
        self.automaticProperties = [self collectAutomaticProperties];
        self.eventsQueue = [NSMutableArray array];
        self.peopleQueue = [NSMutableArray array];
        self.taskId = UIBackgroundTaskInvalid;
        NSString *label = [NSString stringWithFormat:@"com.Sogamo.%@.%p", apiToken, self];
        self.serialQueue = dispatch_queue_create([label UTF8String], DISPATCH_QUEUE_SERIAL);
        self.dateFormatter = [[NSDateFormatter alloc] init];
        [_dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"];
        [_dateFormatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];

        self.showSurveyOnActive = YES;
        self.checkForSurveysOnActive = YES;
        self.surveys = nil;
        self.shownSurveyCollections = [NSMutableSet set];
        self.shownNotifications = [NSMutableSet set];
        self.notifications = nil;

        // wifi reachability
        BOOL reachabilityOk = NO;
        if ((_reachability = SCNetworkReachabilityCreateWithName(NULL, "sogamo-data-collector-chadin.herokuapp.com")) != NULL) {
            SCNetworkReachabilityContext context = {0, (__bridge void*)self, NULL, NULL, NULL};
            if (SCNetworkReachabilitySetCallback(_reachability, SogamoReachabilityCallback, &context)) {
                if (SCNetworkReachabilitySetDispatchQueue(_reachability, self.serialQueue)) {
                    reachabilityOk = YES;
                    SogamoDebug(@"%@ successfully set up reachability callback", self);
                } else {
                    // cleanup callback if setting dispatch queue failed
                    SCNetworkReachabilitySetCallback(_reachability, NULL, NULL);
                }
            }
        }
        if (!reachabilityOk) {
            NSLog(@"%@ failed to set up reachability callback: %s", self, SCErrorString(SCError()));
        }

        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];

        // cellular info
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 70000
        if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_6_1) {
            [self setCurrentRadio];
            [notificationCenter addObserver:self
                                   selector:@selector(setCurrentRadio)
                                       name:CTRadioAccessTechnologyDidChangeNotification
                                     object:nil];
        }
#endif

        [notificationCenter addObserver:self
                               selector:@selector(applicationWillTerminate:)
                                   name:UIApplicationWillTerminateNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(applicationWillResignActive:)
                                   name:UIApplicationWillResignActiveNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(applicationDidBecomeActive:)
                                   name:UIApplicationDidBecomeActiveNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(applicationDidEnterBackground:)
                                   name:UIApplicationDidEnterBackgroundNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(applicationWillEnterForeground:)
                                   name:UIApplicationWillEnterForegroundNotification
                                 object:nil];
        [self unarchive];
    }

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (_reachability != NULL) {
        if (!SCNetworkReachabilitySetCallback(_reachability, NULL, NULL)) {
            NSLog(@"%@ error unsetting reachability callback", self);
        }
        if (!SCNetworkReachabilitySetDispatchQueue(_reachability, NULL)) {
            NSLog(@"%@ error unsetting reachability dispatch queue", self);
        }
        CFRelease(_reachability);
        _reachability = NULL;
        SogamoDebug(@"realeased reachability");
    }
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<Sogamo: %p %@>", self, self.apiToken];
}

- (NSString *)deviceModel
{
    size_t size;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    char answer[size];
    sysctlbyname("hw.machine", answer, &size, NULL, 0);
    NSString *results = @(answer);
    return results;
}

- (NSString *)IFA
{
    NSString *ifa = nil;
#ifndef Sogamo_NO_IFA
    Class ASIdentifierManagerClass = NSClassFromString(@"ASIdentifierManager");
    if (ASIdentifierManagerClass) {
        SEL sharedManagerSelector = NSSelectorFromString(@"sharedManager");
        id sharedManager = ((id (*)(id, SEL))[ASIdentifierManagerClass methodForSelector:sharedManagerSelector])(ASIdentifierManagerClass, sharedManagerSelector);
        SEL advertisingIdentifierSelector = NSSelectorFromString(@"advertisingIdentifier");
        NSUUID *uuid = ((NSUUID* (*)(id, SEL))[sharedManager methodForSelector:advertisingIdentifierSelector])(sharedManager, advertisingIdentifierSelector);
        ifa = [uuid UUIDString];
    }
#endif
    return ifa;
}

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 70000
- (void)setCurrentRadio
{
    dispatch_async(self.serialQueue, ^(){
        NSMutableDictionary *properties = [self.automaticProperties mutableCopy];
        //properties[@"$radio"] = [self currentRadio];
        self.automaticProperties = [properties copy];
    });
}

- (NSString *)currentRadio
{
    NSString *radio = _telephonyInfo.currentRadioAccessTechnology;
    if (!radio) {
        radio = @"None";
    } else if ([radio hasPrefix:@"CTRadioAccessTechnology"]) {
        radio = [radio substringFromIndex:23];
    }
    return radio;
}
#endif

- (NSDictionary *)collectAutomaticProperties
{
    NSMutableDictionary *p = [NSMutableDictionary dictionary];
    UIDevice *device = [UIDevice currentDevice];
    NSString *deviceModel = [self deviceModel];
    CGSize size = [UIScreen mainScreen].bounds.size;
    CTTelephonyNetworkInfo *networkInfo = [[CTTelephonyNetworkInfo alloc] init];
    CTCarrier *carrier = [networkInfo subscriberCellularProvider];

    //[p setValue:@"iphone" forKey:@"mp_lib"];
    //[p setValue:VERSION forKey:@"$lib_version"];
    //[p setValue:[[NSBundle mainBundle] infoDictionary][@"CFBundleVersion"] forKey:@"$app_version"];
    //[p setValue:[[NSBundle mainBundle] infoDictionary][@"CFBundleShortVersionString"] forKey:@"$app_release"];
    //[p setValue:@"Apple" forKey:@"$manufacturer"];
    //[p setValue:[device systemName] forKey:@"$os"];
    //[p setValue:[device systemVersion] forKey:@"$os_version"];
    //[p setValue:deviceModel forKey:@"$model"];
    //[p setValue:deviceModel forKey:@"mp_device_model"]; // legacy
    //[p setValue:@((NSInteger)size.height) forKey:@"$screen_height"];
    //[p setValue:@((NSInteger)size.width) forKey:@"$screen_width"];
    //[p setValue:[self IFA] forKey:@"$ios_ifa"];
    //[p setValue:carrier.carrierName forKey:@"$carrier"];

    return [p copy];
}

+ (BOOL)inBackground
{
    return [UIApplication sharedApplication].applicationState == UIApplicationStateBackground;
}

#pragma mark - Encoding/decoding utilities

- (NSData *)JSONSerializeObject:(id)obj
{
    id coercedObj = [self JSONSerializableObjectForObject:obj];
    NSError *error = nil;
    NSData *data = nil;
    @try {
        data = [NSJSONSerialization dataWithJSONObject:coercedObj options:0 error:&error];
    }
    @catch (NSException *exception) {
        NSLog(@"%@ exception encoding api data: %@", self, exception);
    }
    if (error) {
        NSLog(@"%@ error encoding api data: %@", self, error);
    }
    return data;
}

- (id)JSONSerializableObjectForObject:(id)obj
{
    // valid json types
    if ([obj isKindOfClass:[NSString class]]/* ||
        [obj isKindOfClass:[NSNumber class]] ||
        [obj isKindOfClass:[NSNull class]]*/) {
        return obj;
    }
    // recurse on containers
    if ([obj isKindOfClass:[NSArray class]]) {
        NSMutableArray *a = [NSMutableArray array];
        for (id i in obj) {
            [a addObject:[self JSONSerializableObjectForObject:i]];
        }
        return [NSArray arrayWithArray:a];
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        for (id key in obj) {
            NSString *stringKey;
            if (![key isKindOfClass:[NSString class]]) {
                stringKey = [key description];
                NSLog(@"%@ warning: property keys should be strings. got: %@. coercing to: %@", self, [key class], stringKey);
            } else {
                stringKey = [NSString stringWithString:key];
            }
            if([stringKey isEqualToString:@"timestamp"]) {
                id v = obj[key];
                d[stringKey] = v;
            } else {
                id v = [self JSONSerializableObjectForObject:obj[key]];
                d[stringKey] = v;
            }
        }
        return [NSDictionary dictionaryWithDictionary:d];
    }
    // some common cases
    if ([obj isKindOfClass:[NSDate class]]) {
        return [self.dateFormatter stringFromDate:obj];
    } else if ([obj isKindOfClass:[NSURL class]]) {
        return [obj absoluteString];
    }
    // default to sending the object's description
    NSString *s = [obj description];
    NSLog(@"%@ warning: property values should be valid json types. got: %@. coercing to: %@", self, [obj class], s);
    return s;
}

- (NSString *)encodeAPIData:(NSArray *)array
{
    NSString *b64String = @"";
    NSString *newStr = @"";
    NSDictionary *first = [array objectAtIndex:0];
    NSData *data = [self JSONSerializeObject:first];
    if (data) {
        b64String = [data mp_base64EncodedString];
        b64String = (id)CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,
                                                                (CFStringRef)b64String,
                                                                NULL,
                                                                CFSTR("!*'();:@&=+$,/?%#[]"),
                                                                kCFStringEncodingUTF8));
        newStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        
        //NSError *error = nil;
        //NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\"[^\"]*\"[ \t\n]*:[ \t\n]*[^\"]*[ \t\n]*[,}]" options:NSRegularExpressionCaseInsensitive error:&error];
        //NSString *modifiedString = [regex stringByReplacingMatchesInString:newStr options:0 range:NSMakeRange(0, [newStr length]) withTemplate:@"\"player_id\":\"1\""];
        newStr = (id)CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,
                                                                                  (CFStringRef)newStr,
                                                                                  NULL,
                                                                                  CFSTR("!*'();:@&=+$,/?%#[]"),
                                                                                  kCFStringEncodingUTF8));
    }
    return newStr;
}

#pragma mark - Tracking

+ (void)assertPropertyTypes:(NSDictionary *)properties
{
    for (id __unused k in properties) {
        NSAssert([k isKindOfClass: [NSString class]], @"%@ property keys must be NSString. got: %@ %@", self, [k class], k);
        // would be convenient to do: id v = [properties objectForKey:k]; but
        // when the NSAssert's are stripped out in release, it becomes an
        // unused variable error. also, note that @YES and @NO pass as
        // instances of NSNumber class.
        NSAssert([properties[k] isKindOfClass:[NSString class]] ||
                 [properties[k] isKindOfClass:[NSNumber class]] ||
                 [properties[k] isKindOfClass:[NSNull class]] ||
                 [properties[k] isKindOfClass:[NSArray class]] ||
                 [properties[k] isKindOfClass:[NSDictionary class]] ||
                 [properties[k] isKindOfClass:[NSDate class]] ||
                 [properties[k] isKindOfClass:[NSURL class]],
                 @"%@ property values must be NSString, NSNumber, NSNull, NSArray, NSDictionary, NSDate or NSURL. got: %@ %@", self, [properties[k] class], properties[k]);
    }
}

- (NSString *)defaultDistinctId
{
    NSString *distinctId = [self IFA];

    if (!distinctId && NSClassFromString(@"UIDevice")) {
        distinctId = [[UIDevice currentDevice].identifierForVendor UUIDString];
    }
    if (!distinctId) {
        NSLog(@"%@ error getting device identifier: falling back to uuid", self);
        distinctId = [[NSUUID UUID] UUIDString];
    }
    if (!distinctId) {
        NSLog(@"%@ error getting uuid: no default distinct id could be generated", self);
    }
    return distinctId;
}


- (void)identify:(NSString *)distinctId
{
    if (distinctId == nil || distinctId.length == 0) {
        NSLog(@"%@ error blank distinct id: %@", self, distinctId);
        return;
    }
    dispatch_async(self.serialQueue, ^{
        self.distinctId = distinctId;
        self.people.distinctId = distinctId;
        if ([self.people.unidentifiedQueue count] > 0) {
            for (NSMutableDictionary *r in self.people.unidentifiedQueue) {
                r[@"player_id"] = distinctId;
                [self.peopleQueue addObject:r];
            }
            [self.people.unidentifiedQueue removeAllObjects];
            [self archivePeople];
        }
        if ([Sogamo inBackground]) {
            [self archiveProperties];
        }
    });
}

- (void)createAlias:(NSString *)alias forDistinctID:(NSString *)distinctID
{
    if (!alias || [alias length] == 0) {
        NSLog(@"%@ create alias called with empty alias: %@", self, alias);
        return;
    }
    if (!distinctID || [distinctID length] == 0) {
        NSLog(@"%@ create alias called with empty distinct id: %@", self, distinctID);
        return;
    }
    [self track:@"$create_alias" properties:@{@"distinct_id": distinctID, @"alias": alias}];
}

- (void)track:(NSString *)event
{
    [self track:event properties:nil];
}

- (void)track:(NSString *)event properties:(NSDictionary *)properties
{
    if (event == nil || [event length] == 0) {
        NSLog(@"%@ Sogamo track called with empty event parameter. using 'sgm_action'", self);
        event = @"sgm_action";
    }
    //NSLog(@"Track called, event: %@", event);
    properties = [properties copy];
    [Sogamo assertPropertyTypes:properties];
    //NSNumber *epochSeconds = @(round([[NSDate date] timeIntervalSince1970]));
    NSNumber *epochMilliseconds = @(round([[NSDate date] timeIntervalSince1970] * 1000));
    dispatch_async(self.serialQueue, ^{
        NSMutableDictionary *p = [NSMutableDictionary dictionary];
        [p addEntriesFromDictionary:self.automaticProperties];
        
        p[@"sgm_action"] = event;
        p[@"api_key"] = self.apiToken;
        p[@"timestamp"] = epochMilliseconds;
        if (self.distinctId) {
            p[@"player_id"] = self.distinctId;
        }
        [p addEntriesFromDictionary:self.superProperties];
        if (properties) {
            [p addEntriesFromDictionary:properties];
        }
        
        //NSLog(@"B, event: %@", event);
        for(id key in p) {
            //Check if the value is an integer, and if so, convert to string
            if([p[key] intValue] != 0) {
                int pi = [p[key] intValue];
                //NSLog(@"[%@] %d", key, pi);
            }
        }
        
        SogamoLog(@"%@ queueing event: %@", self, p);
        [self.eventsQueue addObject:p];
        if ([self.eventsQueue count] > 500) {
            [self.eventsQueue removeObjectAtIndex:0];
        }
        if ([Sogamo inBackground]) {
            [self archiveEvents];
        }
    });
}

- (void)registerSuperProperties:(NSDictionary *)properties
{
    properties = [properties copy];
    [Sogamo assertPropertyTypes:properties];
    dispatch_async(self.serialQueue, ^{
        NSMutableDictionary *tmp = [NSMutableDictionary dictionaryWithDictionary:self.superProperties];
        [tmp addEntriesFromDictionary:properties];
        self.superProperties = [NSDictionary dictionaryWithDictionary:tmp];
        if ([Sogamo inBackground]) {
            [self archiveProperties];
        }
    });
}

- (void)registerSuperPropertiesOnce:(NSDictionary *)properties
{
    properties = [properties copy];
    [Sogamo assertPropertyTypes:properties];
    dispatch_async(self.serialQueue, ^{
        NSMutableDictionary *tmp = [NSMutableDictionary dictionaryWithDictionary:self.superProperties];
        for (NSString *key in properties) {
            if (tmp[key] == nil) {
                tmp[key] = properties[key];
            }
        }
        self.superProperties = [NSDictionary dictionaryWithDictionary:tmp];
        if ([Sogamo inBackground]) {
            [self archiveProperties];
        }
    });
}

- (void)registerSuperPropertiesOnce:(NSDictionary *)properties defaultValue:(id)defaultValue
{
    properties = [properties copy];
    [Sogamo assertPropertyTypes:properties];
    dispatch_async(self.serialQueue, ^{
        NSMutableDictionary *tmp = [NSMutableDictionary dictionaryWithDictionary:self.superProperties];
        for (NSString *key in properties) {
            id value = tmp[key];
            if (value == nil || [value isEqual:defaultValue]) {
                tmp[key] = properties[key];
            }
        }
        self.superProperties = [NSDictionary dictionaryWithDictionary:tmp];
        if ([Sogamo inBackground]) {
            [self archiveProperties];
        }
    });
}

- (void)unregisterSuperProperty:(NSString *)propertyName
{
    dispatch_async(self.serialQueue, ^{
        NSMutableDictionary *tmp = [NSMutableDictionary dictionaryWithDictionary:self.superProperties];
        if (tmp[propertyName] != nil) {
            [tmp removeObjectForKey:propertyName];
        }
        self.superProperties = [NSDictionary dictionaryWithDictionary:tmp];
        if ([Sogamo inBackground]) {
            [self archiveProperties];
        }
    });
}

- (void)clearSuperProperties
{
    dispatch_async(self.serialQueue, ^{
        self.superProperties = @{};
        if ([Sogamo inBackground]) {
            [self archiveProperties];
        }
    });
}

- (NSDictionary *)currentSuperProperties
{
    return [self.superProperties copy];
}

- (void)reset
{
    dispatch_async(self.serialQueue, ^{
        self.distinctId = [self defaultDistinctId];
        self.nameTag = nil;
        self.superProperties = [NSMutableDictionary dictionary];
        self.people.distinctId = nil;
        self.people.unidentifiedQueue = [NSMutableArray array];
        self.eventsQueue = [NSMutableArray array];
        self.peopleQueue = [NSMutableArray array];
        [self archive];
    });
}

#pragma mark - Network control

- (NSUInteger)flushInterval
{
    @synchronized(self) {
        return _flushInterval;
    }
}

- (void)setFlushInterval:(NSUInteger)interval
{
    @synchronized(self) {
        _flushInterval = interval;
    }
    [self startFlushTimer];
}

- (void)startFlushTimer
{
    [self stopFlushTimer];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.flushInterval > 0) {
            self.timer = [NSTimer scheduledTimerWithTimeInterval:self.flushInterval
                                                          target:self
                                                        selector:@selector(flush)
                                                        userInfo:nil
                                                         repeats:YES];
            SogamoDebug(@"%@ started flush timer: %@", self, self.timer);
        }
    });
}

- (void)stopFlushTimer
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.timer) {
            [self.timer invalidate];
            SogamoDebug(@"%@ stopped flush timer: %@", self, self.timer);
        }
        self.timer = nil;
    });
}

- (void)flush
{
    dispatch_async(self.serialQueue, ^{
        SogamoDebug(@"%@ flush starting", self);

        __strong id<SogamoDelegate> strongDelegate = _delegate;
        if (strongDelegate != nil && [strongDelegate respondsToSelector:@selector(SogamoWillFlush:)] && ![strongDelegate SogamoWillFlush:self]) {
            SogamoDebug(@"%@ flush deferred by delegate", self);
            return;
        }

        [self flushEvents];
        [self flushPeople];

        SogamoDebug(@"%@ flush complete", self);
    });
}

- (void)flushEvents
{
    [self flushQueue:_eventsQueue
            endpoint:@"/track/"];
}

- (void)flushPeople
{
    [self flushQueue:_peopleQueue
            endpoint:@"/set/"];
}

- (void)flushQueue:(NSMutableArray *)queue endpoint:(NSString *)endpoint
{
    while ([queue count] > 0) {
        NSUInteger batchSize = ([queue count] > /*50*/1) ? /*50*/1 : [queue count];
        NSArray *batch = [queue subarrayWithRange:NSMakeRange(0, batchSize)];

        NSString *requestData = [self encodeAPIData:batch];
        //NSLog(@"%@", requestData);
        NSString *postBody = [NSString stringWithFormat:@"json=%@", requestData];
        SogamoDebug(@"%@ flushing %lu of %lu to %@: %@", self, (unsigned long)[batch count], (unsigned long)[queue count], endpoint, queue);
        NSURLRequest *request = [self apiRequestWithEndpoint:endpoint andBody:postBody];
        NSError *error = nil;

        [self updateNetworkActivityIndicator:YES];

        NSData *responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:nil error:&error];

        [self updateNetworkActivityIndicator:NO];

        if (error) {
            NSLog(@"%@ network failure: %@", self, error);
            break;
        }

        NSString *response = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
        //if ([response intValue] == 0) {
        //    NSLog(@"%@ %@ api rejected some items", self, endpoint);
        //};

        [queue removeObjectsInArray:batch];
    }
}

- (void)updateNetworkActivityIndicator:(BOOL)on
{
    if (_showNetworkActivityIndicator) {
        [UIApplication sharedApplication].networkActivityIndicatorVisible = on;
    }
}

- (void)reachabilityChanged:(SCNetworkReachabilityFlags)flags
{
    // this should be run in the serial queue. the reason we don't dispatch_async here
    // is because it's only ever called by the reachability callback, which is already
    // set to run on the serial queue. see SCNetworkReachabilitySetDispatchQueue in init
    BOOL wifi = (flags & kSCNetworkReachabilityFlagsReachable) && !(flags & kSCNetworkReachabilityFlagsIsWWAN);
    NSMutableDictionary *properties = [self.automaticProperties mutableCopy];
    //properties[@"$wifi"] = wifi ? @YES : @NO;
    self.automaticProperties = [properties copy];
    SogamoDebug(@"%@ reachability changed, wifi=%d", self, wifi);
}

- (NSURLRequest *)apiRequestWithEndpoint:(NSString *)endpoint andBody:(NSString *)body
{
    NSURL *URL = [NSURL URLWithString:[self.serverURL stringByAppendingString:endpoint]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:URL];
    [request setValue:@"gzip" forHTTPHeaderField:@"Accept-Encoding"];
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:[body dataUsingEncoding:NSUTF8StringEncoding]];
    SogamoDebug(@"%@ http request: %@?%@", self, URL, body);
    return request;
}

#pragma mark - Persistence

- (NSString *)filePathForData:(NSString *)data
{
    NSString *filename = [NSString stringWithFormat:@"Sogamo-%@-%@.plist", self.apiToken, data];
    return [[NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) lastObject]
            stringByAppendingPathComponent:filename];
}

- (NSString *)eventsFilePath
{
    return [self filePathForData:@"events"];
}

- (NSString *)peopleFilePath
{
    return [self filePathForData:@"people"];
}

- (NSString *)propertiesFilePath
{
    return [self filePathForData:@"properties"];
}

- (void)archive
{
    [self archiveEvents];
    [self archivePeople];
    [self archiveProperties];
}

- (void)archiveEvents
{
    NSString *filePath = [self eventsFilePath];
    NSMutableArray *eventsQueueCopy = [NSMutableArray arrayWithArray:[self.eventsQueue copy]];
    SogamoDebug(@"%@ archiving events data to %@: %@", self, filePath, eventsQueueCopy);
    if (![NSKeyedArchiver archiveRootObject:eventsQueueCopy toFile:filePath]) {
        NSLog(@"%@ unable to archive events data", self);
    }
}

- (void)archivePeople
{
    NSString *filePath = [self peopleFilePath];
    NSMutableArray *peopleQueueCopy = [NSMutableArray arrayWithArray:[self.peopleQueue copy]];
    SogamoDebug(@"%@ archiving people data to %@: %@", self, filePath, peopleQueueCopy);
    if (![NSKeyedArchiver archiveRootObject:peopleQueueCopy toFile:filePath]) {
        NSLog(@"%@ unable to archive people data", self);
    }
}

- (void)archiveProperties
{
    NSString *filePath = [self propertiesFilePath];
    NSMutableDictionary *p = [NSMutableDictionary dictionary];
    [p setValue:self.distinctId forKey:@"distinctId"];
    [p setValue:self.nameTag forKey:@"nameTag"];
    [p setValue:self.superProperties forKey:@"superProperties"];
    [p setValue:self.people.distinctId forKey:@"peopleDistinctId"];
    [p setValue:self.people.unidentifiedQueue forKey:@"peopleUnidentifiedQueue"];
    [p setValue:self.shownSurveyCollections forKey:@"shownSurveyCollections"];
    [p setValue:self.shownNotifications forKey:@"shownNotifications"];
    SogamoDebug(@"%@ archiving properties data to %@: %@", self, filePath, p);
    if (![NSKeyedArchiver archiveRootObject:p toFile:filePath]) {
        NSLog(@"%@ unable to archive properties data", self);
    }
}

- (void)unarchive
{
    [self unarchiveEvents];
    [self unarchivePeople];
    [self unarchiveProperties];
}

- (void)unarchiveEvents
{
    NSString *filePath = [self eventsFilePath];
    @try {
        self.eventsQueue = [NSKeyedUnarchiver unarchiveObjectWithFile:filePath];
        SogamoDebug(@"%@ unarchived events data: %@", self, self.eventsQueue);
    }
    @catch (NSException *exception) {
        NSLog(@"%@ unable to unarchive events data, starting fresh", self);
        self.eventsQueue = nil;
    }
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        NSError *error;
        BOOL removed = [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
        if (!removed) {
            NSLog(@"%@ unable to remove archived events file at %@ - %@", self, filePath, error);
        }
    }
    if (!self.eventsQueue) {
        self.eventsQueue = [NSMutableArray array];
    }
}

- (void)unarchivePeople
{
    NSString *filePath = [self peopleFilePath];
    @try {
        self.peopleQueue = [NSKeyedUnarchiver unarchiveObjectWithFile:filePath];
        SogamoDebug(@"%@ unarchived people data: %@", self, self.peopleQueue);
    }
    @catch (NSException *exception) {
        NSLog(@"%@ unable to unarchive people data, starting fresh", self);
        self.peopleQueue = nil;
    }
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        NSError *error;
        BOOL removed = [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
        if (!removed) {
            NSLog(@"%@ unable to remove archived people file at %@ - %@", self, filePath, error);
        }
    }
    if (!self.peopleQueue) {
        self.peopleQueue = [NSMutableArray array];
    }
}

- (void)unarchiveProperties
{
    NSString *filePath = [self propertiesFilePath];
    NSDictionary *properties = nil;
    @try {
        properties = [NSKeyedUnarchiver unarchiveObjectWithFile:filePath];
        SogamoDebug(@"%@ unarchived properties data: %@", self, properties);
    }
    @catch (NSException *exception) {
        NSLog(@"%@ unable to unarchive properties data, starting fresh", self);
    }
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        NSError *error;
        BOOL removed = [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
        if (!removed) {
            NSLog(@"%@ unable to remove archived properties file at %@ - %@", self, filePath, error);
        }
    }
    if (properties) {
        self.distinctId = properties[@"distinctId"] ? properties[@"distinctId"] : [self defaultDistinctId];
        self.nameTag = properties[@"nameTag"];
        self.superProperties = properties[@"superProperties"] ? properties[@"superProperties"] : [NSMutableDictionary dictionary];
        self.people.distinctId = properties[@"peopleDistinctId"];
        self.people.unidentifiedQueue = properties[@"peopleUnidentifiedQueue"] ? properties[@"peopleUnidentifiedQueue"] : [NSMutableArray array];
        self.shownSurveyCollections = properties[@"shownSurveyCollections"] ? properties[@"shownSurveyCollections"] : [NSMutableSet set];
        self.shownNotifications = properties[@"shownNotifications"] ? properties[@"shownNotifications"] : [NSMutableSet set];
    }
}

#pragma mark - UIApplication notifications

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    SogamoDebug(@"%@ application did become active", self);
    [self startFlushTimer];

    if (self.checkForSurveysOnActive || self.checkForNotificationsOnActive) {
        NSDate *start = [NSDate date];

        //[self checkForDecideResponseWithCompletion:^(NSArray *surveys, NSArray *notifications) {
        //    if (self.showNotificationOnActive && notifications && [notifications count] > 0) {
        //        [self showNotificationWithObject:notifications[0]];
        //    } else if (self.showSurveyOnActive && surveys && [surveys count] > 0) {
        //        [self showSurveyWithObject:surveys[0] withAlert:([start timeIntervalSinceNow] < -2.0)];
        //    }
        //}];
    }
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    SogamoDebug(@"%@ application will resign active", self);
    [self stopFlushTimer];
}

- (void)applicationDidEnterBackground:(NSNotificationCenter *)notification
{
    SogamoDebug(@"%@ did enter background", self);

    self.taskId = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        SogamoDebug(@"%@ flush %lu cut short", self, (unsigned long)self.taskId);
        [[UIApplication sharedApplication] endBackgroundTask:self.taskId];
        self.taskId = UIBackgroundTaskInvalid;
    }];
    SogamoDebug(@"%@ starting background cleanup task %lu", self, (unsigned long)self.taskId);
    
    if (self.flushOnBackground) {
        [self flush];
    }
    
    dispatch_async(_serialQueue, ^{
        [self archive];
        SogamoDebug(@"%@ ending background cleanup task %lu", self, (unsigned long)self.taskId);
        if (self.taskId != UIBackgroundTaskInvalid) {
            [[UIApplication sharedApplication] endBackgroundTask:self.taskId];
            self.taskId = UIBackgroundTaskInvalid;
        }
        self.surveys = nil;
    });
}

- (void)applicationWillEnterForeground:(NSNotificationCenter *)notification
{
    SogamoDebug(@"%@ will enter foreground", self);
    dispatch_async(self.serialQueue, ^{
        if (self.taskId != UIBackgroundTaskInvalid) {
            [[UIApplication sharedApplication] endBackgroundTask:self.taskId];
            self.taskId = UIBackgroundTaskInvalid;
            [self updateNetworkActivityIndicator:NO];
        }
    });
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    SogamoDebug(@"%@ application will terminate", self);
    dispatch_async(_serialQueue, ^{
       [self archive];
    });
}

#pragma mark - Decide

+ (UIViewController *)topPresentedViewController
{
    UIViewController *controller = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (controller.presentedViewController) {
        controller = controller.presentedViewController;
    }
    return controller;
}

- (void)checkForSurveysWithCompletion:(void (^)(NSArray *surveys))completion
{
    //[self checkForDecideResponseWithCompletion:^(NSArray *surveys, NSArray *notifications) {
    //    if (completion) {
    //        completion(surveys);
    //    }
    //}];
}

- (void)checkForNotificationsWithCompletion:(void (^)(NSArray *notifications))completion
{
    //[self checkForDecideResponseWithCompletion:^(NSArray *surveys, NSArray *notifications) {
    //    if (completion) {
    //        completion(notifications);
    //    }
    //}];
}

@end

@implementation SogamoPeople

- (id)initWithSogamo:(Sogamo *)Sogamo
{
    if (self = [self init]) {
        self.Sogamo = Sogamo;
        self.unidentifiedQueue = [NSMutableArray array];
        self.automaticPeopleProperties = [self collectAutomaticPeopleProperties];
    }
    return self;
}

- (NSString *)description
{
    __strong Sogamo *strongSogamo = _Sogamo;
    return [NSString stringWithFormat:@"<SogamoPeople: %p %@>", self, (strongSogamo ? strongSogamo.apiToken : @"")];
}

- (NSDictionary *)collectAutomaticPeopleProperties
{
    UIDevice *device = [UIDevice currentDevice];
    NSMutableDictionary *p = [NSMutableDictionary dictionary];
    __strong Sogamo *strongSogamo = _Sogamo;
    if (strongSogamo) {
        [p setValue:[strongSogamo deviceModel] forKey:@"$ios_device_model"];
        [p setValue:[strongSogamo IFA] forKey:@"$ios_ifa"];
    }
    [p setValue:[device systemVersion] forKey:@"$ios_version"];
    [p setValue:VERSION forKey:@"$ios_lib_version"];
    [p setValue:[[NSBundle mainBundle] infoDictionary][@"CFBundleVersion"] forKey:@"$ios_app_version"];
    [p setValue:[[NSBundle mainBundle] infoDictionary][@"CFBundleShortVersionString"] forKey:@"$ios_app_release"];
    return [NSDictionary dictionaryWithDictionary:p];
}

- (void)addPeopleRecordToQueueWithAction:(NSString *)action andProperties:(NSDictionary *)properties
{
    properties = [properties copy];
    NSNumber *epochMilliseconds = @(round([[NSDate date] timeIntervalSince1970] * 1000));
    __strong Sogamo *strongSogamo = _Sogamo;
    if (strongSogamo) {
        dispatch_async(strongSogamo.serialQueue, ^{
            NSMutableDictionary *r = [NSMutableDictionary dictionary];
            NSMutableDictionary *p = [NSMutableDictionary dictionary];
            r[@"api_key"] = strongSogamo.apiToken;
            if (!r[@"timestamp"]) {
                // milliseconds unix timestamp
                r[@"timestamp"] = epochMilliseconds;
            }
            //if ([action isEqualToString:@"$set"] || [action isEqualToString:@"$set_once"]) {
            //    [p addEntriesFromDictionary:self.automaticPeopleProperties];
            //}
            //[p addEntriesFromDictionary:properties];
            //r[action] = [NSDictionary dictionaryWithDictionary:p];
            [r addEntriesFromDictionary:properties];
            if (self.distinctId) {
                r[@"player_id"] = self.distinctId;
                //NSLog(@"%@", r);
                SogamoLog(@"%@ queueing people record: %@", self.Sogamo, r);
                [strongSogamo.peopleQueue addObject:r];
                if ([strongSogamo.peopleQueue count] > 500) {
                    [strongSogamo.peopleQueue removeObjectAtIndex:0];
                }
            } else {
                SogamoLog(@"%@ queueing unidentified people record: %@", self.Sogamo, r);
                [self.unidentifiedQueue addObject:r];
                if ([self.unidentifiedQueue count] > 500) {
                    [self.unidentifiedQueue removeObjectAtIndex:0];
                }
            }
            if ([Sogamo inBackground]) {
                [strongSogamo archivePeople];
            }
        });
    }
}

- (void)addPushDeviceToken:(NSData *)deviceToken
{
    const unsigned char *buffer = (const unsigned char *)[deviceToken bytes];
    if (!buffer) {
        return;
    }
    NSMutableString *hex = [NSMutableString stringWithCapacity:(deviceToken.length * 2)];
    for (NSUInteger i = 0; i < deviceToken.length; i++) {
        [hex appendString:[NSString stringWithFormat:@"%02lx", (unsigned long)buffer[i]]];
    }
    //NSLog(@"OK, hex = %@", hex);
    NSArray *tokens = @[[NSString stringWithString:hex]];
    NSDictionary *properties = @{@"reg_id": hex};
    [self addPeopleRecordToQueueWithAction:@"$set" andProperties:properties];
    
    NSString *post = [NSString stringWithFormat:@"&api_key=%@&player_id=%@&reg_id=%@",
                      self.Sogamo.apiToken,
                      self.distinctId,
                      hex];
    
    NSData *postData = [post dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
    
    NSString *postLength = [NSString stringWithFormat:@"%d",[postData length]];
    
    //NSMutableURLRequest *request = [[[NSMutableURLRequest alloc] init] autorelease];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
    
    [request setURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://sogamo-v30-suggestion.herokuapp.com/android/register"]]];
    
    [request setHTTPMethod:@"POST"];
    
    [request setValue:postLength forHTTPHeaderField:@"Content-Length"];
    
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    
    [request setHTTPBody:postData];
    
    NSURLConnection *conn = [[NSURLConnection alloc]initWithRequest:request delegate:self];
    
    if(conn) {
        //NSLog(@"Connection Successful");
    } else {
        //NSLog(@"Connection could not be made");
    }
}

- (void)set:(NSDictionary *)properties
{
    NSAssert(properties != nil, @"properties must not be nil");
    [Sogamo assertPropertyTypes:properties];
    [self addPeopleRecordToQueueWithAction:@"$set" andProperties:properties];
}

- (void)set:(NSString *)property to:(id)object
{
    NSAssert(property != nil, @"property must not be nil");
    NSAssert(object != nil, @"object must not be nil");
    if (property == nil || object == nil) {
        return;
    }
    [self set:@{property: object}];
}

- (void)setOnce:(NSDictionary *)properties
{
    NSAssert(properties != nil, @"properties must not be nil");
    [Sogamo assertPropertyTypes:properties];
    [self addPeopleRecordToQueueWithAction:@"$set_once" andProperties:properties];
}

- (void)increment:(NSDictionary *)properties
{
    NSAssert(properties != nil, @"properties must not be nil");
    for (id __unused v in [properties allValues]) {
        NSAssert([v isKindOfClass:[NSNumber class]],
                 @"%@ increment property values should be NSNumber. found: %@", self, v);
    }
    [self addPeopleRecordToQueueWithAction:@"$add" andProperties:properties];
}

- (void)increment:(NSString *)property by:(NSNumber *)amount
{
    NSAssert(property != nil, @"property must not be nil");
    NSAssert(amount != nil, @"amount must not be nil");
    if (property == nil || amount == nil) {
        return;
    }
    [self increment:@{property: amount}];
}

- (void)append:(NSDictionary *)properties
{
    NSAssert(properties != nil, @"properties must not be nil");
    [Sogamo assertPropertyTypes:properties];
    [self addPeopleRecordToQueueWithAction:@"$append" andProperties:properties];
}

- (void)union:(NSDictionary *)properties
{
    NSAssert(properties != nil, @"properties must not be nil");
    for (id __unused v in [properties allValues]) {
        NSAssert([v isKindOfClass:[NSArray class]],
                 @"%@ union property values should be NSArray. found: %@", self, v);
    }
    [self addPeopleRecordToQueueWithAction:@"$union" andProperties:properties];
}

- (void)trackCharge:(NSNumber *)amount
{
    [self trackCharge:amount withProperties:nil];
}

- (void)trackCharge:(NSNumber *)amount withProperties:(NSDictionary *)properties
{
    NSAssert(amount != nil, @"amount must not be nil");
    if (amount != nil) {
        NSMutableDictionary *txn = [NSMutableDictionary dictionaryWithObjectsAndKeys:amount, @"$amount", [NSDate date], @"$time", nil];
        if (properties) {
            [txn addEntriesFromDictionary:properties];
        }
        [self append:@{@"$transactions": txn}];
    }
}

- (void)clearCharges
{
    [self set:@{@"$transactions": @[]}];
}

- (void)deleteUser
{
    [self addPeopleRecordToQueueWithAction:@"$delete" andProperties:@{}];
}

@end
