//
//  XLDPcmBEOutput.m
//  XLD
//
//  Created by tmkk on 10/11/03.
//  Copyright 2010 tmkk. All rights reserved.
//

#import "XLDPcmBEOutput.h"
#import "XLDDefaultOutputTask.h"

@implementation XLDPcmBEOutput

+ (NSString *)pluginName
{
	return @"PCM (big endian)";
}

- (void)savePrefs
{
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	[pref setInteger:[o_bitDepth indexOfSelectedItem] forKey:@"XLDPcmBEOutput_BitDepth"];
	[pref setInteger:[o_isFloat state] forKey:@"XLDPcmBEOutput_IsFloat"];
	[pref setInteger:[[o_samplerate selectedItem] tag] forKey:@"XLDPcmBEOutput_Samplerate"];
	[pref setInteger:[[o_srcAlgorithm selectedItem] tag] forKey:@"XLDPcmBEOutput_SRCAlgorithm"];
	[pref synchronize];
}

- (NSMutableDictionary *)configurations
{
	NSMutableDictionary *cfg = [super configurations];
	/* for GUI */
	[cfg setObject:[NSNumber numberWithInt:[o_bitDepth indexOfSelectedItem]] forKey:@"XLDPcmBEOutput_BitDepth"];
	[cfg setObject:[NSNumber numberWithInt:[o_isFloat state]] forKey:@"XLDPcmBEOutput_IsFloat"];
	[cfg setObject:[NSNumber numberWithInt:[[o_samplerate selectedItem] tag]] forKey:@"XLDPcmBEOutput_Samplerate"];
	[cfg setObject:[NSNumber numberWithInt:[[o_srcAlgorithm selectedItem] tag]] forKey:@"XLDPcmBEOutput_SRCAlgorithm"];
	/* for task */
	[cfg setObject:[NSNumber numberWithUnsignedInt:SF_FORMAT_RAW|SF_ENDIAN_BIG] forKey:@"SFFormat"];
	return cfg;
}

- (void)loadConfigurations:(id)cfg
{
	id obj;
	if(obj=[cfg objectForKey:@"XLDPcmBEOutput_BitDepth"]) {
		[o_bitDepth selectItemAtIndex:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDPcmBEOutput_IsFloat"]) {
		[o_isFloat setState:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDPcmBEOutput_Samplerate"]) {
		[o_samplerate selectItemWithTag:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDPcmBEOutput_SRCAlgorithm"]) {
		[o_srcAlgorithm selectItemWithTag:[obj intValue]];
	}
	[self statusChanged:nil];
}

@end
