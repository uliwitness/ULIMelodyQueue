//
//  ULIMelodyQueueAppDelegate.h
//  ULIMelodyQueue
//
//  Created by Uli Kusterer on 10.04.11.
//  Copyright 2011 The Void Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface ULIMelodyQueueAppDelegate : NSObject <NSApplicationDelegate>
{
	NSWindow		*window;
	NSTextField		*melodyField;
	NSPopUpButton	*instrumentPopUp;
}

@property (assign) IBOutlet NSWindow	*	window;
@property (assign) IBOutlet NSTextField	*	melodyField;
@property (assign) IBOutlet NSPopUpButton *	instrumentPopUp;

-(IBAction)	playSong: (id)sender;
-(IBAction)	stressTest: (id)sender;

@end
