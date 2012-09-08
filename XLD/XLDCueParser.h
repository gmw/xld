//
//  XLDCueParser.h
//  XLD
//
//  Created by tmkk on 06/06/10.
//  Copyright 2006 tmkk. All rights reserved.
//
// Access to AccurateRip is regulated, see  http://www.accuraterip.com/3rdparty-access.htm for details.

#import <Cocoa/Cocoa.h>
#import "XLDDiscLayout.h"

enum 
{
	XLDCueModeDefault = 0,
	XLDCueModeRaw,
	XLDCueModeMulti
} ;

@interface XLDCueParser : NSObject {
	NSMutableArray *trackList;
	NSMutableArray *checkList;
	id delegate;
	NSString *fileToDecode;
	xldoffset_t totalFrames;
	int samplerate;
	NSString *title;
	XLDFormat format;
	XLDEndian endian;
	int cueMode;
	BOOL rawMode;
	int rawOffset;
	NSData *cover;
	NSString *driveStr;
	XLDDiscLayout *discLayout;
	BOOL ARQueried;
	NSData *accurateRipData;
	BOOL writable;
	NSString *errorMsg;
	NSString *representedFilename;
	NSStringEncoding preferredEncoding;
}

- (id)initWithDelegate:(id)del;
- (void)clean;
- (XLDErr)openFile:(NSString *)file;
- (XLDErr)openFile:(NSString *)file withRawFormat:(XLDFormat)fmt endian:(XLDEndian)e;
- (XLDErr)openFile:(NSString *)file withCueData:(NSString *)cueData decoder:(id)decoder;
- (void)openFile:(NSString *)file withTrackData:(NSMutableArray *)arr decoder:(id)decoder;
- (void)openRawFile:(NSString *)file withTrackData:(NSMutableArray *)arr decoder:(id)decoder;
- (XLDErr)openFiles:(NSArray *)files offset:(xldoffset_t)offset prepended:(BOOL)prepended;
- (id)decoderForCueSheet:(NSString *)file isRaw:(BOOL)raw promptIfNotFound:(BOOL)prompt error:(XLDErr *)error;
- (NSArray *)trackList;
- (NSArray *)checkList;
- (NSString *)lengthOfTrack:(int)track;
- (NSString *)gapOfTrack:(int)track;
- (NSString *)fileToDecode;
- (NSString *)title;
- (NSString *)artist;
- (xldoffset_t)totalFrames;
- (XLDFormat)rawFormat;
- (XLDEndian)rawEndian;
- (int)rawOffset;
- (BOOL)rawMode;
- (NSData *)coverData;
- (void)setCoverData:(NSData *)data;
- (NSArray *)trackListForSingleFile;
- (void)setTitle:(NSString *)str;
- (void)setDriveStr:(NSString *)str;
- (NSString *)driveStr;
- (NSData *)accurateRipData;
- (xldoffset_t)firstAudioFrame;
- (xldoffset_t)lastAudioFrame;
- (BOOL)isCompilation;
- (NSArray *)trackListForDecoder:(id)decoder withEmbeddedCueData:(NSString *)cueData;
- (NSArray *)trackListForDecoder:(id)decoder withEmbeddedTrackList:(NSArray *)tracks;
- (NSArray *)trackListForExternalCueSheet:(NSString *)file decoder:(id *)decoder;
- (int)cueMode;
- (XLDDiscLayout *)discLayout;
- (BOOL)writable;
- (int)samplerate;
- (NSString *)setTrackData:(NSMutableArray *)tracks forCueFile:(NSString *)file withDecoder:(id)decoder;
- (NSString *)errorMsg;
- (NSString *)representedFilename;
- (void)setPreferredEncoding:(NSStringEncoding)enc;
@end
