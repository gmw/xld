//
//  XLDSd2fOutput.m
//  XLD
//
//  Created by tmkk on 13/02/11.
//  Copyright 2013 tmkk. All rights reserved.
//

#import "XLDSd2fOutput.h"
#import "XLDSd2fOutputTask.h"

@implementation XLDSd2fOutput

+ (NSString *)pluginName
{
	return @"Sound Designer II";
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
	[NSBundle loadNibNamed:@"XLDSd2fOutput" owner:self];
	[self statusChanged:nil];
	return self;
}

- (NSView *)prefPane
{
	return o_view;
}

- (void)savePrefs
{
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	[pref setInteger:[o_bitDepth indexOfSelectedItem] forKey:@"XLDSd2fOutput_BitDepth"];
	[pref synchronize];
}

- (void)loadPrefs
{
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	[self loadConfigurations:pref];
}

- (id)createTaskForOutput
{
	return [[XLDSd2fOutputTask alloc] initWithConfigurations:[self configurations]];
}

- (id)createTaskForOutputWithConfigurations:(NSDictionary *)cfg
{
	return [[XLDSd2fOutputTask alloc] initWithConfigurations:cfg];
}

- (IBAction)statusChanged:(id)target
{
	
}

- (NSMutableDictionary *)configurations
{
	NSMutableDictionary *cfg = [[NSMutableDictionary alloc] init];
	/* for GUI */
	[cfg setObject:[NSNumber numberWithInt:[o_bitDepth indexOfSelectedItem]] forKey:@"XLDSd2fOutput_BitDepth"];
	/* for task */
	[cfg setObject:[NSNumber numberWithInt:[[o_bitDepth selectedItem] tag]] forKey:@"BitDepth"];
	[cfg setObject:[NSNumber numberWithUnsignedInt:SF_FORMAT_RAW|SF_ENDIAN_BIG] forKey:@"SFFormat"];
	/* desc */
	if([[o_bitDepth selectedItem] tag]) [cfg setObject:[NSString stringWithFormat:@"%d-bit",[[o_bitDepth selectedItem] tag]*8] forKey:@"ShortDesc"];
	return [cfg autorelease];
}

- (void)loadConfigurations:(id)cfg
{
	id obj;
	if(obj=[cfg objectForKey:@"XLDSd2fOutput_BitDepth"]) {
		[o_bitDepth selectItemAtIndex:[obj intValue]];
	}
	[self statusChanged:nil];
}

@end
