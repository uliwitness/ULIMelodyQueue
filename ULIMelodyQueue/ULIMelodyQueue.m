//
//  ULIMelodyQueue.m
//  ULIMelodyQueue
//
//  Created by Uli Kusterer on 10.04.11.
//  Copyright 2011 The Void Software. All rights reserved.
//
//	Parts extracted from Apple's aqplay sample code,
//	Copyright 2007 Apple Inc. All rights reserved.
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

// -----------------------------------------------------------------------------
//	Headers:
// -----------------------------------------------------------------------------

#import "ULIMelodyQueue.h"
#import "UKHelperMacros.h"
#import "UKTypecastMacros.h"

@interface ULIMelodyQueue ()

@property (nonatomic) BOOL isPlaying;

-(void)	playbackStopped;
-(void)	setUpAudioFormat: (NSURL*)inAudioFileURL;
-(void)	setUpAudioQueue;
-(void)	bufferingDone;
-(void)	playOne;

@end


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


// -----------------------------------------------------------------------------
//	ULIMelodyQueuePitchFromNoteChar:
//		Take a single character from a "note" string and turn it into a pitch
//		modifier.
//
//		A typical note is added up of several pitch modifiers in arbitrary order:
//			a note	-	one of c d e f g a h c
//			a sign	-	either # or b to indicate a sharp or flat sign.
//			an octave -	A number between 2 and 5. The default octave is 4.
// -----------------------------------------------------------------------------

static int	ULIMelodyQueuePitchFromNoteChar( unichar inCh )
{
	switch( inCh )
	{
		case 'c':
			return 0;
			break;
		
		case 'd':
			return 200;
			break;
			
		case 'e':
			return 400;
			break;
			
		case 'f':
			return 500;
			break;
			
		case 'g':
			return 700;
			break;
			
		case 'a':
			return 900;
			break;
			
		case 'h':
			return 1100;
			break;
		
		case 'b':
			return -100;
			break;
			
		case '#':
			return 100;
			break;
			
		case '2':
			return -2400;
			break;
			
		case '3':
			return -1200;
			break;
			
		case '4':
			return 0;
			break;
			
		case '5':
			return 1200;
			break;
	}
	
	return 0;
}


// -----------------------------------------------------------------------------
//	ULIMelodyQueuePitchFromNote:
//		Take a "note" string and turn it into a pitch value suitable for passing
//		to the audio queue as the pitch parameter.
//
//		A typical note is added up of several pitch modifiers in arbitrary order.
//		See ULIMelodyQueuePitchFromNoteChar for the valid characters and their
//		function.
// -----------------------------------------------------------------------------

static int	ULIMelodyQueuePitchFromNote( NSString* inNote )
{
	int			thePitch = 0;
	NSUInteger	count = [inNote length];
	for( NSUInteger x = 0; x < count; x++ )
	{
		unichar		currCh = [inNote characterAtIndex: x];
		thePitch += ULIMelodyQueuePitchFromNoteChar( currCh );
	}
	
	return thePitch;
}


// -----------------------------------------------------------------------------
//	ULIMelodyQueueBufferCallback:
//		Called by the AudioQueue when we need to feed more data from the file.
//
//		This is also where we detect when we run out of audio data and request
//		playback to stop. Once the stop has happened, the property listener
//		callback will notify the ULIMelodyQueue to advance to the next note.
// -----------------------------------------------------------------------------

static void	ULIMelodyQueueBufferCallback(	void *                  inUserData,
											AudioQueueRef           inAQ,
											AudioQueueBufferRef     inCompleteAQBuffer )
{
	//UKLog( @"called" );
	
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
	
	if( nPackets > 0 && [self->mNotes count] > 0 )
	{
		inCompleteAQBuffer->mAudioDataByteSize = numBytes;		
		
		AudioQueueParameterEvent	params[] =
		{
			{ kAudioQueueParam_Pitch, 0 * 100 }
		};
		
		NSString	*	theNote = [self->mNotes objectAtIndex: 0];
		params[0].mValue = ULIMelodyQueuePitchFromNote( theNote );
		
		AudioTimeStamp				actualTime = { 0 };
		AudioQueueEnqueueBufferWithParameters( inAQ, inCompleteAQBuffer,
											  (self->mPacketDescs ? nPackets : 0),
											  self->mPacketDescs,
											  0,
											  0,
											  sizeof(params) / sizeof(AudioQueueParameterEvent),
											  params,
											  NULL,
											  &actualTime );
		
		self->mCurrentPacket += nPackets;
	}
	else
	{
        [self bufferingDone];

		// reading nPackets == 0 is our EOF condition
		self->mDone = YES;
	}
}

// -----------------------------------------------------------------------------
//	ULIMelodyQueueIsRunningCallback:
//		Called when the queue has actually stopped playing an individual note,
//		giving us the opportunity to play the next one.
// -----------------------------------------------------------------------------

static void	ULIMelodyQueueIsRunningCallback(	void *              	inUserData,
											  	AudioQueueRef           inAQ,
											  	AudioQueuePropertyID    inID)
{
	ULIMelodyQueue	*	self = (ULIMelodyQueue*) inUserData;
	UInt32				isPlaying = false;	// Yes, kAudioQueueProperty_IsRunning really returns a bool as an UInt32. Who would'a thunk!
	UInt32				size = sizeof(isPlaying);
	/*OSStatus*/ AudioQueueGetProperty( inAQ, kAudioQueueProperty_IsRunning, &isPlaying, &size );
	
	if( !isPlaying )
		[self performSelectorOnMainThread: @selector(playbackStopped) withObject: nil waitUntilDone: NO];
	else if( [self.delegate respondsToSelector: @selector(melodyQueueDidStartPlaying:)] )
		[(NSObject*)self.delegate performSelectorOnMainThread: @selector(melodyQueueDidStartPlaying:) withObject: self waitUntilDone: NO];
}


// -----------------------------------------------------------------------------
//	initWithInstrument:
//		Designated initializer. Takes any audio file that AudioFile can play.
// -----------------------------------------------------------------------------

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


// -----------------------------------------------------------------------------
//	dealloc
// -----------------------------------------------------------------------------

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
	
	DESTROY_DEALLOC(mNotes);
	
    [super dealloc];
}


// -----------------------------------------------------------------------------
//	setUpAudioFormat:
//		Loads the instrument and determines some metadata needed for creation
//		of the audio queue based on that.
// -----------------------------------------------------------------------------

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
	if( !formatList )
	{
		NSLog( @"Couldn't copy audio file's format list." );
		return;
	}
	
	result = AudioFileGetProperty( mAudioFile, kAudioFilePropertyFormatList, &size, formatList );
	if( result != noErr )
	{
		free( formatList );
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
			free( formatList );
			NSLog( @"Couldn't count audio file's decoder IDs (%d).", result );
			return;
		}
		
		UInt32 numDecoders = size / sizeof(OSType);
		OSType *decoderIDs = calloc( numDecoders , sizeof(OSType) );
		result = AudioFormatGetProperty( kAudioFormatProperty_DecodeFormatIDs, 0, NULL, &size, decoderIDs );
		if( result != noErr )
		{
			free( formatList );
			free(decoderIDs);
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
			free( formatList );
			formatList = NULL;
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


// -----------------------------------------------------------------------------
//	setUpAudioQueue
//		Create our audio queue once the instrument has been loaded.
// -----------------------------------------------------------------------------

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
			free( cookie );
			NSLog( @"Couldn't get cookie from file (%d).", err );
			return;
		}
		err = AudioQueueSetProperty( mQueue, kAudioQueueProperty_MagicCookie, cookie, size );
		if( err != noErr )
		{
			free( cookie );
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
	
	// set the volume of the queue
	Float32		volume = 1.0;
	err = AudioQueueSetParameter( mQueue, kAudioQueueParam_Volume, volume );
	if( err != noErr )
	{
		NSLog( @"Couldn't set queue volume (%d).", err );
		return;
	}
	
	// Make sure we get notified when playback stops:
	err = AudioQueueAddPropertyListener( mQueue, kAudioQueueProperty_IsRunning, ULIMelodyQueueIsRunningCallback, self );
	if( err != noErr )
	{
		NSLog( @"Couldn't add listener to queue (%d).", err );
		return;
	}
	
	// Turn on whatever is so nice to let us change the sound's pitch:
	UInt32 propValue = 1;
	err = AudioQueueSetProperty( mQueue, kAudioQueueProperty_EnableTimePitch, &propValue, sizeof(propValue) );
    UInt32 timePitchAlgorithm = kAudioQueueTimePitchAlgorithm_Spectral; // supports rate and pitch
    AudioQueueSetProperty(mQueue, kAudioQueueProperty_TimePitchAlgorithm, &timePitchAlgorithm, sizeof(timePitchAlgorithm));
	if( err != noErr )
	{
		NSLog( @"Couldn't enable time pitch (%d).", err );
		return;
	}
}


// -----------------------------------------------------------------------------
//	playOne
//		Kick off playback of one note.
// -----------------------------------------------------------------------------

-(void)	playOne
{
	if( mPacketDescs )
	{
		free( mPacketDescs );
		mPacketDescs = NULL;
	}
	
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
        if (!self.isPlaying)
		{
            err = AudioQueueAllocateBuffer( mQueue, bufferByteSize, &mBuffers[i] );
            if( err != noErr )
            {
                NSLog( @"AudioQueueAllocateBuffer failed (%d).", err );
                return;
            }
        }
		
		ULIMelodyQueueBufferCallback( self, mQueue, mBuffers[i] );
		
		if( mDone )
			break;
	}
	// Kick off playback:
    if (!self.isPlaying)
	{
        AudioQueuePrime(mQueue, 0, NULL);
        err = AudioQueueStart( mQueue, NULL );
        self.isPlaying = YES;
    }
    
	if( err != noErr )
	{
		NSLog( @"AudioQueueStart failed (%d).", err );
		return;
	}
}


// -----------------------------------------------------------------------------
//	bufferingDone
//		One note has finished buffering, enqueue the next one, or actually stop
//		playback.
// -----------------------------------------------------------------------------

-(void)	bufferingDone
{
	BOOL	hadAnotherNote = NO;
	if( [mNotes count] > 0 )
	{
		[mNotes removeObjectAtIndex: 0];
        if( mNotes.count )
		{
            [self playOne];
			hadAnotherNote = YES;
        }
	}
	
	if( !hadAnotherNote )
	{
        OSStatus result = AudioQueueStop(mQueue, false);
		if( result )
			NSLog( @"AudioQueueStop(false) failed: %d", (int)result );
	}
}


-(void)	playbackStopped
{
	if( [self.delegate respondsToSelector: @selector(melodyQueueDidFinishPlaying:)] )
		[self.delegate melodyQueueDidFinishPlaying: self];
	[self performSelector: @selector(release) withObject: nil afterDelay: 0.0];	// Balance the retain we performed at the start of playback.
	self.isPlaying = NO;
}


// -----------------------------------------------------------------------------
//	play
//		Trigger playback of our current melody, with our instrument.
// -----------------------------------------------------------------------------

-(void)	play
{
	if( mNotes && [mNotes count] > 0 )
	{
		[self retain];	// Retain ourselves to ensure we don't disappear from under CoreAudio.
		[self playOne];
	}
}


// -----------------------------------------------------------------------------
//	addNote:
//		Add a single note to be played back. See ULIMelodyQueuePitchFromNoteChar
//		for how a note is specified.
// -----------------------------------------------------------------------------

-(void)	addNote: (NSString*)inNote
{
	if( !mNotes )
		mNotes = [[NSMutableArray alloc] initWithObjects: inNote, nil];
	else
		[mNotes addObject: inNote];
}


// -----------------------------------------------------------------------------
//	addMelody:
//		Add a complete melody to be played back.
//
//		inMelody is a space-separated string of notes to play.
//		See ULIMelodyQueuePitchFromNoteChar for how a note is specified.
// -----------------------------------------------------------------------------

-(void)	addMelody: (NSString*)inMelody
{
	if( !mNotes )
		mNotes = [[NSMutableArray alloc] init];
	
	NSArray	*	notes = [inMelody componentsSeparatedByString: @" "];
	for( NSString*	aNote in notes )
		[mNotes addObject: aNote];
}

@end
