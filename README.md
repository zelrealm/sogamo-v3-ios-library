# Sogamo API on iOS #
To integrate the Sogamo API with your iPhone / iPad application, first download the latest [zip archive](http://sogamo.com/) and extract the files. 

# Requirements #

1. Xcode 4.3.3 or later
2. iOS 5.0 or later

# Setup #
Adding the Sogamo to your Xcode project is just a few easy steps:

1. Add the SogamoAPI Framework

	a. Drag and drop the **SogamoLib** folder (located at **Sogamo SDK Project/SogamoV3SDK/SogamoV3SDK/SogamoLib**) into your project. 
	
	b. Check the "Copy items into destination's group's folder" and select 'Create groups for any added folders'

2. Add `#import "Sogamo.h"` to all classes that call SogamoAPI functions
		
Now you're ready to start using Sogamo! 

# Usage #
## Initializing the library ##
The first thing you need to do is to initialize the Sogamo iOS library with your project API key. We recommend doing this in `applicationDidFinishLaunching:` or
`application:didFinishLaunchingWithOptions` in your Application delegate.

To initialize the library, call `sharedInstanceWithToken:` with your project API key as its argument. Once you have called this method once, you can access 
your instance throughout the rest of your application with `sharedInstance`.

	#define SOGAMO_TOKEN @"YOUR_PROJECT_API_KEY"

	// Initialize the library with your
	// Sogamo project token, SOGAMO_TOKEN
	[Sogamo sharedInstanceWithToken:SOGAMO_TOKEN];

	// Later, you can get your instance with
	Sogamo *sogamo = [Sogamo sharedInstance];

## Tracking Events ##
After initializing the Sogamo singleton object, you are ready to track events. This can be done with the `track:properties` method with the event name and properties.

        Sogamo *sogamo = [Sogamo sharedInstance];

	[sogamo track:@"Destroyed a ship" properties:@{
	    @"ship_class": @"Constitution-class"
	}];

Note: Properties parameters are to be stored in a NSDictionary object. Numeric and boolean 
parameters must be wrapped inside a NSNumber object.

## Sending Data ##
Event Data is _flushed_ (i.e transmitted) to the Sogamo server at several points:

- When the app is put into the background (i.e when the user presses the Home button on the device)
- Whenever the periodic flush is triggered (if it is enabled)

## Performance Implications ##

The Sogamo Library runs all of its major functions (Start / Closing a session, flushing data) on a background thread, so it does not affect the performance of your application.
