//
//  XLDVorbisOutput.m
//  XLDVorbisOutput
//
//  Created by tmkk on 06/06/12.
//  Copyright 2006 tmkk. All rights reserved.
//

#import "XLDVorbisOutput.h"
#import "XLDVorbisOutputTask.h"
#import <time.h>

@implementation XLDVorbisOutput

+ (NSString *)pluginName
{
	return @"Ogg Vorbis";
}

+ (BOOL)canLoadThisBundle
{
	if (floor(NSAppKitVersionNumber) <= 620 ) {
		return NO;
	}
	else return YES;
}

- (id)init
{
	[super init];
	[NSBundle loadNibNamed:@"XLDVorbisOutput" owner:self];
	srand(time(NULL));
	return self;
}

- (NSView *)prefPane
{
	return o_prefView;
}

- (void)savePrefs
{
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	[pref setFloat:[o_qValue floatValue] forKey:@"XLDVorbisOutput_Quality"];
	[pref synchronize];
}

- (void)loadPrefs
{
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	[self loadConfigurations:pref];
}

- (id)createTaskForOutput
{
	return [[XLDVorbisOutputTask alloc] initWithConfigurations:[self configurations]];
}

- (id)createTaskForOutputWithConfigurations:(NSDictionary *)cfg
{
	return [[XLDVorbisOutputTask alloc] initWithConfigurations:cfg];
}

- (float)quality
{
	return [o_qValue floatValue]/10.0f;
}

- (NSMutableDictionary *)configurations
{
	NSMutableDictionary *cfg = [[NSMutableDictionary alloc] init];
	/* for GUI */
	[cfg setObject:[NSNumber numberWithFloat:[o_qValue floatValue]] forKey:@"XLDVorbisOutput_Quality"];
	/* for task */
	[cfg setObject:[NSNumber numberWithFloat:[self quality]] forKey:@"Quality"];
	/* desc */
	[cfg setObject:[NSString stringWithFormat:@"quality %.2f",[self quality]*10] forKey:@"ShortDesc"];
	return [cfg autorelease];
}

- (void)loadConfigurations:(id)cfg
{
	id obj;
	if(obj=[cfg objectForKey:@"XLDVorbisOutput_Quality"]) {
		[o_qValue setFloatValue:[obj floatValue]];
		[o_qValue sendAction:[o_qValue action] to:[o_qValue target]];
	}
}

@end
