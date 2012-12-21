//
//  XLDCDDAResult.h
//  XLD
//
//  Created by tmkk on 08/08/13.
//  Copyright 2008 tmkk. All rights reserved.
//
//  Access to AccurateRip is regulated, see  http://www.accuraterip.com/3rdparty-access.htm for details.

#import <Cocoa/Cocoa.h>
#import "gain_analysis.h"
#import "XLDTrackValidator.h"

typedef struct {
	BOOL enabled;
	BOOL finished;
	BOOL cancelled;
	BOOL testEnabled;
	BOOL testFinished;
	BOOL pending;
	NSString *filename;
	NSMutableArray *filelist;
	int errorCount;
	int skipCount;
	int edgeJitterCount;
	int atomJitterCount;
	int droppedCount;
	int duplicatedCount;
	int driftCount;
	int cacheErrorCount;
	int retrySectorCount;
	int damagedSectorCount;
	unsigned int inconsistency;
	unsigned int sampleSum;
	NSMutableArray *suspiciousPosition;
	BOOL checkInconsistency;
	BOOL scanReplayGain;
	replaygain_t *rg;
	float trackGain;
	float peak;
	XLDARStatus ARStatus;
	int ARConfidence;
	NSMutableDictionary *detectedOffset;
	XLDTrackValidator *validator;
	id parent;
} cddaRipResult;

@interface XLDCDDAResult : NSObject {
	cddaRipResult *results;
	NSString *driveStr;
	NSString *deviceStr;
	NSDate *date;
	NSString *logFileName;
	NSString *cueFileName;
	NSMutableArray *logDirectoryArray;
	NSMutableArray *cueDirectoryArray;
	int retryCount;
	int offset;
	NSString *title;
	NSString *artist;
	id database;
	BOOL useAccurateRipDB;
	BOOL trustAccurateRipResult;
	xldoffset_t *lengthArr;
	NSMutableDictionary *detectedOffset;
	NSMutableArray *trackList;
	NSString *cuePath;
	NSArray *cuePathArray;
	replaygain_t *rg;
	BOOL isGoodRip;
	BOOL appendBOM;
	int processOfExistingFiles;
	BOOL includeHTOA;
	unsigned int gapStatus;
	XLDRipperMode ripperMode;
	NSString *mediaType;
@public
	xldoffset_t *indexArr;
	xldoffset_t *actualLengthArr; /* used for detecting the track end for single image ripping */
	int trackNumber;
}

- (id)initWithTrackNumber:(int)t;
- (void)setDriveStr:(NSString *)str;
- (void)setDeviceStr:(NSString *)str;
- (void)setDate:(NSDate *)d;
- (cddaRipResult *)resultForIndex:(int)idx;
- (BOOL)allTasksFinished;
- (int)numberOfTracks;
- (NSString *)deviceStr;
- (void)setLogFileName:(NSString *)str;
- (void)addLogDirectory:(NSString *)str;
- (void)addCueDirectory:(NSString *)str withIndex:(int)idx;
- (NSString *)logFileName;
- (void)setCueFileName:(NSString *)str;
- (NSString *)cueFileName;
- (void)setRipperMode:(XLDRipperMode)mode
	 offsetCorrention:(int)o
		   retryCount:(int)ret
	 useAccurateRipDB:(BOOL)useDB
   checkInconsistency:(BOOL)checkFlag
		trustARResult:(BOOL)trustFlag
	   scanReplayGain:(BOOL)rgFlag
			gapStatus:(unsigned int)status;
- (NSString *)logStr;
- (void)saveLog;
- (void)setTOC:(NSArray *)arr;
- (void)setTitle:(NSString*)t andArtist:(NSString *)a;
- (void)setAccurateRipDB:(id)db;
- (id)accurateRipDB;
- (void)setCuePath:(NSString *)path;
- (void)setCuePathArray:(NSArray *)arr;
- (void)saveCuesheetIfNeeded;
- (BOOL)isGoodRip;
- (void)setAppendBOM:(BOOL)flag;
- (void)setProcessOfExistingFiles:(int)value;
- (void)setIncludeHTOA:(BOOL)flag;
- (void)analyzeGain;
- (void)commitReplayGainTagForTrack:(int)trk;
@end
