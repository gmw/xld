//
//  XLDPcmLEOutput.m
//  XLD
//
//  Created by tmkk on 10/11/03.
//  Copyright 2010 tmkk. All rights reserved.
//

#import "XLDPcmLEOutput.h"
#import "XLDDefaultOutputTask.h"

@implementation XLDPcmLEOutput

+ (NSString *)pluginName
{
	return @"PCM (little endian)";
}

- (void)savePrefs
{
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	[pref setInteger:[o_bitDepth indexOfSelectedItem] forKey:@"XLDPcmLEOutput_BitDepth"];
	[pref setInteger:[o_isFloat state] forKey:@"XLDPcmLEOutput_IsFloat"];
	[pref synchronize];
}

- (NSMutableDictionary *)configurations
{
	NSMutableDictionary *cfg = [super configurations];
	/* for GUI */
	[cfg setObject:[NSNumber numberWithInt:[o_bitDepth indexOfSelectedItem]] forKey:@"XLDPcmLEOutput_BitDepth"];
	[cfg setObject:[NSNumber numberWithInt:[o_isFloat state]] forKey:@"XLDPcmLEOutput_IsFloat"];
	/* for task */
	[cfg setObject:[NSNumber numberWithUnsignedInt:SF_FORMAT_RAW|SF_ENDIAN_LITTLE] forKey:@"SFFormat"];
	return cfg;
}

- (void)loadConfigurations:(id)cfg
{
	id obj;
	if(obj=[cfg objectForKey:@"XLDPcmLEOutput_BitDepth"]) {
		[o_bitDepth selectItemAtIndex:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDPcmLEOutput_BitDepth"]) {
		[o_isFloat setState:[obj intValue]];
	}
	[self statusChanged:nil];
}

@end
