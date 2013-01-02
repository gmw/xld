//
//  XLDAccurateRipDB.m
//  XLD
//
//  Created by tmkk on 08/08/17.
//  Copyright 2008 tmkk. All rights reserved.
//
//  Access to AccurateRip is regulated, see  http://www.accuraterip.com/3rdparty-access.htm for details.

#import "XLDAccurateRipDB.h"


@implementation XLDAccurateRipDB

- (id)init
{
	[super init];
	database = [[NSMutableArray alloc] init];
	offsetDatabase = [[NSMutableArray alloc] init];
	return self;
}

- (void)dealloc
{
	[database release];
	[offsetDatabase release];
	[discID release];
	[super dealloc];
}

/*
 - 1st entry -
 00h: number of tracks
 01h: discid1 (4 bytes, LE)
 05h: discid2 (4 bytes, LE)
 09h: discid3 (4 bytes, LE)
 - 1st track -
 0dh: confidence
 0eh: AR CRC (4 bytes, LE)
 12h: offset finding CRC; CRC of 450th sector in the track (4 bytes, LE)
 - 2nd track -
  :
*/

- (id)initWithData:(NSData *)data
{
	[self init];
	int i,n=0;
	unsigned char *ptr = (unsigned char *)[data bytes];
	
	int trackNum = 0;
	
	while(n<[data length]) {
		trackNum = *(ptr+n);
		for(i=[database count];i<trackNum;i++) {
			NSMutableDictionary *dic = [[NSMutableDictionary alloc] init];
			[dic setObject:[NSNumber numberWithInt:0] forKey:@"MaxConfidence"];
			[dic setObject:[NSNumber numberWithInt:0] forKey:@"TotalConfidence"];
			[database addObject:dic];
			[dic release];
			[offsetDatabase addObject:[NSMutableDictionary dictionary]];
		}
		
		if(!discID) {
			unsigned int discid1 = NSSwapLittleIntToHost(*(unsigned int *)(ptr+n+1));
			unsigned int discid2 = NSSwapLittleIntToHost(*(unsigned int *)(ptr+n+5));
			unsigned int discid3 = NSSwapLittleIntToHost(*(unsigned int *)(ptr+n+9));
			discID = [[NSString stringWithFormat:@"%08x-%08x-%08x",discid1,discid2,discid3] retain];
			//NSLog(@"%@",discID);
		}
		
		n+=13;
		for(i=0;i<trackNum;i++) {
			int confidence = *(ptr+n);
			n++;
			unsigned int crc32 = *(ptr+n) | *(ptr+n+1)<<8 | *(ptr+n+2)<<16 | *(ptr+n+3)<<24;
			if(confidence) [[database objectAtIndex:i] setObject:[NSNumber numberWithInt:confidence] forKey:[NSNumber numberWithUnsignedInt:crc32]];
			n+=4;
			crc32 = *(ptr+n) | *(ptr+n+1)<<8 | *(ptr+n+2)<<16 | *(ptr+n+3)<<24;
			if(crc32 && confidence) [[offsetDatabase objectAtIndex:i] setObject:[NSNumber numberWithInt:confidence] forKey:[NSNumber numberWithUnsignedInt:crc32]];
			n+=4;
			if([[[database objectAtIndex:i] objectForKey:@"MaxConfidence"] intValue] < confidence) {
				[[database objectAtIndex:i] setObject:[NSNumber numberWithInt:confidence] forKey:@"MaxConfidence"];
			}
			[[database objectAtIndex:i] setObject:[NSNumber numberWithInt:confidence+[[[database objectAtIndex:i] objectForKey:@"TotalConfidence"] intValue]] forKey:@"TotalConfidence"];
		}
	}
	//NSLog([database description]);
	
	return self;
}

- (BOOL)hasValidDataForTrack:(int)track
{
	if(track > [database count]) return NO;
	if(![[[database objectAtIndex:track-1] objectForKey:@"MaxConfidence"] intValue]) return NO;
	else return YES;
}

- (BOOL)hasValidDataForDisc
{
	int i;
	for(i=[database count]-1;i>=0;i--) {
		if([[[database objectAtIndex:i] objectForKey:@"MaxConfidence"] intValue]) return YES;
	}
	return NO;
}

- (int)isAccurateCRC:(unsigned int)crc forTrack:(int)track
{
	if(track > [database count]) return -1;
	
	id obj = [[database objectAtIndex:track-1] objectForKey:[NSNumber numberWithUnsignedInt:crc]];
	if(obj) return [obj intValue];
	else return -1;
}

- (int)isAccurateOffsetCRC:(unsigned int)crc forTrack:(int)track
{
	if(track > [offsetDatabase count]) return -1;
	
	id obj = [[offsetDatabase objectAtIndex:track-1] objectForKey:[NSNumber numberWithUnsignedInt:crc]];
	if(obj) return [obj intValue];
	else return -1;
}

- (int)totalSubmissionsForTrack:(int)track
{
	if(track > [database count]) return 0;
	return [[[database objectAtIndex:track-1] objectForKey:@"TotalConfidence"] intValue];
}

- (NSString *)discID
{
	return discID;
}

@end
