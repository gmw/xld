//
//  XLDAacOutput2.m
//  XLDAacOutput2
//
//  Created by tmkk on 06/06/13.
//  Copyright 2006 tmkk. All rights reserved.
//

#import "XLDAacOutput2.h"
#import "XLDAacOutput2Task.h"
#import <AudioToolbox/AudioToolbox.h>
#import <dlfcn.h>

APPKIT_EXTERN const double NSAppKitVersionNumber;
#define NSAppKitVersionNumber10_0 577
#define NSAppKitVersionNumber10_1 620
#define NSAppKitVersionNumber10_2 663
#define NSAppKitVersionNumber10_3 743
#define NSAppKitVersionNumber10_4 824
#define NSAppKitVersionNumber10_5 949

@implementation XLDAacOutput2

+ (NSString *)pluginName
{
	return @"MPEG-4 AAC";
}

+ (BOOL)canLoadThisBundle
{
	long version = 0;
	Gestalt(gestaltQuickTime,&version);
	if (floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_3 || version < 0x07210000) {
		return NO;
	}
	else return YES;
}

- (id)init
{
	[super init];
	[NSBundle loadNibNamed:@"XLDAacOutput2" owner:self];
	
	[o_bitrateField setIntValue:128];
	[o_samplerate setAutoenablesItems:NO];
	long version = 0;
	Gestalt(gestaltQuickTime,&version);
	if(version < 0x07630000 || floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_4) {
		isSBRAvailable = NO;
	}
	else if(floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_5) {
		isSBRAvailable = NO;
		ComponentDescription cd;
		cd.componentType = kAudioEncoderComponentType;
		cd.componentSubType = 'aach';
		cd.componentManufacturer = kAudioUnitManufacturer_Apple;
		cd.componentFlags = 0;
		cd.componentFlagsMask = 0;
		ComponentResult (*ComponentRoutine) (ComponentParameters * cp, Handle componentStorage);
		void *handle = dlopen("/System/Library/Components/AudioCodecs.component/Contents/MacOS/AudioCodecs",RTLD_LAZY|RTLD_LOCAL);
		if(handle) {
			ComponentRoutine = dlsym(handle,"ACMP4AACHighEfficiencyEncoderEntry");
			if(ComponentRoutine) {
				RegisterComponent(&cd,ComponentRoutine,0,NULL,NULL,NULL);
				isSBRAvailable = YES;
			}
		}
	}
	else isSBRAvailable = YES;
	if(version < 0x07630000 || floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_4) {
		isNewVBR = NO;
		[o_vbrQuality setIntValue:90];
		[o_field12 setIntValue:90];
	}
	else {
		isNewVBR = YES;
		[o_vbrQuality setIntValue:65];
		[o_field12 setIntValue:65];
	}
	if (!isSBRAvailable) {
		[o_enableHE setEnabled:NO];
	}
	
	
	/*NSMutableString *str;
	str = [NSMutableString stringWithString:[o_field13 stringValue]];
	[str replaceOccurrencesOfString:@"32" withString:@"40" options:0 range:NSMakeRange(0,[str length])];
	[o_field13 setStringValue:str];
	if(isNewVBR) {
		str = [NSMutableString stringWithString:[o_field14 stringValue]];
		[str replaceOccurrencesOfString:@"192" withString:@"320" options:0 range:NSMakeRange(0,[str length])];
		[o_field14 setStringValue:str];
	}*/
	
	[self modeChanged:self];
	
	//if(floor(NSAppKitVersionNumber) > NSAppKitVersionNumber10_4) [o_accurateBitrate setEnabled:NO];
	
	return self;
}

- (NSView *)prefPane
{
	return o_prefPane;
}

- (void)savePrefs
{
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	[pref setInteger:[o_bitrateField intValue] forKey:@"XLDAacOutput2_Bitrate"];
	[pref setInteger:[o_quality indexOfSelectedItem] forKey:@"XLDAacOutput2_Quality"];
	[pref setInteger:[o_encodeMode indexOfSelectedItem]  forKey:@"XLDAacOutput2_Mode"];
	[pref setInteger:[o_gaplessFlag state]  forKey:@"XLDAacOutput2_AddGapless"];
	[pref setInteger:[o_vbrQuality intValue]  forKey:@"XLDAacOutput2_VBRQuality"];
	[pref setInteger:[o_accurateBitrate state]  forKey:@"XLDAacOutput2_AccurateBitrate"];
	[pref setInteger:[o_samplerate indexOfSelectedItem]  forKey:@"XLDAacOutput2_Samplerate"];
	[pref setInteger:[o_enableHE state]  forKey:@"XLDAacOutput2_UseHE"];
	[pref setInteger:[o_forceMono state]  forKey:@"XLDAacOutput2_ForceMono"];
	[pref setInteger:[o_embedChapter state]  forKey:@"XLDAacOutput2_EmbedChapter"];
	[pref synchronize];
}

- (void)loadPrefs
{
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	[self loadConfigurations:pref];
}

- (id)createTaskForOutput
{
	return [[XLDAacOutput2Task alloc] initWithConfigurations:[self configurations]];
}

- (id)createTaskForOutputWithConfigurations:(NSDictionary *)cfg
{
	return [[XLDAacOutput2Task alloc] initWithConfigurations:cfg];
}

- (IBAction)modeChanged:(id)sender
{
	if([o_encodeMode indexOfSelectedItem] < 3) {
		[o_bitrateField setEnabled:YES];
		[o_vbrQuality setEnabled:NO];
		[o_field01 setTextColor:[NSColor blackColor]];
		[o_field02 setTextColor:[NSColor blackColor]];
		[o_field11 setTextColor:[NSColor grayColor]];
		[o_field12 setTextColor:[NSColor grayColor]];
		//[o_field13 setTextColor:[NSColor grayColor]];
		//[o_field14 setTextColor:[NSColor grayColor]];
		if(isSBRAvailable) [o_enableHE setEnabled:YES];
	}
	else {
		[o_bitrateField setEnabled:NO];
		[o_vbrQuality setEnabled:YES];
		[o_field01 setTextColor:[NSColor grayColor]];
		[o_field02 setTextColor:[NSColor grayColor]];
		[o_field11 setTextColor:[NSColor blackColor]];
		[o_field12 setTextColor:[NSColor blackColor]];
		//[o_field13 setTextColor:[NSColor blackColor]];
		//[o_field14 setTextColor:[NSColor blackColor]];
		[o_enableHE setState:NSOffState];
		[o_enableHE setEnabled:NO];
	}
	if([o_enableHE state] == NSOnState) {
		if([[o_samplerate selectedItem] tag] < 32000 || ![[o_samplerate selectedItem] tag]) {
			[o_samplerate selectItemAtIndex:0];
		}
		int i;
		for(i=[o_samplerate numberOfItems]-1;i>=0;i--) {
			if([[o_samplerate itemAtIndex:i] tag] && [[o_samplerate itemAtIndex:i] tag]<32000) {
				[[o_samplerate itemAtIndex:i] setEnabled:NO];
			}
		}
		[self bitrateEndEdit:nil];
	}
	else {
		int i;
		for(i=[o_samplerate numberOfItems]-1;i>=0;i--) {
			[[o_samplerate itemAtIndex:i] setEnabled:YES];
		}
	}
}

- (IBAction)bitrateEndEdit:(id)sender
{
	if([o_enableHE state] == NSOffState) {
		if([o_forceMono state] == NSOnState) {
			if([o_bitrateField intValue] > 256) [o_bitrateField setIntValue:256];
		}
		else {
			if([o_bitrateField intValue] < 16) [o_bitrateField setIntValue:16];
			if([o_bitrateField intValue] > 320) [o_bitrateField setIntValue:320];
		}
	}
	else {
		if([o_forceMono state] == NSOnState) {
			if([o_bitrateField intValue] > 40) [o_bitrateField setIntValue:40];
		}
		else {
			if([[o_samplerate selectedItem] tag] == 44100 || [[o_samplerate selectedItem] tag] == 48000) {
				if([o_bitrateField intValue] < 36) [o_bitrateField setIntValue:36];
			}
			else {
				if([o_bitrateField intValue] < 24) [o_bitrateField setIntValue:24];
			}
			if([o_bitrateField intValue] > 80) [o_bitrateField setIntValue:80];
		}
	}
}

- (IBAction)vbrQualityChanged:(id)sender
{
	NSString *helpStr;
	int bitrate;
	if(isNewVBR) {
		if([sender floatValue] < 5) bitrate = 40;
		else if([sender floatValue] < 14) bitrate = 45;
		else if([sender floatValue] < 23) bitrate = 75;
		else if([sender floatValue] < 32) bitrate = 80;
		else if([sender floatValue] < 41) bitrate = 95;
		else if([sender floatValue] < 50) bitrate = 105;
		else if([sender floatValue] < 59) bitrate = 115;
		else if([sender floatValue] < 69) bitrate = 135;
		else if([sender floatValue] < 78) bitrate = 150;
		else if([sender floatValue] < 87) bitrate = 165;
		else if([sender floatValue] < 96) bitrate = 195;
		else if([sender floatValue] < 105) bitrate = 225;
		else if([sender floatValue] < 114) bitrate = 255;
		else if([sender floatValue] < 123) bitrate = 285;
		else bitrate = 320;
	}
	else {
		if([sender floatValue] < 7) bitrate = 40;
		else if([sender floatValue] < 20) bitrate = 45;
		else if([sender floatValue] < 32) bitrate = 75;
		else if([sender floatValue] < 45) bitrate = 80;
		else if([sender floatValue] < 58) bitrate = 95;
		else if([sender floatValue] < 70) bitrate = 105;
		else if([sender floatValue] < 83) bitrate = 115;
		else if([sender floatValue] < 96) bitrate = 135;
		else if([sender floatValue] < 108) bitrate = 150;
		else if([sender floatValue] < 121) bitrate = 165;
		else bitrate = 195;
	}
	helpStr = [NSString stringWithFormat:[[NSBundle bundleForClass:[self class]] localizedStringForKey:@"about %d kbps" value:nil table:nil],bitrate];
	[o_field12 takeIntValueFrom:sender];
	NSHelpManager *helpManager = [NSHelpManager sharedHelpManager];
	NSDictionary *attrDic = [NSDictionary dictionaryWithObject:[NSFont systemFontOfSize:11] forKey:NSFontAttributeName];
    NSAttributedString *help = 
        [[[NSAttributedString alloc] initWithString:helpStr attributes:attrDic] autorelease];
    [helpManager setContextHelp:help forObject:sender];
    [helpManager showContextHelpForObject:sender locationHint:[NSEvent mouseLocation]];
	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(sliderDoneMoving:) object:sender];
	[self performSelector:@selector(sliderDoneMoving:) withObject:sender afterDelay:0];
}

- (void)sliderDoneMoving:(id)sender
{
	NSHelpManager *helpManager = [NSHelpManager sharedHelpManager];
    [helpManager removeContextHelpForObject:sender];
    NSEvent	*newEvent;
	
    newEvent = [NSEvent mouseEventWithType:NSLeftMouseDown
								  location:[[o_prefPane window] mouseLocationOutsideOfEventStream]
							 modifierFlags:0
								 timestamp:0
							  windowNumber:[[o_prefPane window] windowNumber]
								   context:[[o_prefPane window] graphicsContext]
							   eventNumber:0
								clickCount:1
								  pressure:0
		];
    [NSApp postEvent:newEvent atStart:NO];
    newEvent = [NSEvent mouseEventWithType:NSLeftMouseUp
								  location:[[o_prefPane window] mouseLocationOutsideOfEventStream]
							 modifierFlags:0 
								 timestamp:0
							  windowNumber:[[o_prefPane window] windowNumber]
								   context:[[o_prefPane window] graphicsContext]
							   eventNumber:0
								clickCount:1
								  pressure:0
		];
    [NSApp postEvent:newEvent atStart:NO];
}


- (unsigned int)bitrate
{
	//return (unsigned int)[[[[o_bitrate titleOfSelectedItem] componentsSeparatedByString:@" "] objectAtIndex:0] intValue] * 1000;
	if([o_bitrateField intValue] < 16) [o_bitrateField setIntValue:16];
	if([o_bitrateField intValue] > 320) [o_bitrateField setIntValue:320];
	return (unsigned int)[o_bitrateField intValue] * 1000;
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

- (BOOL)addGaplessInfo
{
	return ([o_gaplessFlag state] == NSOnState) ? YES : NO;
}

- (unsigned int)encodeMode
{
	return (unsigned int)[o_encodeMode indexOfSelectedItem];
}

- (unsigned int)vbrQuality
{
	return (unsigned int)[o_vbrQuality intValue];
}
/*
- (BOOL)writeAccurateBitrate
{
	if(floor(NSAppKitVersionNumber) > NSAppKitVersionNumber10_4) return NO;
	else return ([o_accurateBitrate state] == NSOnState) ? YES : NO;
}
*/
- (unsigned int)bitrateToWrite
{
	if(([o_accurateBitrate state] == NSOnState) || ([o_encodeMode indexOfSelectedItem] == 3)) return 0;
	else return (unsigned int)[o_bitrateField intValue] * 1000;
}

- (int)samplerate
{
	return [[o_samplerate selectedItem] tag];
}

- (BOOL)sbrEnabled
{
	return ([o_enableHE state] == NSOnState);
}

- (BOOL)forceMono
{
	return ([o_forceMono state] == NSOnState);
}

- (BOOL)embedChapter
{
	return ([o_embedChapter state] == NSOnState);
}

- (NSMutableDictionary *)configurations
{
	NSMutableDictionary *cfg = [[NSMutableDictionary alloc] init];
	/* for GUI */
	[cfg setObject:[NSNumber numberWithInt:[o_bitrateField intValue]] forKey:@"XLDAacOutput2_Bitrate"];
	[cfg setObject:[NSNumber numberWithInt:[o_quality indexOfSelectedItem]] forKey:@"XLDAacOutput2_Quality"];
	[cfg setObject:[NSNumber numberWithInt:[o_encodeMode indexOfSelectedItem]] forKey:@"XLDAacOutput2_Mode"];
	[cfg setObject:[NSNumber numberWithInt:[o_gaplessFlag state]] forKey:@"XLDAacOutput2_AddGapless"];
	[cfg setObject:[NSNumber numberWithInt:[o_vbrQuality intValue]] forKey:@"XLDAacOutput2_VBRQuality"];
	[cfg setObject:[NSNumber numberWithInt:[o_accurateBitrate state]] forKey:@"XLDAacOutput2_AccurateBitrate"];
	[cfg setObject:[NSNumber numberWithInt:[o_samplerate indexOfSelectedItem]] forKey:@"XLDAacOutput2_Samplerate"];
	[cfg setObject:[NSNumber numberWithInt:[o_enableHE state]] forKey:@"XLDAacOutput2_UseHE"];
	[cfg setObject:[NSNumber numberWithInt:[o_forceMono state]] forKey:@"XLDAacOutput2_ForceMono"];
	[cfg setObject:[NSNumber numberWithInt:[o_embedChapter state]] forKey:@"XLDAacOutput2_EmbedChapter"];
	/* for task */
	[cfg setObject:[NSNumber numberWithUnsignedInt:[self bitrate]] forKey:@"Bitrate"];
	[cfg setObject:[NSNumber numberWithUnsignedInt:[self quality]] forKey:@"Quality"];
	[cfg setObject:[NSNumber numberWithBool:[self addGaplessInfo]] forKey:@"AddGaplessInfo"];
	[cfg setObject:[NSNumber numberWithUnsignedInt:[self encodeMode]] forKey:@"EncodeMode"];
	[cfg setObject:[NSNumber numberWithUnsignedInt:[self vbrQuality]] forKey:@"VbrQuality"];
	[cfg setObject:[NSNumber numberWithUnsignedInt:[self bitrateToWrite]] forKey:@"BitrateToWrite"];
	[cfg setObject:[NSNumber numberWithInt:[self samplerate]] forKey:@"Samplerate"];
	[cfg setObject:[NSNumber numberWithBool:[self sbrEnabled]] forKey:@"SbrEnabled"];
	[cfg setObject:[NSNumber numberWithBool:[self forceMono]] forKey:@"ForceMono"];
	[cfg setObject:[NSNumber numberWithBool:[self embedChapter]] forKey:@"EmbedChapter"];
	/* desc */
	if([self encodeMode] == 3) {
		[cfg setObject:[NSString stringWithFormat:@"TVBR quality %d",[self vbrQuality]] forKey:@"ShortDesc"];
	}
	else if([self encodeMode] == 0) {
		if([self sbrEnabled])
			[cfg setObject:[NSString stringWithFormat:@"High efficiency, CBR %dkbps",[self bitrate]/1000] forKey:@"ShortDesc"];
		else
			[cfg setObject:[NSString stringWithFormat:@"CBR %dkbps",[self bitrate]/1000] forKey:@"ShortDesc"];
	}
	else if([self encodeMode] == 1) {
		if([self sbrEnabled])
			[cfg setObject:[NSString stringWithFormat:@"High efficiency, ABR %dkbps",[self bitrate]/1000] forKey:@"ShortDesc"];
		else
			[cfg setObject:[NSString stringWithFormat:@"ABR %dkbps",[self bitrate]/1000] forKey:@"ShortDesc"];
	}
	else if([self encodeMode] == 2) {
		if([self sbrEnabled])
			[cfg setObject:[NSString stringWithFormat:@"High efficiency, CVBR %dkbps",[self bitrate]/1000] forKey:@"ShortDesc"];
		else
			[cfg setObject:[NSString stringWithFormat:@"CVBR %dkbps",[self bitrate]/1000] forKey:@"ShortDesc"];
	}

	return [cfg autorelease];
}

- (void)loadConfigurations:(id)cfg
{
	id obj;
	if(obj=[cfg objectForKey:@"XLDAacOutput2_Bitrate"]) {
		[o_bitrateField setIntValue:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDAacOutput2_Quality"]) {
		if([obj intValue] < [o_quality numberOfItems]) [o_quality selectItemAtIndex:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDAacOutput2_Mode"]) {
		if([obj intValue] < [o_encodeMode numberOfItems]) [o_encodeMode selectItemAtIndex:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDAacOutput2_AddGapless"]) {
		[o_gaplessFlag setState:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDAacOutput2_VBRQuality"]) {
		[o_vbrQuality setIntValue:[obj intValue]];
		[o_field12 setIntValue:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDAacOutput2_AccurateBitrate"]) {
		[o_accurateBitrate setState:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDAacOutput2_Samplerate"]) {
		if([obj intValue] < [o_samplerate numberOfItems]) [o_samplerate selectItemAtIndex:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDAacOutput2_UseHE"]) {
		[o_enableHE setState:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDAacOutput2_ForceMono"]) {
		[o_forceMono setState:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDAacOutput2_EmbedChapter"]) {
		[o_embedChapter setState:[obj intValue]];
	}
	[self modeChanged:self];
}

@end
