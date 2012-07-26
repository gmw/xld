//
//  XLDFlacOutput.h
//  XLDFlacOutput
//
//  Created by tmkk on 06/09/15.
//  Copyright 2006 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "XLDOutput.h"

@interface XLDFlacOutput : NSObject <XLDOutput> {
	IBOutlet id o_prefView;
	IBOutlet id o_compressionLevel;
	IBOutlet id o_oggFlacCheckBox;
	IBOutlet id o_padding;
	IBOutlet id o_allowEmbeddedCuesheet;
	IBOutlet id o_setOggS;
	IBOutlet id o_useCustomApodization;
	IBOutlet id o_apodization;
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

- (IBAction)statusChanged:(id)sender;

@end
