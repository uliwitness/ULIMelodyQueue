//
//  ULIMelodyQueue.h
//  ULIMelodyQueue
//
//  Created by Uli Kusterer on 10.04.11.
//  Copyright 2011 The Void Software. All rights reserved.
//
//	This software is provided 'as-is', without any express or implied
//	warranty. In no event will the authors be held liable for any damages
//	arising from the use of this software.
//
//	Permission is granted to anyone to use this software for any purpose,
//	including commercial applications, and to alter it and redistribute it
//	freely, subject to the following restrictions:
//
//	   1. The origin of this software must not be misrepresented; you must not
//	   claim that you wrote the original software. If you use this software
//	   in a product, an acknowledgment in the product documentation would be
//	   appreciated but is not required.
//
//	   2. Altered source versions must be plainly marked as such, and must not be
//	   misrepresented as being the original software.
//
//	   3. This notice may not be removed or altered from any source
//	   distribution.
//

/*
	ULIMelodyQueue is a class that takes a sound file as an instrument and plays
	a melody by changing its pitch.
 */

// -----------------------------------------------------------------------------
//	Headers:
// -----------------------------------------------------------------------------

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioQueue.h>
#import <AudioToolbox/AudioFile.h>
#import <AudioToolbox/AudioFormat.h>


// -----------------------------------------------------------------------------
//	Constants:
// -----------------------------------------------------------------------------

#define kNumberBuffers		3


// -----------------------------------------------------------------------------
//	Classes:
// -----------------------------------------------------------------------------

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
