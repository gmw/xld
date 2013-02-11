//
//  XLDSd2fOutput.h
//  XLD
//
//  Created by tmkk on 13/02/11.
//  Copyright 2013 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "XLDOutput.h"

@interface XLDSd2fOutput : NSObject <XLDOutput> {
	IBOutlet id o_bitDepth;
	IBOutlet id o_view;
}

- (IBAction)statusChanged:(id)target;

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
