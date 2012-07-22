//
//  XLDMultipleFileWrappedDecoder.m
//  XLD
//
//  Created by tmkk on 11/02/24.
//  Copyright 2011 tmkk. All rights reserved.
//

#import "XLDMultipleFileWrappedDecoder.h"
#import "XLDSilentDecoder.h"

@implementation XLDMultipleFileWrappedDecoder

+ (BOOL)canHandleFile:(char *)path
{
	return YES;
}

+ (BOOL)canLoadThisBundle
{
	return YES;
}

- (id)initWithDiscLayout:(XLDDiscLayout *)layout
{
	[self init];
	discLayout = [layout retain];
	totalFrames = [layout totalFrames];
	error = XLDNoErr;
	return self;
}

- (void)dealloc
{
	if(decoder) {
		[decoder closeFile];
		[decoder release];
		decoder = nil;
	}
	[discLayout release];
	[super dealloc];
}

- (BOOL)openFile:(char *)path
{
	decoder = [[discLayout decoderInstanceForFrame:0] retain];
	currentFrame = 0;
	return YES;
}
	
- (int)samplerate
{
	return [discLayout samplerate];
}

- (int)bytesPerSample
{
	return [discLayout bytesPerSample];
}

- (int)channels
{
	return [discLayout channels];
}

- (int)decodeToBuffer:(int *)buffer frames:(int)count
{
	int read = 0;
	if(currentFrame >= totalFrames) return 0;

	while(count) {
		int ret = [decoder decodeToBuffer:buffer+read*[discLayout channels] frames:count];
		error = [(id <XLDDecoder>)decoder error];
		if(error) {
			break;
		}
		read += ret;
		currentFrame += ret;
		if(currentFrame >= totalFrames) break;
		if(ret < count) {
			[decoder closeFile];
			[decoder release];
			if([discLayout remainingFramesForFrame:currentFrame]) 
				decoder = [[XLDSilentDecoder alloc] initWithTotalFrames:[discLayout remainingFramesForFrame:currentFrame] channels:[self channels]];
			else
				decoder = [[discLayout decoderInstanceForFrame:currentFrame] retain];
		}
		count -= ret;
	}
	return read;
}
- (void)closeFile
{
	if(decoder) {
		[decoder closeFile];
		[decoder release];
		decoder = nil;
	}
}

- (xldoffset_t)seekToFrame:(xldoffset_t)count
{
	if(count >= totalFrames) {
		currentFrame = totalFrames;
		return totalFrames;
	}
	
	if(currentFrame != count) {
		currentFrame = count;
		[decoder closeFile];
		[decoder release];
		decoder = [[discLayout decoderInstanceForFrame:currentFrame] retain];
	}
	return count;
}
- (xldoffset_t)totalFrames
{
	return totalFrames;
}

- (int)isFloat
{
	return [discLayout isFloat];
}

- (BOOL)error
{
	return error;
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

- (XLDDiscLayout *)discLayout
{
	return discLayout;
}

@end

