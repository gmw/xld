//
//  XLDAccurateRipChecker.m
//  XLD
//
//  Created by tmkk on 08/08/22.
//  Copyright 2008 tmkk. All rights reserved.
//
//  Access to AccurateRip is regulated, see  http://www.accuraterip.com/3rdparty-access.htm for details.

#import <sys/time.h>
#import "XLDAccurateRipChecker.h"
#import "XLDecoderCenter.h"
#import "XLDDecoder.h"
#import "XLDTrack.h"
#import "XLDController.h"
#import "XLDAccurateRipDB.h"

static NSString *framesToMSFStr(xldoffset_t frames, int samplerate)
{
	int min = frames/samplerate/60;
	frames -= min*samplerate*60;
	int sec = frames/samplerate;
	frames -= sec*samplerate;
	int f = frames*75/samplerate;
	return [NSString stringWithFormat:@"%02d:%02d:%02d",min,sec,f];
}

static int intSort(id num1, id num2, void *context)
{
    int v1 = [num1 intValue];
    int v2 = [num2 intValue];
	
    if (v1 < v2)
        return NSOrderedDescending;
    else if (v1 > v2)
        return NSOrderedAscending;
    else
        return NSOrderedSame;
}

@implementation XLDAccurateRipChecker

- (id)init
{
	unsigned int i, k, value;
	[super init];
	[NSBundle loadNibNamed:@"ARChecker" owner:self];
	detectedOffset = [[NSMutableDictionary alloc] init];
	trackList = [[NSMutableArray alloc] init];
	preTrackSamples = calloc(1,588*4*2*sizeof(int));
	postTrackSamples = calloc(1,588*4*2*sizeof(int));
	rg = (replaygain_t *)malloc(sizeof(replaygain_t));
	gain_init_analysis(rg,44100);
	
	for(i = 0; i < 256; ++i){
		value = i;
		for(k = 0; k < 8; ++k){
			if(value & 1)
				value = 0xEDB88320 ^ (value >> 1);
			else
				value >>= 1;
		}
		crc32Table[i] = value;
	}	
	
	return self;
}

static BOOL dumpAccurateRipLog(NSMutableString *out, checkResult *result)
{
	BOOL ret = YES;
	result->ARStatus = [result->validator accurateRipStatus];
	int totalSubmissions = [result->validator totalARSubmissions];
#if 1
	if(result->ARStatus == XLDARStatusDifferentPressingMatch ||
	   result->ARStatus == XLDARStatusBothVerDifferentPressingMatch) {
		[out appendString:[NSString stringWithFormat:@"    AccurateRip v1 signature : %08X (%08X w/correction)\n",[result->validator AR1CRC],[result->validator offsetModifiedAR1CRC]]];
	}
	else {
		[out appendString:[NSString stringWithFormat:@"    AccurateRip v1 signature : %08X\n",[result->validator AR1CRC]]];
	}
	if(result->ARStatus == XLDARStatusVer2DifferentPressingMatch ||
	   result->ARStatus == XLDARStatusBothVerDifferentPressingMatch) {
		[out appendString:[NSString stringWithFormat:@"    AccurateRip v2 signature : %08X (%08X w/correction)\n",[result->validator AR2CRC],[result->validator offsetModifiedAR2CRC]]];
	}
	else {
		[out appendString:[NSString stringWithFormat:@"    AccurateRip v2 signature : %08X\n",[result->validator AR2CRC]]];
	}
	if(result->ARStatus == XLDARStatusNotFound) {
		[out appendString:@"        ->Track not present in AccurateRip database.\n"];
	}
	else if(result->ARStatus == XLDARStatusMatch || result->ARStatus == XLDARStatusDifferentPressingMatch) {
		result->ARConfidence = [result->validator AR1Confidence];
		if(result->ARStatus == XLDARStatusMatch)
			[out appendString:[NSString stringWithFormat:@"        ->Accurately ripped (v1, confidence %d/%d)\n",result->ARConfidence,totalSubmissions]];
		else
			[out appendString:[NSString stringWithFormat:@"        ->Accurately ripped with different offset (v1, confidence %d/%d, offset %+d)\n",result->ARConfidence,totalSubmissions,[result->validator modifiedAR1Offset]]];
	}
	else if(result->ARStatus == XLDARStatusVer2Match || result->ARStatus == XLDARStatusVer2DifferentPressingMatch) {
		result->ARConfidence = [result->validator AR2Confidence];
		if(result->ARStatus == XLDARStatusVer2Match)
			[out appendString:[NSString stringWithFormat:@"        ->Accurately ripped (v2, confidence %d/%d)\n",result->ARConfidence,totalSubmissions]];
		else
			[out appendString:[NSString stringWithFormat:@"        ->Accurately ripped with different offset (v2, confidence %d/%d, offset %+d)\n",result->ARConfidence,totalSubmissions,[result->validator modifiedAR2Offset]]];
	}
	else if(result->ARStatus == XLDARStatusBothVerMatch || result->ARStatus == XLDARStatusBothVerDifferentPressingMatch) {
		result->ARConfidence = [result->validator AR1Confidence] + [result->validator AR2Confidence];
		if(result->ARStatus == XLDARStatusBothVerMatch)
			[out appendString:[NSString stringWithFormat:@"        ->Accurately ripped (v1+v2, confidence %d+%d/%d)\n",[result->validator AR1Confidence],[result->validator AR2Confidence],totalSubmissions]];
		else
			[out appendString:[NSString stringWithFormat:@"        ->Accurately ripped with different offset (v1+v2, confidence %d+%d/%d, offset %+d)\n",[result->validator AR1Confidence],[result->validator AR2Confidence],totalSubmissions,[result->validator modifiedAR2Offset]]];
	}
	else {
		ret = NO;
		[out appendString:[NSString stringWithFormat:@"        ->Rip may not be accurate (total %d submission%s).\n",totalSubmissions,totalSubmissions>1?"s":""]];
	}
#else
	if(result->ARStatus == XLDARStatusVer2Match || result->ARStatus == XLDARStatusVer2DifferentPressingMatch)
		[out appendString:[NSString stringWithFormat:@"    AccurateRip signature  : %08X\n",[result->validator AR2CRC]]];
	else
		[out appendString:[NSString stringWithFormat:@"    AccurateRip signature  : %08X\n",[result->validator AR1CRC]]];
	if(result->ARStatus == XLDARStatusNotFound) {
		[out appendString:@"        ->Track not present in AccurateRip database.\n"];
	}
	else if(result->ARStatus == XLDARStatusMatch) {
		result->ARConfidence = [result->validator AR1Confidence];
		[out appendString:[NSString stringWithFormat:@"        ->Accurately ripped! (confidence %d/%d)\n",result->ARConfidence,totalSubmissions]];
	}
	else if(result->ARStatus == XLDARStatusVer2Match) {
		result->ARConfidence = [result->validator AR2Confidence];
		[out appendString:[NSString stringWithFormat:@"        ->Accurately ripped! (AR2, confidence %d/%d)\n",result->ARConfidence,totalSubmissions]];
	}
	else if(result->ARStatus == XLDARStatusDifferentPressingMatch) {
		result->ARConfidence = [result->validator AR1Confidence];
		[out appendString:[NSString stringWithFormat:@"        ->Accurately ripped! (confidence %d/%d)\n",result->ARConfidence,totalSubmissions]];
		[out appendString:@"          (matched with the different offset correction value;\n"];
		[out appendString:[NSString stringWithFormat:@"           calculated using an additional offset of %d;\n",[result->validator modifiedOffset]]];
		[out appendString:[NSString stringWithFormat:@"           the signature after correction is: %08X)\n",[result->validator offsetModifiedAR1CRC]]];
	}
	else if(result->ARStatus == XLDARStatusVer2DifferentPressingMatch) {
		result->ARConfidence = [result->validator AR2Confidence];
		[out appendString:[NSString stringWithFormat:@"        ->Accurately ripped! (AR2, confidence %d/%d)\n",result->ARConfidence,totalSubmissions]];
		[out appendString:@"          (matched with the different offset correction value;\n"];
		[out appendString:[NSString stringWithFormat:@"           calculated using an additional offset of %d;\n",[result->validator modifiedOffset]]];
		[out appendString:[NSString stringWithFormat:@"           the signature after correction is: %08X)\n",[result->validator offsetModifiedAR2CRC]]];
	}
	else {
		ret = NO;
		[out appendString:[NSString stringWithFormat:@"        ->Rip may not be accurate (total %d submission%s).\n",totalSubmissions,totalSubmissions>1?"s":""]];
	}
#endif
	return ret;
}	

- (id)initWithTracks:(NSArray *)tracks totalFrames:(xldoffset_t)frame
{
	[self init];
	results = (checkResult *)calloc(1,sizeof(checkResult)*([tracks count]));
	trackNumber = [tracks count];
	int i;
	for(i=0;i<trackNumber;i++) {
		[trackList addObject:[tracks objectAtIndex:i]];
		results[i].index = [(XLDTrack *)[tracks objectAtIndex:i] index];
		results[i].detectedOffset = [[NSMutableDictionary alloc] init];
		results[i].validator = [[XLDTrackValidator alloc] init];
		[results[i].validator setTrackNumber:i+1];
		if(i == 0) [results[i].validator setIsFirstTrack:YES];
		if(i == (trackNumber-1)) {
			results[i].length = frame - [(XLDTrack *)[tracks objectAtIndex:i] index];
			[results[i].validator setIsLastTrack:YES];
		}
		else {
			results[i].length = [(XLDTrack *)[tracks objectAtIndex:i] frames] + [(XLDTrack *)[tracks objectAtIndex:i+1] gap];
		}
		[results[i].validator setTrackLength:results[i].length];
	}
	crc32_global = 0xFFFFFFFF;
	crc32_eac_global = 0xFFFFFFFF;
	
	totalFrames = frame - results[0].index;
	
	return self;
}

- (void)dealloc
{
	int i;
	for(i=0;i<trackNumber;i++) {
		[results[i].detectedOffset release];
		[results[i].validator release];
	}
	if(results) free(results);
	if(database) [database release];
	if(delegate) [delegate release];
	if(decoder) [decoder release];
	[detectedOffset release];
	[trackList release];
	free(preTrackSamples);
	free(postTrackSamples);
	free(rg);
	[super dealloc];
}

- (void)startCheckingForFile:(NSString *)path withDecoder:(id)decoderObj
{
	decoder = [decoderObj retain];
	if(![(id <XLDDecoder>)decoder openFile:(char *)[path UTF8String]]) {
		fprintf(stderr,"error: cannot open\n");
		[decoder closeFile];
		[delegate accurateRipCheckDidFinish:self];
		return;
	}
	
	if(([(id <XLDDecoder>)decoder samplerate] != 44100) || ([(id <XLDDecoder>)decoder channels] != 2)) {
		fprintf(stderr,"error: not a CD format\n");
		[decoder closeFile];
		[delegate accurateRipCheckDidFinish:self];
		return;
	}
	
	[decoder seekToFrame:results[0].index];
	if([(id <XLDDecoder>)decoder error]) {
		fprintf(stderr,"error: cannot seek\n");
		[decoder closeFile];
		[delegate accurateRipCheckDidFinish:self];
		return;
	}
	
	[o_progress setDoubleValue:0.0];
	[o_panel center];
	[o_message setStringValue:LS(@"calculating hash...")];
	[o_panel setTitle:[path lastPathComponent]];
	[o_panel makeKeyAndOrderFront:nil];
	
	running = YES;
	[NSThread detachNewThreadSelector:@selector(check) toTarget:self withObject:nil];
}

- (void)startOffsetCheckingForFile:(NSString *)path withDecoder:(id)decoderObj
{
	decoder = [decoderObj retain];
	if(![(id <XLDDecoder>)decoder openFile:(char *)[path UTF8String]]) {
		fprintf(stderr,"error: cannot open\n");
		[decoder closeFile];
		[delegate accurateRipCheckDidFinish:self];
		return;
	}
	
	if(([(id <XLDDecoder>)decoder samplerate] != 44100) || ([(id <XLDDecoder>)decoder channels] != 2)) {
		[decoder closeFile];
		[delegate accurateRipCheckDidFinish:self];
		return;
	}
	
	[decoder seekToFrame:results[0].index];
	if([(id <XLDDecoder>)decoder error]) {
		fprintf(stderr,"error: cannot seek\n");
		[decoder closeFile];
		[delegate accurateRipCheckDidFinish:self];
		return;
	}
	
	[o_progress setDoubleValue:0.0];
	[o_panel center];
	[o_message setStringValue:LS(@"detecting offset...")];
	[o_panel setTitle:[path lastPathComponent]];
	[o_panel makeKeyAndOrderFront:nil];
	
	running = YES;
	[NSThread detachNewThreadSelector:@selector(checkOffset) toTarget:self withObject:nil];
}

- (void)startReplayGainScanningForFile:(NSString *)path withDecoder:(id)decoderObj
{
	decoder = [decoderObj retain];
	if(![(id <XLDDecoder>)decoder openFile:(char *)[path UTF8String]]) {
		fprintf(stderr,"error: cannot open\n");
		[decoder closeFile];
		[delegate accurateRipCheckDidFinish:self];
		return;
	}
	
	if(([(id <XLDDecoder>)decoder samplerate] != 44100) || ([(id <XLDDecoder>)decoder channels] != 2)) {
		[decoder closeFile];
		[delegate accurateRipCheckDidFinish:self];
		return;
	}
	
	[decoder seekToFrame:results[0].index];
	if([(id <XLDDecoder>)decoder error]) {
		fprintf(stderr,"error: cannot seek\n");
		[decoder closeFile];
		[delegate accurateRipCheckDidFinish:self];
		return;
	}
	
	[o_progress setDoubleValue:0.0];
	[o_panel center];
	[o_message setStringValue:LS(@"scanning replaygain...")];
	[o_panel setTitle:[path lastPathComponent]];
	[o_panel makeKeyAndOrderFront:nil];
	
	running = YES;
	[NSThread detachNewThreadSelector:@selector(scanReplayGain) toTarget:self withObject:nil];
}

- (void)updateStatus
{
	[o_progress setDoubleValue:percent];
}

- (void)commitBufferForTrack:(int)currentTrack withBuffer:(int *)buffer length:(int)ret currentFrame:(xldoffset_t)currentFrame
{
	int i;
	[results[currentTrack-1].validator commitSamples:buffer length:ret];
	for(i=0;i<ret;i++) {
		unsigned int sample = ((buffer[i*2] >> 16)&0xffff) | (buffer[i*2+1] & 0xffff0000);
		
		if((currentTrack <= trackNumber) && (currentFrame >=results[currentTrack-1].length-2352)) {
			preTrackSamples[(2352+currentFrame - results[currentTrack-1].length)*2] = buffer[i*2];
			preTrackSamples[(2352+currentFrame - results[currentTrack-1].length)*2+1] = buffer[i*2+1];
		}
		if(currentFrame < 2352) {
			postTrackSamples[currentFrame*2] = buffer[i*2];
			postTrackSamples[currentFrame*2+1] = buffer[i*2+1];
		}
		
		crc32_global = (crc32_global >> 8) ^ crc32Table[(crc32_global ^ (sample)) & 0xFF];
		crc32_global = (crc32_global >> 8) ^ crc32Table[(crc32_global ^ (sample>>8)) & 0xFF];
		crc32_global = (crc32_global >> 8) ^ crc32Table[(crc32_global ^ (sample>>16)) & 0xFF];
		crc32_global = (crc32_global >> 8) ^ crc32Table[(crc32_global ^ (sample>>24)) & 0xFF];
		if(buffer[i*2] != 0) {
			crc32_eac_global = (crc32_eac_global >> 8) ^ crc32Table[(crc32_eac_global ^ (sample)) & 0xFF];
			crc32_eac_global = (crc32_eac_global >> 8) ^ crc32Table[(crc32_eac_global ^ (sample>>8)) & 0xFF];
		}
		if(buffer[i*2+1] != 0) {
			crc32_eac_global = (crc32_eac_global >> 8) ^ crc32Table[(crc32_eac_global ^ (sample>>16)) & 0xFF];
			crc32_eac_global = (crc32_eac_global >> 8) ^ crc32Table[(crc32_eac_global ^ (sample>>24)) & 0xFF];
		}
		
		currentFrame++;
		
		if((currentTrack > 1) && (currentFrame == 2352)) {
			[results[currentTrack-2].validator commitPostTrackSamples:postTrackSamples];
		}
		else if(currentTrack < trackNumber && currentFrame == results[currentTrack-1].length) {
			[results[currentTrack].validator commitPreTrackSamples:preTrackSamples];
		}
	}
}

- (void)check
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	struct timeval tv1,tv2;
	xldoffset_t framesToCopy = results[0].length;
	xldoffset_t currentFrame = 0;
	int *buffer = (int *)malloc(8192 * 2 * 4);
	int currentTrack = 1;
	
	results[0].enabled = YES;
	
	gettimeofday(&tv1,NULL);
	do {
		if(stop) {
			results[currentTrack-1].cancelled = YES;
			goto finish;
		}
		int ret = [decoder decodeToBuffer:(int *)buffer frames:framesToCopy>8192 ? 8192 : framesToCopy];
		if([(id <XLDDecoder>)decoder error]) {
			fprintf(stderr,"error: cannot decode\n");
			break;
		}
		if(ret > 0) {
			[self commitBufferForTrack:currentTrack withBuffer:buffer length:ret currentFrame:currentFrame];
			gain_analyze_samples_interleaved_int32(rg,buffer,ret,2);
		}
		framesToCopy -= ret;
		currentFrame += ret;
		
		gettimeofday(&tv2,NULL);
		double elapsed1 = tv2.tv_sec-tv1.tv_sec + (tv2.tv_usec-tv1.tv_usec)*0.000001;
		if(elapsed1 > 0.25) {
			percent = 100.0*(((double)results[currentTrack-1].index + (double)currentFrame - (double)results[0].index))/(double)totalFrames;
			[self performSelectorOnMainThread:@selector(updateStatus) withObject:nil waitUntilDone:YES];
			tv1 = tv2;
		}
		
		if(!framesToCopy) {
			results[currentTrack-1].trackGain = PINK_REF-gain_get_title(rg);
			results[currentTrack-1].peak = peak_get_title(rg);
			currentFrame = 0;
			currentTrack++;
			if(currentTrack <= trackNumber) {
				framesToCopy = results[currentTrack-1].length;
				results[currentTrack-1].enabled = YES;
			}
		}
		
		if(currentTrack > trackNumber) {
			[o_progress setDoubleValue:100.0];
			break;
		}
	} while(1);
	
finish:
		free(buffer);
	[decoder closeFile];
	[o_panel close];
	[delegate performSelectorOnMainThread:@selector(accurateRipCheckDidFinish:) withObject:self waitUntilDone:NO];
	[pool release];
}

- (void)fillBufferForTrack:(int)currentTrack
{
	int *tmp = malloc(2352*4*2);
	if(currentTrack != 1) {
		[decoder seekToFrame:results[currentTrack-1].index-2352];
		[decoder decodeToBuffer:tmp frames:2352];
		[results[currentTrack-1].validator commitPreTrackSamples:tmp];
	}
	if(currentTrack != trackNumber) {
		[decoder seekToFrame:results[currentTrack].index];
		[decoder decodeToBuffer:tmp frames:2352];
		[results[currentTrack-1].validator commitPostTrackSamples:tmp];
	}
	free(tmp);
}

- (void)checkOffset
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	xldoffset_t framesToCopy;
	xldoffset_t currentFrame = 0;
	struct timeval tv1,tv2;
	int *buffer = (int *)malloc(8192 * 2 * 4);
	int i;
	int currentTrack = 1;
	
	int minLength = 0x7FFFFFFF;
	for(i=1;i<trackNumber-1;i++) {
		if((minLength > results[i].length) && [database hasValidDataForTrack:i+1]) {
			minLength = results[i].length;
			currentTrack = i+1;
		}
	}
	
	framesToCopy = results[currentTrack-1].length;
	
	[self fillBufferForTrack:currentTrack];
	
	[decoder seekToFrame:results[currentTrack-1].index];
	
	gettimeofday(&tv1,NULL);
	do {
		if(stop) {
			goto finish;
		}
		int getLength = (framesToCopy < 8192) ? framesToCopy : 8192;
		int ret = [decoder decodeToBuffer:(int *)buffer frames:getLength];
		if([(id <XLDDecoder>)decoder error]) {
			fprintf(stderr,"error: cannot decode\n");
			break;
		}
		
		if(ret > 0) {
			[results[currentTrack-1].validator commitSamples:buffer length:ret];
		}
		framesToCopy -= ret;
		currentFrame += ret;
		
		gettimeofday(&tv2,NULL);
		double elapsed1 = tv2.tv_sec-tv1.tv_sec + (tv2.tv_usec-tv1.tv_usec)*0.000001;
		if(elapsed1 > 0.25) {
			percent = 100.0*(double)currentFrame/(double)results[currentTrack-1].length;
			[self performSelectorOnMainThread:@selector(updateStatus) withObject:nil waitUntilDone:YES];
			tv1 = tv2;
		}
		
		if(!framesToCopy) {
			break;
		}
		if(!ret) break;
	} while(1);
	
	if([results[currentTrack-1].validator detectedOffsetDictionary])
		[detectedOffset setDictionary:[results[currentTrack-1].validator detectedOffsetDictionary]];
	
finish:
		free(buffer);
	[decoder closeFile];
	[o_panel close];
	[delegate performSelectorOnMainThread:@selector(offsetCheckDidFinish:) withObject:self waitUntilDone:NO];
	[pool release];
}

- (void)scanReplayGain
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	struct timeval tv1,tv2;
	xldoffset_t framesToCopy = results[0].length;
	xldoffset_t currentFrame = 0;
	int *buffer = (int *)malloc(8192 * 2 * 4);
	int currentTrack = 1;
	
	results[0].enabled = YES;
	
	gettimeofday(&tv1,NULL);
	do {
		if(stop) {
			results[currentTrack-1].cancelled = YES;
			goto finish;
		}
		int ret = [decoder decodeToBuffer:(int *)buffer frames:(framesToCopy < 8192) ? framesToCopy : 8192];
		if([(id <XLDDecoder>)decoder error]) {
			fprintf(stderr,"error: cannot decode\n");
			break;
		}
		if(ret > 0) {
			int i;
			[results[currentTrack-1].validator commitSamples:buffer length:ret];
			for(i=0;i<ret;i++) {
				unsigned int sample = ((buffer[i*2] >> 16)&0xffff) | (buffer[i*2+1] & 0xffff0000);
				crc32_global = (crc32_global >> 8) ^ crc32Table[(crc32_global ^ (sample)) & 0xFF];
				crc32_global = (crc32_global >> 8) ^ crc32Table[(crc32_global ^ (sample>>8)) & 0xFF];
				crc32_global = (crc32_global >> 8) ^ crc32Table[(crc32_global ^ (sample>>16)) & 0xFF];
				crc32_global = (crc32_global >> 8) ^ crc32Table[(crc32_global ^ (sample>>24)) & 0xFF];
				if(buffer[i*2] != 0) {
					crc32_eac_global = (crc32_eac_global >> 8) ^ crc32Table[(crc32_eac_global ^ (sample)) & 0xFF];
					crc32_eac_global = (crc32_eac_global >> 8) ^ crc32Table[(crc32_eac_global ^ (sample>>8)) & 0xFF];
				}
				if(buffer[i*2+1] != 0) {
					crc32_eac_global = (crc32_eac_global >> 8) ^ crc32Table[(crc32_eac_global ^ (sample>>16)) & 0xFF];
					crc32_eac_global = (crc32_eac_global >> 8) ^ crc32Table[(crc32_eac_global ^ (sample>>24)) & 0xFF];
				}
			}
			gain_analyze_samples_interleaved_int32(rg,buffer,ret,2);
		}
		framesToCopy -= ret;
		currentFrame += ret;
		
		gettimeofday(&tv2,NULL);
		double elapsed1 = tv2.tv_sec-tv1.tv_sec + (tv2.tv_usec-tv1.tv_usec)*0.000001;
		if(elapsed1 > 0.25) {
			percent = 100.0*(((double)results[currentTrack-1].index + (double)currentFrame - (double)results[0].index))/(double)totalFrames;
			[self performSelectorOnMainThread:@selector(updateStatus) withObject:nil waitUntilDone:YES];
			tv1 = tv2;
		}
		
		if(!framesToCopy) {
			results[currentTrack-1].trackGain = PINK_REF-gain_get_title(rg);
			results[currentTrack-1].peak = peak_get_title(rg);
			currentFrame = 0;
			currentTrack++;
			if(currentTrack <= trackNumber) {
				framesToCopy = results[currentTrack-1].length;
				results[currentTrack-1].enabled = YES;
			}
		}
		
		if(currentTrack > trackNumber) {
			[o_progress setDoubleValue:100.0];
			break;
		}
	} while(1);
	
finish:
		free(buffer);
	[decoder closeFile];
	[o_panel close];
	[delegate performSelectorOnMainThread:@selector(replayGainScanningDidFinish:) withObject:self waitUntilDone:NO];
	[pool release];
}

- (void)setAccurateRipDB:(id)db
{
	if(database) [database release];
	database = [db retain];
	int i;
	for(i=0;i<trackNumber;i++) {
		[results[i].validator setAccurateRipDB:db];
	}
}

- (void)setDelegate:(id)del
{
	if(delegate) [delegate release];
	delegate = [del retain];
}

- (IBAction)cancel:(id)sender
{
	stop = YES;
}

- (NSString *)logStr
{
	if(!results) return nil;
	if(!running) return nil;
	int i,j;
	NSMutableString *out = [[NSMutableString alloc] init];
	[out appendString:[NSString stringWithFormat:@"X Lossless Decoder version %@ (%@)\n\n",[[[NSBundle mainBundle] infoDictionary] valueForKey:@"CFBundleShortVersionString"],[[[NSBundle mainBundle] infoDictionary] valueForKey:@"CFBundleVersion"]]];
	[out appendString:@"XLD AccurateRip checking logfile\n\n"];
	[out appendString:@"TOC of the selected file\n"];
	[out appendString:@"     Track |   Start  |  Length  | Start sector | End sector \n"];
	[out appendString:@"    ---------------------------------------------------------\n"];
	for(i=0;i<trackNumber;i++) {
		[out appendString:[NSString stringWithFormat:@"      % 3d  | %@ | %@ |   % 7lld    |  % 7lld   \n",i+1,framesToMSFStr(results[i].index,44100),framesToMSFStr(results[i].length,44100),results[i].index/588,(results[i].index+results[i].length)/588-1]];
	}
	[out appendString:@"\n"];
	
	for(i=0;i<trackNumber;i++) {
		NSDictionary *dic = [results[i].validator detectedOffsetDictionary];
		if(!dic) continue;
		NSArray *offsetList = [dic allKeys];
		for(j=0;j<[offsetList count];j++) {
			id currentOffset = [offsetList objectAtIndex:j];
			if([detectedOffset objectForKey:currentOffset]) {
				int currentConfidence = [[dic objectForKey:currentOffset] intValue];
				int existingConfidence = [[detectedOffset objectForKey:currentOffset] intValue];
				if(currentConfidence < existingConfidence) continue;
			}
			[detectedOffset setObject:[dic objectForKey:currentOffset] forKey:currentOffset];
		}
	}
	if([detectedOffset count]) {
		NSArray *confidenceList = [[detectedOffset allValues] sortedArrayUsingFunction:intSort context:NULL];
		NSArray *offsetList = [detectedOffset allKeys];
		int n=1;
		int previousConfidence = -1;
		for(j=0;j<[confidenceList count];j++) {
			int confidence = [[confidenceList objectAtIndex:j] intValue];
			if(confidence == previousConfidence) continue;
			for(i=0;i<[offsetList count];i++) {
				int value = [[detectedOffset objectForKey:[offsetList objectAtIndex:i]] intValue];
				if((value == confidence) && [[offsetList objectAtIndex:i] intValue]) {
					if(n==1) [out appendString:@"List of alternate offset correction values\n"];
					NSString *str = [NSString stringWithFormat:@"    (%d) %d (confidence %d)\n",n++,[[offsetList objectAtIndex:i] intValue],confidence];
					[out appendString:str];
				}
			}
			previousConfidence = confidence;
		}
		if(n>1) [out appendString:@"\n"];
	}
	
	int ARStatusPos = [out length];
	
	if(!stop) {
		float albumGain = PINK_REF-gain_get_album(rg);
		float albumPeak = peak_get_album(rg);
		for(i=0;i<[trackList count];i++) {
			[[[trackList objectAtIndex:i] metadata] setObject:[NSNumber numberWithFloat:albumGain] forKey:XLD_METADATA_REPLAYGAIN_ALBUM_GAIN];
			[[[trackList objectAtIndex:i] metadata] setObject:[NSNumber numberWithFloat:albumPeak] forKey:XLD_METADATA_REPLAYGAIN_ALBUM_PEAK];
		}
		[out appendString:@"All Tracks\n"];
		[out appendString:[NSString stringWithFormat:@"    Album gain               : %.2f dB\n",albumGain]];
		[out appendString:[NSString stringWithFormat:@"    Peak                     : %f\n",albumPeak]];
		[out appendString:[NSString stringWithFormat:@"    CRC32 hash               : %08X\n",crc32_global^0xFFFFFFFF]];
		[out appendString:[NSString stringWithFormat:@"    CRC32 hash (skip zero)   : %08X\n\n",crc32_eac_global^0xFFFFFFFF]];
	}
	
	for(i=0;i<trackNumber;i++) {
		if(!results[i].enabled) continue;
		[out appendString:[NSString stringWithFormat:@"Track %02d\n",i+1]];
		if(results[i].cancelled) {
			[out appendString:@"    (cancelled by user)\n\n"];
			continue;
		}
		[[[trackList objectAtIndex:i] metadata] setObject:[NSNumber numberWithFloat:results[i].trackGain] forKey:XLD_METADATA_REPLAYGAIN_TRACK_GAIN];
		[[[trackList objectAtIndex:i] metadata] setObject:[NSNumber numberWithFloat:results[i].peak] forKey:XLD_METADATA_REPLAYGAIN_TRACK_PEAK];
		[out appendString:[NSString stringWithFormat:@"    Track gain               : %.2f dB\n",results[i].trackGain]];
		[out appendString:[NSString stringWithFormat:@"    Peak                     : %f\n",results[i].peak]];
		[out appendString:[NSString stringWithFormat:@"    CRC32 hash               : %08X\n",[results[i].validator crc32]]];
		[out appendString:[NSString stringWithFormat:@"    CRC32 hash (skip zero)   : %08X\n",[results[i].validator crc32EAC]]];
		dumpAccurateRipLog(out, &results[i]);
		[out appendString:@"\n"];
	}
	
	if(database) {
		int checked = 0;
		int good = 0;
		int bad = 0;
		int notfound = 0;
		NSMutableString *status = [NSMutableString string];
		[status appendString:[NSString stringWithFormat:@"AccurateRip Summary (DiscID: %@)\n",[database discID]]];
		for(i=0;i<trackNumber;i++) {
			if(results[i].ARStatus == XLDARStatusNoQuery) continue;
			int totalSubmissions = [results[i].validator totalARSubmissions];
			[status appendString:[NSString stringWithFormat:@"    Track %02d : ",i+1]];
			if(results[i].ARStatus == XLDARStatusMatch) {
				[status appendString:[NSString stringWithFormat:@"OK (v1, confidence %d/%d)\n",results[i].ARConfidence,totalSubmissions]];
				good++;
			}
			else if(results[i].ARStatus == XLDARStatusVer2Match) {
				[status appendString:[NSString stringWithFormat:@"OK (v2, confidence %d/%d)\n",results[i].ARConfidence,totalSubmissions]];
				good++;
			}
			else if(results[i].ARStatus == XLDARStatusBothVerMatch) {
				[status appendString:[NSString stringWithFormat:@"OK (v1+v2, confidence %d/%d)\n",results[i].ARConfidence,totalSubmissions]];
				good++;
			}
			else if(results[i].ARStatus == XLDARStatusDifferentPressingMatch) {
				[status appendString:[NSString stringWithFormat:@"OK (v1, confidence %d/%d, with different offset)\n",results[i].ARConfidence,totalSubmissions]];
				good++;
			}
			else if(results[i].ARStatus == XLDARStatusVer2DifferentPressingMatch) {
				[status appendString:[NSString stringWithFormat:@"OK (v2, confidence %d/%d, with different offset)\n",results[i].ARConfidence,totalSubmissions]];
				good++;
			}
			else if(results[i].ARStatus == XLDARStatusBothVerDifferentPressingMatch) {
				[status appendString:[NSString stringWithFormat:@"OK (v1+v2, confidence %d/%d, with different offset)\n",results[i].ARConfidence,totalSubmissions]];
				good++;
			}
			else if(results[i].ARStatus == XLDARStatusMismatch) {
				[status appendString:[NSString stringWithFormat:@"NG (total %d submission%s)\n",totalSubmissions,totalSubmissions>1?"s":""]];
				bad++;
			}
			else if(results[i].ARStatus == XLDARStatusNotFound) {
				[status appendString:@"Not Found\n"];
				notfound++;
			}
			checked++;
		}
		if(!stop) {
			if(checked == good) [status appendString:@"        ->All tracks accurately ripped.\n\n"];
			else if(notfound && bad) [status appendString:[NSString stringWithFormat:@"        ->%d track%s accurately ripped, %d track%s not, %d track%s not found\n\n",good,good>1?"s":"",bad,bad>1?"s":"",notfound,notfound>1?"s":""]];
			else if(bad) [status appendString:[NSString stringWithFormat:@"        ->%d track%s accurately ripped, %d track%s not\n\n",good,good>1?"s":"",bad,bad>1?"s":""]];
			else [status appendString:[NSString stringWithFormat:@"        ->%d track%s accurately ripped, %d track%s not found\n\n",good,good>1?"s":"",notfound,notfound>1?"s":""]];
		}
		else [status appendString:@"\n"];
		[out insertString:status atIndex:ARStatusPos];
	}
	else [out insertString:@"AccurateRip Summary\n    Disc not found in AccurateRip DB.\n\n"  atIndex:ARStatusPos];
	
	[out appendString:@"End of status report\n"];
	
	return [out autorelease];
}

- (NSString *)logStrForReplayGainScanner
{
	if(!results) return nil;
	if(!running) return nil;
	int i;
	NSMutableString *out = [[NSMutableString alloc] init];
	[out appendString:[NSString stringWithFormat:@"X Lossless Decoder version %@ (%@)\n\n",[[[NSBundle mainBundle] infoDictionary] valueForKey:@"CFBundleShortVersionString"],[[[NSBundle mainBundle] infoDictionary] valueForKey:@"CFBundleVersion"]]];
	[out appendString:@"XLD ReplayGain scanning logfile\n\n"];
	[out appendString:@"TOC of the selected file\n"];
	[out appendString:@"     Track |   Start  |  Length  | Start sector | End sector \n"];
	[out appendString:@"    ---------------------------------------------------------\n"];
	for(i=0;i<trackNumber;i++) {
		[out appendString:[NSString stringWithFormat:@"      % 3d  | %@ | %@ |   % 7lld    |  % 7lld   \n",i+1,framesToMSFStr(results[i].index,44100),framesToMSFStr(results[i].length,44100),results[i].index/588,(results[i].index+results[i].length)/588-1]];
	}
	[out appendString:@"\n"];
	
	if(!stop) {
		float albumGain = PINK_REF-gain_get_album(rg);
		float albumPeak = peak_get_album(rg);
		for(i=0;i<[trackList count];i++) {
			[[[trackList objectAtIndex:i] metadata] setObject:[NSNumber numberWithFloat:albumGain] forKey:XLD_METADATA_REPLAYGAIN_ALBUM_GAIN];
			[[[trackList objectAtIndex:i] metadata] setObject:[NSNumber numberWithFloat:albumPeak] forKey:XLD_METADATA_REPLAYGAIN_ALBUM_PEAK];
		}
		[out appendString:@"All Tracks\n"];
		[out appendString:[NSString stringWithFormat:@"    Album gain             : %.2f dB\n",albumGain]];
		[out appendString:[NSString stringWithFormat:@"    Peak                   : %f\n",albumPeak]];
		[out appendString:[NSString stringWithFormat:@"    CRC32 hash             : %08X\n",crc32_global^0xFFFFFFFF]];
		[out appendString:[NSString stringWithFormat:@"    CRC32 hash (skip zero) : %08X\n\n",crc32_eac_global^0xFFFFFFFF]];
	}
	
	for(i=0;i<trackNumber;i++) {
		if(!results[i].enabled) continue;
		[out appendString:[NSString stringWithFormat:@"Track %02d\n",i+1]];
		if(results[i].cancelled) {
			[out appendString:@"    (cancelled by user)\n\n"];
			continue;
		}
		[[[trackList objectAtIndex:i] metadata] setObject:[NSNumber numberWithFloat:results[i].trackGain] forKey:XLD_METADATA_REPLAYGAIN_TRACK_GAIN];
		[[[trackList objectAtIndex:i] metadata] setObject:[NSNumber numberWithFloat:results[i].peak] forKey:XLD_METADATA_REPLAYGAIN_TRACK_PEAK];
		[out appendString:[NSString stringWithFormat:@"    Track gain             : %.2f dB\n",results[i].trackGain]];
		[out appendString:[NSString stringWithFormat:@"    Peak                   : %f\n",results[i].peak]];
		[out appendString:[NSString stringWithFormat:@"    CRC32 hash             : %08X\n",[results[i].validator crc32]]];
		[out appendString:[NSString stringWithFormat:@"    CRC32 hash (skip zero) : %08X\n\n",[results[i].validator crc32EAC]]];
	}
	
	[out appendString:@"End of status report\n"];
	
	return [out autorelease];
}

- (NSDictionary *)detectedOffset
{
	return detectedOffset;
}

- (BOOL)cancelled
{
	return stop;
}

@end
