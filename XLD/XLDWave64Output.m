//
//  XLDWave64Output.m
//  XLD
//
//  Created by tmkk on 10/11/03.
//  Copyright 2010 tmkk. All rights reserved.
//

#import "XLDWave64Output.h"
#import "XLDDefaultOutputTask.h"

@implementation XLDWave64Output

+ (NSString *)pluginName
{
	return @"Wave64";
}

- (void)savePrefs
{
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	[pref setInteger:[o_bitDepth indexOfSelectedItem] forKey:@"XLDWave64Output_BitDepth"];
	[pref setInteger:[o_isFloat state] forKey:@"XLDWave64Output_IsFloat"];
	[pref setInteger:[[o_samplerate selectedItem] tag] forKey:@"XLDWave64Output_Samplerate"];
	[pref setInteger:[[o_srcAlgorithm selectedItem] tag] forKey:@"XLDWave64Output_SRCAlgorithm"];
	[pref synchronize];
}

- (NSMutableDictionary *)configurations
{
	NSMutableDictionary *cfg = [super configurations];
	/* for GUI */
	[cfg setObject:[NSNumber numberWithInt:[o_bitDepth indexOfSelectedItem]] forKey:@"XLDWave64Output_BitDepth"];
	[cfg setObject:[NSNumber numberWithInt:[o_isFloat state]] forKey:@"XLDWave64Output_IsFloat"];
	[cfg setObject:[NSNumber numberWithInt:[[o_samplerate selectedItem] tag]] forKey:@"XLDWav64Output_Samplerate"];
	[cfg setObject:[NSNumber numberWithInt:[[o_srcAlgorithm selectedItem] tag]] forKey:@"XLDWav64Output_SRCAlgorithm"];
	/* for task */
	[cfg setObject:[NSNumber numberWithUnsignedInt:SF_FORMAT_W64] forKey:@"SFFormat"];
	return cfg;
}

- (void)loadConfigurations:(id)cfg
{
	id obj;
	if(obj=[cfg objectForKey:@"XLDWave64Output_BitDepth"]) {
		[o_bitDepth selectItemAtIndex:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDWave64Output_IsFloat"]) {
		[o_isFloat setState:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDWav64Output_Samplerate"]) {
		[o_samplerate selectItemWithTag:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDWav64Output_SRCAlgorithm"]) {
		[o_srcAlgorithm selectItemWithTag:[obj intValue]];
	}
	[self statusChanged:nil];
}

@end
