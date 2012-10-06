//
//  XLDCDDARipper.m
//  XLD
//
//  Created by tmkk on 08/08/09.
//  Copyright 2008 tmkk. All rights reserved.
//
//  Access to AccurateRip is regulated, see  http://www.accuraterip.com/3rdparty-access.htm for details.

#import <fcntl.h>
#import "XLDCDDARipper.h"
#import "XLDAccurateRipDB.h"
#import "paranoia/cachetest.c"

char *callback_msg[] = {
	"PARANOIA_CB_READ",           
	"PARANOIA_CB_VERIFY",         
	"PARANOIA_CB_FIXUP_EDGE",     
	"PARANOIA_CB_FIXUP_ATOM",     
	"PARANOIA_CB_SCRATCH",        
	"PARANOIA_CB_REPAIR",         
	"PARANOIA_CB_SKIP",           
	"PARANOIA_CB_DRIFT",          
	"PARANOIA_CB_BACKOFF",        
	"PARANOIA_CB_OVERLAP",        
	"PARANOIA_CB_FIXUP_DROPPED",  
	"PARANOIA_CB_FIXUP_DUPED",    
	"PARANOIA_CB_READERR"         
};

static paranoia_cb_mode_t callback_result; 

void paranoia_callback(long int n, paranoia_cb_mode_t ret)
{
	//if((ret != PARANOIA_CB_READ) && (ret != PARANOIA_CB_VERIFY) && (ret != PARANOIA_CB_OVERLAP)) NSLog(@"callback: %d (%s)\n",n,callback_msg[ret]);
	if(ret == PARANOIA_CB_FIXUP_EDGE) callback_result |= 0x1;
	else if(ret == PARANOIA_CB_FIXUP_ATOM) callback_result |= 0x2;
	else if(ret == PARANOIA_CB_SKIP) callback_result |= 0x4;
	else if(ret == PARANOIA_CB_DRIFT) callback_result |= 0x8;
	else if(ret == PARANOIA_CB_FIXUP_DROPPED) callback_result |= 0x10;
	else if(ret == PARANOIA_CB_FIXUP_DUPED) callback_result |= 0x20;
	else if(ret == PARANOIA_CB_READERR) callback_result |= 0x40;
	else if(ret == PARANOIA_CB_CACHEERR) callback_result |= 0x80;
}

static void commitParanoiaResult(cddaRipResult *result, int currentTrack)
{
	if(callback_result & 0x1) result->edgeJitterCount++;
	if(callback_result & 0x2) result->atomJitterCount++;
	if(callback_result & 0x4) result->skipCount++;
	if(callback_result & 0x8) result->driftCount++;
	if(callback_result & 0x10) result->droppedCount++;
	if(callback_result & 0x20) result->duplicatedCount++;
	if(callback_result & 0x40) result->errorCount++;
	if(callback_result & 0x80) result->cacheErrorCount++;
	if(result->parent) {
		XLDCDDAResult *obj = result->parent;
		cddaRipResult *targetResult = [obj resultForIndex:currentTrack];
		if(callback_result & 0x1) targetResult->edgeJitterCount++;
		if(callback_result & 0x2) targetResult->atomJitterCount++;
		if(callback_result & 0x4) targetResult->skipCount++;
		if(callback_result & 0x8) targetResult->driftCount++;
		if(callback_result & 0x10) targetResult->droppedCount++;
		if(callback_result & 0x20) targetResult->duplicatedCount++;
		if(callback_result & 0x40) targetResult->errorCount++;
		if(callback_result & 0x80) targetResult->cacheErrorCount++;
	}
}

static void commitSecureRipperResult(cddaRipResult *result, XLDSecureRipperResult ripperResult, int currentTrack)
{
	if(ripperResult & XLDSecureRipperReadErr) result->errorCount++;
	if(ripperResult & XLDSecureRipperJitterErr) result->edgeJitterCount++;
	if(ripperResult & XLDSecureRipperRetry) result->retrySectorCount++;
	if(ripperResult & XLDSecureRipperDamaged) result->damagedSectorCount++;
	if(result->parent) {
		XLDCDDAResult *obj = result->parent;
		cddaRipResult *targetResult = [obj resultForIndex:currentTrack];
		if(ripperResult & XLDSecureRipperReadErr) targetResult->errorCount++;
		if(ripperResult & XLDSecureRipperJitterErr) targetResult->edgeJitterCount++;
		if(ripperResult & XLDSecureRipperRetry) targetResult->retrySectorCount++;
		if(ripperResult & XLDSecureRipperDamaged) targetResult->damagedSectorCount++;
	}
}

@implementation XLDCDDARipper

+ (BOOL)canHandleFile:(char *)path
{
	return YES;
}

+ (BOOL)canLoadThisBundle
{
	return YES;
}

+ (int)analyzeCacheForDrive:(NSString *)device result:(cache_analysis_t *)result_t delegate:(id)delegate
{
	xld_cdread_t cdread_test;
	if(xld_cdda_open(&cdread_test, (char *)[device UTF8String]) == -1) return -1;
	
	short *buf = malloc(2352*5000);
	int ret = analyze_cache(&cdread_test,NULL,NULL,-1,buf,result_t);
	free(buf);
	
	xld_cdda_close(&cdread_test);
	
	//NSLog(@"%d,%d,%d,%d",ret,result_t->have_cache,result_t->cache_sector_size,result_t->backseek_flush_capable);
	return ret;
}

- (id)init
{
	[super init];
	retryCount = 1;
	cddaBuffer = (short *)malloc(65536);
	preTrackSamples = calloc(1,588*4*2*sizeof(int));
	postTrackSamples = calloc(1,588*4*2*sizeof(int));
	burstBuffer = malloc((2352+294)*100);
	startLSN = 999999;
	return self;
}

- (BOOL)openFile:(char *)path
{
	//NSLog(@"open");
	unsigned int i, k, value;
	
	//NSLog(@"engine is: %@",useOldEngine ? @"old" : @"new");
	
	if(xld_cdda_open(&cdread, path) == -1) return NO;
	
	totalFrames = 588*(xld_cdda_disc_lastsector(&cdread) + 1);
	
	firstAudioFrame = -1;
	for(i=1;i<=cdread.numTracks;i++) {
		if(cdread.tracks[i-1].type != kTrackTypeAudio) {
			continue;
		}
		if(firstAudioFrame < 0) {
			if(i==1) firstAudioFrame = 0;
			else firstAudioFrame = xld_cdda_track_firstsector(&cdread, i)*588;
		}
		lastAudioFrame = 588*(1+xld_cdda_track_lastsector(&cdread,i));
	}
	
	//NSLog(@"%lld,%d,%d,%d",totalFrames,lastAudioFrame,totalLSN,lastAudioFrame/588);
	
	//analyze_cache(p_drive,NULL,stderr,-1);
	
	if(ripperMode & kRipperModeParanoia) {
		p_paranoia = paranoia_init(&cdread);
		if(!p_paranoia) return NO;
		paranoia_modeset(p_paranoia, PARANOIA_MODE_VERIFY|PARANOIA_MODE_OVERLAP);
	}
	else {
		secureRipper = [[XLDSecureRipperEngine alloc] initWithReader:&cdread];
		[secureRipper setRipperMode:ripperMode];
		[secureRipper setMaxRetryCount:retryCount];
	}
	
	if(srcPath) [srcPath release];
	srcPath = [[NSString alloc] initWithUTF8String:path];
	
	cddaBufferSize = 0;
	currentFrame = 0;
	currentTrack = 1;
	firstRead = YES;
	
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
    
	fcntl(cdread.fd,F_NOCACHE,1);
	
	cancel = NO;
	currentLSN = 0;
    
	return YES;
}

- (void)dealloc
{
	//NSLog(@"dealoced");
	if(p_paranoia) paranoia_free(p_paranoia);
	if(srcPath) [srcPath release];
	if(secureRipper) [secureRipper release];
	free(cddaBuffer);
	free(burstBuffer);
	free(preTrackSamples);
	free(postTrackSamples);
	[super dealloc];
}

- (int)samplerate
{
	return 44100;
}

- (int)bytesPerSample
{
	return 2;
}

- (int)channels
{
	return 2;
}

- (xldoffset_t)totalFrames
{
	return totalFrames;
}

- (int)isFloat
{
	return NO;
}

- (BOOL)readSectorWithC2Detection:(short *)buffer;
{
	int i;
	BOOL ret = NO;
	if((startLSN > currentLSN) || (startLSN + cacheSectorCount <= currentLSN)) {
		cacheSectorCount = (currentLSN + 100 <= lastAudioFrame/588) ? 100 : 1;
		if(xld_cdda_read_with_c2(&cdread,burstBuffer,currentLSN,cacheSectorCount) < 0) return YES;
		startLSN = currentLSN;
	}
	
	int startPoint = (currentLSN - startLSN)*(2352+294);
	memcpy(buffer,burstBuffer+startPoint,2352);
	
	for(i=startPoint+2352;i<startPoint+2352+294;i++) {
		if(burstBuffer[i] != 0) {
			ret = YES;
			break;
		}
	}
	return ret;
}

- (int)decodeToBuffer:(int *)buffer frames:(int)count
{
	short *readBuf;
	short burstReadBuf[588*2];
	int i;
	if(firstRead) {
		[self seekToFrame:0];
	}
	
	int framesToCopy = count;
	
	if(cddaBufferSize) {
		if(framesToCopy > cddaBufferSize/4) {
			for(i=0;i<cddaBufferSize/2;i++) {
				buffer[i] = cddaBuffer[i] << 16;
			}
			framesToCopy -= cddaBufferSize/4;
			cddaBufferSize = 0;
		}
		else {
			for(i=0;i<framesToCopy*2;i++) {
				buffer[i] = cddaBuffer[i] << 16;
			}
			framesToCopy = 0;
			memmove(cddaBuffer,cddaBuffer+framesToCopy*2,cddaBufferSize-framesToCopy*4);
			cddaBufferSize = cddaBufferSize-framesToCopy*4;
		}
	}
	
	//NSLog(@"framesToCopy:%d",framesToCopy);
	
	while(framesToCopy) {
		if(cancel) return count;
		if(lastAudioFrame/588 == currentLSN) { // lead-out offset
			memset(buffer+(count-framesToCopy)*2,0,framesToCopy*2*4);
			framesToCopy = 0;
		}
		else {
			callback_result = 0;
			if(ripperMode & kRipperModeParanoia) {
				if(ripperMode & kRipperModeC2) {
					if([self readSectorWithC2Detection:burstReadBuf]) {
						//NSLog(@"c2 error detected");
						paranoia_seek(p_paranoia,currentLSN,SEEK_SET);
						readBuf = paranoia_read_limited(p_paranoia,(void *)paranoia_callback,retryCount);
					}
					else readBuf = burstReadBuf;
				}
				else readBuf = paranoia_read_limited(p_paranoia,(void *)paranoia_callback,retryCount);
				if(!testMode) {
					commitParanoiaResult(result,currentTrack);
				}
			}
			else {
				XLDSecureRipperResult ripperResult;
				readBuf = [secureRipper readSector:&ripperResult];
				if(!testMode) {
					commitSecureRipperResult(result,ripperResult,currentTrack);
					if(result->checkInconsistency) {
						if(ripperResult & XLDSecureRipperDamaged) {
							result->inconsistency++;
							[result->suspiciousPosition addObject:[NSNumber numberWithInt:currentLSN]];
							if(result->parent) {
								XLDCDDAResult *obj = result->parent;
								cddaRipResult *targetResult = [obj resultForIndex:currentTrack];
								targetResult->inconsistency++;
								[targetResult->suspiciousPosition addObject:[NSNumber numberWithInt:currentLSN]];
							}
						}
					}
				}
			}

			currentLSN++;
			if(framesToCopy < 588) {
				for(i=0;i<framesToCopy*2;i++) {
					buffer[i+(count-framesToCopy)*2] = readBuf[i] << 16;
				}
				memcpy(cddaBuffer,readBuf+framesToCopy*2,(588-framesToCopy)*4);
				cddaBufferSize = (588-framesToCopy)*4;
				framesToCopy = 0;
			}
			else {
				for(i=0;i<588*2;i++) {
					buffer[i+(count-framesToCopy)*2] = readBuf[i] << 16;
				}
				framesToCopy -= 588;
			}

			if(ripperMode & kRipperModeParanoia) {
				if(callback_result & 0x7f) {
					if(!testMode && result->checkInconsistency) {
						short* tmpBuf = malloc(sizeof(short)*2*588);
						memcpy(tmpBuf,readBuf,2352);
						paranoia_seek(p_paranoia,-1,SEEK_CUR);
						readBuf = paranoia_read_limited(p_paranoia,NULL,retryCount);
						if(memcmp(tmpBuf,readBuf,2352)) {
							result->inconsistency++;
							[result->suspiciousPosition addObject:[NSNumber numberWithInt:currentLSN]];
							if(result->parent) {
								XLDCDDAResult *obj = result->parent;
								cddaRipResult *targetResult = [obj resultForIndex:currentTrack];
								targetResult->inconsistency++;
								[targetResult->suspiciousPosition addObject:[NSNumber numberWithInt:currentLSN]];
							}
						}
						free(tmpBuf);
					}
				}
#if 1
				else if(!(ripperMode & kRipperModeC2) && !(currentLSN & 0xfff)) { //hack
					paranoia_seek(p_paranoia,0,SEEK_SET);
					paranoia_seek(p_paranoia,currentLSN,SEEK_SET);
				}
#endif
			}
		}
	}
	
	/* ReplayGain */
	if(result->scanReplayGain && !testMode) {
		if(result->parent) {
			XLDCDDAResult *obj = result->parent;
			if(currentTrack <= obj->trackNumber) {
				if(currentFrame+count >= obj->actualLengthArr[currentTrack-1]) {
					cddaRipResult *targetResult = [obj resultForIndex:currentTrack];
					gain_analyze_samples_interleaved_int32(result->rg,buffer,obj->actualLengthArr[currentTrack-1]-currentFrame,2);
					targetResult->trackGain = PINK_REF-gain_get_title(result->rg);
					targetResult->peak = peak_get_title(result->rg);
					gain_analyze_samples_interleaved_int32(result->rg,buffer+2*(obj->actualLengthArr[currentTrack-1]-currentFrame),count+currentFrame-obj->actualLengthArr[currentTrack-1],2);
					//NSLog(@"track %d: gain %.2f, peak %f",currentTrack,targetResult->trackGain,targetResult->peak);
				}
				else gain_analyze_samples_interleaved_int32(result->rg,buffer,count,2);
			}
		}
		else gain_analyze_samples_interleaved_int32(result->rg,buffer,count,2);
	}
	
	/* AccurateRip & CRC32 stuff */
	if(result->parent) {
		XLDCDDAResult *obj = result->parent;
		BOOL perSampleCommit = YES;
		if(currentFrame + count <= obj->actualLengthArr[currentTrack-1]) {
			cddaRipResult *targetResult = [obj resultForIndex:currentTrack];
			if(!testMode) {
				[targetResult->validator commitSamples:buffer length:count];
			}
			else {
				[targetResult->validator commitTestSamples:buffer length:count];
			}
			perSampleCommit = NO;
		}
		for(i=0;i<count;i++) {
			if(perSampleCommit) {
				cddaRipResult *targetResult = [obj resultForIndex:currentTrack];
				if(!testMode) {
					[targetResult->validator commitSamples:buffer+i*2 length:1];
				}
				else {
					[targetResult->validator commitTestSamples:buffer+i*2 length:1];
				}
			}
			if((currentTrack <= obj->trackNumber) && (currentFrame >= obj->actualLengthArr[currentTrack-1]-2352)) {
				preTrackSamples[(2352+currentFrame - obj->actualLengthArr[currentTrack-1])*2] = buffer[i*2];
				preTrackSamples[(2352+currentFrame - obj->actualLengthArr[currentTrack-1])*2+1] = buffer[i*2+1];
			}
			if(currentFrame < 2352) {
				postTrackSamples[currentFrame*2] = buffer[i*2];
				postTrackSamples[currentFrame*2+1] = buffer[i*2+1];
			}
			currentFrame++;
			if((currentTrack <= obj->trackNumber) && (currentFrame == obj->actualLengthArr[currentTrack-1])) {
				currentTrack++;
				currentFrame = 0;
				
				/* commit preTrackSamples */
				if(currentTrack <= obj->trackNumber && cdread.tracks[currentTrack-1].type == kTrackTypeAudio) {
					cddaRipResult *nextResult = [obj resultForIndex:currentTrack];
					[nextResult->validator commitPreTrackSamples:preTrackSamples];
				}
				/* re-initialize cdparanoia */
				if(ripperMode & kRipperModeParanoia) {
					paranoia_free(p_paranoia);
					p_paranoia = paranoia_init(&cdread);
					paranoia_modeset(p_paranoia, PARANOIA_MODE_VERIFY|PARANOIA_MODE_OVERLAP);
					paranoia_seek(p_paranoia,currentLSN,SEEK_SET);
				}
			}
			else if((currentTrack > 1) && (currentFrame == 2352) && cdread.tracks[currentTrack-2].type == kTrackTypeAudio) {
				/* commit postTrackSamples */
				cddaRipResult *prevResult = [obj resultForIndex:currentTrack-1];
				[prevResult->validator commitPostTrackSamples:postTrackSamples];
			}
		}
	}
	if(!testMode) {
		[result->validator commitSamples:buffer length:count];
	}
	else {
		[result->validator commitTestSamples:buffer length:count];
	}

	
	return count;
}

- (int)decodeToBufferWithoutReport:(int *)buffer frames:(int)count
{
	short* readBuf;
	short burstReadBuf[588*2];
	int i;
	if(firstRead) {
		[self seekToFrame:0];
	}
	
	int framesToCopy = count;
	
	if(cddaBufferSize) {
		if(framesToCopy > cddaBufferSize/4) {
			for(i=0;i<cddaBufferSize/2;i++) {
				buffer[i] = cddaBuffer[i] << 16;
			}
			framesToCopy -= cddaBufferSize/4;
			cddaBufferSize = 0;
		}
		else {
			for(i=0;i<framesToCopy*2;i++) {
				buffer[i] = cddaBuffer[i] << 16;
			}
			framesToCopy = 0;
			memmove(cddaBuffer,cddaBuffer+framesToCopy*2,cddaBufferSize-framesToCopy*4);
			cddaBufferSize = cddaBufferSize-framesToCopy*4;
		}
	}
	
	//NSLog(@"framesToCopy:%d",framesToCopy);
	
	while(framesToCopy) {
		if(lastAudioFrame/588 == currentLSN) { // lead-out offset
			memset(buffer+(count-framesToCopy)*2,0,framesToCopy*2*4);
			framesToCopy = 0;
		}
		else {
			callback_result = 0;
			if(ripperMode & kRipperModeParanoia) {
				if(ripperMode & kRipperModeC2) {
					if([self readSectorWithC2Detection:burstReadBuf]) {
						//NSLog(@"c2 error detected");
						paranoia_seek(p_paranoia,currentLSN,SEEK_SET);
						readBuf = paranoia_read_limited(p_paranoia,(void *)paranoia_callback,retryCount);
					}
					else readBuf = burstReadBuf;
				}
				else readBuf = paranoia_read_limited(p_paranoia,(void *)paranoia_callback,retryCount);
				if(!testMode) {
					commitParanoiaResult(result,currentTrack);
				}
			}
			else {
				XLDSecureRipperResult ripperResult;
				readBuf = [secureRipper readSector:&ripperResult];
				if(!testMode) {
					commitSecureRipperResult(result,ripperResult,currentTrack);
				}
			}

			currentLSN++;
			if(framesToCopy < 588) {
				for(i=0;i<framesToCopy*2;i++) {
					buffer[i+(count-framesToCopy)*2] = readBuf[i] << 16;
				}
				memcpy(cddaBuffer,readBuf+framesToCopy*2,(588-framesToCopy)*4);
				cddaBufferSize = (588-framesToCopy)*4;
				framesToCopy = 0;
			}
			else {
				for(i=0;i<588*2;i++) {
					buffer[i+(count-framesToCopy)*2] = readBuf[i] << 16;
				}
				framesToCopy -= 588;
			}
			
#if 1
			if(ripperMode & kRipperModeParanoia && !(ripperMode & kRipperModeC2) && !(currentLSN & 0xfff)) { //hack
				paranoia_seek(p_paranoia,0,SEEK_SET);
				paranoia_seek(p_paranoia,currentLSN,SEEK_SET);
			}
#endif
		}
	}
	
	return count;
}

- (xldoffset_t)seekToFrame:(xldoffset_t)count
{
	firstRead = NO;
	//currentFrame = count;
	int seekFrame = count + offsetCorrectionValue;
	int seekLSN = seekFrame/588;
	
	if(result->parent) {
		XLDCDDAResult *obj = result->parent;
		int i;
		for(i=0;i<obj->trackNumber;i++) {
			if(count<obj->indexArr[i]) break;
			currentTrack = i+1;
		}
	}
	if(seekFrame < firstAudioFrame) {
		if(ripperMode & kRipperModeParanoia)
			paranoia_seek(p_paranoia,firstAudioFrame/588,SEEK_SET);
		else
			[secureRipper seekToSector:firstAudioFrame/588];
		cddaBufferSize = (firstAudioFrame-seekFrame)*2*2;
		memset(cddaBuffer,0,cddaBufferSize);
		currentLSN = firstAudioFrame/588;
	}
	else if(seekFrame >= lastAudioFrame) {
		currentLSN = lastAudioFrame/588;
		cddaBufferSize = 0;
	}
	else {
		currentLSN = seekLSN;
		int restFrame = seekFrame - seekLSN*588;
		if(restFrame) {
			short *buf, burstReadBuf[588*2];
			
			if(ripperMode & kRipperModeParanoia) {
				callback_result = 0;
				if(ripperMode & kRipperModeC2) {
					if([self readSectorWithC2Detection:burstReadBuf]) {
						//NSLog(@"c2 error detected");
						paranoia_seek(p_paranoia,seekLSN,SEEK_SET);
						buf = paranoia_read_limited(p_paranoia,(void *)paranoia_callback,retryCount);
					}
					else buf = burstReadBuf;
				}
				else {
					paranoia_seek(p_paranoia,seekLSN,SEEK_SET);
					buf = paranoia_read_limited(p_paranoia,(void *)paranoia_callback,retryCount);
				}
				if(!testMode) {
					commitParanoiaResult(result,currentTrack);
				}
			}
			else {
				[secureRipper seekToSector:seekLSN];
				XLDSecureRipperResult ripperResult;
				buf = [secureRipper readSector:&ripperResult];
				if(!testMode) {
					commitSecureRipperResult(result,ripperResult,currentTrack);
				}
			}
			currentLSN++;
			memcpy(cddaBuffer,buf+restFrame*2,(588-restFrame)*2*2);
			cddaBufferSize = (588-restFrame)*2*2;
		}
		else {
			if(ripperMode & kRipperModeParanoia) paranoia_seek(p_paranoia,seekLSN,SEEK_SET);
			else [secureRipper seekToSector:seekLSN];
			cddaBufferSize = 0;
		}
	}
	
	return count;
}

- (void)closeFile
{
	//NSLog(@"closed");
	if(p_paranoia) paranoia_free(p_paranoia);
	if(secureRipper) [secureRipper release];
    xld_cdda_close(&cdread);
	p_paranoia = NULL;
	secureRipper = nil;
#if 0
	/* moved to -analyzeTrackGain */
	if(result) {
		if(result->scanReplayGain && !testMode) {
			if(!result->parent) {
				result->trackGain = PINK_REF-gain_get_title(result->rg);
				result->peak = peak_get_title(result->rg);
			}
		}
	}
#endif
	error = NO;
}

- (BOOL)error
{
	return error;
}

- (XLDEmbeddedCueSheetType)hasCueSheet
{
	return XLDNoCueSheet;
}

- (id)cueSheet
{
	return nil;
}

- (id)metadata
{
	return nil;
}

- (NSString *)srcPath
{
	return srcPath;
}

- (void)setOffsetCorrectionValue:(int)value
{
	offsetCorrectionValue = value;
	//NSLog(@"offset: %d",value);
}

- (void)setRetryCount:(int)value
{
	retryCount = value;
	//NSLog(@"retry: %d",value);
}

- (void)setResultStructure:(cddaRipResult *)ptr
{
	result = ptr;
}

- (void)setTestMode
{
	testMode = YES;
}

- (void)cancel
{
	cancel = YES;
}

- (void)setRipperMode:(XLDRipperMode)mode
{
	ripperMode = mode;
}

- (NSString *)driveStr
{
	return [NSString stringWithFormat:@"%s %s (revision %s)",cdread.vendor,cdread.product,cdread.revision];
}

- (void)analyzeTrackGain
{
	if(result) {
		if(result->scanReplayGain && !testMode) {
			if(!result->parent) {
				result->trackGain = PINK_REF-gain_get_title(result->rg);
				result->peak = peak_get_title(result->rg);
			}
		}
	}
}

@end
