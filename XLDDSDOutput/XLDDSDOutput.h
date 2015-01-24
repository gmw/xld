//
//  XLDDSDOutput.h
//  XLDDSDOutput
//
//  Created by tmkk on 15/01/24.
//  Copyright 2015 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "XLDOutput.h"

@interface XLDDSDOutput : NSObject <XLDOutput> {
	IBOutlet id o_view;
	IBOutlet id o_dsdType;
	IBOutlet id o_dsdFormat;
	IBOutlet id o_dsmType;
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

@end
