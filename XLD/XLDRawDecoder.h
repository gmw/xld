//
//  XLDRawDecoder.h
//  XLD
//
//  Created by tmkk on 06/10/09.
//  Copyright 2006 tmkk. All rights reserved.
//

#import "XLDDecoder.h"

@interface XLDRawDecoder : NSObject <XLDDecoder>
{
	XLDFormat format;
	FILE *fp;
	xldoffset_t totalFrames;
	XLDEndian endian;
	BOOL error;
	NSString *srcPath;
	int offsetBytes;
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

- (id)initWithFormat:(XLDFormat)fmt endian:(XLDEndian)e;
- (id)initWithFormat:(XLDFormat)fmt endian:(XLDEndian)e offset:(int)offset;
- (int)offset;
- (XLDEndian)endian;
@end