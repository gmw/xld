//
//  XLDDiscLayout.m
//  XLD
//
//  Created by tmkk on 11/02/23.
//  Copyright 2011 tmkk. All rights reserved.
//

#import "XLDDiscLayout.h"
#import "XLDecoderCenter.h"
#import "XLDSilentDecoder.h"
#import "XLDRawDecoder.h"

@implementation XLDDiscLayout

- (id)initWithDecoderCenter:(id)center
{
	[self init];
	decoderCenter = [center retain];
	return self;
}

- (id)copyWithZone:(NSZone*)zone
{
	XLDDiscLayout * clone = [[[self class] allocWithZone:zone] initWithDecoderCenter:decoderCenter];
	clone->totalSections = totalSections;
	clone->channels = channels;
	clone->samplerate = samplerate;
	clone->bytesPerSample = bytesPerSample;
	clone->isFloat = isFloat;
	clone->sections = malloc(sizeof(xld_disc_section_t)*totalSections);
	memcpy(clone->sections,sections,sizeof(xld_disc_section_t)*totalSections);
	return clone;
}

- (void)dealloc
{
	int i;
	for(i=0;i<totalSections;i++) {
		if(sections[i].path) [sections[i].path release];
	}
	free(sections);
	[decoderCenter release];
	[super dealloc];
}

- (void)addSection:(NSString*)path withLength:(xldoffset_t)length
{
	sections = realloc(sections,sizeof(xld_disc_section_t)*++totalSections);
	if(totalSections == 1) {
		sections[0].index = 0;
	}
	else {
		sections[totalSections-1].index = sections[totalSections-2].index+sections[totalSections-2].length;
	}
	sections[totalSections-1].length = length;
	if(path) sections[totalSections-1].path = [path retain];
	else sections[totalSections-1].path = nil;
	sections[totalSections-1].raw = NO;
	sections[totalSections-1].endian = 0;
	sections[totalSections-1].rawOffset = 0;
}

- (void)addRawSection:(NSString*)path withLength:(xldoffset_t)length endian:(XLDEndian)e offset:(int)offset
{
	sections = realloc(sections,sizeof(xld_disc_section_t)*++totalSections);
	if(totalSections == 1) {
		sections[0].index = 0;
	}
	else {
		sections[totalSections-1].index = sections[totalSections-2].index+sections[totalSections-2].length;
	}
	sections[totalSections-1].length = length;
	if(path) sections[totalSections-1].path = [path retain];
	else sections[totalSections-1].path = nil;
	sections[totalSections-1].raw = YES;
	sections[totalSections-1].endian = e;
	sections[totalSections-1].rawOffset = offset;
}

- (void)insertSection:(NSString*)path atIndex:(int)idx withLength:(xldoffset_t)length
{
	int i;
	if(idx < 0 || idx > totalSections) return;
	sections = realloc(sections,sizeof(xld_disc_section_t)*++totalSections);
	for(i=totalSections-2;i>=idx;i--) {
		sections[i+1].index = sections[i].index + length;
		sections[i+1].length = sections[i].length;
		sections[i+1].path = sections[i].path;
		sections[i+1].raw = sections[i].raw;
		sections[i+1].endian = sections[i].endian;
		sections[i+1].rawOffset = sections[i].rawOffset;
	}
	if(idx == 0) sections[idx].index = 0;
	else sections[idx].index = sections[idx-1].index + sections[idx-1].length;
	sections[idx].length = length;
	if(path) sections[idx].path = [path retain];
	else sections[idx].path = nil;
	sections[idx].raw = NO;
	sections[idx].endian = 0;
	sections[idx].rawOffset = 0;
}

- (id)decoderInstanceForFrame:(xldoffset_t)index
{
	int i;

	if(index<0) return nil;

	for(i=1;i<totalSections;i++) 
		if(sections[i].index > index) break;

	if(index >= sections[i-1].index+sections[i-1].length) {
		NSLog(@"out of range");
		return nil; // out of range
	}

	// create instance for section i-1
	id decoder;
	if(!sections[i-1].path) {
		// silence decoder
		decoder = [[[XLDSilentDecoder alloc] initWithTotalFrames:sections[i-1].length channels:channels] autorelease];
	}
	else {
		// normal/raw decoder
		if(sections[i-1].raw) {
			XLDFormat fmt;
			fmt.bps = bytesPerSample;
			fmt.channels = channels;
			fmt.isFloat = isFloat;
			fmt.samplerate = samplerate;
			decoder = [[[XLDRawDecoder alloc] initWithFormat:(XLDFormat)fmt endian:sections[i-1].endian offset:sections[i-1].rawOffset] autorelease];
		}
		else
			decoder = [decoderCenter preferredDecoderForFile:sections[i-1].path];
		[(id <XLDDecoder>)decoder openFile:(char *)[sections[i-1].path UTF8String]];
	}
	//NSLog(@"creating decoder class %@ @ %lld (section %lld-%lld)",[[decoder class] className],index,sections[i-1].index,sections[i-1].index+sections[i-1].length);
	[decoder seekToFrame:index-sections[i-1].index];
	return decoder;
}

- (void)setChannels:(int)ch
{
	channels = ch;
}

- (void)setSamplerate:(int)rate
{
	samplerate = rate;
}

- (void)setBytesPerSample:(int)bps
{
	bytesPerSample = bps;
}

- (void)setIsFloat:(int)f
{
	isFloat = f;
}

- (int)channels
{
	return channels;
}

- (int)samplerate
{
	return samplerate;
}

- (int)bytesPerSample
{
	return bytesPerSample;
}

- (int)isFloat
{
	return isFloat;
}

- (xldoffset_t)totalFrames
{
	/*int i;
	for(i=0;i<totalSections;i++) {
		fprintf(stderr,"section %2d: %8lld-%8lld, %s\n",i,sections[i].index,sections[i].index+sections[i].length,sections[i].raw?"raw":"normal");
	}*/
	if(!totalSections) return 0;
	return sections[totalSections-1].index + sections[totalSections-1].length;
}

- (NSArray *)filePathList
{
	int i;
	NSMutableArray *arr = [NSMutableArray array];
	for(i=0;i<totalSections;i++) {
		if(sections[i].path) [arr addObject:sections[i].path];
	}
	return arr;
}

- (xldoffset_t)remainingFramesForFrame:(xldoffset_t)index
{
	int i;
	for(i=1;i<totalSections;i++) 
		if(sections[i].index > index) break;
	
	if(index >= sections[i-1].index+sections[i-1].length) {
		//NSLog(@"out of range");
		return 0; // out of range
	}
	
	if(sections[i-1].index == index) {
		//NSLog(@"EOF");
		return 0;
	}
	
	//NSLog(@"%lld samples remaining",sections[i-1].length - (index - sections[i-1].index));
	
	return sections[i-1].length - (index - sections[i-1].index);
}

@end
