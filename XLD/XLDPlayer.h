//
//  XLDPlayer.h
//  XLD
//
//  Created by tmkk on 06/08/07.
//  Copyright 2006 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <AudioToolbox/AudioToolbox.h>
#import "sfifo.h"
#import "XLDDiscLayout.h"

@interface XLDPlayer : NSObject {
	AudioUnit outputUnit;
	id delegate;
	id decoder;
	BOOL playThreadIsDone;
	xldoffset_t seekpoint;
	int *buffer_decoder;
	NSArray *currentTrack;
	NSString *currentFile;
	NSLock *lock;
	
	IBOutlet id o_playerWindow;
	IBOutlet id o_currentTrack;
	IBOutlet id o_positionSlider;
	IBOutlet id o_playButton;
	IBOutlet id o_secondStr;
	
@public
	AudioConverterRef converter;
	
	int channels;
	int bps;
	int samplerate;
	int length;
	xldoffset_t totalFrame;
	xldoffset_t currentFrame;
	int currentIndex;
	int percentage;
	double second;
	
	BOOL playing;
	BOOL pause;
	BOOL lastBuffer;
	BOOL decodeFinished;
	BOOL playDone;
	
	unsigned char *buffer;
	int bufferSize;
	sfifo_t fifo;
}
- (IBAction)play:(id)sender;
- (IBAction)stop:(id)sender;
- (IBAction)next:(id)sender;
- (IBAction)prev:(id)sender;
- (IBAction)seek:(id)sender;

- (id)initWithDelegate:(id)del;
- (XLDErr)playFile:(NSString *)path withTrack:(NSArray *)track fromIndex:(int)idx;
- (XLDErr)playRawFile:(NSString *)path withTrack:(NSArray *)track fromIndex:(int)idx withFormat:(XLDFormat)fmt endian:(XLDEndian)e offset:(int)offset;
- (XLDErr)playDiscLayout:(XLDDiscLayout *)layout withFile:(NSString *)path withTrack:(NSArray *)track fromIndex:(int)idx;
- (void)stop;
- (void)seekToFrame:(xldoffset_t)frame;
- (void)openFileForPlay:(NSString *)path;
- (void)showPlayer;
- (void)releaseDecoder;
@end
