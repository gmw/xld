//
//  XLDAacOutput.m
//  XLDAacOutput
//
//  Created by tmkk on 06/06/13.
//  Copyright 2006 tmkk. All rights reserved.
//

#import "XLDAacOutput.h"
#import "XLDAacOutputTask.h"
#import <AudioToolbox/AudioToolbox.h>

APPKIT_EXTERN const double NSAppKitVersionNumber;
#define NSAppKitVersionNumber10_0 577
#define NSAppKitVersionNumber10_1 620
#define NSAppKitVersionNumber10_2 663
#define NSAppKitVersionNumber10_3 743

@implementation XLDAacOutput

+ (NSString *)pluginName
{
	return @"MPEG-4 AAC";
}

+ (BOOL)canLoadThisBundle
{
	long version = 0;
	Gestalt(gestaltQuickTime,&version);
	if (floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_3 || version >= 0x07210000) {
		return NO;
	}
	else return YES;
}

- (id)init
{
	[super init];
	[NSBundle loadNibNamed:@"XLDAacOutput" owner:self];
	
	[o_bitrate setAutoenablesItems:NO];
	
	[o_bitrate addItemWithTitle:@"20 kbps"];
	[o_bitrate addItemWithTitle:@"24 kbps"];
	[o_bitrate addItemWithTitle:@"28 kbps"];
	[o_bitrate addItemWithTitle:@"32 kbps"];
	[o_bitrate addItemWithTitle:@"40 kbps"];
	[o_bitrate addItemWithTitle:@"48 kbps"];
	[o_bitrate addItemWithTitle:@"56 kbps"];
	[o_bitrate addItemWithTitle:@"64 kbps"];
	[o_bitrate addItemWithTitle:@"80 kbps"];
	[o_bitrate addItemWithTitle:@"96 kbps"];
	[o_bitrate addItemWithTitle:@"112 kbps"];
	[o_bitrate addItemWithTitle:@"128 kbps"];
	[o_bitrate addItemWithTitle:@"160 kbps"];
	[o_bitrate addItemWithTitle:@"192 kbps"];
	[o_bitrate addItemWithTitle:@"224 kbps"];
	[o_bitrate addItemWithTitle:@"256 kbps"];
	[o_bitrate addItemWithTitle:@"320 kbps"];
	
	[o_bitrate selectItemAtIndex:12];
	
	return self;
}

- (NSView *)prefPane
{
	return o_prefPane;
}

- (void)savePrefs
{
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	[pref setInteger:[o_bitrate indexOfSelectedItem] forKey:@"XLDAacOutput_Bitrate"];
	[pref setInteger:[o_quality indexOfSelectedItem] forKey:@"XLDAacOutput_Quality"];
	[pref setInteger:[o_useVBR state]  forKey:@"XLDAacOutput_VBR"];
	[pref setInteger:[o_gaplessFlag state]  forKey:@"XLDAacOutput_AddGapless"];
	[pref synchronize];
}

- (void)loadPrefs
{
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	[self loadConfigurations:pref];
}

- (id)createTaskForOutput
{
	return [[XLDAacOutputTask alloc] initWithConfigurations:[self configurations]];
}

- (id)createTaskForOutputWithConfigurations:(NSDictionary *)cfg
{
	return [[XLDAacOutputTask alloc] initWithConfigurations:cfg];
}

- (IBAction)vbrChecked:(id)sender
{
	if([o_useVBR state] == NSOnState) {
		switch([o_bitrate indexOfSelectedItem]) {
			case 10:
			case 12:
			case 13:
			case 14:
			case 16:
				break;
			default:
				[o_bitrate selectItemAtIndex:12];
		}
		[[o_bitrate itemAtIndex:0] setEnabled:NO];
		[[o_bitrate itemAtIndex:1] setEnabled:NO];
		[[o_bitrate itemAtIndex:2] setEnabled:NO];
		[[o_bitrate itemAtIndex:3] setEnabled:NO];
		[[o_bitrate itemAtIndex:4] setEnabled:NO];
		[[o_bitrate itemAtIndex:5] setEnabled:NO];
		[[o_bitrate itemAtIndex:6] setEnabled:NO];
		[[o_bitrate itemAtIndex:7] setEnabled:NO];
		[[o_bitrate itemAtIndex:8] setEnabled:NO];
		[[o_bitrate itemAtIndex:9] setEnabled:NO];
		[[o_bitrate itemAtIndex:11] setEnabled:NO];
		[[o_bitrate itemAtIndex:15] setEnabled:NO];
		[[o_bitrate itemAtIndex:17] setEnabled:NO];
	}
	else {
		[[o_bitrate itemAtIndex:0] setEnabled:YES];
		[[o_bitrate itemAtIndex:1] setEnabled:YES];
		[[o_bitrate itemAtIndex:2] setEnabled:YES];
		[[o_bitrate itemAtIndex:3] setEnabled:YES];
		[[o_bitrate itemAtIndex:4] setEnabled:YES];
		[[o_bitrate itemAtIndex:5] setEnabled:YES];
		[[o_bitrate itemAtIndex:6] setEnabled:YES];
		[[o_bitrate itemAtIndex:7] setEnabled:YES];
		[[o_bitrate itemAtIndex:8] setEnabled:YES];
		[[o_bitrate itemAtIndex:9] setEnabled:YES];
		[[o_bitrate itemAtIndex:11] setEnabled:YES];
		[[o_bitrate itemAtIndex:15] setEnabled:YES];
		[[o_bitrate itemAtIndex:17] setEnabled:YES];
	}
}

- (unsigned int)bitrate
{
	return (unsigned int)[[[[o_bitrate titleOfSelectedItem] componentsSeparatedByString:@" "] objectAtIndex:0] intValue] * 1000;
}

- (unsigned int)quality
{
	switch([o_quality indexOfSelectedItem]) {
		case 0:
			return kAudioConverterQuality_Max;
		case 1:
			return kAudioConverterQuality_High;
		case 2:
			return kAudioConverterQuality_Medium;
		case 3:
			return kAudioConverterQuality_Low;
		case 4:
			return kAudioConverterQuality_Min;
	}
	return kAudioConverterQuality_Medium;
}

- (BOOL)useVBR
{
	return ([o_useVBR state] == NSOnState) ? YES : NO;
}

- (BOOL)addGaplessInfo
{
	return ([o_gaplessFlag state] == NSOnState) ? YES : NO;
}

- (NSMutableDictionary *)configurations
{
	NSMutableDictionary *cfg = [[NSMutableDictionary alloc] init];
	/* for GUI */
	[cfg setObject:[NSNumber numberWithInt:[o_bitrate indexOfSelectedItem]] forKey:@"XLDAacOutput_Bitrate"];
	[cfg setObject:[NSNumber numberWithInt:[o_quality indexOfSelectedItem]] forKey:@"XLDAacOutput_Quality"];
	[cfg setObject:[NSNumber numberWithInt:[o_useVBR state]] forKey:@"XLDAacOutput_VBR"];
	[cfg setObject:[NSNumber numberWithInt:[o_gaplessFlag state]] forKey:@"XLDAacOutput_AddGapless"];
	/* for task */
	[cfg setObject:[NSNumber numberWithUnsignedInt:[self bitrate]] forKey:@"Bitrate"];
	[cfg setObject:[NSNumber numberWithUnsignedInt:[self quality]] forKey:@"Quality"];
	[cfg setObject:[NSNumber numberWithBool:[self useVBR]] forKey:@"UseVBR"];
	[cfg setObject:[NSNumber numberWithBool:[self addGaplessInfo]] forKey:@"AddGaplessInfo"];
	/* desc */
	if([self useVBR]) {
		[cfg setObject:[NSString stringWithFormat:@"CVBR %dkbps",[self bitrate]/1000] forKey:@"ShortDesc"];
	}
	else {
		[cfg setObject:[NSString stringWithFormat:@"ABR %dkbps",[self bitrate]/1000] forKey:@"ShortDesc"];
	}
	return [cfg autorelease];
}

- (void)loadConfigurations:(id)cfg
{
	id obj;
	if(obj=[cfg objectForKey:@"XLDAacOutput_Bitrate"]) {
		if([obj intValue] < [o_bitrate numberOfItems]) [o_bitrate selectItemAtIndex:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDAacOutput_Quality"]) {
		if([obj intValue] < [o_quality numberOfItems]) [o_quality selectItemAtIndex:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDAacOutput_VBR"]) {
		[o_useVBR setState:[obj intValue]];
		[self vbrChecked:self];
	}
	if(obj=[cfg objectForKey:@"XLDAacOutput_AddGapless"]) {
		[o_gaplessFlag setState:[obj intValue]];
	}
}

@end
