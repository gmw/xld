//
//  XLDMusicBrainzReleaseList.h
//  XLD
//
//  Created by tmkk on 11/05/28.
//  Copyright 2011 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface XLDMusicBrainzReleaseList : NSObject
{
	NSMutableArray *releases;
}
- (id)initWithDiscID:(NSString *)discid;
- (NSArray *)releaseList;
@end
