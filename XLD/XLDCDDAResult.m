//
//  XLDCDDAResult.m
//  XLD
//
//  Created by tmkk on 08/08/13.
//  Copyright 2008 tmkk. All rights reserved.
//
//  Access to AccurateRip is regulated, see  http://www.accuraterip.com/3rdparty-access.htm for details.

#import "XLDCDDAResult.h"
#import "XLDTrack.h"
#import "XLDAccurateRipDB.h"
#import "XLDCustomClasses.h"

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

static BOOL dumpAccurateRipLog(NSMutableString *out, cddaRipResult *result)
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

@implementation XLDCDDAResult

- (id)init
{
	[super init];
	detectedOffset = [[NSMutableDictionary alloc] init];
	trackList = [[NSMutableArray alloc] init];
	rg = (replaygain_t *)malloc(sizeof(replaygain_t));
	gain_init_analysis(rg,44100);
	logDirectoryArray = [[NSMutableArray alloc] init];
	cueDirectoryArray = [[NSMutableArray alloc] init];
	return self;
}

- (id)initWithTrackNumber:(int)t
{
	[self init];
	results = (cddaRipResult *)calloc(t+1,sizeof(cddaRipResult));
	indexArr = (xldoffset_t *)malloc(sizeof(xldoffset_t)*t);
	lengthArr = (xldoffset_t *)malloc(sizeof(xldoffset_t)*t);
	actualLengthArr = (xldoffset_t *)malloc(sizeof(xldoffset_t)*t);
	int i;
	for(i=0;i<t+1;i++) {
		results[i].suspiciousPosition = [[NSMutableArray alloc] init];
		results[i].rg = rg;
		results[i].detectedOffset = [[NSMutableDictionary alloc] init];
		results[i].validator = [[XLDTrackValidator alloc] init];
		[results[i].validator setTrackNumber:i];
	}
	trackNumber = t;
	return self;
}

- (void)dealloc
{
	int i;
	if(results) {
		for(i=0;i<trackNumber+1;i++) {
			if(results[i].filename) [results[i].filename release];
			if(results[i].filelist) [results[i].filelist release];
			[results[i].suspiciousPosition release];
			[results[i].detectedOffset release];
			[results[i].validator release];
		}
		free(results);
	}
	if(driveStr) [driveStr release];
	if(deviceStr) [deviceStr release];
	if(date) [date release];
	if(title) [title release];
	if(artist) [artist release];
	if(database) [database release];
	free(indexArr);
	free(lengthArr);
	free(actualLengthArr);
	[detectedOffset release];
	[trackList release];
	if(cuePath) [cuePath release];
	if(cuePathArray) [cuePathArray release];
	if(logFileName) [logFileName release];
	if(cueFileName) [cueFileName release];
	[logDirectoryArray release];
	[cueDirectoryArray release];
	free(rg);
	[super dealloc];
}

- (cddaRipResult *)resultForIndex:(int)idx
{
	return &results[idx];
}

- (void)setDriveStr:(NSString *)str
{
	if(driveStr) [driveStr release];
	driveStr = [str retain];
}

- (void)setDeviceStr:(NSString *)str
{
	if(deviceStr) [deviceStr release];
	deviceStr = [str retain];
}

- (void)setDate:(NSDate *)d
{
	if(date) [date release];
	date = [d retain];
}

- (void)setLogFileName:(NSString *)str
{
	if(logFileName) [logFileName release];
	logFileName = [str retain];
}

- (NSString *)logFileName
{
	return logFileName;
}

- (void)setCueFileName:(NSString *)str
{
	if(cueFileName) [cueFileName release];
	cueFileName = [str retain];
}

- (NSString *)cueFileName
{
	return cueFileName;
}

- (void)addLogDirectory:(NSString *)str
{
	int i;
	for(i=0;i<[logDirectoryArray count];i++) {
		if([str isEqualToString:[logDirectoryArray objectAtIndex:i]]) return;
	}
	[logDirectoryArray addObject:str];
}

- (void)addCueDirectory:(NSString *)str withIndex:(int)idx
{
	int i;
	for(i=0;i<[cueDirectoryArray count];i++) {
		if([str isEqualToString:[[cueDirectoryArray objectAtIndex:i] objectAtIndex:0]]) {
			if([[[cueDirectoryArray objectAtIndex:i] objectAtIndex:1] intValue] == idx) return;
		}
	}
	[cueDirectoryArray addObject:[NSArray arrayWithObjects:str,[NSNumber numberWithInt:idx],nil]];
}

- (BOOL)allTasksFinished
{
	int i;
	if(!results) return YES;
	for(i=0;i<trackNumber+1;i++) {
		if(results[i].enabled && !results[i].finished) return NO;
		if(results[i].testEnabled && !results[i].testFinished) return NO;
	}
	return YES;
}

- (int)numberOfTracks
{
	return trackNumber;
}

- (NSString *)deviceStr
{
	return deviceStr;
}

- (void)setRipperMode:(XLDRipperMode)mode
	  offsetCorrention:(int)o
			retryCount:(int)ret
	  useAccurateRipDB:(BOOL)useDB
	checkInconsistency:(BOOL)checkFlag
		 trustARResult:(BOOL)trustFlag
		scanReplayGain:(BOOL)rgFlag
			 gapStatus:(unsigned int)status
{
	ripperMode = mode;
	offset = o;
	retryCount = ret;
	useAccurateRipDB = useDB;
	trustAccurateRipResult = trustFlag;
	gapStatus = status;
	int i;
	for(i=0;i<trackNumber+1;i++) {
		results[i].checkInconsistency = checkFlag;
		results[i].scanReplayGain = rgFlag;
	}
}

- (void)analyzeGain
{
	int i;
	if(results[0].enabled) {
		if(!results[0].cancelled && results[0].scanReplayGain) {
			float albumGain = PINK_REF-gain_get_album(rg);
			float albumPeak = peak_get_album(rg);
			for(i=0;i<[trackList count];i++) {
				[[[trackList objectAtIndex:i] metadata] setObject:[NSNumber numberWithFloat:albumGain] forKey:XLD_METADATA_REPLAYGAIN_ALBUM_GAIN];
				[[[trackList objectAtIndex:i] metadata] setObject:[NSNumber numberWithFloat:albumPeak] forKey:XLD_METADATA_REPLAYGAIN_ALBUM_PEAK];
			}
		}
		for(i=1;i<trackNumber+1;i++) {
			if(![results[i].validator crc32]) continue;
			if(results[0].cancelled && (i == trackNumber || ![results[i+1].validator crc32])) continue;
			if(!results[0].cancelled && results[i].scanReplayGain) {
				[[[trackList objectAtIndex:i-1] metadata] setObject:[NSNumber numberWithFloat:results[i].trackGain] forKey:XLD_METADATA_REPLAYGAIN_TRACK_GAIN];
				[[[trackList objectAtIndex:i-1] metadata] setObject:[NSNumber numberWithFloat:results[i].peak] forKey:XLD_METADATA_REPLAYGAIN_TRACK_PEAK];
			}
		}
	}
	else {
		/* album gain should be disabled unless all tracks except the data track are ripped */
		for(i=0;i<[trackList count];i++) {
			BOOL dataTrack = NO;
			if([[[trackList objectAtIndex:i] metadata] objectForKey:XLD_METADATA_DATATRACK]) {
				dataTrack = [[[[trackList objectAtIndex:i] metadata] objectForKey:XLD_METADATA_DATATRACK] boolValue];
			}
			if(results[i+1].cancelled || (!results[i+1].enabled && !dataTrack)) {
				results[0].scanReplayGain = NO;
				break;
			}
		}
		if(results[0].scanReplayGain) {
			float albumGain = PINK_REF-gain_get_album(rg);
			float albumPeak = peak_get_album(rg);
			for(i=0;i<[trackList count];i++) {
				[[[trackList objectAtIndex:i] metadata] setObject:[NSNumber numberWithFloat:albumGain] forKey:XLD_METADATA_REPLAYGAIN_ALBUM_GAIN];
				[[[trackList objectAtIndex:i] metadata] setObject:[NSNumber numberWithFloat:albumPeak] forKey:XLD_METADATA_REPLAYGAIN_ALBUM_PEAK];
			}
		}
		for(i=1;i<trackNumber+1;i++) {
			if(!results[i].enabled) continue;
			if(results[i].scanReplayGain) {
				[[[trackList objectAtIndex:i-1] metadata] setObject:[NSNumber numberWithFloat:results[i].trackGain] forKey:XLD_METADATA_REPLAYGAIN_TRACK_GAIN];
				[[[trackList objectAtIndex:i-1] metadata] setObject:[NSNumber numberWithFloat:results[i].peak] forKey:XLD_METADATA_REPLAYGAIN_TRACK_PEAK];
			}
		}
	}
}

- (NSString *)logStr
{
	if(!results) return nil;
	//if(!useParanoia) return nil;
	isGoodRip = YES;
	BOOL error = NO;
	BOOL inconsistency = NO;
	int i,j;
	NSMutableString *out = [[NSMutableString alloc] init];
	[out appendString:[NSString stringWithFormat:@"X Lossless Decoder version %@ (%@)\n\n",[[[NSBundle mainBundle] infoDictionary] valueForKey:@"CFBundleShortVersionString"],[[[NSBundle mainBundle] infoDictionary] valueForKey:@"CFBundleVersion"]]];
	[out appendString:[NSString stringWithFormat:@"XLD extraction logfile from %@\n\n",[date localizedDateDescription]]];
	[out appendString:[NSString stringWithFormat:@"%@ / %@\n\n",artist ? artist : @"",title]];
	[out appendString:[NSString stringWithFormat:@"Used drive : %@\n\n",driveStr]];
	if(ripperMode & kRipperModeParanoia) {
		[out appendString:@"Ripper mode             : CDParanoia III 10.2\n"];
		[out appendString:@"Disable audio cache     : OK for the drive with a cache less than 2750KiB\n"];
	}
	else if(ripperMode & kRipperModeXLD) {
		[out appendString:@"Ripper mode             : XLD Secure Ripper\n"];
		[out appendString:@"Disable audio cache     : OK for the drive with a cache less than 1375KiB\n"];
	}
	else {
		[out appendString:@"Ripper mode             : Burst\n"];
		[out appendString:@"Disable audio cache     : NO\n"];
	}
	[out appendString:[NSString stringWithFormat:@"Make use of C2 pointers : %@\n",(ripperMode & kRipperModeC2) ? @"YES" : @"NO"]];
	[out appendString:[NSString stringWithFormat:@"Read offset correction  : %d\n",offset]];
	[out appendString:[NSString stringWithFormat:@"Max retry count         : %d\n",retryCount]];
	[out appendString:@"Gap status              : "];
	if(gapStatus >> 16) [out appendString:@"Not analyzed\n\n"];
	else {
		switch(gapStatus & 0xffff) {
			case 0:
				[out appendString:@"Analyzed, Appended\n\n"];
				break;
			case 1:
				[out appendString:@"Analyzed, Not appended\n\n"];
				break;
			case 2:
				[out appendString:@"Analyzed, Appended\n\n"];
				break;
			case 3:
				[out appendString:@"Analyzed, Appended (except HTOA)\n\n"];
				break;
			default:
				[out appendString:@"Unknown\n\n"];
				break;
		}
	}
	
	[out appendString:@"TOC of the extracted CD\n"];
	[out appendString:@"     Track |   Start  |  Length  | Start sector | End sector \n"];
	[out appendString:@"    ---------------------------------------------------------\n"];
	for(i=0;i<trackNumber;i++) {
		[out appendString:[NSString stringWithFormat:@"      % 3d  | %@ | %@ |   % 7lld    |  % 7lld   \n",i+1,framesToMSFStr(indexArr[i],44100),framesToMSFStr(lengthArr[i],44100),indexArr[i]/588,(indexArr[i]+lengthArr[i])/588-1]];
	}
	[out appendString:@"\n"];
	
	if(useAccurateRipDB) {
		for(i=1;i<=trackNumber;i++) {
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
	}
	if(useAccurateRipDB && [detectedOffset count]) {
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
					if(n==1) {
						[out appendString:@"List of alternate offset correction values\n"];
						[out appendString:@"        #  | Absolute | Relative | Confidence \n"];
						[out appendString:@"    ------------------------------------------\n"];
					}
					NSString *str = [NSString stringWithFormat:@"       %2d  |  % 5d   |  % 5d   |    % 3d     \n",n++,offset+[[offsetList objectAtIndex:i] intValue],[[offsetList objectAtIndex:i] intValue],confidence];
					[out appendString:str];
				}
			}
			previousConfidence = confidence;
		}
		if(n>1) [out appendString:@"\n"];
	}
	
	int ARStatusPos = [out length];
	
	if(results[0].enabled) {
		if(results[0].errorCount || results[0].skipCount) error = YES;
		[out appendString:@"All Tracks\n"];
		if(results[0].filename) [out appendString:[NSString stringWithFormat:@"    Filename : %@\n",results[0].filename]];
		else {
			for(i=0;i<[results[0].filelist count];i++) {
				if(i==0) [out appendString:[NSString stringWithFormat:@"    Filename : %@\n",[results[0].filelist objectAtIndex:i]]];
				else [out appendString:[NSString stringWithFormat:@"               %@\n",[results[0].filelist objectAtIndex:i]]];
			}
		}
		if(results[0].cancelled) {
			[out appendString:@"    (cancelled by user)\n\n"];
			isGoodRip = NO;
		}
		else {
			if(results[0].scanReplayGain) {
				float albumGain = PINK_REF-gain_get_album(rg);
				float albumPeak = peak_get_album(rg);
				/*for(i=0;i<[trackList count];i++) {
					[[[trackList objectAtIndex:i] metadata] setObject:[NSNumber numberWithFloat:albumGain] forKey:XLD_METADATA_REPLAYGAIN_ALBUM_GAIN];
					[[[trackList objectAtIndex:i] metadata] setObject:[NSNumber numberWithFloat:albumPeak] forKey:XLD_METADATA_REPLAYGAIN_ALBUM_PEAK];
				}*/
				[out appendString:[NSString stringWithFormat:@"    Album gain               : %.2f dB\n",albumGain]];
				[out appendString:[NSString stringWithFormat:@"    Peak                     : %f\n",albumPeak]];
			}
			if(results[0].testEnabled) {
				[out appendString:[NSString stringWithFormat:@"    CRC32 hash (test run)    : %08X\n",[results[0].validator crc32Test]]];
			}
			[out appendString:[NSString stringWithFormat:@"    CRC32 hash               : %08X\n",[results[0].validator crc32]]];
			if(results[0].testEnabled) {
				if([results[0].validator crc32Test] != [results[0].validator crc32]) {
					inconsistency = YES;
					[out appendString:@"        ->Rip may not be accurate.\n"];
				}
			}
			[out appendString:[NSString stringWithFormat:@"    CRC32 hash (skip zero)   : %08X\n",[results[0].validator crc32EAC]]];
			if(ripperMode & kRipperModeParanoia) {
				[out appendString:@"    Statistics\n"];
				[out appendString:[NSString stringWithFormat:@"        Read error                           : %d\n",results[0].errorCount]];
				[out appendString:[NSString stringWithFormat:@"        Skipped (treated as error)           : %d\n",results[0].skipCount]];
				[out appendString:[NSString stringWithFormat:@"        Edge jitter error (maybe fixed)      : %d\n",results[0].edgeJitterCount]];
				[out appendString:[NSString stringWithFormat:@"        Atom jitter error (maybe fixed)      : %d\n",results[0].atomJitterCount]];
				[out appendString:[NSString stringWithFormat:@"        Drift error (maybe fixed)            : %d\n",results[0].driftCount]];
				[out appendString:[NSString stringWithFormat:@"        Dropped bytes error (maybe fixed)    : %d\n",results[0].droppedCount]];
				[out appendString:[NSString stringWithFormat:@"        Duplicated bytes error (maybe fixed) : %d\n",results[0].duplicatedCount]];
				//[out appendString:[NSString stringWithFormat:@"        Cache error (maybe not a problem)    : %d\n",results[0].cacheErrorCount]];
				if(results[0].checkInconsistency) {
					[out appendString:[NSString stringWithFormat:@"        Inconsistency in error sectors       : %d\n",results[0].inconsistency]];
					if(results[0].inconsistency) {
						inconsistency = YES;
						[out appendString:@"        List of suspicious positions         :\n"];
						for(j=0;j<[results[0].suspiciousPosition count];j++) {
							[out appendString:[NSString stringWithFormat:@"            (%d) %@\n",j+1,framesToMSFStr([[results[0].suspiciousPosition objectAtIndex:j] intValue]*588,44100)]];
						}
					}
				}
			}
			else if(ripperMode & kRipperModeXLD) {
				[out appendString:@"    Statistics\n"];
				[out appendString:[NSString stringWithFormat:@"        Read error                           : %d\n",results[0].errorCount]];
				[out appendString:[NSString stringWithFormat:@"        Jitter error (maybe fixed)           : %d\n",results[0].edgeJitterCount]];
				[out appendString:[NSString stringWithFormat:@"        Retry sector count                   : %d\n",results[0].retrySectorCount]];
				[out appendString:[NSString stringWithFormat:@"        Damaged sector count                 : %d\n",results[0].damagedSectorCount]];
				if(results[0].damagedSectorCount) inconsistency = YES;
				if(results[0].checkInconsistency) {
					if(results[0].inconsistency) {
						[out appendString:@"        List of damaged sector positions     :\n"];
						for(j=0;j<[results[0].suspiciousPosition count];j++) {
							[out appendString:[NSString stringWithFormat:@"            (%d) %@\n",j+1,framesToMSFStr([[results[0].suspiciousPosition objectAtIndex:j] intValue]*588,44100)]];
						}
					}
				}
				
			}
			[out appendString:@"\n"];
		}
		for(i=1;i<trackNumber+1;i++) {
			if(![results[i].validator crc32]) continue;
			if(results[0].cancelled && (i == trackNumber || ![results[i+1].validator crc32])) continue;
			[out appendString:[NSString stringWithFormat:@"Track %02d\n",i]];
			int gap = [[trackList objectAtIndex:i-1] gap]+((i==1)?88200:0);
			if(gap) [out appendString:[NSString stringWithFormat:@"    Pre-gap length : %@\n",framesToMSFStr(gap,44100)]];
			[out appendString:@"\n"];
			if(!results[0].cancelled && results[i].scanReplayGain) {
				[out appendString:[NSString stringWithFormat:@"    Track gain               : %.2f dB\n",results[i].trackGain]];
				[out appendString:[NSString stringWithFormat:@"    Peak                     : %f\n",results[i].peak]];
				/*[[[trackList objectAtIndex:i-1] metadata] setObject:[NSNumber numberWithFloat:results[i].trackGain] forKey:XLD_METADATA_REPLAYGAIN_TRACK_GAIN];
				[[[trackList objectAtIndex:i-1] metadata] setObject:[NSNumber numberWithFloat:results[i].peak] forKey:XLD_METADATA_REPLAYGAIN_TRACK_PEAK];*/
			}
			if([results[i].validator crc32Test]) {
				[out appendString:[NSString stringWithFormat:@"    CRC32 hash (test run)    : %08X\n",[results[i].validator crc32Test]]];
			}
			[out appendString:[NSString stringWithFormat:@"    CRC32 hash               : %08X\n",[results[i].validator crc32]]];
			if([results[i].validator crc32Test]) {
				if([results[i].validator crc32Test] != [results[i].validator crc32]) [out appendString:@"        ->Rip may not be accurate.\n"];
			}
			[out appendString:[NSString stringWithFormat:@"    CRC32 hash (skip zero)   : %08X\n",[results[i].validator crc32EAC]]];
			if(useAccurateRipDB) {
				BOOL result = dumpAccurateRipLog(out, &results[i]);
				if(!result && trustAccurateRipResult) inconsistency = YES;
			}
			
			if(ripperMode == kRipperModeBurst) {
				[out appendString:@"\n"];
				continue;
			}
			else if(ripperMode & kRipperModeParanoia) {
				[out appendString:@"    Statistics\n"];
				[out appendString:[NSString stringWithFormat:@"        Read error                           : %d\n",results[i].errorCount]];
				[out appendString:[NSString stringWithFormat:@"        Skipped (treated as error)           : %d\n",results[i].skipCount]];
				[out appendString:[NSString stringWithFormat:@"        Edge jitter error (maybe fixed)      : %d\n",results[i].edgeJitterCount]];
				[out appendString:[NSString stringWithFormat:@"        Atom jitter error (maybe fixed)      : %d\n",results[i].atomJitterCount]];
				[out appendString:[NSString stringWithFormat:@"        Drift error (maybe fixed)            : %d\n",results[i].driftCount]];
				[out appendString:[NSString stringWithFormat:@"        Dropped bytes error (maybe fixed)    : %d\n",results[i].droppedCount]];
				[out appendString:[NSString stringWithFormat:@"        Duplicated bytes error (maybe fixed) : %d\n",results[i].duplicatedCount]];
				//[out appendString:[NSString stringWithFormat:@"        Cache error (maybe not a problem)    : %d\n",results[i].cacheErrorCount]];
				if(results[i].checkInconsistency) {
					[out appendString:[NSString stringWithFormat:@"        Inconsistency in error sectors       : %d\n",results[i].inconsistency]];
					if(results[i].inconsistency) {
						[out appendString:@"        List of suspicious positions         :\n"];
						for(j=0;j<[results[i].suspiciousPosition count];j++) {
							[out appendString:[NSString stringWithFormat:@"            (%d) %@\n",j+1,framesToMSFStr([[results[i].suspiciousPosition objectAtIndex:j] intValue]*588-indexArr[i-1],44100)]];
						}
					}
				}
			}
			else if(ripperMode & kRipperModeXLD) {
				[out appendString:@"    Statistics\n"];
				[out appendString:[NSString stringWithFormat:@"        Read error                           : %d\n",results[i].errorCount]];
				[out appendString:[NSString stringWithFormat:@"        Jitter error (maybe fixed)           : %d\n",results[i].edgeJitterCount]];
				[out appendString:[NSString stringWithFormat:@"        Retry sector count                   : %d\n",results[i].retrySectorCount]];
				[out appendString:[NSString stringWithFormat:@"        Damaged sector count                 : %d\n",results[i].damagedSectorCount]];
				if(results[i].damagedSectorCount) inconsistency = YES;
				if(results[i].checkInconsistency) {
					if(results[i].inconsistency) {
						[out appendString:@"        List of damaged sector positions     :\n"];
						for(j=0;j<[results[i].suspiciousPosition count];j++) {
							[out appendString:[NSString stringWithFormat:@"            (%d) %@\n",j+1,framesToMSFStr([[results[i].suspiciousPosition objectAtIndex:j] intValue]*588-indexArr[i-1],44100)]];
						}
					}
				}
				
			}
			[out appendString:@"\n"];
		}
	}
	else {
		if(results[0].scanReplayGain) {
			/* album gain should be disabled unless all tracks except the data track are ripped */
			for(i=0;i<[trackList count];i++) {
				BOOL dataTrack = NO;
				if([[[trackList objectAtIndex:i] metadata] objectForKey:XLD_METADATA_DATATRACK]) {
					dataTrack = [[[[trackList objectAtIndex:i] metadata] objectForKey:XLD_METADATA_DATATRACK] boolValue];
				}
				if(results[i+1].cancelled || (!results[i+1].enabled && !dataTrack)) {
					results[0].scanReplayGain = NO;
					break;
				}
			}
		}
		if(results[0].scanReplayGain || (!results[0].cancelled && ripperMode != kRipperModeBurst))
			[out appendString:@"All Tracks\n"];
		if(results[0].scanReplayGain) {
			float albumGain = PINK_REF-gain_get_album(rg);
			float albumPeak = peak_get_album(rg);
			/*for(i=0;i<[trackList count];i++) {
				[[[trackList objectAtIndex:i] metadata] setObject:[NSNumber numberWithFloat:albumGain] forKey:XLD_METADATA_REPLAYGAIN_ALBUM_GAIN];
				[[[trackList objectAtIndex:i] metadata] setObject:[NSNumber numberWithFloat:albumPeak] forKey:XLD_METADATA_REPLAYGAIN_ALBUM_PEAK];
			}*/
			[out appendString:[NSString stringWithFormat:@"    Album gain               : %.2f dB\n",albumGain]];
			[out appendString:[NSString stringWithFormat:@"    Peak                     : %f\n",albumPeak]];
		}
		if(!results[0].cancelled) {
			if(ripperMode & kRipperModeParanoia) {
				[out appendString:@"    Statistics\n"];
				[out appendString:[NSString stringWithFormat:@"        Read error                           : %d\n",results[0].errorCount]];
				[out appendString:[NSString stringWithFormat:@"        Skipped (treated as error)           : %d\n",results[0].skipCount]];
				[out appendString:[NSString stringWithFormat:@"        Edge jitter error (maybe fixed)      : %d\n",results[0].edgeJitterCount]];
				[out appendString:[NSString stringWithFormat:@"        Atom jitter error (maybe fixed)      : %d\n",results[0].atomJitterCount]];
				[out appendString:[NSString stringWithFormat:@"        Drift error (maybe fixed)            : %d\n",results[0].driftCount]];
				[out appendString:[NSString stringWithFormat:@"        Dropped bytes error (maybe fixed)    : %d\n",results[0].droppedCount]];
				[out appendString:[NSString stringWithFormat:@"        Duplicated bytes error (maybe fixed) : %d\n",results[0].duplicatedCount]];
			}
			else if(ripperMode & kRipperModeXLD) {
				[out appendString:@"    Statistics\n"];
				[out appendString:[NSString stringWithFormat:@"        Read error                           : %d\n",results[0].errorCount]];
				[out appendString:[NSString stringWithFormat:@"        Jitter error (maybe fixed)           : %d\n",results[0].edgeJitterCount]];
				[out appendString:[NSString stringWithFormat:@"        Retry sector count                   : %d\n",results[0].retrySectorCount]];
				[out appendString:[NSString stringWithFormat:@"        Damaged sector count                 : %d\n",results[0].damagedSectorCount]];
			}
		}
		if(results[0].scanReplayGain || (!results[0].cancelled && ripperMode != kRipperModeBurst))
			[out appendString:@"\n"];
		
		for(i=1;i<trackNumber+1;i++) {
			if(!results[i].enabled) continue;
			if(results[i].errorCount || results[i].skipCount) error = YES;
			[out appendString:[NSString stringWithFormat:@"Track %02d\n",i]];
			if(results[i].filename) [out appendString:[NSString stringWithFormat:@"    Filename : %@\n",results[i].filename]];
			else {
				for(j=0;j<[results[i].filelist count];j++) {
					if(j==0) [out appendString:[NSString stringWithFormat:@"    Filename : %@\n",[results[i].filelist objectAtIndex:j]]];
					else [out appendString:[NSString stringWithFormat:@"               %@\n",[results[i].filelist objectAtIndex:j]]];
				}
			}
			if(results[i].cancelled) {
				[out appendString:@"    (cancelled by user)\n\n"];
				isGoodRip = NO;
				continue;
			}
			int gap = [[trackList objectAtIndex:i-1] gap]+((i==1)?88200:0);
			if(gap) [out appendString:[NSString stringWithFormat:@"    Pre-gap length : %@\n",framesToMSFStr(gap,44100)]];
			[out appendString:@"\n"];
			if(results[i].scanReplayGain) {
				[out appendString:[NSString stringWithFormat:@"    Track gain               : %.2f dB\n",results[i].trackGain]];
				[out appendString:[NSString stringWithFormat:@"    Peak                     : %f\n",results[i].peak]];
				/*[[[trackList objectAtIndex:i-1] metadata] setObject:[NSNumber numberWithFloat:results[i].trackGain] forKey:XLD_METADATA_REPLAYGAIN_TRACK_GAIN];
				[[[trackList objectAtIndex:i-1] metadata] setObject:[NSNumber numberWithFloat:results[i].peak] forKey:XLD_METADATA_REPLAYGAIN_TRACK_PEAK];*/
			}
			if(results[i].testEnabled) {
				[out appendString:[NSString stringWithFormat:@"    CRC32 hash (test run)    : %08X\n",[results[i].validator crc32Test]]];
			}
			[out appendString:[NSString stringWithFormat:@"    CRC32 hash               : %08X\n",[results[i].validator crc32]]];
			if(results[i].testEnabled) {
				if([results[i].validator crc32Test] != [results[i].validator crc32]) {
					inconsistency = YES;
					[out appendString:@"        ->Rip may not be accurate.\n"];
				}
			}
			[out appendString:[NSString stringWithFormat:@"    CRC32 hash (skip zero)   : %08X\n",[results[i].validator crc32EAC]]];
			if(useAccurateRipDB) {
				BOOL result = dumpAccurateRipLog(out, &results[i]);
				if(!result && trustAccurateRipResult) inconsistency = YES;
			}
			
			if(ripperMode == kRipperModeBurst) {
				[out appendString:@"\n"];
				continue;
			}
			else if(ripperMode & kRipperModeParanoia) {
				[out appendString:@"    Statistics\n"];
				[out appendString:[NSString stringWithFormat:@"        Read error                           : %d\n",results[i].errorCount]];
				[out appendString:[NSString stringWithFormat:@"        Skipped (treated as error)           : %d\n",results[i].skipCount]];
				[out appendString:[NSString stringWithFormat:@"        Edge jitter error (maybe fixed)      : %d\n",results[i].edgeJitterCount]];
				[out appendString:[NSString stringWithFormat:@"        Atom jitter error (maybe fixed)      : %d\n",results[i].atomJitterCount]];
				[out appendString:[NSString stringWithFormat:@"        Drift error (maybe fixed)            : %d\n",results[i].driftCount]];
				[out appendString:[NSString stringWithFormat:@"        Dropped bytes error (maybe fixed)    : %d\n",results[i].droppedCount]];
				[out appendString:[NSString stringWithFormat:@"        Duplicated bytes error (maybe fixed) : %d\n",results[i].duplicatedCount]];
				//[out appendString:[NSString stringWithFormat:@"        Cache error (maybe not a problem)    : %d\n",results[i].cacheErrorCount]];
				if(results[i].checkInconsistency) {
					[out appendString:[NSString stringWithFormat:@"        Inconsistency in error sectors       : %d\n",results[i].inconsistency]];
					if(results[i].inconsistency) {
						inconsistency = YES;
						[out appendString:@"        List of suspicious positions         :\n"];
						for(j=0;j<[results[i].suspiciousPosition count];j++) {
							[out appendString:[NSString stringWithFormat:@"            (%d) %@\n",j+1,framesToMSFStr([[results[i].suspiciousPosition objectAtIndex:j] intValue]*588-indexArr[i-1],44100)]];
						}
					}
				}
			}
			else if(ripperMode & kRipperModeXLD) {
				[out appendString:@"    Statistics\n"];
				[out appendString:[NSString stringWithFormat:@"        Read error                           : %d\n",results[i].errorCount]];
				[out appendString:[NSString stringWithFormat:@"        Jitter error (maybe fixed)           : %d\n",results[i].edgeJitterCount]];
				[out appendString:[NSString stringWithFormat:@"        Retry sector count                   : %d\n",results[i].retrySectorCount]];
				[out appendString:[NSString stringWithFormat:@"        Damaged sector count                 : %d\n",results[i].damagedSectorCount]];
				if(results[i].damagedSectorCount) inconsistency = YES;
				if(results[i].checkInconsistency) {
					if(results[i].inconsistency) {
						[out appendString:@"        List of damaged sector positions     :\n"];
						for(j=0;j<[results[i].suspiciousPosition count];j++) {
							[out appendString:[NSString stringWithFormat:@"            (%d) %@\n",j+1,framesToMSFStr([[results[i].suspiciousPosition objectAtIndex:j] intValue]*588-indexArr[i-1],44100)]];
						}
					}
				}
				
			}
			[out appendString:@"\n"];
		}
	}
	
	if(useAccurateRipDB && database) {
		int checked = 0;
		int good = 0;
		int bad = 0;
		int notfound = 0;
		NSMutableString *status = [NSMutableString string];
		[status appendString:[NSString stringWithFormat:@"AccurateRip Summary (DiscID: %@)\n",[database discID]]];
		for(i=1;i<=trackNumber;i++) {
			if(results[i].ARStatus == XLDARStatusNoQuery) continue;
			int totalSubmissions = [results[i].validator totalARSubmissions];
			[status appendString:[NSString stringWithFormat:@"    Track %02d : ",i]];
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
		if(isGoodRip) {
			if(checked == good) [status appendString:@"        ->All tracks accurately ripped.\n\n"];
			else if(notfound && bad) [status appendString:[NSString stringWithFormat:@"        ->%d track%s accurately ripped, %d track%s not, %d track%s not found\n\n",good,good>1?"s":"",bad,bad>1?"s":"",notfound,notfound>1?"s":""]];
			else if(bad) [status appendString:[NSString stringWithFormat:@"        ->%d track%s accurately ripped, %d track%s not\n\n",good,good>1?"s":"",bad,bad>1?"s":""]];
			else [status appendString:[NSString stringWithFormat:@"        ->%d track%s accurately ripped, %d track%s not found\n\n",good,good>1?"s":"",notfound,notfound>1?"s":""]];
		}
		else [status appendString:@"\n"];
		[out insertString:status atIndex:ARStatusPos];
	}
	else if(useAccurateRipDB) {
		[out insertString:@"AccurateRip Summary\n    Disc not found in AccurateRip DB.\n\n"  atIndex:ARStatusPos];
	}
	
	if(ripperMode != kRipperModeBurst) {
		if(!error && !inconsistency) [out appendString:@"No errors occurred\n\n"];
		else if(error) {
			[out appendString:@"Some errors occurred\n\n"];
			isGoodRip = NO;
		}
		else if(inconsistency) {
			[out appendString:@"Some inconsistencies found\n\n"];
			isGoodRip = NO;
		}
	}
	
	[out appendString:@"End of status report\n"];
	
	return [out autorelease];
}

- (BOOL)isGoodRip
{
	return isGoodRip;
}

- (void)saveLog
{
	int i,j;
	if(results[0].enabled && results[0].cancelled) return;
	else {
		for(i=1;i<trackNumber+1;i++) {
			if(!results[i].enabled) continue;
			if(results[i].cancelled) return;
		}
	}
	if(logFileName && [logDirectoryArray count]) {
		NSString *logStr = [self logStr];
		if(!logStr) return;
		for(i=0;i<[logDirectoryArray count];i++) {
			NSString *savePath = [[logDirectoryArray objectAtIndex:i] stringByAppendingPathComponent:logFileName];
			if(processOfExistingFiles != 2) {
				j=1;
				while([[NSFileManager defaultManager] fileExistsAtPath:savePath]) {
					savePath = [[logDirectoryArray objectAtIndex:i] stringByAppendingPathComponent:[[NSString stringWithFormat:@"%@(%d)",[logFileName stringByDeletingPathExtension],j] stringByAppendingPathExtension:@"log"]];
					j++;
				}
			}
			[[logStr dataUsingEncoding:NSUTF8StringEncoding] writeToFile:savePath atomically:YES];
		}
	}
}

- (void)setTOC:(NSArray *)arr
{
	int i;
	for(i=0;i<[arr count];i++) {
		[trackList addObject:[arr objectAtIndex:i]];
		indexArr[i] = [(XLDTrack *)[arr objectAtIndex:i] index];
		if(i == ([arr count]-1)) {
			lengthArr[i] = [(XLDTrack *)[arr objectAtIndex:i] frames];
			if((i==0) && ([(XLDTrack *)[arr objectAtIndex:i] gap] !=0) && includeHTOA) {
				actualLengthArr[i] = [(XLDTrack *)[arr objectAtIndex:i] gap] + [(XLDTrack *)[arr objectAtIndex:i] frames];
				[results[1].validator setInitialFrame:-[(XLDTrack *)[arr objectAtIndex:i] gap]];
			}
			else {
				actualLengthArr[i] = [(XLDTrack *)[arr objectAtIndex:i] frames];
			}
			[results[i+1].validator setTrackLength:[(XLDTrack *)[arr objectAtIndex:i] frames]];
		}
		else {
			lengthArr[i] = [(XLDTrack *)[arr objectAtIndex:i] frames] + [(XLDTrack *)[arr objectAtIndex:i+1] gap];
			if((i==0) && ([(XLDTrack *)[arr objectAtIndex:i] gap] !=0) && includeHTOA) {
				actualLengthArr[i] = [(XLDTrack *)[arr objectAtIndex:i] gap] + [(XLDTrack *)[arr objectAtIndex:i] frames] + [(XLDTrack *)[arr objectAtIndex:i+1] gap];
				[results[1].validator setInitialFrame:-[(XLDTrack *)[arr objectAtIndex:i] gap]];
			}
			else {
				actualLengthArr[i] = [(XLDTrack *)[arr objectAtIndex:i] frames] + [(XLDTrack *)[arr objectAtIndex:i+1] gap];
			}
			[results[i+1].validator setTrackLength:[(XLDTrack *)[arr objectAtIndex:i] frames] + [(XLDTrack *)[arr objectAtIndex:i+1] gap]];
		}
		
		if(i==0) {
			[results[1].validator setIsFirstTrack:YES];
		}
		if(i==([arr count]-1)) {
			[results[i+1].validator setIsLastTrack:YES];
		}
	}
	if([arr count] > 1 && ![(XLDTrack *)[arr objectAtIndex:[arr count]-1] enabled]) {
		int tmp1,tmp2;
		tmp1 = [(XLDTrack *)[arr objectAtIndex:[arr count]-1] index];
		tmp2 = [(XLDTrack *)[arr objectAtIndex:[arr count]-2] index] + [(XLDTrack *)[arr objectAtIndex:[arr count]-2] frames];
		if((tmp1 - tmp2) == 11400*588) {
			[results[[arr count]-1].validator setIsLastTrack:YES];
		}
	}
}

- (void)setTitle:(NSString*)t andArtist:(NSString *)a
{
	if(title) [title release];
	if(artist) [artist release];
	title = [t retain];
	artist = [a retain];
}

- (void)setAccurateRipDB:(id)db
{
	if(database) [database release];
	database = [db retain];
	if(useAccurateRipDB) {
		int i;
		for(i=1;i<trackNumber+1;i++) {
			[results[i].validator setAccurateRipDB:db];
		}
	}
}

- (id)accurateRipDB
{
	return database;
}

- (void)setCuePath:(NSString *)path
{
	if(cuePath) [cuePath release];
	cuePath = [path retain];
}

- (void)setCuePathArray:(NSArray *)arr
{
	if(cuePathArray) [cuePathArray release];
	cuePathArray = [arr retain];
}

- (void)saveCuesheetIfNeeded
{
	int i,j;
	/* single file */
	if(results[0].enabled) {
		if(results[0].cancelled) return;
		if(!results[0].scanReplayGain) return;
		if(!cuePath && !cuePathArray) return;
		if(cuePath) {
			[[XLDTrackListUtil cueDataForTracks:trackList withFileName:[results[0].filename lastPathComponent] appendBOM:appendBOM samplerate:44100] writeToFile:cuePath atomically:YES];
		}
		else {
			for(i=0;i<[cuePathArray count];i++) {
				[[XLDTrackListUtil cueDataForTracks:trackList withFileName:[[results[0].filelist objectAtIndex:i] lastPathComponent] appendBOM:appendBOM samplerate:44100] writeToFile:[cuePathArray objectAtIndex:i] atomically:YES];
			}
		}
	}
	/* separated files */
	else {
		if(!cueFileName) return;
		/* check if all audio tracks are ripped */
		BOOL isCompleteRip = YES;
		for(i=0;i<[trackList count];i++) {
			BOOL dataTrack = NO;
			if([[[trackList objectAtIndex:i] metadata] objectForKey:XLD_METADATA_DATATRACK]) {
				dataTrack = [[[[trackList objectAtIndex:i] metadata] objectForKey:XLD_METADATA_DATATRACK] boolValue];
			}
			if(results[i+1].cancelled || (!results[i+1].enabled && !dataTrack)) {
				isCompleteRip = NO;
				break;
			}
		}
		if(!isCompleteRip) return;
		for(j=0;j<[cueDirectoryArray count];j++) {
			int multipleFileIdx = [[[cueDirectoryArray objectAtIndex:j] objectAtIndex:1] intValue];
			NSMutableArray *filenameArray = [[NSMutableArray alloc] init];
			for(i=0;i<[trackList count];i++) {
				if(!results[i+1].enabled) continue;
				if(results[i+1].filename) [filenameArray addObject:[results[i+1].filename lastPathComponent]];
				else {
					if([results[i+1].filelist count] > multipleFileIdx)
						[filenameArray addObject:[[results[i+1].filelist objectAtIndex:multipleFileIdx] lastPathComponent]];
					else [filenameArray addObject:[NSString stringWithFormat:@"Track %d.wav",i+1]];
				}
			}
			NSString *savePath = [[[cueDirectoryArray objectAtIndex:j] objectAtIndex:0] stringByAppendingPathComponent:cueFileName];
			if(processOfExistingFiles != 2) {
				int k=1;
				while([[NSFileManager defaultManager] fileExistsAtPath:savePath]) {
					savePath = [[[cueDirectoryArray objectAtIndex:j] objectAtIndex:0] stringByAppendingPathComponent:[[NSString stringWithFormat:@"%@(%d)",[cueFileName stringByDeletingPathExtension],k] stringByAppendingPathExtension:@"cue"]];
					k++;
				}
			}
			[[XLDTrackListUtil nonCompliantCueDataForTracks:trackList withFileNameArray:filenameArray appendBOM:appendBOM gapStatus:gapStatus samplerate:44100] writeToFile:savePath atomically:YES];
			[filenameArray release];
		}
	}
}

- (void)setProcessOfExistingFiles:(int)value
{
	processOfExistingFiles = value;
}

- (void)setAppendBOM:(BOOL)flag
{
	appendBOM = flag;
}

- (void)setIncludeHTOA:(BOOL)flag
{
	includeHTOA = flag;
}

- (void)setRipperMode:(XLDRipperMode)mode
{
	ripperMode = mode;
}

@end
