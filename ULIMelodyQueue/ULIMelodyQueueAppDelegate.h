//
//  ULIMelodyQueueAppDelegate.h
//  ULIMelodyQueue
//
//  Created by Uli Kusterer on 10.04.11.
//  Copyright 2011 The Void Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface ULIMelodyQueueAppDelegate : NSObject <NSApplicationDelegate> {
@private
	NSWindow *window;
}

@property (assign) IBOutlet NSWindow *window;

@end
