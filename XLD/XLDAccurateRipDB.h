//
//  XLDAccurateRipDB.h
//  XLD
//
//  Created by tmkk on 08/08/17.
//  Copyright 2008 tmkk. All rights reserved.
//
//  Access to AccurateRip is regulated, see  http://www.accuraterip.com/3rdparty-access.htm for details.

#import <Cocoa/Cocoa.h>


@interface XLDAccurateRipDB : NSObject {
	NSMutableArray *database;
	NSMutableArray *offsetDatabase;
	NSString *discID;
}

- (id)initWithData:(NSData *)data;
- (int)isAccurateCRC:(unsigned int)crc forTrack:(int)track;
- (int)isAccurateOffsetCRC:(unsigned int)crc forTrack:(int)track;
- (BOOL)hasValidDataForTrack:(int)track;
- (int)totalSubmissionsForTrack:(int)track;
- (NSString *)discID;
@end
