//
//  XLDMultipleFileWrappedDecoder.h
//  XLD
//
//  Created by tmkk on 11/02/24.
//  Copyright 2011 tmkk. All rights reserved.
//

#import "XLDDecoder.h"
#import "XLDDiscLayout.h"

@interface XLDMultipleFileWrappedDecoder : NSObject <XLDDecoder>
{
	xldoffset_t totalFrames;
	xldoffset_t currentFrame;
	BOOL error;
	id decoder;
	XLDDiscLayout *discLayout;
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

- (id)initWithDiscLayout:(XLDDiscLayout *)layout;
- (XLDDiscLayout *)discLayout;

@end
