//
//  XLDPlayer.m
//  XLD
//
//  Created by tmkk on 06/08/07.
//  Copyright 2006 tmkk. All rights reserved.
//

#import "XLDPlayer.h"
#import "XLDecoderCenter.h"
#import "XLDDecoder.h"
#import "XLDController.h"
#import "XLDRawDecoder.h"
#import "XLDTrack.h"
#import "XLDPlayerSlider.h"
#import "XLDMultipleFileWrappedDecoder.h"
#import <CoreServices/CoreServices.h>

#define FIFO_DURATION (0.5f)

static OSStatus MyFileRenderProc(void *inRefCon, AudioUnitRenderActionFlags    *inActionFlags,
								 const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber,
								 UInt32 inNumFrames, AudioBufferList *ioData);

@implementation XLDPlayer

- (XLDErr)beginPlayFromFrame:(xldoffset_t)idx
{
	bps = [decoder bytesPerSample];
	channels = [decoder channels];
	samplerate = [decoder samplerate];
	totalFrame = [decoder totalFrames];
	
	AudioStreamBasicDescription outFormat;
	AudioStreamBasicDescription inFormat;
	
	inFormat.mSampleRate = samplerate;
	inFormat.mFormatID = kAudioFormatLinearPCM;
	if([decoder isFloat]) {
#ifdef _BIG_ENDIAN
		inFormat.mFormatFlags=kLinearPCMFormatFlagIsFloat|kLinearPCMFormatFlagIsPacked|kAudioFormatFlagIsBigEndian;
#else
		inFormat.mFormatFlags=kLinearPCMFormatFlagIsFloat|kLinearPCMFormatFlagIsPacked;
#endif
	}
	else {
#ifdef _BIG_ENDIAN
		inFormat.mFormatFlags=kLinearPCMFormatFlagIsSignedInteger|kLinearPCMFormatFlagIsPacked|kAudioFormatFlagIsBigEndian;
#else
		inFormat.mFormatFlags=kLinearPCMFormatFlagIsSignedInteger|kLinearPCMFormatFlagIsPacked;
#endif
	}
	inFormat.mFramesPerPacket = 1;
	inFormat.mBytesPerPacket=4*channels;
	inFormat.mBytesPerFrame=4*channels;
	inFormat.mChannelsPerFrame=channels;
	inFormat.mBitsPerChannel=32;
	
	OSStatus	err ;
	UInt32		count;
	
	/*  get the default output device for the HAL */
	ComponentDescription desc;
	Component comp;
	AudioUnitConnection	connection;
	connection.sourceOutputNumber = 0;
	connection.destInputNumber    = 0;
	Boolean outWritable;
	AURenderCallbackStruct  renderCallback;
	
	/* Open default output nuit */
	desc.componentType = kAudioUnitType_Output; 
	desc.componentSubType = kAudioUnitSubType_DefaultOutput; // kAudioUnitSubType_HALOutput
	desc.componentManufacturer = kAudioUnitManufacturer_Apple;
	desc.componentFlags = 0;
	desc.componentFlagsMask = 0;
	comp = FindNextComponent(NULL, &desc);
	if (comp == NULL) {
		fprintf(stderr, "can't find HAL output unit\n");
		[decoder closeFile];
		decoder = nil;
		return XLDUnknownErr;
	}
	
	err = OpenAComponent(comp, &outputUnit);
	if (err)  {
		fprintf(stderr, "can't open HAL output unit\n");
		[decoder closeFile];
		decoder = nil;
		return XLDUnknownErr;
	}
	
	err = AudioUnitInitialize(outputUnit);
	if(err != noErr) {
		fprintf(stderr, "AudioUnitInitialize failed.\n");
		[decoder closeFile];
		decoder = nil;
		CloseComponent(outputUnit);
		return XLDUnknownErr;
	}
	
#if 0
	UInt32 enableIO;
	UInt32 size=0;
	AudioDeviceID outputDevice;
	/* Get default output device */
	enableIO = 0;
	AudioUnitSetProperty(outputUnit,
						 kAudioOutputUnitProperty_EnableIO,
						 kAudioUnitScope_Input,
						 1,
						 &enableIO,
						 sizeof(enableIO));
	
	enableIO = 1;
	AudioUnitSetProperty(outputUnit,
						 kAudioOutputUnitProperty_EnableIO,
						 kAudioUnitScope_Output,
						 0,
						 &enableIO,
						 sizeof(enableIO));
	
	size = sizeof(AudioDeviceID);
    err = AudioHardwareGetProperty(kAudioHardwarePropertyDefaultOutputDevice,
								   &size,
								   &outputDevice);
	if (err)  {
		fprintf(stderr, "can't get default output device\n");
		[decoder closeFile];
		decoder = nil;
		return XLDUnknownErr;
	}
	err = AudioUnitSetProperty(outputUnit,
							   kAudioOutputUnitProperty_CurrentDevice,
							   kAudioUnitScope_Global,
							   0,
							   &outputDevice,
							   sizeof(outputDevice));
	if (err)  {
		fprintf(stderr, "can't set default output device\n");
		[decoder closeFile];
		decoder = nil;
		return XLDUnknownErr;
	}
#endif
	
	/* setup output unit */
	
	err = AudioUnitGetPropertyInfo(outputUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &count, &outWritable);
	err = AudioUnitGetProperty(outputUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &outFormat, &count);
	if(err != noErr) {
		fprintf(stderr, "AudioUnitGetProperty failed.\n");
		[decoder closeFile];
		decoder = nil;
		CloseComponent(outputUnit);
		return XLDUnknownErr;
	}
	err = AudioUnitSetProperty(outputUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &outFormat, count);
	if(err != noErr) {
		fprintf(stderr, "AudioUnitSetProperty failed.\n");
		[decoder closeFile];
		decoder = nil;
		CloseComponent(outputUnit);
		return XLDUnknownErr;
	}
	
	err = AudioConverterNew(&inFormat, &outFormat, &converter);
	if(err != noErr) {
		fprintf(stderr, "AudioConverterNew failed.\n");
		[decoder closeFile];
		decoder = nil;
		CloseComponent(outputUnit);
		return XLDUnknownErr;
	}
	
	if(channels == 1) {
		SInt32 channelMap[2] = { 0, 0 };
		err = AudioConverterSetProperty(converter, kAudioConverterChannelMap, sizeof(channelMap), channelMap);
		if(err != noErr) {
			fprintf(stderr, "AudioConverterSetProperty(kAudioConverterChannelMap) failed\n");
			return XLDUnknownErr;
		}
	}
	
	memset(&renderCallback, 0, sizeof(AURenderCallbackStruct));
	renderCallback.inputProc = MyFileRenderProc;
	renderCallback.inputProcRefCon = self;
	err = AudioUnitSetProperty (outputUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &renderCallback, sizeof(AURenderCallbackStruct));
	if(err != noErr) {
		fprintf(stderr, "AudioUnitSetProperty failed.\n");
		[decoder closeFile];
		decoder = nil;
		AudioConverterDispose(converter);
		CloseComponent(outputUnit);
		return XLDUnknownErr;
	}
	
	playDone = YES;
	playing = YES;
	decodeFinished = NO;
	lastBuffer = NO;
	playThreadIsDone = NO;
	currentFrame = idx;
	seekpoint = -1;
	
	int ringbuffer_len = samplerate * FIFO_DURATION * 4 * channels;
	sfifo_init(&fifo, ringbuffer_len );
	bufferSize = ringbuffer_len >> 1;
	buffer = (unsigned char *)malloc(bufferSize);
	
	[(id <XLDDecoder>)decoder seekToFrame:idx];
	[o_playButton setImage:[NSImage imageNamed:@"pause_active"]];
	[o_playButton setAlternateImage:[NSImage imageNamed:@"pause_blue"]];
	[o_positionSlider setEnabled:YES];
	
	[NSThread detachNewThreadSelector:@selector(play) toTarget:self withObject:nil];
	
	return XLDNoErr;
}

- (void)fadeout
{
	if(!playing) return;
	float volume = 1.0f;
	int i,repeat=10;
	for(i=0;i<repeat;i++) {
		volume -= 1.0f/repeat;
		AudioUnitSetParameter(outputUnit, kAudioUnitParameterUnit_LinearGain, kAudioUnitScope_Global, 0, volume, 0);
		usleep(10000);
	}
}

- (void)fadein
{
	if(!playing) return;
	float volume = 0.0f;
	int i,repeat=10;
	for(i=0;i<repeat;i++) {
		volume += 1.0f/repeat;
		AudioUnitSetParameter(outputUnit, kAudioUnitParameterUnit_LinearGain, kAudioUnitScope_Global, 0, volume, 0);
		usleep(10000);
	}
}

- (void)togglePause
{
	if(!pause) {
		[o_playButton setImage:[NSImage imageNamed:@"play_active"]];
		[o_playButton setAlternateImage:[NSImage imageNamed:@"play_blue"]];
		[self fadeout];
		AudioOutputUnitStop(outputUnit);
		AudioUnitSetParameter(outputUnit, kAudioUnitParameterUnit_LinearGain, kAudioUnitScope_Global, 0, 1.0f, 0);
		pause = YES;
	}
	else {
		[o_playButton setImage:[NSImage imageNamed:@"pause_active"]];
		[o_playButton setAlternateImage:[NSImage imageNamed:@"pause_blue"]];
		AudioOutputUnitStart(outputUnit);
		pause = NO;
	}
}

- (void)setTrackNameOfIndex:(int)i
{
	if(!currentTrack) return;
	if([currentTrack count] == 1) {
		if([[[currentTrack objectAtIndex:0] metadata] objectForKey:XLD_METADATA_ARTIST] && [[[currentTrack objectAtIndex:0] metadata] objectForKey:XLD_METADATA_TITLE]) {
			[o_currentTrack setStringValue:
				[NSString stringWithFormat:@"%@ - %@",
					[[[currentTrack objectAtIndex:0] metadata] objectForKey:XLD_METADATA_ARTIST],
					[[[currentTrack objectAtIndex:0] metadata] objectForKey:XLD_METADATA_TITLE]]];
		}
		else if([[[currentTrack objectAtIndex:0] metadata] objectForKey:XLD_METADATA_TITLE]) {
			[o_currentTrack setStringValue:
				[[[currentTrack objectAtIndex:0] metadata] objectForKey:XLD_METADATA_TITLE]];
		}
		else [o_currentTrack setStringValue:[currentFile lastPathComponent]];
	}
	else {
		NSMutableString *str = [[NSMutableString alloc] initWithString:[NSString stringWithFormat:@"%d ",i+1]];
		if([[[currentTrack objectAtIndex:i] metadata] objectForKey:XLD_METADATA_ARTIST]) {
			[str appendString:[NSString stringWithFormat:@"%@ - ",[[[currentTrack objectAtIndex:i] metadata] objectForKey:XLD_METADATA_ARTIST]]];
		}
		else [str appendString:@"Unknown Artist - "];
		if([[[currentTrack objectAtIndex:i] metadata] objectForKey:XLD_METADATA_TITLE]) {
			[str appendString:[[[currentTrack objectAtIndex:i] metadata] objectForKey:XLD_METADATA_TITLE]];
		}
		else [str appendString:@"Unknown Title"];
		[o_currentTrack setStringValue:str];
		[str release];
	}
}

- (void)setSecond:(double)sec
{
	[o_secondStr setStringValue:[NSString stringWithFormat:@"%d:%02d",(int)(sec/60),(int)(sec-(int)(sec/60)*60)]];
}

- (IBAction)play:(id)sender
{
	if(playing) [self togglePause];
	else if(currentFile && currentTrack && decoder) {
		currentIndex = 0;
		second = 0;
		[o_positionSlider setDoubleValue:0.0];
		[self setTrackNameOfIndex:0];
		[self setSecond:0];
		[self beginPlayFromFrame:0];
	}
}

- (IBAction)stop:(id)sender
{
	[self stop];
}

- (IBAction)next:(id)sender
{
	if(!playing) return;
	[lock lock];
	if(pause) {
		[o_playButton setImage:[NSImage imageNamed:@"pause_active"]];
		[o_playButton setAlternateImage:[NSImage imageNamed:@"pause_blue"]];
		pause = NO;
	}
	[self fadeout];
	AudioOutputUnitStop(outputUnit);
	//AudioUnitSetParameter(outputUnit, kAudioUnitParameterUnit_LinearGain, kAudioUnitScope_Global, 0, 1.0f, 0);
	[o_positionSlider setDoubleValue:0.0];
	second = 0;
	currentIndex = (currentIndex == [currentTrack count]-1) ? 0 : currentIndex+1;
	[self setTrackNameOfIndex:currentIndex];
	[self setSecond:0];
	seekpoint = [(XLDTrack *)[currentTrack objectAtIndex:currentIndex] index];
	[lock unlock];
}

- (IBAction)prev:(id)sender
{
	if(!playing) return;
	[lock lock];
	if(pause) {
		[o_playButton setImage:[NSImage imageNamed:@"pause_active"]];
		[o_playButton setAlternateImage:[NSImage imageNamed:@"pause_blue"]];
		pause = NO;
	}
	[self fadeout];
	AudioOutputUnitStop(outputUnit);
	//AudioUnitSetParameter(outputUnit, kAudioUnitParameterUnit_LinearGain, kAudioUnitScope_Global, 0, 1.0f, 0);
	[o_positionSlider setDoubleValue:0.0];
	second = 0;
	currentIndex = (currentIndex == 0) ? [currentTrack count]-1 : currentIndex-1;
	[self setTrackNameOfIndex:currentIndex];
	[self setSecond:0];
	seekpoint = [(XLDTrack *)[currentTrack objectAtIndex:currentIndex] index];
	[lock unlock];
}

- (IBAction)seek:(id)sender
{
	if(!playing) return;
	[lock lock];
	if(!pause) {
		[self fadeout];
		AudioOutputUnitStop(outputUnit);
		//AudioUnitSetParameter(outputUnit, kAudioUnitParameterUnit_LinearGain, kAudioUnitScope_Global, 0, 1.0f, 0);
	}
	xldoffset_t framesToPlay;
	if(currentIndex == [currentTrack count] - 1) { //last track
		framesToPlay = totalFrame - [(XLDTrack *)[currentTrack objectAtIndex:currentIndex] index];
	}
	else {
		framesToPlay = [[currentTrack objectAtIndex:currentIndex] frames];
	}
	second = [sender doubleValue]*framesToPlay/100/samplerate;
	[self setSecond:second];
	seekpoint = [(XLDTrack *)[currentTrack objectAtIndex:currentIndex] index] + [sender doubleValue]*framesToPlay/100;
	[lock unlock];
	[o_positionSlider setMouseDownFlag:NO];
}

- (id)init
{
	[super init];
	lock = [[NSLock alloc] init];
	
	[NSBundle loadNibNamed:@"Player" owner:self];
	
	NSArray* array = [NSArray arrayWithObject:NSFilenamesPboardType];
	[o_playerWindow registerForDraggedTypes:array];
	
	return self;
}

- (id)initWithDelegate:(id)del
{
	[self init];
	delegate = [del retain];
	
	return self;
}

- (void)dealloc
{
	[self stop];
	if(decoder) {
		[decoder closeFile];
		[decoder release];
	}
	[lock release];
	if(delegate) [delegate release];
	if(currentFile) [currentFile release];
	if(currentTrack) [currentTrack release];
	[super dealloc];
}

- (void)releaseDecoder
{
	[self stop];
	if(decoder) {
		[decoder closeFile];
		[decoder release];
	}
}

- (XLDErr)playFile:(NSString *)path withTrack:(NSArray *)track fromIndex:(int)idx
{
	if(playing) {
		if([path isEqualToString:currentFile] && [track isEqualTo:track]) {
			if(!pause) {
				[self fadeout];
				AudioOutputUnitStop(outputUnit);
				AudioUnitSetParameter(outputUnit, kAudioUnitParameterUnit_LinearGain, kAudioUnitScope_Global, 0, 1.0f, 0);
			}
			currentIndex = idx;
			[self setTrackNameOfIndex:idx];
			[o_positionSlider setDoubleValue:0.0];
			second = 0;
			[self setSecond:0];
			seekpoint = [(XLDTrack *)[track objectAtIndex:idx] index];
			if(pause) [self togglePause];
			return XLDNoErr;
		}
		[self stop];
		if(currentTrack) [currentTrack release];
		if(currentFile) [currentFile release];
		currentTrack = nil;
		currentFile = nil;
	}
	if(decoder) {
		[decoder closeFile];
		[decoder release];
	}
	decoder = nil;
	decoder = [[[delegate decoderCenter] preferredDecoderForFile:path] retain];
	if(!decoder) return XLDUnknownFormatErr;
	
	if(![(id <XLDDecoder>)decoder openFile:(char *)[path UTF8String]]) {
		[decoder closeFile];
		decoder = nil;
		return XLDUnknownFormatErr;
	}
	
	if(currentTrack) [currentTrack release];
	if(currentFile) [currentFile release];
	if(!track) {
		XLDTrack *trk = [[XLDTrack alloc] init];
		[trk setMetadata:[decoder metadata]];
		currentTrack = [[NSArray alloc] initWithObjects:trk,nil];
		[trk release];
	}
	else currentTrack = [track copy];
	currentFile = [path retain];
	
	currentIndex = idx;
	[self setTrackNameOfIndex:idx];
	[o_positionSlider setDoubleValue:0.0];
	second = 0;
	[self setSecond:0];
	
	return [self beginPlayFromFrame:[(XLDTrack *)[currentTrack objectAtIndex:idx] index]];
}

- (XLDErr)playRawFile:(NSString *)path withTrack:(NSArray *)track fromIndex:(int)idx withFormat:(XLDFormat)fmt endian:(XLDEndian)e offset:(int)offset
{
	if(playing) {
		if([path isEqualToString:currentFile] && track == currentTrack) {
			if(!pause) {
				[self fadeout];
				AudioOutputUnitStop(outputUnit);
				AudioUnitSetParameter(outputUnit, kAudioUnitParameterUnit_LinearGain, kAudioUnitScope_Global, 0, 1.0f, 0);
			}
			currentIndex = idx;
			[self setTrackNameOfIndex:idx];
			[o_positionSlider setDoubleValue:0.0];
			second = 0;
			[self setSecond:0];
			seekpoint = [(XLDTrack *)[track objectAtIndex:idx] index];
			if(pause) [self togglePause];
			return XLDNoErr;
		}
		[self stop];
		if(currentTrack) [currentTrack release];
		if(currentFile) [currentFile release];
		currentTrack = nil;
		currentFile = nil;
	}
	if(decoder) {
		[decoder closeFile];
		[decoder release];
	}
	decoder = nil;
	decoder = (id <XLDDecoder>)[[XLDRawDecoder alloc] initWithFormat:fmt endian:e offset:offset];
	if(!decoder) return XLDUnknownFormatErr;
	
	if(![(id <XLDDecoder>)decoder openFile:(char *)[path UTF8String]]) {
		[decoder closeFile];
		decoder = nil;
		return XLDUnknownFormatErr;
	}
	
	if(currentTrack) [currentTrack release];
	if(currentFile) [currentFile release];
	if(!track) {
		XLDTrack *trk = [[XLDTrack alloc] init];
		[trk setMetadata:[decoder metadata]];
		currentTrack = [[NSArray alloc] initWithObjects:trk,nil];
		[trk release];
	}
	else currentTrack = [track copy];
	currentFile = [path retain];
	
	currentIndex = idx;
	[self setTrackNameOfIndex:idx];
	[o_positionSlider setDoubleValue:0.0];
	second = 0;
	[self setSecond:0];
	
	return [self beginPlayFromFrame:[(XLDTrack *)[currentTrack objectAtIndex:idx] index]];
}

- (XLDErr)playDiscLayout:(XLDDiscLayout *)layout withFile:(NSString *)path withTrack:(NSArray *)track fromIndex:(int)idx
{
	if(playing) {
		if([path isEqualToString:currentFile] && [track isEqualTo:track]) {
			if(!pause) {
				[self fadeout];
				AudioOutputUnitStop(outputUnit);
				AudioUnitSetParameter(outputUnit, kAudioUnitParameterUnit_LinearGain, kAudioUnitScope_Global, 0, 1.0f, 0);
			}
			currentIndex = idx;
			[self setTrackNameOfIndex:idx];
			[o_positionSlider setDoubleValue:0.0];
			second = 0;
			[self setSecond:0];
			seekpoint = [(XLDTrack *)[track objectAtIndex:idx] index];
			if(pause) [self togglePause];
			return XLDNoErr;
		}
		[self stop];
		if(currentTrack) [currentTrack release];
		if(currentFile) [currentFile release];
		currentTrack = nil;
		currentFile = nil;
	}
	if(decoder) {
		[decoder closeFile];
		[decoder release];
	}
	decoder = nil;
	decoder = [[XLDMultipleFileWrappedDecoder alloc] initWithDiscLayout:layout];
	if(!decoder) return XLDUnknownFormatErr;
	
	if(![(id <XLDDecoder>)decoder openFile:(char *)[path UTF8String]]) {
		[decoder closeFile];
		decoder = nil;
		return XLDUnknownFormatErr;
	}
	
	if(currentTrack) [currentTrack release];
	if(currentFile) [currentFile release];
	if(!track) {
		XLDTrack *trk = [[XLDTrack alloc] init];
		[trk setMetadata:[decoder metadata]];
		currentTrack = [[NSArray alloc] initWithObjects:trk,nil];
		[trk release];
	}
	else currentTrack = [track retain];
	currentFile = [path retain];
	
	currentIndex = idx;
	[self setTrackNameOfIndex:idx];
	[o_positionSlider setDoubleValue:0.0];
	second = 0;
	[self setSecond:0];
	
	return [self beginPlayFromFrame:[(XLDTrack *)[currentTrack objectAtIndex:idx] index]];
}

- (void)play
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	int blockToDecode = bufferSize/4/channels;
	buffer_decoder = (int *)malloc(bufferSize);
	
	while(playing) {
		if(seekpoint >= 0) {
			sfifo_flush(&fifo);
			[(id <XLDDecoder>)decoder seekToFrame:seekpoint];
			currentFrame = seekpoint;
			seekpoint = -1;
			if(!pause) AudioOutputUnitStart(outputUnit);
			[self fadein];
		}
		
		int ret = [decoder decodeToBuffer:(int *)buffer_decoder frames:blockToDecode];
		while (playing && (sfifo_space(&fifo) < ret*4*channels) && seekpoint < 0) {
			usleep(10000);
		}
		if(seekpoint < 0) sfifo_write(&fifo, buffer_decoder, ret*4*channels);
		
		if(playDone) {
			playDone = NO;
			AudioOutputUnitStart(outputUnit);
		}
		//NSLog(@"%d,%d",ret,blockToDecode);
		if(ret <= 0) {
			decodeFinished = YES;
			break;
		}
		
	}
	while(!playDone && playing) usleep(10000);
	
	playThreadIsDone = YES;
	if(playing) {
		[self stop];
		[self performSelectorOnMainThread:@selector(play:)withObject:self waitUntilDone:NO];
	}
	
	[pool release];
}

- (void)stop
{
	if(!playing) return;
	[self fadeout];
	playing = NO;
	pause = NO;
	[o_playButton setImage:[NSImage imageNamed:@"play_active"]];
	[o_playButton setAlternateImage:[NSImage imageNamed:@"play_blue"]];
	AudioOutputUnitStop(outputUnit);
	AudioUnitUninitialize (outputUnit);
	CloseComponent(outputUnit);
	AudioConverterDispose(converter);
	while(!playThreadIsDone) usleep(10000);
	/*if(decoder) {
		[decoder closeFile];
		[decoder release];
	}
	decoder = nil;*/
	if(buffer) free(buffer);
	buffer = nil;
	if(buffer_decoder) free(buffer_decoder);
	buffer_decoder = nil;
	sfifo_close(&fifo);
	[o_positionSlider setDoubleValue:0.0];
	[o_currentTrack setStringValue:@""];
	[o_positionSlider setEnabled:NO];
	[o_secondStr setStringValue:@""];
}

- (void)seekToFrame:(xldoffset_t)frame
{
	[self fadeout];
	AudioOutputUnitStop(outputUnit);
	AudioUnitSetParameter(outputUnit, kAudioUnitParameterUnit_LinearGain, kAudioUnitScope_Global, 0, 1.0f, 0);
	seekpoint = frame;
}

- (void)openFileForPlay:(NSString *)path
{
	[self playFile:path withTrack:nil fromIndex:0];
}

- (void)windowWillClose:(NSNotification *)aNotification
{
	
}

- (void)showPlayer
{
	/*if(![o_playerWindow isVisible]) */[o_playerWindow makeKeyAndOrderFront:self];
}

static void updateStatus(XLDPlayer *player)
{
	if(player->currentIndex != [player->currentTrack count] - 1 && player->currentFrame >= [(XLDTrack *)[player->currentTrack objectAtIndex:player->currentIndex+1] index]) {
		player->currentIndex = player->currentIndex+1;
		player->second = 0;
		[player setTrackNameOfIndex:player->currentIndex];
		[player setSecond:player->second];
	}
	double sec = (double)(player->currentFrame - [(XLDTrack *)[player->currentTrack objectAtIndex:player->currentIndex] index])/player->samplerate;
	if(sec >= player->second + 0.5) {
		[player setSecond:sec];
		player->second = sec;
		xldoffset_t framesToPlay;
		if(player->currentIndex == [player->currentTrack count] - 1) { //last track
			framesToPlay = player->totalFrame - [(XLDTrack *)[player->currentTrack objectAtIndex:player->currentIndex] index];
		}
		else {
			framesToPlay = [[player->currentTrack objectAtIndex:player->currentIndex] frames];
		}
		double percentage = (double)(player->currentFrame - [(XLDTrack *)[player->currentTrack objectAtIndex:player->currentIndex] index]) / framesToPlay * 100.0;
		//if(percentage != player->percentage) {
			//player->percentage = percentage;
			if(![player->o_positionSlider mouseDownFlag]) [player->o_positionSlider setDoubleValue:percentage];
		//}
	}
}

static OSStatus MyACComplexInputProc   (AudioConverterRef                        inAudioConverter,
										UInt32                               *ioNumberDataPackets,
										AudioBufferList                                   *ioData,
										AudioStreamPacketDescription  **outDataPacketDescription,
										void*                                          inUserData)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	XLDPlayer *player = (XLDPlayer *)inUserData;
	
	if(player->lastBuffer) {
		player->playDone = YES;
		[pool release];
		return noErr;
	}
	
	unsigned int wanted = *ioNumberDataPackets * player->channels * 4;
	unsigned char *dest;
	unsigned int read;
	
	if(player->bufferSize < wanted) {
		player->buffer = realloc(player->buffer, wanted);
		player->bufferSize = wanted;
	}
	dest = player->buffer;
	
	if (sfifo_used(&player->fifo) < wanted) {
		if(!player->decodeFinished) {
			[pool release];
			return -1;
		}
		wanted = sfifo_used(&player->fifo);
		player->lastBuffer = YES;
	}
	
	read = sfifo_read(&player->fifo, dest, wanted);
	
	ioData->mBuffers[0].mDataByteSize = read;
	ioData->mBuffers[0].mData = dest;
	
	player->currentFrame += *ioNumberDataPackets;
	updateStatus(player);
	
	[pool release];
	return noErr;
}

static OSStatus MyFileRenderProc(void *inRefCon, AudioUnitRenderActionFlags    *inActionFlags,
								 const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber,
								 UInt32 inNumFrames, AudioBufferList *ioData)
{
	OSStatus err = noErr;
	AudioStreamPacketDescription* outPacketDescription = NULL;
	XLDPlayer *player = (XLDPlayer *)inRefCon;
	
	err = AudioConverterFillComplexBuffer(player->converter, MyACComplexInputProc, inRefCon, &inNumFrames, ioData, outPacketDescription);
	
	return err;
}

@end
