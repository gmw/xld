//
//  XLDMusicBrainzRelease.h
//  XLD
//
//  Created by tmkk on 11/05/28.
//  Copyright 2011 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface XLDMusicBrainzRelease : NSObject
{
	NSMutableDictionary *release;
	int threads;
}
- (id)initWithReleaseID:(NSString *)releaseid discID:(NSString *)discid totalTracks:(int)totalTracks totalSectors:(int)sectors ambiguous:(BOOL)ambiguous;
- (NSDictionary *)disc;
@end
