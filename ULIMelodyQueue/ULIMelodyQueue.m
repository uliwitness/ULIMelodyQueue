//
//  ULIMelodyQueue.m
//  ULIMelodyQueue
//
//  Created by Uli Kusterer on 10.04.11.
//  Copyright 2011 The Void Software. All rights reserved.
//
//	Parts extracted from Apple's aqplay sample code,
//	Copyright © 2007 Apple Inc. All Rights Reserved.
//

#import "ULIMelodyQueue.h"
#import "UKTypecastMacros.h"


@implementation ULIMelodyQueue

// we only use time here as a guideline
// we're really trying to get somewhere between 16K and 64K buffers, but not allocate too much if we don't need it
static void		ULIMelodyQueueCalculateBytesForTime( AudioStreamBasicDescription *inDesc, UInt32 inMaxPacketSize, Float64 inSeconds, UInt32 *outBufferSize, UInt32 *outNumPackets )
{
	static const int maxBufferSize = 0x10000;	// limit size to 64K
	static const int minBufferSize = 0x4000;	// limit size to 16K
	
	if( inDesc->mFramesPerPacket )
	{
		Float64 numPacketsForTime = inDesc->mSampleRate / inDesc->mFramesPerPacket * inSeconds;
		*outBufferSize = numPacketsForTime * inMaxPacketSize;
	}
	else
	{
		// if frames per packet is zero, then the codec has no predictable packet == time
		// so we can't tailor this (we don't know how many Packets represent a time period
		// we'll just return a default buffer size
		*outBufferSize = maxBufferSize > inMaxPacketSize ? maxBufferSize : inMaxPacketSize;
	}
	
	// we're going to limit our size to our default
	if( *outBufferSize > maxBufferSize && *outBufferSize > inMaxPacketSize )
		*outBufferSize = maxBufferSize;
	else
	{
		// also make sure we're not too small - we don't want to go the disk for too small chunks
		if( *outBufferSize < minBufferSize )
			*outBufferSize = minBufferSize;
	}
	*outNumPackets = *outBufferSize / inMaxPacketSize;
}


static void	ULIMelodyQueueBufferCallback(	void *                  inUserData,
											AudioQueueRef           inAQ,
											AudioQueueBufferRef     inCompleteAQBuffer )
{
	ULIMelodyQueue	*	self = (ULIMelodyQueue*) inUserData;
	if( self->mDone )
		return;
	
	UInt32 numBytes = 0;
	UInt32 nPackets = self->mNumPacketsToRead;
	
	OSStatus result = AudioFileReadPackets( self->mAudioFile, false, &numBytes, self->mPacketDescs, self->mCurrentPacket, &nPackets, 
											inCompleteAQBuffer->mAudioData );
	if( result )
	{
		NSLog( @"Error reading from file: %d\n", (int)result );
		return;
	}
	
	if( nPackets > 0 )
	{
		inCompleteAQBuffer->mAudioDataByteSize = numBytes;		
		
		AudioQueueEnqueueBuffer( inAQ, inCompleteAQBuffer, (self->mPacketDescs ? nPackets : 0), self->mPacketDescs );
		
		self->mCurrentPacket += nPackets;
	}
	else
	{
		result = AudioQueueStop( self->mQueue, false );
		if( result )
		{
			NSLog( @"AudioQueueStop(false) failed: %d", (int)result );
			return;
		}
		// reading nPackets == 0 is our EOF condition
		self->mDone = YES;
	}
}


static void	ULIMelodyQueueIsRunningCallback(	void *              	inUserData,
											  	AudioQueueRef           inAQ,
											  	AudioQueuePropertyID    inID)
{
	ULIMelodyQueue	*	self = (ULIMelodyQueue*) inUserData;
	bool				isPlaying = false;
	UInt32				size = sizeof(isPlaying);
	/*OSStatus*/ AudioQueueGetProperty( inAQ, kAudioQueueProperty_IsRunning, &isPlaying, &size );
	
	if( !isPlaying )
		[self playbackStopped];
}



-(id)	initWithInstrument: (NSURL*)inAudioFileURL
{
    self = [super init];
    if( self )
	{
		[self setUpAudioFormat: inAudioFileURL];
		
		[self setUpAudioQueue];
    }
    
    return self;
}

-(void)	dealloc
{
	AudioQueueDispose( mQueue, true );
	AudioFileClose( mAudioFile );
	
	if( mChannelLayout )
	{
		free( mChannelLayout );
		mChannelLayout = NULL;
	}
	
	if( mPacketDescs )
	{
		free( mPacketDescs );
		mPacketDescs = NULL;
	}
	
    [super dealloc];
}


-(void)	setUpAudioFormat: (NSURL*)inAudioFileURL
{
	OSStatus result = AudioFileOpenURL( UKNSToCFURL(inAudioFileURL), fsRdPerm, 0/*inFileTypeHint*/, &mAudioFile );
	if( result != noErr )
	{
		NSLog( @"AudioFileOpenURL failed (%d).", result );
		return;
	}
	
	UInt32 size;
	result = AudioFileGetPropertyInfo( mAudioFile, kAudioFilePropertyFormatList, &size, NULL);
	if( result != noErr )
	{
		NSLog( @"Couldn't get audio file's format list (%d).", result );
		return;
	}
	
	UInt32 numFormats = size / sizeof(AudioFormatListItem);
	AudioFormatListItem *formatList = calloc( numFormats, sizeof(AudioFormatListItem) );
	
	result = AudioFileGetProperty( mAudioFile, kAudioFilePropertyFormatList, &size, formatList );
	if( result != noErr )
	{
		NSLog( @"Couldn't get audio file's data format (%d).", result );
		return;
	}
	
	numFormats = size / sizeof(AudioFormatListItem); // we need to reassess the actual number of formats when we get it
	if( numFormats == 1 )
	{
		// this is the common case
		mDataFormat = formatList[0].mASBD;
		
		// see if there is a channel layout (multichannel file)
		result = AudioFileGetPropertyInfo( mAudioFile, kAudioFilePropertyChannelLayout, &mChannelLayoutSize, NULL);
		if( result == noErr && mChannelLayoutSize > 0 )
		{
			mChannelLayout = (AudioChannelLayout *) calloc( mChannelLayoutSize, 1 );
			result = AudioFileGetProperty( mAudioFile, kAudioFilePropertyChannelLayout, &mChannelLayoutSize, mChannelLayout);
			if( result != noErr )
			{
				NSLog( @"Couldn't get audio file's channel layout (%d).", result );
				return;
			}
		}
	}
	else
	{
		// now we should look to see which decoders we have on the system
		result = AudioFormatGetPropertyInfo( kAudioFormatProperty_DecodeFormatIDs, 0, NULL, &size );
		if( result != noErr )
		{
			NSLog( @"Couldn't count audio file's decoder IDs (%d).", result );
			return;
		}
		
		UInt32 numDecoders = size / sizeof(OSType);
		OSType *decoderIDs = calloc( numDecoders , sizeof(OSType) );
		result = AudioFormatGetProperty( kAudioFormatProperty_DecodeFormatIDs, 0, NULL, &size, decoderIDs );
		if( result != noErr )
		{
			NSLog( @"Couldn't retrieve audio file's decoder IDs (%d).", result );
			return;
		}
		
		unsigned int i = 0;
		for( ; i < numFormats; ++i )
		{
			OSType decoderID = formatList[i].mASBD.mFormatID;
			bool found = false;
			for( unsigned int j = 0; j < numDecoders; ++j )
			{
				if( decoderID == decoderIDs[j] )
				{
					found = true;
					break;
				}
			}
			if( found )
				break;
		}
		free( decoderIDs );
		decoderIDs = NULL;
		
		if( i >= numFormats )
		{
			NSLog( @"Cannot play any of the formats in this file" );
			return;
		}
		
		mDataFormat = formatList[i].mASBD;
		mChannelLayoutSize = sizeof(AudioChannelLayout);
		mChannelLayout = (AudioChannelLayout*) calloc( mChannelLayoutSize, 1 );
		mChannelLayout->mChannelLayoutTag = formatList[i].mChannelLayoutTag;
		mChannelLayout->mChannelBitmap = 0;
		mChannelLayout->mNumberChannelDescriptions = 0;
	}
	free( formatList );
	formatList = NULL;
}


-(void)	setUpAudioQueue
{
	OSStatus	err = AudioQueueNewOutput(	&mDataFormat, ULIMelodyQueueBufferCallback, self, 
									 		CFRunLoopGetCurrent(), kCFRunLoopCommonModes, 0,
									 		&mQueue);
	if( err != noErr )
	{
		NSLog( @"Couldn't create queue (%d).", err );
		return;
	}

	// (2) If the file has a cookie, we should get it and set it on the AQ
	UInt32	size = sizeof(UInt32);
	err = AudioFileGetPropertyInfo( mAudioFile, kAudioFilePropertyMagicCookieData, &size, NULL );
	
	if( !err && size )
	{
		char*	cookie = calloc( size, 1 );		
		err = AudioFileGetProperty( mAudioFile, kAudioFilePropertyMagicCookieData, &size, cookie);
		if( err != noErr )
		{
			NSLog( @"Couldn't get cookie from file (%d).", err );
			return;
		}
		err = AudioQueueSetProperty( mQueue, kAudioQueueProperty_MagicCookie, cookie, size );
		if( err != noErr )
		{
			NSLog( @"Couldn't set cookie on queue (%d).", err );
			return;
		}
		free( cookie );
		cookie = NULL;
	}

	// set ACL if there is one
	if( mChannelLayout )
	{
		err = AudioQueueSetProperty( mQueue, kAudioQueueProperty_ChannelLayout, mChannelLayout, mChannelLayoutSize );
		if( err != noErr )
		{
			NSLog( @"Couldn't set channel layout on queue (%d).", err );
			return;
		}
	}
}


-(void)	playOne
{
	OSStatus	err = noErr;
	UInt32		bufferByteSize = 0;
	
	// we need to calculate how many packets we read at a time, and how big a buffer we need
	// we base this on the size of the packets in the file and an approximate duration for each buffer
	{
		bool		isFormatVBR = (mDataFormat.mBytesPerPacket == 0 || mDataFormat.mFramesPerPacket == 0);
		
		// first check to see what the max size of a packet is - if it is bigger
		// than our allocation default size, that needs to become larger
		UInt32		maxPacketSize = 0;
		UInt32		size = sizeof(maxPacketSize);
		err = AudioFileGetProperty( mAudioFile, kAudioFilePropertyPacketSizeUpperBound, &size, &maxPacketSize );
		if( err != noErr )
		{
			NSLog( @"Couldn't get file's max packet size (%d).", err );
			return;
		}
		
		// adjust buffer size to represent about a half second of audio based on this format
		ULIMelodyQueueCalculateBytesForTime( &mDataFormat, maxPacketSize, 0.5/*seconds*/, &bufferByteSize, &mNumPacketsToRead );
		
		if( isFormatVBR )
			mPacketDescs = calloc( mNumPacketsToRead, sizeof(AudioStreamPacketDescription) );
		else
			mPacketDescs = NULL; // we don't provide packet descriptions for constant bit rate formats (like linear PCM)
	}
	
	// prime the queue with some data before starting
	mDone = NO;
	mCurrentPacket = 0;
	for( int i = 0; i < kNumberBuffers; ++i )
	{
		err = AudioQueueAllocateBuffer( mQueue, bufferByteSize, &mBuffers[i] );
		if( err != noErr )
		{
			NSLog( @"AudioQueueAllocateBuffer failed (%d).", err );
			return;
		}
		
		ULIMelodyQueueBufferCallback( self, mQueue, mBuffers[i] );
		
		if( mDone )
			break;
	}
	
	// set the volume of the queue
	Float32		volume = 1.0;
	err = AudioQueueSetParameter( mQueue, kAudioQueueParam_Volume, volume );
	if( err != noErr )
	{
		NSLog( @"Couldn't set queue volume (%d).", err );
		return;
	}
	
	// Make sure we get notified when playback stops:
	err = AudioQueueAddPropertyListener( mQueue, kAudioQueueProperty_IsRunning, ULIMelodyQueueIsRunningCallback, NULL );
	if( err != noErr )
	{
		NSLog( @"Couldn't add listener to queue (%d).", err );
		return;
	}
	
	// Turn on whatever is so nice to let us change the sound's pitch:
	UInt32 propValue = 1;
	err = AudioQueueSetProperty( mQueue, kAudioQueueProperty_EnableTimePitch, &propValue, sizeof(propValue) );
	if( err != noErr )
	{
		NSLog( @"Couldn't enable time pitch (%d).", err );
		return;
	}
	
	// Actually change the pitch:
	Float32		pitch = 4 * 100;
	err = AudioQueueSetParameter( mQueue, kAudioQueueParam_Pitch, pitch );
	if( err != noErr )
	{
		NSLog( @"Couldn't set pitch (%d).", err );
		return;
	}
	
	// Kick off playback:
	err = AudioQueueStart( mQueue, NULL );
	if( err != noErr )
	{
		NSLog( @"AudioQueueStart failed (%d).", err );
		return;
	}
}


-(void)	playbackStopped
{
	[NSApp terminate: nil];
}

@end
