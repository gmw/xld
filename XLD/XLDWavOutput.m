//
//  XLDWavOutput.m
//  XLD
//
//  Created by tmkk on 10/11/03.
//  Copyright 2010 tmkk. All rights reserved.
//

#import "XLDWavOutput.h"
#import "XLDDefaultOutputTask.h"

@implementation XLDWavOutput

+ (NSString *)pluginName
{
	return @"WAV";
}

- (id)init
{
	[super init];
	[NSBundle loadNibNamed:@"XLDWavOutput" owner:self];
	NSMenuItem *item = [o_tagEncoding itemAtIndex:[o_tagEncoding indexOfItemWithTag:2]];
	NSString *title = [NSString stringWithFormat:@"%@ - %@",[item title],[NSString localizedNameOfStringEncoding:[NSString defaultCStringEncoding]]];
	[item setTitle:title];
	[self statusChanged:nil];
	return self;
}

- (void)savePrefs
{
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	[pref setInteger:[o_bitDepth indexOfSelectedItem] forKey:@"XLDWavOutput_BitDepth"];
	[pref setInteger:[o_isFloat state] forKey:@"XLDWavOutput_IsFloat"];
	[pref setInteger:[o_addTags state] forKey:@"XLDWavOutput_AddTags"];
	[pref setInteger:[[o_tagFormat selectedCell] tag] forKey:@"XLDWavOutput_WavTagFormat"];
	[pref setInteger:[[o_tagEncoding selectedItem] tag] forKey:@"XLDWavOutput_WavTagEncoding"];
	[pref synchronize];
}

- (NSMutableDictionary *)configurations
{
	NSMutableDictionary *cfg = [super configurations];
	/* for GUI */
	[cfg setObject:[NSNumber numberWithInt:[o_bitDepth indexOfSelectedItem]] forKey:@"XLDWavOutput_BitDepth"];
	[cfg setObject:[NSNumber numberWithInt:[o_isFloat state]] forKey:@"XLDWavOutput_IsFloat"];
	[cfg setObject:[NSNumber numberWithInt:[[o_tagFormat selectedCell] tag]] forKey:@"XLDWavOutput_WavTagFormat"];
	[cfg setObject:[NSNumber numberWithInt:[[o_tagEncoding selectedItem] tag]] forKey:@"XLDWavOutput_WavTagEncoding"];
	/* for task */
	[cfg setObject:[NSNumber numberWithUnsignedInt:SF_FORMAT_WAV] forKey:@"SFFormat"];
	if([o_addTags state] == NSOnState) {
		[cfg setObject:[NSNumber numberWithInt:[[o_tagFormat selectedCell] tag]] forKey:@"WavTagFormat"];
		[cfg setObject:[NSNumber numberWithInt:[[o_tagEncoding selectedItem] tag]] forKey:@"WavTagEncoding"];
	}
	return cfg;
}

- (void)loadConfigurations:(id)cfg
{
	id obj;
	if(obj=[cfg objectForKey:@"XLDWavOutput_BitDepth"]) {
		[o_bitDepth selectItemAtIndex:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDWavOutput_IsFloat"]) {
		[o_isFloat setState:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDWavOutput_AddTags"]) {
		[o_addTags setState:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDWavOutput_WavTagFormat"]) {
		[o_tagFormat selectCellWithTag:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDWavOutput_WavTagEncoding"]) {
		[o_tagEncoding selectItemWithTag:[obj intValue]];
	}
	
	[self statusChanged:nil];
}

- (IBAction)statusChanged:(id)target
{
	[super statusChanged:target];
	if([o_addTags state] == NSOnState) {
		[o_tagFormat setEnabled:YES];
		[o_tagEncoding setEnabled:YES];
		[o_text1 setTextColor:[NSColor blackColor]];
		[o_text2 setTextColor:[NSColor blackColor]];
		[o_text3 setTextColor:[NSColor blackColor]];
		if([[o_tagFormat selectedCell] tag] == 1) {
			[o_tagEncoding setEnabled:NO];
			[o_text2 setTextColor:[NSColor lightGrayColor]];
			[o_text3 setTextColor:[NSColor lightGrayColor]];
		}
	}
	else {
		[o_tagFormat setEnabled:NO];
		[o_tagEncoding setEnabled:NO];
		[o_text1 setTextColor:[NSColor lightGrayColor]];
		[o_text2 setTextColor:[NSColor lightGrayColor]];
		[o_text3 setTextColor:[NSColor lightGrayColor]];
	}
}

@end
