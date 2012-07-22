//
//  XLDAccurateRipChecker.h
//  XLD
//
//  Created by tmkk on 08/08/22.
//  Copyright 2008 tmkk. All rights reserved.
//
//  Access to AccurateRip is regulated, see  http://www.accuraterip.com/3rdparty-access.htm for details.

#import <Cocoa/Cocoa.h>
#import "gain_analysis.h"
#import "XLDTrackValidator.h"

typedef struct {
	xldoffset_t index;
	xldoffset_t length;
	unsigned int sampleSum;
	float trackGain;
	float peak;
	BOOL enabled;
	BOOL cancelled;
	NSMutableDictionary *detectedOffset;
	XLDARStatus ARStatus;
	int ARConfidence;
	XLDTrackValidator *validator;
} checkResult;

@interface XLDAccurateRipChecker : NSObject {
	checkResult *results;
	unsigned int crc32_global;
	unsigned int crc32_eac_global;
	IBOutlet id o_panel;
	IBOutlet id o_message;
	IBOutlet id o_progress;
	id database;
	id delegate;
	id decoder;
	int trackNumber;
	BOOL running;
	BOOL stop;
	xldoffset_t totalFrames;
	unsigned int crc32Table[256];
	int *preTrackSamples;
	int *postTrackSamples;
	NSMutableDictionary *detectedOffset;
	NSMutableArray *trackList;
	replaygain_t *rg;
	double percent;
}
- (id)initWithTracks:(NSArray *)tracks totalFrames:(xldoffset_t)frame;
- (void)startCheckingForFile:(NSString *)path withDecoder:(id)decoderObj;
- (void)startOffsetCheckingForFile:(NSString *)path withDecoder:(id)decoderObj;
- (void)startReplayGainScanningForFile:(NSString *)path withDecoder:(id)decoderObj;
- (void)setAccurateRipDB:(id)db;
- (void)setDelegate:(id)del;
- (IBAction)cancel:(id)sender;
- (NSString *)logStr;
- (NSString *)logStrForReplayGainScanner;
- (NSDictionary *)detectedOffset;
- (BOOL)cancelled;
@end
