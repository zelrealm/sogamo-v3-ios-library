# Sogamo API on iOS #
To integrate the Sogamo API with your iPhone / iPad application, first download the latest [zip archive](http://sogamo.com/) and extract the files. 

# Requirements #

1. Xcode 4.3.3 or later
2. iOS 5.0 or later

# Setup #
Adding the Sogamo to your Xcode project is just a few easy steps:

1. Add the SogamoAPi Framework

	a. Drag and drop the **SogamoLib** folder (located at **Sogamo SDK Project/SogamoV3SDK/SogamoV3SDK/SogamoLib**) into your project. 
	
	![Folder Structure][Folder Structure]
	
	b. Check the "Copy items into destination's group's folder" and select 'Create groups for any added folders'
![Copy][Copy into Xcode]

2. Add `#import "Sogamo.h"` to all classes that call SogamoAPI functions
		
Now you're ready to start using Sogamo! 

# Usage #
## Start a Session ##
The first thing you need to do is to initialize a Sogamo session with your project API key. We recommend doing this in `applicationDidFinishLaunching:` or
`application:didFinishLaunchingWithOptions` in your Application delegate, with the following method:

	[[SogamoAPI sharedAPI] startSessionWithAPIKey:YOUR_PROJECT_KEY 
										facebookId:USERS_FACEBOOK_ID_OR_NIL];

You can set the facebookId: parameter to nil if that information is unavailable. We, however, strongly recommend that you include the Facebook ID of the user when starting the session. This will allow you to gain insight into how your users behave across all other Sogamo-linked applications that they use. Obtaining the user's Facebook ID is easy with the [Facebook SDK](https://developers.facebook.com/docs/getting-started/facebook-sdk-for-ios/3.1/).

## Tracking Events ##
After initializing the SogamoAPI singleton object, you are ready to track events. This can be done with the following method:

Example Code:

	SogamoAPI *sogamoAPI = [SogamoAPI sharedAPI];
	[sogamoAPI trackEventWithName:@"playerTopUp" 
			params:[NSDictionary dictionaryWithObjectsAndKeys:
				@"First top up", @"remarks",
				[NSNumber numberWithInteger:100], @"currencyEarned",
				[NSNumber numberWithInteger:200], @"currencyBalance",
				[NSNumber numberWithBool:YES], @"successful"
				[NSDate date], @"logDatetime", nil]];


Note: Event params are to be stored in a NSDictionary object. Numeric and boolean parameters must be wrapped inside a NSNumber object, and similarly, datetime parameters are to be represented as NSDate objects.

For a full list of the events that can be tracked, visit the [Sogamo website](http://www.sogamo.com)

## Sending Data ##
Event Data is _flushed_ (i.e transmitted) to the Sogamo server at several points:

- When the app is put into the background (i.e when the user presses the Home button on the device)
- Whenever the periodic flush is triggered (if it is enabled)

### Periodic Flush ###
When the periodic flush is enabled, SogamoAPI will flush accumulated event data at the specified intervals.

_Note: The value for the flushInterval property must be in seconds, and between 0 (the default) and 3600._

Example:

	[[SogamoAPI sharedAPI] setFlushInterval:30]; // Event Data will be flushed every 30s


## Suggestions ##
Suggestions can be requsted from the Sogamo servers via the `requestSuggestionOfType:success:error:` method, which requires the suggestion type as a parameter, along with blocks to handle both success and error outcomes.

Example:

    [[SogamoAPI sharedAPI] requestSuggestionOfType:@"buy"
                                           success:^(NSString *suggestion)
    {
        NSLog(@"Suggestion Request: %@", suggestion);
        // Handle successful suggestion request
    }
                                             error:^(NSError *error)
    {
        NSLog(@"Suggestion Request Error: %@", [error localizedDescription]);
        // Handle failed suggestion request
    }];

## Performance Implications ##

The Sogamo Library runs all of its major functions (Start / Closing a session, flushing data) on a background thread, so it does not affect the performance of your application.

[Folder Structure]: https://raw.github.com/zelrealm/sogamo-ios-library/master/Docs/Images/Folder%20Structure.png "Folder Structure" 
[Copy into Xcode]: https://github.com/zelrealm/Sogamo-iOS-library/raw/master/Docs/Images/Copy%20into%20Xcode.png "Copy into Xcode"
[Add SystemConfiguration]: https://github.com/zelrealm/Sogamo-iOS-library/raw/master/Docs/Images/Added%20SystemConfiguration%20framework.png "Add System Configuration"

