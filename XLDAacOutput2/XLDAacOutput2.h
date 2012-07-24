//
//  XLDAacOutput.h
//  XLDAacOutput
//
//  Created by tmkk on 06/06/13.
//  Copyright 2006 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "XLDOutput.h"

@interface XLDAacOutput2 : NSObject <XLDOutput> {
	IBOutlet id o_quality;
	IBOutlet id o_prefPane;
	IBOutlet id o_gaplessFlag;
	IBOutlet id o_bitrateField;
	IBOutlet id o_encodeMode;
	IBOutlet id o_vbrQuality;
	IBOutlet id o_field01;
	IBOutlet id o_field02;
	IBOutlet id o_field11;
	IBOutlet id o_field12;
	IBOutlet id o_accurateBitrate;
	IBOutlet id o_samplerate;
	IBOutlet id o_enableHE;
	IBOutlet id o_forceMono;
	IBOutlet id o_embedChapter;
	BOOL isNewVBR;
	BOOL isSBRAvailable;
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

- (IBAction)modeChanged:(id)sender;
- (IBAction)bitrateEndEdit:(id)sender;
- (IBAction)vbrQualityChanged:(id)sender;

@end
