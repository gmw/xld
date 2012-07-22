//
//  XLDDefaultOutput.h
//  XLD
//
//  Created by tmkk on 06/06/08.
//  Copyright 2006 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "XLDOutput.h"

@interface XLDDefaultOutput : NSObject <XLDOutput> {
	IBOutlet id o_bitDepth;
	IBOutlet id o_isFloat;
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
