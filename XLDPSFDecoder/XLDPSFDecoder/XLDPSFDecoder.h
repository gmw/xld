//
//  XLDPSFDecoder.h
//  XLDPSFDecoder
//
//  Created by tmkk on 2017/03/09.
//  Copyright © 2017年 tmkk. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "XLDDecoder.h"

@interface XLDPSFDecoder : NSObject <XLDDecoder>
{
    NSString *srcPath;
    BOOL error;
    NSMutableDictionary *metadataDic;
    xldoffset_t totalFrames;
    xldoffset_t fadeBeginning;
    xldoffset_t currentPos;
    float *decodeBuffer;
    int bufferSize;
    
    int psfVersion;
    void *psxState;
    void *psf2fs;
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
