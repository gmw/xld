//
//  XLDAlacOutput.h
//  XLDAlacOutput
//
//  Created by tmkk on 06/06/23.
//  Copyright 2006 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "XLDOutput.h"

@interface XLDAlacOutput : NSObject <XLDOutput> {
	IBOutlet id o_prefPane;
	IBOutlet id o_samplerate;
	IBOutlet id o_embedChapter;
	IBOutlet id o_bitDepth;
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
