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
	[pref setInteger:[[o_samplerate selectedItem] tag] forKey:@"XLDPcmLEOutput_Samplerate"];
	[pref setInteger:[[o_srcAlgorithm selectedItem] tag] forKey:@"XLDPcmLEOutput_SRCAlgorithm"];
	[pref synchronize];
}

- (NSMutableDictionary *)configurations
{
	NSMutableDictionary *cfg = [super configurations];
	/* for GUI */
	[cfg setObject:[NSNumber numberWithInt:[o_bitDepth indexOfSelectedItem]] forKey:@"XLDPcmLEOutput_BitDepth"];
	[cfg setObject:[NSNumber numberWithInt:[o_isFloat state]] forKey:@"XLDPcmLEOutput_IsFloat"];
	[cfg setObject:[NSNumber numberWithInt:[[o_samplerate selectedItem] tag]] forKey:@"XLDPcmLEOutput_Samplerate"];
	[cfg setObject:[NSNumber numberWithInt:[[o_srcAlgorithm selectedItem] tag]] forKey:@"XLDPcmLEOutput_SRCAlgorithm"];
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
	if(obj=[cfg objectForKey:@"XLDPcmLEOutput_Samplerate"]) {
		[o_samplerate selectItemWithTag:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDPcmLEOutput_SRCAlgorithm"]) {
		[o_srcAlgorithm selectItemWithTag:[obj intValue]];
	}
	[self statusChanged:nil];
}

@end
