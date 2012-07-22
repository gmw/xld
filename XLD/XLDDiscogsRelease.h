//
//  XLDDiscogsRelease.h
//  XLD
//
//  Created by tmkk on 11/12/30.
//  Copyright 2011 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface XLDDiscogsRelease : NSObject {
	NSMutableDictionary *release;
}

- (id)initWithReleaseID:(NSString *)releaseid totalTracks:(int)totalTracks totalSectors:(int)sectors;

@end
