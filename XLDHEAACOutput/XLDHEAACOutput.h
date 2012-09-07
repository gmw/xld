//
//  XLDHEAACOutput.h
//  XLDHEAACOutput
//
//  Created by tmkk on 08/03/04.
//  Copyright 2008 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "XLDOutput.h"

@interface XLDHEAACOutput : NSObject <XLDOutput> {
	IBOutlet id o_prefView;
	IBOutlet id o_bitrate;
	IBOutlet id o_useMP4;
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
