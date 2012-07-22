//
//  XLDDiscBurner.m
//  XLD
//
//  Created by tmkk on 11/05/07.
//  Copyright 2011 tmkk. All rights reserved.
//

#import <DiscRecording/DiscRecording.h>
#import "XLDDiscBurner.h"
#import "XLDTrack.h"
#import "XLDTrackProducer.h"
#import "XLDCustomClasses.h"

@implementation XLDDiscBurner

- (id)initWithTracks:(NSArray *)tracks andLayout:(XLDDiscLayout*)layout
{
	[super init];
	trackList = [tracks retain];
	discLayout = [layout copy];
	discLayoutForVerify = [layout copy];
	recordingTrackList = [[NSMutableArray alloc] init];
	totalFrames = [layout totalFrames];
	status = malloc(sizeof(int)*[tracks count]);
	memset(status,-1,sizeof(int)*[tracks count]);
	int i;
	for(i=0;i<[trackList count];i++) {
		XLDTrackProducer *producer = [[XLDTrackProducer alloc] initWithDelegate:self];
		DRTrack *track = [[DRTrack alloc] initWithProducer:producer];
		[producer release];
		NSMutableDictionary *dic = [NSMutableDictionary dictionary];
		[dic setObject:[NSNumber numberWithUnsignedShort:2352] forKey:DRBlockSizeKey];
		if(i==[trackList count]-1)
			[dic setObject:[NSNumber numberWithLongLong:([discLayout totalFrames] - [(XLDTrack *)[trackList objectAtIndex:i] index])/588] forKey:DRTrackLengthKey];
		else
			[dic setObject:[NSNumber numberWithLongLong:[(XLDTrack *)[trackList objectAtIndex:i] frames]/588] forKey:DRTrackLengthKey];
		if(i==0) {
			//[dic setObject:[NSNumber numberWithInt:([(XLDTrack *)[trackList objectAtIndex:i] index])/588] forKey:DRTrackStartAddressKey];
			[dic setObject:[NSNumber numberWithInt:(588*75*2+[(XLDTrack *)[trackList objectAtIndex:i] gap])/588] forKey:DRPreGapLengthKey];
		}
		else
			[dic setObject:[NSNumber numberWithInt:[(XLDTrack *)[trackList objectAtIndex:i] gap]/588] forKey:DRPreGapLengthKey];
		NSString *isrc = [[[trackList objectAtIndex:i] metadata] objectForKey:XLD_METADATA_ISRC];
		if(isrc && [isrc length] == 12)
			[dic setObject:[NSData dataWithBytes:[isrc UTF8String] length:12] forKey:DRTrackISRCKey];
		
		// See DRTrackCore.h or MMC document for details
		// See Table 350 in mmc3r10g.pdf
		[dic setObject:[NSNumber numberWithInt:0] forKey:DRBlockTypeKey];
		// See Table 288, 290, 291, Figure 43 in mmc3r10g.pdf
		[dic setObject:[NSNumber numberWithInt:0] forKey:DRDataFormKey];
		unsigned char form = 0;
		NSNumber *pre = [[[trackList objectAtIndex:i] metadata] objectForKey:XLD_METADATA_PREEMPHASIS];
		NSNumber *dcp = [[[trackList objectAtIndex:i] metadata] objectForKey:XLD_METADATA_DCP];
		if(pre) [dic setObject:pre forKey:DRAudioPreEmphasisKey];
		if(dcp && [dcp boolValue]) [dic setObject:DRSCMSCopyrightFree forKey:DRSerialCopyManagementStateKey];
		// See Table 222 in mmc3r10g.pdf
		[dic setObject:[NSNumber numberWithUnsignedChar:form] forKey:DRTrackModeKey];
		// See Table 351 in mmc3r10g.pdf
		[dic setObject:[NSNumber numberWithInt:0] forKey:DRSessionFormatKey];
		[dic setObject:[NSNumber numberWithInt:i+1] forKey:DRTrackNumberKey];
		[dic setObject:DRVerificationTypeReceiveData forKey:DRVerificationTypeKey];
		[track setProperties:dic];
		[recordingTrackList addObject:track];
		[track release];
	}
	[discLayout insertSection:nil atIndex:0 withLength:588*75*2];
	return self;
}

- (void)dealloc
{
	[trackList release];
	[discLayout release];
	[discLayoutForVerify release];
	[recordingTrackList release];
	free(status);
	[super dealloc];
}

- (NSArray *)recordingTrackList
{
	return recordingTrackList;
}

- (XLDDiscLayout *)discLayout
{
	return discLayout;
}

- (XLDDiscLayout *)discLayoutForVerify
{
	return discLayoutForVerify;
}

- (XLDTrack *)trackAt:(int)n
{
	return [trackList objectAtIndex:n-1];
}

- (void)setWriteOffset:(int)n
{
	if(writeOffsetModified) return;
	writeOffsetModified = YES;
	// offset is positive
	// extra samples are added at the beginning of the disc
	// so append extra n samples at the end of the disc and
	// set the offset correction value to n
	// <<first n samples are lost>>
	if(n>0) {
		[discLayout addSection:nil withLength:n];
		writeOffsetCorrectionValue = n;
	}
	// offset is negative
	// samples at the beginning of the disc is removed
	// so append extra n samples at the beginning of the disc
	// <<last n samples are lost>>
	else if(n<0) [discLayout insertSection:nil atIndex:0 withLength:-n];
	writeOffset = n;
}

- (void)setReadOffsetCorrectionValue:(int)n
{
	if(readOffsetModified) return;
	readOffsetModified = YES;
	// offset correction value is positive
	// extra n samples are added at the beginning of the disc without correction
	// so append extra n samples at the beginning of the disc to verify
	// <<first n samples from the disc are untrustful>>
	if(n>0) [discLayoutForVerify insertSection:nil atIndex:0 withLength:n];
	// offset correction value is negative
	// n samples at the beginning of the disc is skipped without correction
	// so append extra n samples at the end of the disc and
	// set the offset correction value to -n to verify
	// <<last n samples from the disc are untrustful>>
	else if(n<0) {
		[discLayoutForVerify addSection:nil withLength:-n];
		readOffsetCorrectionValue = -n;
	}
	readOffset = n;
}

- (int)writeOffsetCorrectionValue
{
	return writeOffsetCorrectionValue;
}

- (int)readOffsetCorrectionValue
{
	return readOffsetCorrectionValue;
}

- (int)totalTracks
{
	return [trackList count];
}

- (int)igoredSamplesAtTheBeginningOfTrack:(int)n
{
	if(n==1 && (writeOffset > 0 || readOffset > 0)) return (writeOffset > readOffset) ? writeOffset : readOffset;
	return 0;
}

- (int)igoredSamplesAtTheEndOfTrack:(int)n
{
	if(n==[trackList count] && (writeOffset < 0 || readOffset < 0)) return (writeOffset > readOffset) ? -readOffset : -writeOffset;
	return 0;
}

- (xldoffset_t)totalFrames
{
	return totalFrames;
}

- (void)reportStatusOfTrack:(int)n difference:(int)difference
{
	status[n-1] = difference;
}

- (NSString *)reportString
{
	int i;
	BOOL shouldReport = NO;
	for(i=0;i<[trackList count];i++) {
		if(status[i] >= 0) {
			shouldReport = YES;
			break;
		}
	}
	if(!shouldReport) return nil;
	
	BOOL corruptionFound = NO;
	NSMutableString *out = [NSMutableString string];
	[out appendString:[NSString stringWithFormat:@"X Lossless Decoder version %@ (%@)\n\n",[[[NSBundle mainBundle] infoDictionary] valueForKey:@"CFBundleShortVersionString"],[[[NSBundle mainBundle] infoDictionary] valueForKey:@"CFBundleVersion"]]];
	[out appendString:[NSString stringWithFormat:@"XLD disc burning verification logfile from %@\n\n",[[NSDate date] localizedDateDescription]]];
	for(i=0;i<[trackList count];i++) {
		NSString *msg;
		if(status[i] == 0) msg = @"OK";
		else if(status[i] > 0 && (float)status[i]/(float)[[recordingTrackList objectAtIndex:i] estimateLength]/588.0f < 0.5f) {
			msg = [NSString stringWithFormat:@"May be corrupted (difference in %d sample%s)",status[i],status[i]>1?"s":""];
			corruptionFound = YES;
		}
		else if(status[i] > 0) {
			msg = @"Offset mismatch? (too many differences)";
		}
		else msg = @"Not verified";
		[out appendString:[NSString stringWithFormat:@"Track %02d : %@\n",i+1,msg]];
	}
	if(corruptionFound) {
		[out appendString:@"\nThis verification is done with the burst ripping, so re-verification with the secure ripping is highly recommended.\n"];
	}
	[out appendString:@"\nEnd of status report\n"];
	
	return out;
}

@end
