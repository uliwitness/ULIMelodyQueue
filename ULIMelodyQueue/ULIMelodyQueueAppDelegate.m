//
//  ULIMelodyQueueAppDelegate.m
//  ULIMelodyQueue
//
//  Created by Uli Kusterer on 10.04.11.
//  Copyright 2011 The Void Software. All rights reserved.
//

#import "ULIMelodyQueueAppDelegate.h"
#import "ULIMelodyQueue.h"


@implementation ULIMelodyQueueAppDelegate

@synthesize window;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	ULIMelodyQueue	*	melodyPlayer = [[ULIMelodyQueue alloc] initWithInstrument: [[NSBundle mainBundle] URLForResource: @"snd_128" withExtension: @"aiff"]];
	[melodyPlayer playOne];
}

@end
