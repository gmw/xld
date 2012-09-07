//
//  XLDHEAACOutput.m
//  XLDHEAACOutput
//
//  Created by tmkk on 08/03/04.
//  Copyright 2008 tmkk. All rights reserved.
//

#import "XLDHEAACOutput.h"
#import "XLDHEAACOutputTask.h"

@implementation XLDHEAACOutput

+ (NSString *)pluginName
{
	return @"MPEG-4 HE-AAC";
}

+ (BOOL)canLoadThisBundle
{
	return YES;
}

- (id)init
{
	[super init];
	[NSBundle loadNibNamed:@"XLDHEAACOutput" owner:self];
	return self;
}

- (NSView *)prefPane
{
	return o_prefView;
}

- (void)savePrefs
{
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	[pref setInteger:[o_bitrate intValue] forKey:@"XLDHEAACOutput_BitRate"];
	[pref setInteger:[o_useMP4 state] forKey:@"XLDHEAACOutput_UseMP4"];
	[pref synchronize];
}

- (void)loadPrefs
{
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	[self loadConfigurations:pref];
}

- (id)createTaskForOutput
{
	return [[XLDHEAACOutputTask alloc] initWithConfigurations:[self configurations]];
}

- (id)createTaskForOutputWithConfigurations:(NSDictionary *)cfg
{
	return [[XLDHEAACOutputTask alloc] initWithConfigurations:cfg];
}

- (int)bitrate
{
	return [o_bitrate intValue];
}

- (BOOL)useMP4
{
	return [o_useMP4 state] == NSOnState ? YES : NO;
}

- (NSMutableDictionary *)configurations
{
	NSMutableDictionary *cfg = [[NSMutableDictionary alloc] init];
	/* for GUI */
	[cfg setObject:[NSNumber numberWithInt:[o_bitrate intValue]] forKey:@"XLDHEAACOutput_BitRate"];
	[cfg setObject:[NSNumber numberWithInt:[o_useMP4 state]] forKey:@"XLDHEAACOutput_UseMP4"];
	/* for task */
	[cfg setObject:[NSNumber numberWithInt:[self bitrate]] forKey:@"Bitrate"];
	[cfg setObject:[NSNumber numberWithBool:[self useMP4]] forKey:@"UseMP4"];
	/* desc */
	if([self useMP4]) {
		[cfg setObject:[NSString stringWithFormat:@"MP4, %dkbps",[self bitrate]] forKey:@"ShortDesc"];
	}
	else {
		[cfg setObject:[NSString stringWithFormat:@"ADTS, %dkbps",[self bitrate]] forKey:@"ShortDesc"];
	}
	return [cfg autorelease];
}

- (void)loadConfigurations:(id)cfg
{
	id obj;
	if(obj=[cfg objectForKey:@"XLDHEAACOutput_BitRate"]) {
		[o_bitrate setIntValue:[obj intValue]];
		[o_bitrate performClick:nil];
	}
	if(obj=[cfg objectForKey:@"XLDHEAACOutput_UseMP4"]) {
		[o_useMP4 setState:[obj intValue]];
	}
}

@end
