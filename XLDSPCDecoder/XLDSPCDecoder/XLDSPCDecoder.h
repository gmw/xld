//
//  XLDSPCDecoder.h
//  XLDSPCDecoder
//
//  Created by tmkk on 2017/02/28.
//  Copyright © 2017年 tmkk. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "XLDDecoder.h"

@interface XLDSPCDecoder : NSObject <XLDDecoder>
{
    NSTask *task;
    NSString *srcPath;
    unsigned char *recvBuf;
    int recvBufSize;
    BOOL error;
    NSMutableDictionary *metadataDic;
    xldoffset_t totalFrames;
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
