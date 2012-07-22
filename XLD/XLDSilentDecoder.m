//
//  XLDSilentDecoder.m
//  XLD
//
//  Created by tmkk on 11/02/24.
//  Copyright 2011 tmkk. All rights reserved.
//

#import "XLDSilentDecoder.h"

@implementation XLDSilentDecoder

+ (BOOL)canHandleFile:(char *)path
{
	return YES;
}

+ (BOOL)canLoadThisBundle
{
	return YES;
}

- (id)initWithTotalFrames:(xldoffset_t)length channels:(int)ch
{
	[self init];
	currentFrame = 0;
	totalFrames = length;
	channels = ch;
	return self;
}

- (BOOL)openFile:(char *)path
{
	return YES;
}

- (int)samplerate
{
	return 44100;
}

- (int)bytesPerSample
{
	return 2;
}

- (int)channels
{
	return channels;
}

- (int)decodeToBuffer:(int *)buffer frames:(int)count
{
	int ret = 0;
	if(currentFrame + count <= totalFrames) {
		bzero(buffer,count*4*channels);
		currentFrame += count;
		ret = count;
	}
	else if(currentFrame < totalFrames) {
		bzero(buffer,(totalFrames-currentFrame)*4*channels);
		ret = totalFrames-currentFrame;
		currentFrame = totalFrames;
	}	
	return ret;
}

- (void)closeFile
{

}

- (xldoffset_t)seekToFrame:(xldoffset_t)count
{
	currentFrame = count;
	if(currentFrame > totalFrames) currentFrame = totalFrames;
	return currentFrame;
}

- (xldoffset_t)totalFrames
{
	return totalFrames;
}

- (int)isFloat
{
	return 0;
}

- (BOOL)error
{
	return NO;
}

- (XLDEmbeddedCueSheetType)hasCueSheet
{
	return XLDNoCueSheet;
}

- (id)cueSheet
{
	return nil;
}

- (id)metadata
{
	return nil;
}

- (NSString *)srcPath
{
	return nil;
}

@end
