//
//  ULIMelodyQueueAppDelegate.m
//  ULIMelodyQueue
//
//  Created by Uli Kusterer on 10.04.11.
//  Copyright 2011 The Void Software. All rights reserved.
//

#import "ULIMelodyQueueAppDelegate.h"
#import "ULIMelodyQueue.h"


@interface ULIMelodyQueueAppDelegate () <ULIMelodyQueueDelegate>

@end


@implementation ULIMelodyQueueAppDelegate

@synthesize window;
@synthesize melodyField;
@synthesize instrumentPopUp;


- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
}


-(IBAction)	playSong: (id)sender
{
	NSString*		instrument[] = { @"harpsichord", @"boing", @"flute" };
	NSUInteger		instrumentIndex = [instrumentPopUp indexOfSelectedItem];
	
	NSURL*			soundFile = [[NSBundle mainBundle] URLForResource: instrument[instrumentIndex] withExtension: @"aiff"];
	ULIMelodyQueue	*	melodyPlayer = [[[ULIMelodyQueue alloc] initWithInstrument: soundFile] autorelease];
	[melodyPlayer setDelegate: self];
	[melodyPlayer addMelody: [melodyField stringValue]];
	[melodyPlayer play];
}


-(IBAction)	stressTest: (id)sender
{
	NSArray		*	melodies = @[ @"c", @"d", @"e", @"f", @"g", @"a", @"h", @"c5" ];
	for( NSString * currMelody in melodies )
	{
		NSURL*			soundFile = [[NSBundle mainBundle] URLForResource: @"harpsichord" withExtension: @"aiff"];
		ULIMelodyQueue	*	melodyPlayer = [[[ULIMelodyQueue alloc] initWithInstrument: soundFile] autorelease];
		[melodyPlayer addMelody: currMelody];
		[melodyPlayer play];
	}
}

-(void)	melodyQueueDidFinishPlaying: (ULIMelodyQueue*)inSender
{
	NSLog(@"Finished playing.");
}

-(void)	melodyQueueDidStartPlaying: (ULIMelodyQueue*)inSender
{
	NSLog(@"Started playing.");
}

@end
