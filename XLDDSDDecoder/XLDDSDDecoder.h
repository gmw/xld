//
//  XLDDSDDecoder.h
//  XLDDSDDecoder
//
//  Created by tmkk on 14/05/10.
//  Copyright 2014 tmkk. All rights reserved.
//

typedef enum {
	XLDNoCueSheet = 0,
	XLDTrackTypeCueSheet,
	XLDTextTypeCueSheet
} XLDEmbeddedCueSheetType;

#import <Cocoa/Cocoa.h>
#import "XLDDecoder.h"
#import "XLDSACDISOReader.h"
#import "dsd2pcm.h"
#import <soxr.h>

typedef enum {
	XLDDSDFormatDFF = 0,
	XLDDSDFormatDSF = 1,
	XLDDSDFormatSACDISO = 2
} XLDDSDFormat;

@interface XLDDSDDecoder : NSObject <XLDDecoder> {
	FILE *dsd_fp;
	int channels;
	int samplerate;
	int outSamplerate;
	int blockSize;
	unsigned char *dsdBuffer;
	float *pcmBuffer;
	float *residueBuffer;
	float *resampleBuffer;
	int residueSampleCount;
	xldoffset_t currentBlock;
	xldoffset_t totalBlocks;
	xldoffset_t totalDSDSamples;
	xldoffset_t totalPCMSamples;
	int DSDSamplesPerBlock;
	int PCMSamplesPerBlock;
	int DSDBytesPerBlock;
	int lastBlockDSDBytes;
	dsd2pcm_ctx **dsdProc;
	off_t dataStart;
	NSString *srcPath;
	XLDDSDFormat dsdFormat;
	id metadataDic;
	soxr_t soxr;
	float globalGain;
	int isFloat;
	unsigned long srcAlgorithm;
	int decimation;
	NSDictionary *configurations;
	XLDSACDISOReader *sacdReader;
	NSMutableArray *trackList;
}

+ (BOOL)canHandleFile:(char *)path;
+ (BOOL)canLoadThisBundle;
- (BOOL)openFile:(char *)path;
- (int)samplerate;
- (int)bytesPerSample;
- (int)channels;
- (int)decodeToBuffer:(int *)buffer frames:(int)count;
- (void)closeFile;
- (xldoffset_t)seekToFrame:(xldoffset_t)count;
- (xldoffset_t)totalFrames;
- (int)isFloat;
- (BOOL)error;
- (XLDEmbeddedCueSheetType)hasCueSheet;
- (id)cueSheet;
- (id)metadata;
- (NSString *)srcPath;
- (void)loadConfigurations:(NSDictionary *)cfg;

@end
