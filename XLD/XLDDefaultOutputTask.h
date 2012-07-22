//
//  XLDDefaultOutputTask.h
//  XLD
//
//  Created by tmkk on 06/09/08.
//  Copyright 2006 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "XLDOutputTask.h"
#import <sndfile.h>
#import <AudioToolbox/AudioToolbox.h>

@interface XLDDefaultOutputTask : NSObject <XLDOutputTask> {
	SF_INFO sfinfo;
	SNDFILE *sf_w;
	BOOL addTag;
	NSString *path;
	NSMutableData *tagData;
	XLDFormat inFormat;
	NSDictionary *configurations;
}

- (BOOL)setOutputFormat:(XLDFormat)fmt;
- (BOOL)openFileForOutput:(NSString *)str withTrackData:(id)track;
- (NSString *)extensionStr;
- (BOOL)writeBuffer:(int *)buffer frames:(int)counts;
- (void)finalize;
- (void)closeFile;
- (void)setEnableAddTag:(BOOL)flag;

- (id)initWithConfigurations:(NSDictionary *)cfg;

@end
