//
//  XLDOpusOutput.h
//  XLDOpusOutput
//
//  Created by tmkk on 12/08/09.
//  Copyright 2012 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "XLDOutput.h"

@interface XLDOpusOutput : NSObject <XLDOutput> {
	IBOutlet id o_encoderMode;
	IBOutlet id o_bitrate;
	IBOutlet id o_frameSize;
	IBOutlet id o_prefPane;
	IBOutlet id o_credit;
}

+ (NSString *)pluginName;
+ (BOOL)canLoadThisBundle;
- (NSView *)prefPane;
- (void)savePrefs;
- (void)loadPrefs;
- (id)createTaskForOutput;
- (id)createTaskForOutputWithConfigurations:(NSDictionary *)cfg;
- (NSMutableDictionary *)configurations;
- (void)loadConfigurations:(id)configurations;

@end
