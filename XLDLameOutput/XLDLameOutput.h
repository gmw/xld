//
//  XLDLameOutput.h
//  XLDLameOutput
//
//  Created by tmkk on 06/06/13.
//  Copyright 2006 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "XLDOutput.h"

typedef enum
{
	XLDLameAutoStereoMode = 0,
	XLDLameJointStereoMode = 1,
	XLDLameSimpleStereoMode = 2,
	XLDLameMonoStereoMode = 3
} XLDLameStereoMode;

@interface XLDLameOutput : NSObject <XLDOutput> {
	IBOutlet id o_bitrate;
	IBOutlet id o_quality;
	IBOutlet id o_prefPane;
	IBOutlet id o_vbrQuality;
	IBOutlet id o_vbrMethod;
	IBOutlet id o_abrBitrate;
	IBOutlet id o_mode;
	IBOutlet id o_replayGain;
	IBOutlet id o_stereoMode;
	IBOutlet id o_vbrQualityValue;
	IBOutlet id o_sampleRate;
	IBOutlet id o_appendTLEN;
	IBOutlet id o_creditStr;
}

+ (NSString *)pluginName;
+ (BOOL)canLoadThisBundle;
- (NSView *)prefPane;
- (void)savePrefs;
- (void)loadPrefs;
- (id)createTaskForOutput;
- (id)createTaskForOutputWithConfigurations:(NSDictionary *)cfg;
- (NSMutableDictionary *)configurations;
- (void)loadConfigurations:(id)cfg;

- (IBAction)setVbrQuality:(id)sender;
- (IBAction)modeChanged:(id)sender;

@end
