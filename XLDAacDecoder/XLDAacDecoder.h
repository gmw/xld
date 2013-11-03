//
//  XLDAacDecoder.h
//  XLDAacDecoder
//
//  Created by tmkk on 13/11/03.
//  Copyright 2013 tmkk. All rights reserved.
//

typedef enum {
	XLDNoCueSheet = 0,
	XLDTrackTypeCueSheet,
	XLDTextTypeCueSheet
} XLDEmbeddedCueSheetType;

#import <Cocoa/Cocoa.h>
#import <AudioToolbox/AudioToolbox.h>
#import "XLDDecoder.h"

@interface XLDAacDecoder : NSObject <XLDDecoder> {
	ExtAudioFileRef file;
	AudioBufferList fillBufList;
	int bps;
	int samplerate;
	int channels;
	xldoffset_t totalFrames;
	BOOL error;
	NSMutableDictionary *metadataDic;
	NSString *srcPath;
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
