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
@synthesize melodyField;
@synthesize instrumentPopUp;


- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	[self playSong: self];
}


-(IBAction)	playSong: (id)sender
{
	NSString*		instrument[] = { @"snd_128", @"snd_129", @"snd_146" };
	NSUInteger		instrumentIndex = [instrumentPopUp indexOfSelectedItem];
	
	NSURL*			soundFile = [[NSBundle mainBundle] URLForResource: instrument[instrumentIndex] withExtension: @"aiff"];
	ULIMelodyQueue	*	melodyPlayer = [[[ULIMelodyQueue alloc] initWithInstrument: soundFile] autorelease];
	[melodyPlayer addMelody: [melodyField stringValue]];
	[melodyPlayer play];
}

@end
