//
//  XLDAacOutput.h
//  XLDAacOutput
//
//  Created by tmkk on 06/06/13.
//  Copyright 2006 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "XLDOutput.h"

@interface XLDAacOutput : NSObject <XLDOutput> {
	IBOutlet id o_bitrate;
	IBOutlet id o_quality;
	IBOutlet id o_useVBR;
	IBOutlet id o_prefPane;
	IBOutlet id o_gaplessFlag;
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

- (IBAction)vbrChecked:(id)sender;

@end
