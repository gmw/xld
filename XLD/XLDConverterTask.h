//
//  XLDConverterTask.h
//  XLD
//
//  Created by tmkk on 07/11/14.
//  Copyright 2007 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "XLDTrack.h"
#import "XLDCustomClasses.h"
#import "XLDDiscLayout.h"

@interface XLDConverterTask : NSObject {
	id encoder;
	Class decoderClass;
	id encoderTask;
	id decoder;
	NSMutableArray *encoderArray;
	NSMutableArray *encoderTaskArray;
	NSDictionary *config;
	NSArray *configArray;
	XLDTrack *track;
	NSString *inFile;
	NSString *outDir;
	xldoffset_t index;
	xldoffset_t totalFrame;
	BOOL fixOffset;
	BOOL tagWritable;
	XLDFormat rawFmt;
	XLDEndian rawEndian;
	int rawOffset;
	int processOfExistingFiles;
	BOOL embedImages;
	
	BOOL running;
	BOOL stopConvert;
	
	NSProgressIndicator *progress;
	NSButton *stopButton;
	NSTextField *nameField;
	NSTextField *statusField;
	NSTextField *speedField;
	
	id queue;
	XLDScaleType scaleType;
	float compressionQuality;
	int scaleSize;
	NSString *iTunesLib;
	//BOOL mountOnEnd;
	BOOL useParanoiaMode;
	int offsetCorrectionValue;
	int retryCount;
	id resultObj;
	int defeatPower;
	BOOL testMode;
	int offsetFixupValue;
	BOOL detectOffset;
	int currentTrack;
	int totalTrack;
	
	double percent;
	double speed;
	double remainingSec;
	double remainingMin;
	BOOL useOldEngine;
	xldoffset_t firstAudioFrame;
	xldoffset_t lastAudioFrame;
	BOOL useC2Pointer;
	XLDView *superview;
	int position;
	
	BOOL appendBOM;
	BOOL moveAfterFinish;
	NSString *tmpPathStr;
	NSString *dstPathStr;
	NSString *cuePathStr;
	NSMutableArray *outputPathStrArray;
	NSMutableArray *tmpPathStrArray;
	NSMutableArray *cuePathStrArray;
	NSArray *trackListForCuesheet;
	BOOL removeOriginalFile;
	XLDRipperMode ripperMode;
	XLDDiscLayout *discLayout;
}

- (id)initWithQueue:(id)q;
- (void)beginConvert;
- (void)stopConvert:(id)sender;
- (void)showProgressInView:(NSTableView *)view row:(int)row;
- (void)hideProgress;
- (void)setFixOffset:(BOOL)flag;
- (void)setIndex:(xldoffset_t)idx;
- (void)setTotalFrame:(xldoffset_t)frame;
- (void)setDecoderClass:(Class)dec;
- (void)setEncoder:(id)enc withConfiguration:(NSDictionary*)cfg;
- (void)setEncoders:(id)enc withConfigurations:(NSArray*)cfg;
- (void)setRawFormat:(XLDFormat)fmt;
- (void)setRawEndian:(XLDEndian)e;
- (void)setRawOffset:(int)offset;
- (void)setInputPath:(NSString *)path;
- (NSString *)outputDir;
- (void)setOutputDir:(NSString *)path;
- (void)setTagWritable:(BOOL)flag;
- (void)setTrack:(XLDTrack *)t;
- (void)setScaleType:(XLDScaleType)type;
- (void)setCompressionQuality:(float)quality;
- (void)setScaleSize:(int)pixel;
- (BOOL)isActive;
- (void)setiTunesLib:(NSString *)lib;
- (BOOL)isAtomic;
//- (void)setMountOnEnd;
- (void)setOffsetCorrectionValue:(int)value;
- (void)setRetryCount:(int)value;
- (void)setTrackListForCuesheet:(NSArray *)tracks appendBOM:(BOOL)flag;
- (void)setResultObj:(id)obj;
- (id)resultObj;
- (void)setTestMode;
- (void)setOffsetFixupValue:(int)value;
- (void)setFirstAudioFrame:(xldoffset_t)frame;
- (void)setLastAudioFrame:(xldoffset_t)frame;
- (NSView *)progressView;
- (int)position;
- (void)setProcessOfExistingFiles:(int)value;
- (void)setEmbedImages:(BOOL)flag;
- (void)setMoveAfterFinish:(BOOL)flag;
- (void)setRemoveOriginalFile:(BOOL)flag;
- (void)setRipperMode:(XLDRipperMode)mode;
- (void)setDiscLayout:(XLDDiscLayout *)layout;
- (void)taskSelected;
- (void)taskDeselected;
@end
