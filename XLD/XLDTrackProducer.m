//
//  XLDTrackProducer.m
//  XLD
//
//  Created by tmkk on 11/05/07.
//  Copyright 2011 tmkk. All rights reserved.
//

#import <DiscRecording/DiscRecording.h>
#import "XLDTrackProducer.h"
#import "XLDDiscBurner.h"
#import "XLDTrack.h"

static int sample_compare(const void *A, const void *B, int numSamples, unsigned int *totalDifference)
{
	int i;
	int difference = 0;
	for(i=0;i<numSamples;i++) {
		if(*(((unsigned int *)A)+i) != *(((unsigned int *)B)+i)) difference++;
	}
	if(totalDifference) *totalDifference = *totalDifference + difference;
	return difference;
}

@implementation XLDTrackProducer

- (id)initWithDelegate:(id)del
{
	[super init];
	delegate = [del retain];
	decodeBufferSize = 588*sizeof(int)*2*75;
	decodeBuffer = (int *)malloc(decodeBufferSize);
	verifyBufferSize = 588*sizeof(short)*2*75;
	verifyBuffer = (char *)malloc(verifyBufferSize);
	return self;
}

- (void)dealloc
{
	if(decoder) {
		[decoder closeFile];
		[decoder release];
		decoder = nil;
	}
	[delegate release];
	free(decodeBuffer);
	free(verifyBuffer);
	[super dealloc];
}

- (void) cleanupTrackAfterBurn:(DRTrack*)track
{
	//NSLog(@"cleanupTrackAfterBurn");
	/*fprintf(stderr, "     written: %llu\n",written);
	fprintf(stderr, " gap written: %llu\n",gapWritten);
	fprintf(stderr, "    verified: %llu\n",verified);
	fprintf(stderr, "gap verified: %llu\n\n",gapVerified);*/
	if(decoder) {
		[decoder closeFile];
		[decoder release];
		decoder = nil;
	}
}

- (BOOL) cleanupTrackAfterVerification:(DRTrack*)track
{
	if(decoder) {
		[decoder closeFile];
		[decoder release];
		decoder = nil;
	}
	[delegate reportStatusOfTrack:trackNumber difference:difference];
	return YES;
}

- (uint64_t) estimateLengthOfTrack:(DRTrack*)track
{
	//NSLog(@"estimateLengthOfTrack");
	return [[[track properties] objectForKey:DRTrackLengthKey] unsignedLongLongValue];
}

- (BOOL) prepareTrack:(DRTrack*)track forBurn:(DRBurn*)burn toMedia:(NSDictionary*)mediaInfo
{
	trackNumber = [[[track properties] objectForKey:DRTrackNumberKey] intValue];
	//NSLog(@"prepareTrack @ %d",trackNumber);
	decoder = [[XLDMultipleFileWrappedDecoder alloc] initWithDiscLayout:[delegate discLayout]];
	[decoder openFile:nil];
	XLDTrack *t = [delegate trackAt:trackNumber];
	trackIndex = [t index];
	gapLength = [t gap];
	if(trackNumber == [delegate totalTracks])
		trackLength = [delegate totalFrames] - trackIndex + gapLength;
	else
		trackLength = [t frames]+gapLength;
	//NSLog(@"%lld,%lld,%d",trackIndex,trackLength,gapLength);
	
	if(trackNumber>1) {
		if(gapLength) [decoder seekToFrame:trackIndex-gapLength+588*75*2+[delegate writeOffsetCorrectionValue]];
		else [decoder seekToFrame:trackIndex+588*75*2+[delegate writeOffsetCorrectionValue]];
	}
	else [decoder seekToFrame:[delegate writeOffsetCorrectionValue]];
	return YES;
}

- (BOOL) prepareTrackForVerification:(DRTrack*)track; 
{
	//NSLog(@"prepareTrackForVerification @ %d",trackNumber);
	ignoredBytesAtTheBeginning = [delegate igoredSamplesAtTheBeginningOfTrack:trackNumber]*4;
	ignoredBytesAtTheEnd = [delegate igoredSamplesAtTheEndOfTrack:trackNumber]*4;
	//NSLog(@"ignoring: %d,%d",ignoredBytesAtTheBeginning,ignoredBytesAtTheEnd);
	
	[decoder closeFile];
	[decoder release];
	decoder = [[XLDMultipleFileWrappedDecoder alloc] initWithDiscLayout:[delegate discLayoutForVerify]];
	[decoder openFile:nil];
	
	if(trackNumber>1) {
		if(gapLength) [decoder seekToFrame:trackIndex-gapLength+[delegate readOffsetCorrectionValue]];
		else [decoder seekToFrame:trackIndex+[delegate readOffsetCorrectionValue]];
	}
	else [decoder seekToFrame:[delegate readOffsetCorrectionValue]];
	
	if(trackNumber == 1) gapWritten -= 44100*4*2;
	return YES;
}

- (uint32_t) produceDataForTrack:(DRTrack*)track
					  intoBuffer:(char*)buffer length:(uint32_t)bufferLength
					   atAddress:(uint64_t)address blockSize:(uint32_t)blockSize
						 ioFlags:(uint32_t*)flags
{
	int i;
	if(decodeBufferSize < bufferLength*2) decodeBuffer = realloc(decodeBuffer, bufferLength*2);
	int ret = [decoder decodeToBuffer:decodeBuffer frames:bufferLength/4];
	for(i=0;i<ret;i++) {
		short L = decodeBuffer[i*2] >> 16;
		short R = decodeBuffer[i*2+1] >> 16;
		((short *)buffer)[i*2] = NSSwapHostShortToLittle(L);
		((short *)buffer)[i*2+1] = NSSwapHostShortToLittle(R);
	}
	written += ret*4;
	return ret*4;
}

- (uint32_t) producePreGapForTrack:(DRTrack*)track 
 intoBuffer:(char*)buffer length:(uint32_t)bufferLength 
 atAddress:(uint64_t)address blockSize:(uint32_t)blockSize 
 ioFlags:(uint32_t*)flags
{
	int i;
	if(decodeBufferSize < bufferLength*2) decodeBuffer = realloc(decodeBuffer, bufferLength*2);
	int ret = [decoder decodeToBuffer:decodeBuffer frames:bufferLength/4];
	for(i=0;i<ret;i++) {
		short L = decodeBuffer[i*2] >> 16;
		short R = decodeBuffer[i*2+1] >> 16;
		((short *)buffer)[i*2] = NSSwapHostShortToLittle(L);
		((short *)buffer)[i*2+1] = NSSwapHostShortToLittle(R);
	}
	gapWritten += ret*4;
	return ret*4;
}

- (BOOL) verifyDataForTrack:(DRTrack*)track inBuffer:(const char*)buffer 
					 length:(uint32_t)bufferLength atAddress:(uint64_t)address 
				  blockSize:(uint32_t)blockSize ioFlags:(uint32_t*)flags; 
{
	int i;
	if(verified == 0 && gapWritten != gapVerified) {
		// DR framework seems to misdetect the pregap length
		// this happens to the 2nd track on discs with HTOA
		//NSLog(@"position fixed");
		difference = 0;
		[decoder seekToFrame:trackIndex+[delegate readOffsetCorrectionValue]];
	}
	if(decodeBufferSize < bufferLength*2) decodeBuffer = realloc(decodeBuffer, bufferLength*2);
	if(verifyBufferSize < bufferLength) verifyBuffer = realloc(verifyBuffer, bufferLength);
	int ret = [decoder decodeToBuffer:decodeBuffer frames:bufferLength/4];
	for(i=0;i<ret;i++) {
		short L = decodeBuffer[i*2] >> 16;
		short R = decodeBuffer[i*2+1] >> 16;
		((short *)verifyBuffer)[i*2] = NSSwapHostShortToLittle(L);
		((short *)verifyBuffer)[i*2+1] = NSSwapHostShortToLittle(R);
	}
	
	verified += ret*4;
	int bytesToVerify = bufferLength;
	address += gapLength*4;
	if(ignoredBytesAtTheBeginning) {
		if(address < ignoredBytesAtTheBeginning) {
			if(address+bufferLength < ignoredBytesAtTheBeginning) bytesToVerify = 0;
			else bytesToVerify = address+bufferLength - ignoredBytesAtTheBeginning;
		}
		if(!bytesToVerify) return YES;
		if(sample_compare(buffer+bufferLength-bytesToVerify, verifyBuffer+bufferLength-bytesToVerify, bytesToVerify/4, &difference)) {
			//NSLog(@"inconsistency found @ %llu",address);
		}
		return YES;
	}
	if(ignoredBytesAtTheEnd) {
		if(address + bufferLength >= trackLength*4-ignoredBytesAtTheEnd) {
			if(address >= trackLength*4-ignoredBytesAtTheEnd) bytesToVerify = 0;
			else bytesToVerify = trackLength*4-ignoredBytesAtTheEnd - address;
		}
		if(!bytesToVerify) return YES;
		if(sample_compare(buffer, verifyBuffer, bytesToVerify/4, &difference)) {
			//NSLog(@"inconsistency found @ %llu",address);
		}
		return YES;
	}
	if(sample_compare(buffer, verifyBuffer, bytesToVerify/4, &difference)) {
		//NSLog(@"inconsistency found @ %llu",address);
	}
	return YES;
}

- (BOOL) verifyPreGapForTrack:(DRTrack*)track inBuffer:(const char*)buffer 
					   length:(uint32_t)bufferLength atAddress:(uint64_t)address 
					blockSize:(uint32_t)blockSize ioFlags:(uint32_t*)flags
{
	if(decodeBufferSize < bufferLength*2) decodeBuffer = realloc(decodeBuffer, bufferLength*2);
	if(verifyBufferSize < bufferLength) verifyBuffer = realloc(verifyBuffer, bufferLength);
	int ret = [decoder decodeToBuffer:decodeBuffer frames:bufferLength/4];
	gapVerified += ret*4;
#if 1
	int i;
	for(i=0;i<ret;i++) {
		short L = decodeBuffer[i*2] >> 16;
		short R = decodeBuffer[i*2+1] >> 16;
		((short *)verifyBuffer)[i*2] = NSSwapHostShortToLittle(L);
		((short *)verifyBuffer)[i*2+1] = NSSwapHostShortToLittle(R);
	}
	/*if(trackNumber == 1 && address < 44100*2*4) return YES;
	
	if(trackNumber == 1) address -= 44100*2*4;*/
	int bytesToVerify = bufferLength;
	if(address < ignoredBytesAtTheBeginning) {
		if(address+bufferLength < ignoredBytesAtTheBeginning) bytesToVerify = 0;
		else bytesToVerify = address+bufferLength - ignoredBytesAtTheBeginning;
	}
	
	if(!bytesToVerify) return YES;
	if(sample_compare(buffer+bufferLength-bytesToVerify, verifyBuffer+bufferLength-bytesToVerify, bytesToVerify/4, &difference)) {
		//NSLog(@"inconsistency found (pregap) @ %llu,%u",address,bufferLength);
	}
#endif
	return YES;
}

@end
