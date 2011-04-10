//
//  ULIMelodyQueue.h
//  ULIMelodyQueue
//
//  Created by Uli Kusterer on 10.04.11.
//  Copyright 2011 The Void Software. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioQueue.h>
#import <AudioToolbox/AudioFile.h>
#import <AudioToolbox/AudioFormat.h>


#define kNumberBuffers		3


@interface ULIMelodyQueue : NSObject
{
	AudioFileID						mAudioFile;
	AudioQueueRef					mQueue;
	AudioStreamBasicDescription		mDataFormat;
	AudioChannelLayout *			mChannelLayout;
	UInt32							mChannelLayoutSize;
	UInt32							mNumPacketsToRead;
	AudioStreamPacketDescription *	mPacketDescs;
	SInt64							mCurrentPacket;
	bool							mDone;
	AudioQueueBufferRef				mBuffers[kNumberBuffers];
	NSMutableArray*					mNotes;
}

-(id)	initWithInstrument: (NSURL*)inAudioFileURL;

-(void)	play;
-(void)	addMelody: (NSString*)inMelody;
-(void)	addNote: (NSString*)inNote;

// private:
-(void)	setUpAudioFormat: (NSURL*)inAudioFileURL;
-(void)	setUpAudioQueue;
-(void)	playbackStopped;
-(void)	playOne;

@end
