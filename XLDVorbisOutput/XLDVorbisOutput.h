//
//  XLDVorbisOutput.h
//  XLDVorbisOutput
//
//  Created by tmkk on 06/06/12.
//  Copyright 2006 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "XLDOutput.h"

@interface XLDVorbisOutput : NSObject <XLDOutput>
{
	IBOutlet id o_prefView;
	IBOutlet id o_qValue;
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
