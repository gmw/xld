//
//  XLDSACDISOReader.h
//  XLDDSDDecoder
//
//  Created by tmkk on 14/11/16.
//  Copyright 2014 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#include "DST/types.h"

@interface XLDSACDISOReader : NSObject {
	FILE *fp;
	xldoffset_t totalSamples;
	int numTracks;
	int trackLSN[256];
	NSMutableArray *trackList;
	int currentLSN;
	unsigned char *buffer;
	int bytesInBuffer;
	unsigned char *dstBuffer;
	unsigned int bytesInDSTBuffer;
	ebunch *dstDecoder;
}

- (BOOL)openFile:(NSString *)path;
- (int)readBytes:(unsigned char*)buf size:(int)size;
- (BOOL)seekTo:(off_t)pos;
- (xldoffset_t)totalDSDSamples;
- (void)closeFile;
- (NSMutableArray *)trackList;

@end
