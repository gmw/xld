//
//  XLDDiscLayout.h
//  XLD
//
//  Created by tmkk on 11/02/23.
//  Copyright 2011 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>

typedef struct
{
	xldoffset_t index;
	xldoffset_t length;
	NSString *path;
	BOOL raw;
	XLDEndian endian;
	int rawOffset;
} xld_disc_section_t;

@interface XLDDiscLayout : NSObject <NSCopying>
{
	id decoderCenter;
	int totalSections;
	xld_disc_section_t *sections;
	int channels;
	int samplerate;
	int bytesPerSample;
	int isFloat;
}

- (id)initWithDecoderCenter:(id)center;
- (void)addSection:(NSString*)path withLength:(xldoffset_t)length;
- (void)addRawSection:(NSString*)path withLength:(xldoffset_t)length endian:(XLDEndian)e offset:(int)offset;
- (void)insertSection:(NSString*)path atIndex:(int)idx withLength:(xldoffset_t)length;
- (id)decoderInstanceForFrame:(xldoffset_t)index;
- (void)setChannels:(int)ch;
- (void)setSamplerate:(int)rate;
- (void)setBytesPerSample:(int)bps;
- (void)setIsFloat:(int)f;
- (int)channels;
- (int)samplerate;
- (int)bytesPerSample;
- (int)isFloat;
- (xldoffset_t)totalFrames;
- (NSArray *)filePathList;
- (xldoffset_t)remainingFramesForFrame:(xldoffset_t)index;

@end
