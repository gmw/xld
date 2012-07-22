
#import "XLDTrack.h"

@implementation XLDTrack
		
- (id)init
{
	[super init];
	frames = -1;
	enabled = YES;
	metadataDic = [[NSMutableDictionary alloc] init];
	return self;
}

- (void)dealloc
{
	if(desiredFileName) [desiredFileName release];
	[metadataDic release];
	[super dealloc];
}

- (xldoffset_t)index
{
	return index;
}

- (void)setIndex:(xldoffset_t)idx
{
	index = idx;
}

- (xldoffset_t)frames
{
	return frames;
}

- (void)setFrames:(xldoffset_t)blk
{
	frames = blk;
}

- (int)gap
{
	return gap;
}

- (void)setGap:(int)g
{
	gap = g;
}

- (BOOL)enabled
{
	return enabled;
}

- (void)setEnabled:(BOOL)flag
{
	enabled = flag;
}

- (NSString *)desiredFileName
{
	return desiredFileName;
}

- (void)setDesiredFileName:(NSString *)str
{
	if(desiredFileName) [desiredFileName release];
	desiredFileName = [str retain];
}

- (int)seconds
{
	return seconds;
}

- (void)setSeconds:(int)sec
{
	seconds = sec;
}

- (id)metadata
{
	return metadataDic;
}

- (void)setMetadata:(NSMutableDictionary *)data
{
	if(data) [metadataDic addEntriesFromDictionary:data];
}

@end