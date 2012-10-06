//
//  XLDCDDARipper.h
//  XLD
//
//  Created by tmkk on 08/08/09.
//  Copyright 2008 tmkk. All rights reserved.
//
//  Access to AccurateRip is regulated, see  http://www.accuraterip.com/3rdparty-access.htm for details.

#import <Cocoa/Cocoa.h>
#import "XLDCDDABackend.h"
#import "paranoia/cdda_paranoia.h"
#import "XLDDecoder.h"
#import "XLDCDDAResult.h"
#import "XLDSecureRipperEngine.h"

typedef struct
{
	BOOL have_cache;
	int cache_sector_size;
	int backseek_flush_capable;
} cache_analysis_t;

@interface XLDCDDARipper : NSObject <XLDDecoder>
{
	XLDFormat format;
	xldoffset_t totalFrames;
	BOOL error;
	NSString *srcPath;
	xld_cdread_t cdread;
	cdrom_paranoia_t* p_paranoia;
	int offsetCorrectionValue;
	int currentLSN;
	short *cddaBuffer;
	int cddaBufferSize;
	BOOL firstRead;
	int retryCount;
	BOOL unmounted;
	cddaRipResult *result;
	unsigned int currentFrame;
	unsigned int crc32Table[256];
	int currentTrack;
	BOOL testMode;
	int *preTrackSamples;
	int *postTrackSamples;
	BOOL cancel;
	int firstAudioFrame;
	int lastAudioFrame;
	unsigned char *burstBuffer;
	int cacheSectorCount;
	int startLSN;
	XLDSecureRipperEngine *secureRipper;
	XLDRipperMode ripperMode;
}

+ (BOOL)canHandleFile:(char *)path;
+ (BOOL)canLoadThisBundle;
+ (int)analyzeCacheForDrive:(NSString *)device result:(cache_analysis_t *)result_t delegate:(id)delegate;
- (BOOL)openFile:(char *)path;
- (int)samplerate;
- (int)bytesPerSample;
- (int)channels;
- (int)decodeToBuffer:(int *)buffer frames:(int)count;
- (int)decodeToBufferWithoutReport:(int *)buffer frames:(int)count;
- (void)closeFile;
- (xldoffset_t)seekToFrame:(xldoffset_t)count;
- (xldoffset_t)totalFrames;
- (int)isFloat;
- (BOOL)error;
- (XLDEmbeddedCueSheetType)hasCueSheet;
- (id)cueSheet;
- (id)metadata;
- (NSString *)srcPath;
- (void)setOffsetCorrectionValue:(int)value;
- (void)setRetryCount:(int)value;
- (void)setResultStructure:(cddaRipResult *)ptr;
- (void)setTestMode;
- (void)cancel;
- (void)setRipperMode:(XLDRipperMode)mode;
- (NSString *)driveStr;
- (void)analyzeTrackGain;
@end
