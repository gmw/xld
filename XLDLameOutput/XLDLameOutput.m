//
//  XLDLameOutput.m
//  XLDLameOutput
//
//  Created by tmkk on 06/06/13.
//  Copyright 2006 tmkk. All rights reserved.
//

#import "XLDLameOutput.h"
#import "XLDLameOutputTask.h"
#import <lame/lame.h>

@implementation XLDLameOutput

+ (NSString *)pluginName
{
	return @"LAME MP3";
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
	[NSBundle loadNibNamed:@"XLDLameOutput" owner:self];
	
	[o_bitrate addItemWithTitle:@"16 kbps"];
	[o_bitrate addItemWithTitle:@"24 kbps"];
	[o_bitrate addItemWithTitle:@"32 kbps"];
	[o_bitrate addItemWithTitle:@"40 kbps"];
	[o_bitrate addItemWithTitle:@"48 kbps"];
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
	
	[o_bitrate selectItemAtIndex:10];
	
	[o_creditStr setStringValue:[NSString stringWithFormat:@"%@ %s",[o_creditStr stringValue],get_lame_version()]];
	
	return self;
}

- (NSView *)prefPane
{
	return o_prefPane;
}

- (void)savePrefs
{
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	[pref setInteger:[o_bitrate indexOfSelectedItem] forKey:@"XLDLameOutput_Bitrate"];
	[pref setInteger:[o_quality indexOfSelectedItem] forKey:@"XLDLameOutput_Quality2"];
	[pref setInteger:[o_abrBitrate intValue] forKey:@"XLDLameOutput_ABRBitrate"];
	[pref setFloat:[o_vbrQuality floatValue] forKey:@"XLDLameOutput_VBRQuality_Float"];
	[pref setInteger:[o_vbrMethod indexOfSelectedItem] forKey:@"XLDLameOutput_VBRMethod"];
	[pref setInteger:[o_replayGain state] forKey:@"XLDLameOutput_ReplayGain"];
	[pref setInteger:[o_mode indexOfSelectedItem]  forKey:@"XLDLameOutput_EncodeMode"];
	[pref setInteger:[o_stereoMode indexOfSelectedItem] forKey:@"XLDLameOutput_StereoMode"];
	[pref setInteger:[o_sampleRate indexOfSelectedItem] forKey:@"XLDLameOutput_SampleRate"];
	[pref setInteger:[o_appendTLEN state] forKey:@"XLDLameOutput_AppendTLEN"];
	[pref synchronize];
}

- (void)loadPrefs
{
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	[self loadConfigurations:pref];
}

- (id)createTaskForOutput
{
	return [[XLDLameOutputTask alloc] initWithConfigurations:[self configurations]];
}

- (id)createTaskForOutputWithConfigurations:(NSDictionary *)cfg
{
	return [[XLDLameOutputTask alloc] initWithConfigurations:cfg];
}

- (int)quality
{
	switch([o_quality indexOfSelectedItem]) {
		case 0:
			return 2;
		case 1:
			return 3;
		case 2:
			return 5;
		case 3:
			return 7;
	}
	
	return 3;
}

- (float)vbrQuality
{
	float quality = roundf((10.0f - [o_vbrQuality floatValue])*10.0f)*0.1f;
	if(quality > 9.999f) quality = 9.999f;
	if(quality < 0.0f) quality = 0.0f;
	return quality;
}

- (int)bitrate
{
	return [[[[o_bitrate titleOfSelectedItem] componentsSeparatedByString:@" "] objectAtIndex:0] intValue];
}

- (int)abrBitrate
{
	return [o_abrBitrate intValue];
}

- (BOOL)useReplayGain
{
	return ([o_replayGain state] == NSOnState);
}

- (int)encodeMode
{
	return [o_mode indexOfSelectedItem];
}

- (int)vbrMethod
{
	return [o_vbrMethod indexOfSelectedItem];
}

- (XLDLameStereoMode)stereoMode
{
	return [[o_stereoMode selectedItem] tag];
}

- (int)sampleRate
{
	return [[o_sampleRate selectedItem] tag];
}

- (IBAction)setVbrQuality:(id)sender
{
	[o_vbrQualityValue setDoubleValue:10.0-[o_vbrQuality floatValue]];
	//NSLog(@"%f",[[o_vbrQualityValue stringValue] floatValue]);
}

- (IBAction)modeChanged:(id)sender
{
	int i;
	id abrBox = [o_abrBitrate superview];
	id cbrBox = [o_bitrate superview];
	id vbrBox = [o_vbrMethod superview];
	switch([o_mode indexOfSelectedItem]) {
		case 0:
			for(i=0;i<[[abrBox subviews] count];i++) {
				id subview = [[abrBox subviews] objectAtIndex:i];
				if([subview respondsToSelector:@selector(setEnabled:)])
					[subview setEnabled:NO];
				if([subview respondsToSelector:@selector(setTextColor:)])
					[subview setTextColor:[NSColor lightGrayColor]];
				[o_abrBitrate setTextColor:[NSColor blackColor]];
			}
			for(i=0;i<[[cbrBox subviews] count];i++) {
				id subview = [[cbrBox subviews] objectAtIndex:i];
				if([subview respondsToSelector:@selector(setEnabled:)])
					[subview setEnabled:NO];
				if([subview respondsToSelector:@selector(setTextColor:)])
					[subview setTextColor:[NSColor lightGrayColor]];
			}
			for(i=0;i<[[vbrBox subviews] count];i++) {
				id subview = [[vbrBox subviews] objectAtIndex:i];
				if([subview respondsToSelector:@selector(setEnabled:)])
					[subview setEnabled:YES];
				if([subview respondsToSelector:@selector(setTextColor:)])
					[subview setTextColor:[NSColor blackColor]];
			}
			break;
		case 1:
			for(i=0;i<[[abrBox subviews] count];i++) {
				id subview = [[abrBox subviews] objectAtIndex:i];
				if([subview respondsToSelector:@selector(setEnabled:)])
					[subview setEnabled:YES];
				if([subview respondsToSelector:@selector(setTextColor:)])
					[subview setTextColor:[NSColor blackColor]];
			}
			for(i=0;i<[[cbrBox subviews] count];i++) {
				id subview = [[cbrBox subviews] objectAtIndex:i];
				if([subview respondsToSelector:@selector(setEnabled:)])
					[subview setEnabled:NO];
				if([subview respondsToSelector:@selector(setTextColor:)])
					[subview setTextColor:[NSColor lightGrayColor]];
			}
			for(i=0;i<[[vbrBox subviews] count];i++) {
				id subview = [[vbrBox subviews] objectAtIndex:i];
				if([subview respondsToSelector:@selector(setEnabled:)])
					[subview setEnabled:NO];
				if([subview respondsToSelector:@selector(setTextColor:)])
					[subview setTextColor:[NSColor lightGrayColor]];
			}
			break;
		case 2:
			for(i=0;i<[[abrBox subviews] count];i++) {
				id subview = [[abrBox subviews] objectAtIndex:i];
				if([subview respondsToSelector:@selector(setEnabled:)])
					[subview setEnabled:NO];
				if([subview respondsToSelector:@selector(setTextColor:)])
					[subview setTextColor:[NSColor lightGrayColor]];
				[o_abrBitrate setTextColor:[NSColor blackColor]];
			}
			for(i=0;i<[[cbrBox subviews] count];i++) {
				id subview = [[cbrBox subviews] objectAtIndex:i];
				if([subview respondsToSelector:@selector(setEnabled:)])
					[subview setEnabled:YES];
				if([subview respondsToSelector:@selector(setTextColor:)])
					[subview setTextColor:[NSColor blackColor]];
			}
			for(i=0;i<[[vbrBox subviews] count];i++) {
				id subview = [[vbrBox subviews] objectAtIndex:i];
				if([subview respondsToSelector:@selector(setEnabled:)])
					[subview setEnabled:NO];
				if([subview respondsToSelector:@selector(setTextColor:)])
					[subview setTextColor:[NSColor lightGrayColor]];
			}
			break;
	}
}

- (BOOL)appendTLEN
{
	return ([o_appendTLEN state] == NSOnState);
}

- (NSMutableDictionary *)configurations
{
	NSMutableDictionary *cfg = [[NSMutableDictionary alloc] init];
	/* for GUI */
	[cfg setObject:[NSNumber numberWithInt:[o_bitrate indexOfSelectedItem]] forKey:@"XLDLameOutput_Bitrate"];
	[cfg setObject:[NSNumber numberWithInt:[o_quality indexOfSelectedItem]] forKey:@"XLDLameOutput_Quality2"];
	[cfg setObject:[NSNumber numberWithInt:[o_abrBitrate intValue]] forKey:@"XLDLameOutput_ABRBitrate"];
	[cfg setObject:[NSNumber numberWithFloat:[o_vbrQuality floatValue]] forKey:@"XLDLameOutput_VBRQuality_Float"];
	[cfg setObject:[NSNumber numberWithInt:[o_vbrMethod indexOfSelectedItem]] forKey:@"XLDLameOutput_VBRMethod"];
	[cfg setObject:[NSNumber numberWithInt:[o_replayGain state]] forKey:@"XLDLameOutput_ReplayGain"];
	[cfg setObject:[NSNumber numberWithInt:[o_mode indexOfSelectedItem]]  forKey:@"XLDLameOutput_EncodeMode"];
	[cfg setObject:[NSNumber numberWithInt:[o_stereoMode indexOfSelectedItem]] forKey:@"XLDLameOutput_StereoMode"];
	[cfg setObject:[NSNumber numberWithInt:[o_sampleRate indexOfSelectedItem]] forKey:@"XLDLameOutput_SampleRate"];
	[cfg setObject:[NSNumber numberWithInt:[o_appendTLEN state]] forKey:@"XLDLameOutput_AppendTLEN"];
	/* for task */
	[cfg setObject:[NSNumber numberWithInt:[self quality]] forKey:@"Quality"];
	[cfg setObject:[NSNumber numberWithFloat:[self vbrQuality]] forKey:@"VbrQuality"];
	[cfg setObject:[NSNumber numberWithInt:[self bitrate]] forKey:@"Bitrate"];
	[cfg setObject:[NSNumber numberWithInt:[self abrBitrate]] forKey:@"AbrBitrate"];
	[cfg setObject:[NSNumber numberWithBool:[self useReplayGain]] forKey:@"UseReplayGain"];
	[cfg setObject:[NSNumber numberWithInt:[self encodeMode]] forKey:@"EncodeMode"];
	[cfg setObject:[NSNumber numberWithInt:[self vbrMethod]] forKey:@"VbrMethod"];
	[cfg setObject:[NSNumber numberWithInt:[self stereoMode]] forKey:@"StereoMode"];
	[cfg setObject:[NSNumber numberWithInt:[self sampleRate]] forKey:@"SampleRate"];
	[cfg setObject:[NSNumber numberWithBool:[self appendTLEN]] forKey:@"AppendTLEN"];
	/* desc */
	if([self encodeMode] == 0) {
		[cfg setObject:[NSString stringWithFormat:@"VBR-%@ quality %.1f",[self vbrMethod]?@"old":@"new",[self vbrQuality]] forKey:@"ShortDesc"];
	}
	else if([self encodeMode] == 2) {
		[cfg setObject:[NSString stringWithFormat:@"CBR %dkbps",[self bitrate]] forKey:@"ShortDesc"];
	}
	else {
		[cfg setObject:[NSString stringWithFormat:@"ABR %dkbps",[self abrBitrate]] forKey:@"ShortDesc"];
	}
	return [cfg autorelease];
}

- (void)loadConfigurations:(id)cfg
{
	id obj;
	if(obj=[cfg objectForKey:@"XLDLameOutput_Bitrate"]) {
		if([obj intValue] < [o_bitrate numberOfItems]) [o_bitrate selectItemAtIndex:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDLameOutput_Quality2"]) {
		if([obj intValue] < [o_quality numberOfItems]) [o_quality selectItemAtIndex:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDLameOutput_ABRBitrate"]) {
		[o_abrBitrate setIntValue:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDLameOutput_VBRQuality_Float"]) {
		[o_vbrQuality setDoubleValue:[obj floatValue]];
		[self setVbrQuality:o_vbrQuality];
	}
	else if(obj=[cfg objectForKey:@"XLDLameOutput_VBRQuality"]) {
		[o_vbrQuality setIntValue:[obj intValue]+1];
		[self setVbrQuality:o_vbrQuality];
	}
	if(obj=[cfg objectForKey:@"XLDLameOutput_VBRMethod"]) {
		if([obj intValue] < [o_vbrMethod numberOfItems]) [o_vbrMethod selectItemAtIndex:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDLameOutput_ReplayGain"]) {
		[o_replayGain setState:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDLameOutput_EncodeMode"]) {
		if([obj intValue] < [o_mode numberOfItems]) [o_mode selectItemAtIndex:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDLameOutput_StereoMode"]) {
		if([obj intValue] < [o_stereoMode numberOfItems]) [o_stereoMode selectItemAtIndex:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDLameOutput_SampleRate"]) {
		if([obj intValue] < [o_sampleRate numberOfItems]) [o_sampleRate selectItemAtIndex:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDLameOutput_AppendTLEN"]) {
		[o_appendTLEN setState:[obj intValue]];
	}
	[self modeChanged:nil];
}

@end
