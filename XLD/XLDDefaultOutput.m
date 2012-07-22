//
//  XLDDefaultOutput.m
//  XLD
//
//  Created by tmkk on 06/06/08.
//  Copyright 2006 tmkk. All rights reserved.
//

#import "XLDDefaultOutput.h"
#import "XLDDefaultOutputTask.h"

@implementation XLDDefaultOutput

+ (NSString *)pluginName
{
	return @"Default PCM Output";
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
	[NSBundle loadNibNamed:@"XLDDefaultOutput" owner:self];
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
	[pref setInteger:[o_bitDepth indexOfSelectedItem] forKey:@"XLDDefaultOutput_BitDepth"];
	[pref setInteger:[o_isFloat state] forKey:@"XLDDefaultOutput_IsFloat"];
	[pref synchronize];
}

- (void)loadPrefs
{
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	[self loadConfigurations:pref];
}

- (id)createTaskForOutput
{
	return [[XLDDefaultOutputTask alloc] initWithConfigurations:[self configurations]];
}

- (id)createTaskForOutputWithConfigurations:(NSDictionary *)cfg
{
	return [[XLDDefaultOutputTask alloc] initWithConfigurations:cfg];
}

- (IBAction)statusChanged:(id)target
{
	if([[o_bitDepth selectedItem] tag] == 4) {
		[o_isFloat setEnabled:YES];
	}
	else {
		[o_isFloat setEnabled:NO];
		[o_isFloat setState:NSOffState];
	}
}

- (NSMutableDictionary *)configurations
{
	NSMutableDictionary *cfg = [[NSMutableDictionary alloc] init];
	/* for task */
	[cfg setObject:[NSNumber numberWithInt:[[o_bitDepth selectedItem] tag]] forKey:@"BitDepth"];
	[cfg setObject:[NSNumber numberWithBool:([o_isFloat state] == NSOnState)] forKey:@"IsFloat"];
	/* desc */
	if([o_isFloat state]==NSOnState) [cfg setObject:@"32-bit, float" forKey:@"ShortDesc"];
	else if([[o_bitDepth selectedItem] tag]) [cfg setObject:[NSString stringWithFormat:@"%d-bit",[[o_bitDepth selectedItem] tag]*8] forKey:@"ShortDesc"];
	return [cfg autorelease];
}

- (void)loadConfigurations:(id)cfg
{
	id obj;
	if(obj=[cfg objectForKey:@"XLDDefaultOutput_BitDepth"]) {
		[o_bitDepth selectItemAtIndex:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDDefaultOutput_IsFloat"]) {
		[o_isFloat setState:[obj intValue]];
	}
	[self statusChanged:nil];
}

@end
