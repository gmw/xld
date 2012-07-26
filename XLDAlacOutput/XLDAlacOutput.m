//
//  XLDAlacOutput.m
//  XLDAlacOutput
//
//  Created by tmkk on 06/06/23.
//  Copyright 2006 tmkk. All rights reserved.
//

#import "XLDAlacOutput.h"
#import "XLDAlacOutputTask.h"

APPKIT_EXTERN const double NSAppKitVersionNumber;
#define NSAppKitVersionNumber10_0 577
#define NSAppKitVersionNumber10_1 620
#define NSAppKitVersionNumber10_2 663
#define NSAppKitVersionNumber10_3 743

@implementation XLDAlacOutput

+ (NSString *)pluginName
{
	return @"Apple Lossless";
}

+ (BOOL)canLoadThisBundle
{
	if (floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_3 ) {
		return NO;
	}
	else return YES;
}

- (id)init
{
	[super init];
	[NSBundle loadNibNamed:@"XLDAlacOutput" owner:self];
	return self;
}

- (NSView *)prefPane
{
	return o_prefPane;
}

- (void)savePrefs
{
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	[pref setInteger:[o_samplerate indexOfSelectedItem]  forKey:@"XLDAlacOutput_Samplerate"];
	[pref setInteger:[o_embedChapter state]  forKey:@"XLDAlacOutput_EmbedChapter"];
	[pref setInteger:[o_bitDepth indexOfSelectedItem]  forKey:@"XLDAlacOutput_BitDepth"];
	[pref synchronize];
}

- (void)loadPrefs
{
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	[self loadConfigurations:pref];
}

- (id)createTaskForOutput
{
	return [[XLDAlacOutputTask alloc] initWithConfigurations:[self configurations]];
}

- (id)createTaskForOutputWithConfigurations:(NSDictionary *)cfg
{
	return [[XLDAlacOutputTask alloc] initWithConfigurations:cfg];
}

- (BOOL)embedChapter
{
	return ([o_embedChapter state] == NSOnState);
}

- (NSMutableDictionary *)configurations
{
	NSMutableDictionary *cfg = [[NSMutableDictionary alloc] init];
	/* for GUI */
	[cfg setObject:[NSNumber numberWithInt:[o_samplerate indexOfSelectedItem]] forKey:@"XLDAlacOutput_Samplerate"];
	[cfg setObject:[NSNumber numberWithInt:[o_embedChapter state]] forKey:@"XLDAlacOutput_EmbedChapter"];
	[cfg setObject:[NSNumber numberWithInt:[o_bitDepth indexOfSelectedItem]] forKey:@"XLDAlacOutput_BitDepth"];
	/* for task */
	[cfg setObject:[NSNumber numberWithInt:[[o_samplerate selectedItem] tag]] forKey:@"Samplerate"];
	[cfg setObject:[NSNumber numberWithBool:[self embedChapter]] forKey:@"EmbedChapter"];
	[cfg setObject:[NSNumber numberWithInt:[[o_bitDepth selectedItem] tag]] forKey:@"BitDepth"];
	/* desc */
	if([[o_samplerate selectedItem] tag] && [[o_bitDepth selectedItem] tag]) {
		[cfg setObject:[NSString stringWithFormat:@"%d Hz, %d bit",[[o_samplerate selectedItem] tag],[[o_bitDepth selectedItem] tag]] forKey:@"ShortDesc"];
	}
	else if([[o_samplerate selectedItem] tag]) {
		[cfg setObject:[NSString stringWithFormat:@"%d Hz",[[o_samplerate selectedItem] tag]] forKey:@"ShortDesc"];
	}
	else if([[o_bitDepth selectedItem] tag]) {
		[cfg setObject:[NSString stringWithFormat:@"%d bit",[[o_bitDepth selectedItem] tag]] forKey:@"ShortDesc"];
	}
	return [cfg autorelease];
}

- (void)loadConfigurations:(id)cfg
{
	id obj;
	if(obj=[cfg objectForKey:@"XLDAlacOutput_Samplerate"]) {
		if([obj intValue] < [o_samplerate numberOfItems]) [o_samplerate selectItemAtIndex:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDAlacOutput_EmbedChapter"]) {
		[o_embedChapter setState:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDAlacOutput_BitDepth"]) {
		if([obj intValue] < [o_bitDepth numberOfItems]) [o_bitDepth selectItemAtIndex:[obj intValue]];
	}
}

@end
