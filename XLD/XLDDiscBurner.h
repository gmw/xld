//
//  XLDDiscBurner.h
//  XLD
//
//  Created by tmkk on 11/05/07.
//  Copyright 2011 tmkk. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "XLDDiscLayout.h"
#import "XLDTrack.h"

@interface XLDDiscBurner : NSObject {
	NSArray *trackList;
	NSMutableArray *recordingTrackList;
	XLDDiscLayout *discLayout;
	XLDDiscLayout *discLayoutForVerify;
	int writeOffsetCorrectionValue;
	int readOffsetCorrectionValue;
	int writeOffset;
	int readOffset;
	BOOL writeOffsetModified;
	BOOL readOffsetModified;
	xldoffset_t totalFrames;
	int *status;
}

- (id)initWithTracks:(NSArray *)tracks andLayout:(XLDDiscLayout*)layout;
- (NSArray *)recordingTrackList;
- (XLDDiscLayout *)discLayout;
- (XLDDiscLayout *)discLayoutForVerify;
- (XLDTrack *)trackAt:(int)n;
- (void)setWriteOffset:(int)n;
- (void)setReadOffsetCorrectionValue:(int)n;
- (int)writeOffsetCorrectionValue;
- (int)readOffsetCorrectionValue;
- (int)totalTracks;
- (int)igoredSamplesAtTheBeginningOfTrack:(int)n;
- (int)igoredSamplesAtTheEndOfTrack:(int)n;
- (xldoffset_t)totalFrames;
- (void)reportStatusOfTrack:(int)n difference:(int)difference;
- (NSString *)reportString;
@end
