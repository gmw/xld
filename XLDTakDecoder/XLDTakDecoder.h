//
//  XLDTakDecoder.h
//  XLDTakDecoder
//
//  Created by tmkk on 10/02/13.
//  Copyright 2010 tmkk. All rights reserved.
//

typedef enum {
	XLDNoCueSheet = 0,
	XLDTrackTypeCueSheet,
	XLDTextTypeCueSheet
} XLDEmbeddedCueSheetType;

#import <Cocoa/Cocoa.h>
#import "XLDDecoder.h"

@interface XLDTakDecoder : NSObject <XLDDecoder> {
	int bps;
	int samplerate;
	int channels;
	xldoffset_t totalFrames;
	BOOL error;
	NSMutableDictionary *metadataDic;
	NSString *srcPath;
	NSTask *task;
	unsigned char *recvBuf;
	int recvBufSize;
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

@end
