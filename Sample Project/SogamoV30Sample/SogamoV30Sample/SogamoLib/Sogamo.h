#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class    SogamoPeople;
@protocol SogamoDelegate;

/*!
 @class
 Sogamo API.

 @abstract
 The primary interface for integrating Sogamo with your app.

 @discussion
 Use the Sogamo class to set up your project and track events in Sogamo
 Engagement. It now also includes a <code>people</code> property for accesseing
 the Sogamo People API.

 <pre>
 // Initialize the API
 Sogamo *Sogamo = [Sogamo sharedInstanceWithToken:@"YOUR API TOKEN"];

 // Track an event in Sogamo Engagement
 [Sogamo track:@"Button Clicked"];

 // Set properties on a user in Sogamo People
 [Sogamo.people identify:@"CURRENT USER DISTINCT ID"];
 [Sogamo.people set:@"Plan" to:@"Premium"];
 </pre>

 For more advanced usage, please see the <a
 href="https://Sogamo.com/docs/integration-libraries/iphone">Sogamo iPhone
 Library Guide</a>.
 */
@interface Sogamo : NSObject

/*!
 @property

 @abstract
 Accessor to the Sogamo People API object.

 @discussion
 See the documentation for SogamoDelegate below for more information.
 */
@property (atomic, readonly, strong) SogamoPeople *people;

/*!
 @property

 @abstract
 The distinct ID of the current user.

 @discussion
 A distinct ID is a string that uniquely identifies one of your users.
 Typically, this is the user ID from your database. By default, we'll use a
 hash of the MAC address of the device. To change the current distinct ID,
 use the <code>identify:</code> method.
 */
@property (atomic, readonly, copy) NSString *distinctId;

/*!
 @property

 @abstract
 Current user's name in Sogamo Streams.
 */
@property (atomic, copy) NSString *nameTag;

/*!
 @property

 @abstract
 The base URL used for Sogamo API requests.

 @discussion
 Useful if you need to proxy Sogamo requests. Defaults to
 https://api.Sogamo.com.
 */
@property (atomic, copy) NSString *serverURL;

/*!
 @property

 @abstract
 Flush timer's interval.

 @discussion
 Setting a flush interval of 0 will turn off the flush timer.
 */
@property (atomic) NSUInteger flushInterval;

/*!
 @property

 @abstract
 Control whether the library should flush data to Sogamo when the app
 enters the background.

 @discussion
 Defaults to YES. Only affects apps targeted at iOS 4.0, when background
 task support was introduced, and later.
 */
@property (atomic) BOOL flushOnBackground;

/*!
 @property

 @abstract
 Controls whether to show spinning network activity indicator when flushing
 data to the Sogamo servers.

 @discussion
 Defaults to YES.
 */
@property (atomic) BOOL showNetworkActivityIndicator;

/*!
 @property

 @abstract
 Controls whether to automatically check for surveys for the
 currently identified user when the application becomes active.

 @discussion
 Defaults to YES. Will fire a network request on
 <code>applicationDidBecomeActive</code> to retrieve a list of valid suerveys
 for the currently identified user.
 */
@property (atomic) BOOL checkForSurveysOnActive;

/*!
 @property

 @abstract
 Controls whether to automatically show a survey for the
 currently identified user when the application becomes active.

 @discussion
 Defaults to YES. This will only show a survey if
 <code>checkForSurveysOnActive</code> is also set to YES, and the
 survey check retrieves at least 1 valid survey for the currently
 identified user.
 */
@property (atomic) BOOL showSurveyOnActive;

/*!
 @property

 @abstract
 Controls whether to automatically check for notifications for the
 currently identified user when the application becomes active.

 @discussion
 Defaults to YES. Will fire a network request on
 <code>applicationDidBecomeActive</code> to retrieve a list of valid notifications
 for the currently identified user.
 */
@property (atomic) BOOL checkForNotificationsOnActive;

/*!
 @property

 @abstract
 Controls whether to automatically check for and show in-app notifications
 for the currently identified user when the application becomes active.

 @discussion
 Defaults to YES.
 */
@property (atomic) BOOL showNotificationOnActive;

/*!
 @property

 @abstract
 The a SogamoDelegate object that can be used to assert fine-grain control
 over Sogamo network activity.

 @discussion
 Using a delegate is optional. See the documentation for SogamoDelegate
 below for more information.
 */
@property (atomic, weak) id<SogamoDelegate> delegate; // allows fine grain control over uploading (optional)

/*!
 @method

 @abstract
 Initializes and returns a singleton instance of the API.

 @discussion
 If you are only going to send data to a single Sogamo project from your app,
 as is the common case, then this is the easiest way to use the API. This
 method will set up a singleton instance of the <code>Sogamo</code> class for
 you using the given project token. When you want to make calls to Sogamo
 elsewhere in your code, you can use <code>sharedInstance</code>.

 <pre>
 [Sogamo sharedInstance] track:@"Something Happened"]];
 </pre>

 If you are going to use this singleton approach,
 <code>sharedInstanceWithToken:</code> <b>must be the first call</b> to the
 <code>Sogamo</code> class, since it performs important initializations to
 the API.

 @param apiToken        your project token
 */
+ (Sogamo *)sharedInstanceWithToken:(NSString *)apiToken;

/*!
 @method

 @abstract
 Returns the previously instantiated singleton instance of the API.

 @discussion
 The API must be initialized with <code>sharedInstanceWithToken:</code> before
 calling this class method.
 */
+ (Sogamo *)sharedInstance;

/*!
 @method

 @abstract
 Initializes an instance of the API with the given project token.

 @discussion
 Returns the a new API object. This allows you to create more than one instance
 of the API object, which is convenient if you'd like to send data to more than
 one Sogamo project from a single app. If you only need to send data to one
 project, consider using <code>sharedInstanceWithToken:</code>.

 @param apiToken        your project token
 @param flushInterval   interval to run background flushing
 */
- (instancetype)initWithToken:(NSString *)apiToken andFlushInterval:(NSUInteger)flushInterval;

/*!
 @property

 @abstract
 Sets the distinct ID of the current user.

 @discussion
 As of version 2.3.1, Sogamo will choose a default distinct ID based on
 whether you are using the AdSupport.framework or not.

 If you are not using the AdSupport Framework (iAds), then we use the
 <code>[UIDevice currentDevice].identifierForVendor</code> (IFV) string as the
 default distinct ID.  This ID will identify a user across all apps by the same
 vendor, but cannot be used to link the same user across apps from different
 vendors.

 If you are showing iAds in your application, you are allowed use the iOS ID
 for Advertising (IFA) to identify users. If you have this framework in your
 app, Sogamo will use the IFA as the default distinct ID. If you have
 AdSupport installed but still don't want to use the IFA, you can define the
 <code>Sogamo_NO_IFA</code> preprocessor flag in your build settings, and
 Sogamo will use the IFV as the default distinct ID.

 If we are unable to get an IFA or IFV, we will fall back to generating a
 random persistent UUID.

 For tracking events, you do not need to call <code>identify:</code> if you
 want to use the default.  However, <b>Sogamo People always requires an
 explicit call to <code>identify:</code></b>. If calls are made to
 <code>set:</code>, <code>increment</code> or other <code>SogamoPeople</code>
 methods prior to calling <code>identify:</code>, then they are queued up and
 flushed once <code>identify:</code> is called.

 If you'd like to use the default distinct ID for Sogamo People as well
 (recommended), call <code>identify:</code> using the current distinct ID:
 <code>[Sogamo identify:Sogamo.distinctId]</code>.

 @param distinctId string that uniquely identifies the current user
 */
- (void)identify:(NSString *)distinctId;

/*!
 @method

 @abstract
 Tracks an event.

 @param event           event name
 */
- (void)track:(NSString *)event;

/*!
 @method

 @abstract
 Tracks an event with properties.

 @discussion
 Properties will allow you to segment your events in your Sogamo reports.
 Property keys must be <code>NSString</code> objects and values must be
 <code>NSString</code>, <code>NSNumber</code>, <code>NSNull</code>,
 <code>NSArray</code>, <code>NSDictionary</code>, <code>NSDate</code> or
 <code>NSURL</code> objects.

 @param event           event name
 @param properties      properties dictionary
 */
- (void)track:(NSString *)event properties:(NSDictionary *)properties;

/*!
 @method

 @abstract
 Registers super properties, overwriting ones that have already been set.

 @discussion
 Super properties, once registered, are automatically sent as properties for
 all event tracking calls. They save you having to maintain and add a common
 set of properties to your events. Property keys must be <code>NSString</code>
 objects and values must be <code>NSString</code>, <code>NSNumber</code>,
 <code>NSNull</code>, <code>NSArray</code>, <code>NSDictionary</code>,
 <code>NSDate</code> or <code>NSURL</code> objects.

 @param properties      properties dictionary
 */
- (void)registerSuperProperties:(NSDictionary *)properties;

/*!
 @method

 @abstract
 Registers super properties without overwriting ones that have already been
 set.

 @discussion
 Property keys must be <code>NSString</code> objects and values must be
 <code>NSString</code>, <code>NSNumber</code>, <code>NSNull</code>,
 <code>NSArray</code>, <code>NSDictionary</code>, <code>NSDate</code> or
 <code>NSURL</code> objects.

 @param properties      properties dictionary
 */
- (void)registerSuperPropertiesOnce:(NSDictionary *)properties;

/*!
 @method

 @abstract
 Registers super properties without overwriting ones that have already been set
 unless the existing value is equal to defaultValue.

 @discussion
 Property keys must be <code>NSString</code> objects and values must be
 <code>NSString</code>, <code>NSNumber</code>, <code>NSNull</code>,
 <code>NSArray</code>, <code>NSDictionary</code>, <code>NSDate</code> or
 <code>NSURL</code> objects.

 @param properties      properties dictionary
 @param defaultValue    overwrite existing properties that have this value
 */
- (void)registerSuperPropertiesOnce:(NSDictionary *)properties defaultValue:(id)defaultValue;

/*!
 @method

 @abstract
 Removes a previously registered super property.

 @discussion
 As an alternative to clearing all properties, unregistering specific super
 properties prevents them from being recorded on future events. This operation
 does not affect the value of other super properties. Any property name that is
 not registered is ignored.

 Note that after removing a super property, events will show the attribute as
 having the value <code>undefined</code> in Sogamo until a new value is
 registered.

 @param propertyName   array of property name strings to remove
 */
- (void)unregisterSuperProperty:(NSString *)propertyName;

/*!
 @method

 @abstract
 Clears all currently set super properties.
 */
- (void)clearSuperProperties;

/*!
 @method

 @abstract
 Returns the currently set super properties.
 */
- (NSDictionary *)currentSuperProperties;

/*!
 @method

 @abstract
 Clears all stored properties and distinct IDs. Useful if your app's user logs out.
 */
- (void)reset;

/*!
 @method

 @abstract
 Uploads queued data to the Sogamo server.

 @discussion
 By default, queued data is flushed to the Sogamo servers every minute (the
 default for <code>flushInvterval</code>), and on background (since
 <code>flushOnBackground</code> is on by default). You only need to call this
 method manually if you want to force a flush at a particular moment.
 */
- (void)flush;

/*!
 @method

 @abstract
 Writes current project info, including distinct ID, super properties and pending event
 and People record queues to disk.

 @discussion
 This state will be recovered when the app is launched again if the Sogamo
 library is initialized with the same project token. <b>You do not need to call
 this method</b>. The library listens for app state changes and handles
 persisting data as needed. It can be useful in some special circumstances,
 though, for example, if you'd like to track app crashes from main.m.
 */
- (void)archive;

/*!
 @method

 @abstract
 Shows the survey with the given name.

 @discussion
 This method allows you to explicitly show a named survey at the time of your choosing.

 */
- (void)showSurveyWithID:(NSUInteger)ID;

/*!
 @method

 @abstract
 Show a survey if one is available.

 @discussion
 This method allows you to display the first available survey targeted to the currently
 identified user at the time of your choosing. You would typically pair this with
 setting <code>showSurveyOnActive = NO;</code> so that the survey won't show automatically.

 */
- (void)showSurvey;


/*!
 @method

 @abstract
 Shows the notification of the given id.

 @discussion
 You do not need to call this method on the main thread.
 */
- (void)showNotificationWithID:(NSUInteger)ID;


/*!
 @method

 @abstract
 Shows a notification with the given type if one is available.

 @discussion
 You do not need to call this method on the main thread.

 @param type The type of notification to show, either @"mini", or @"takeover"
 */
- (void)showNotificationWithType:(NSString *)type;

/*!
 @method

 @abstract
 Shows a notification if one is available.

 @discussion
 You do not need to call this method on the main thread.
 */
- (void)showNotification;

- (void)createAlias:(NSString *)alias forDistinctID:(NSString *)distinctID;

@end

/*!
 @class
 Sogamo People API.

 @abstract
 Access to the Sogamo People API, available as a property on the main
 Sogamo API.

 @discussion
 <b>You should not instantiate this object yourself.</b> An instance of it will
 be available as a property of the main Sogamo object. Calls to Sogamo
 People methods will look like this:

 <pre>
 [Sogamo.people increment:@"App Opens" by:1];
 </pre>

 Please note that the core <code>Sogamo</code> and
 <code>SogamoPeople</code> classes have separate <code>identify:<code>
 methods. The <code>Sogamo</code> <code>identify:</code> affects the
 <code>distinct_id</code> property of events sent by <code>track:</code> and
 <code>track:properties:</code>. The <code>SogamoPeople</code>
 <code>identify:</code> determines which Sogamo People user record will be
 updated by <code>set:</code>, <code>increment:</code> and other
 <code>SogamoPeople</code> methods.

 <b>If you are going to set your own distinct IDs for core Sogamo event
 tracking, make sure to use the same distinct IDs when using Sogamo
 People</b>.
 */
@interface SogamoPeople : NSObject

/*!
 @method

 @abstract
 Register the given device to receive push notifications.

 @discussion
 This will associate the device token with the current user in Sogamo People,
 which will allow you to send push notifications to the user from the Sogamo
 People web interface. You should call this method with the <code>NSData</code>
 token passed to
 <code>application:didRegisterForRemoteNotificationsWithDeviceToken:</code>.

 @param deviceToken     device token as returned <code>application:didRegisterForRemoteNotificationsWithDeviceToken:</code>
 */
- (void)addPushDeviceToken:(NSData *)deviceToken;

/*!
 @method

 @abstract
 Set properties on the current user in Sogamo People.

 @discussion
 The properties will be set on the current user. The keys must be NSString
 objects and the values should be NSString, NSNumber, NSArray, NSDate, or
 NSNull objects. We use an NSAssert to enforce this type requirement. In
 release mode, the assert is stripped out and we will silently convert
 incorrect types to strings using [NSString stringWithFormat:@"%@", value]. You
 can override the default the current project token and distinct ID by
 including the special properties: $token and $distinct_id. If the existing
 user record on the server already has a value for a given property, the old
 value is overwritten. Other existing properties will not be affected.

 <pre>
 // applies to both Sogamo Engagement track: AND Sogamo People set: and
 // increment: calls
 [Sogamo identify:distinctId];

 // applies ONLY to Sogamo People set: and increment: calls
 [Sogamo.people identify:distinctId];
 </pre>

 @param properties       properties dictionary

 */
- (void)set:(NSDictionary *)properties;

/*!
 @method

 @abstract
 Convenience method for setting a single property in Sogamo People.

 @discussion
 Property keys must be <code>NSString</code> objects and values must be
 <code>NSString</code>, <code>NSNumber</code>, <code>NSNull</code>,
 <code>NSArray</code>, <code>NSDictionary</code>, <code>NSDate</code> or
 <code>NSURL</code> objects.

 @param property        property name
 @param object          property value
 */
- (void)set:(NSString *)property to:(id)object;

/*!
 @method

 @abstract
 Set properties on the current user in Sogamo People, but don't overwrite if
 there is an existing value.

 @discussion
 This method is identical to <code>set:</code> except it will only set
 properties that are not already set. It is particularly useful for collecting
 data about the user's initial experience and source, as well as dates
 representing the first time something happened.

 @param properties       properties dictionary

 */
- (void)setOnce:(NSDictionary *)properties;

/*!
 @method

 @abstract
 Increment the given numeric properties by the given values.

 @discussion
 Property keys must be NSString names of numeric properties. A property is
 numeric if its current value is a number. If a property does not exist, it
 will be set to the increment amount. Property values must be NSNumber objects.

 @param properties      properties dictionary
 */
- (void)increment:(NSDictionary *)properties;

/*!
 @method

 @abstract
 Convenience method for incrementing a single numeric property by the specified
 amount.

 @param property        property name
 @param amount          amount to increment by
 */
- (void)increment:(NSString *)property by:(NSNumber *)amount;

/*!
 @method

 @abstract
 Append values to list properties.

 @discussion
 Property keys must be <code>NSString</code> objects and values must be
 <code>NSString</code>, <code>NSNumber</code>, <code>NSNull</code>,
 <code>NSArray</code>, <code>NSDictionary</code>, <code>NSDate</code> or
 <code>NSURL</code> objects.

 @param properties      mapping of list property names to values to append
 */
- (void)append:(NSDictionary *)properties;

/*!
 @method

 @abstract
 Union list properties.

 @discussion
 Property keys must be <code>NSArray</code> objects.

 @param properties      mapping of list property names to lists to union
 */
- (void)union:(NSDictionary *)properties;

/*!
 @method

 @abstract
 Track money spent by the current user for revenue analytics.

 @param amount          amount of revenue received
 */
- (void)trackCharge:(NSNumber *)amount;

/*!
 @method

 @abstract
 Track money spent by the current user for revenue analytics and associate
 properties with the charge.

 @discussion
 Charge properties allow you segment on types of revenue. For instance, you
 could record a product ID with each charge so that you could segement on it in
 revenue analytics to see which products are generating the most revenue.
 */
- (void)trackCharge:(NSNumber *)amount withProperties:(NSDictionary *)properties;

/*!
 @method

 @abstract
 Delete current user's revenue history.
 */
- (void)clearCharges;

/*!
 @method

 @abstract
 Delete current user's record from Sogamo People.
 */
- (void)deleteUser;

@end

/*!
 @protocol

 @abstract
 Delegate protocol for controlling the Sogamo API's network behavior.

 @discussion
 Creating a delegate for the Sogamo object is entirely optional. It is only
 necessary when you want full control over when data is uploaded to the server,
 beyond simply calling stop: and start: before and after a particular block of
 your code.
 */
@protocol SogamoDelegate <NSObject>
@optional

/*!
 @method

 @abstract
 Asks the delegate if data should be uploaded to the server.

 @discussion
 Return YES to upload now, NO to defer until later.

 @param Sogamo        Sogamo API instance
 */
- (BOOL)SogamoWillFlush:(Sogamo *)Sogamo;

@end
