//
//  XLDDSDOutput.m
//  XLDDSDOutput
//
//  Created by tmkk on 15/01/24.
//  Copyright 2015 tmkk. All rights reserved.
//

#import "XLDDSDOutput.h"
#import "XLDDSDOutputTask.h"

@implementation XLDDSDOutput

+ (NSString *)pluginName
{
	return @"Direct Stream Digital";
}

+ (BOOL)canLoadThisBundle
{
	return YES;
}

- (id)init
{
	[super init];
	[NSBundle loadNibNamed:@"XLDDSDOutput" owner:self];
	return self;
}

- (NSView *)prefPane
{
	//NSRect frame = [o_view frame];
	//fprintf(stderr, "%f,%f,%f,%f\n",frame.origin.x,frame.origin.y,frame.size.width,frame.size.height);
	return o_view;
}

- (void)savePrefs
{
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	[pref setInteger:[[o_dsdType selectedItem] tag] forKey:@"XLDDSDOutput_DSDType"];
	[pref setInteger:[[o_dsdFormat selectedItem] tag] forKey:@"XLDDSDOutput_DSDFormat"];
	[pref setInteger:[[o_dsmType selectedItem] tag] forKey:@"XLDDSDOutput_DSMType"];
	[pref synchronize];
}

- (void)loadPrefs
{
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	[self loadConfigurations:pref];
}

- (id)createTaskForOutput
{
	return [[XLDDSDOutputTask alloc] initWithConfigurations:[self configurations]];
}

- (id)createTaskForOutputWithConfigurations:(NSDictionary *)cfg
{
	return [[XLDDSDOutputTask alloc] initWithConfigurations:cfg];
}

- (NSMutableDictionary *)configurations
{
	NSMutableDictionary *cfg = [[NSMutableDictionary alloc] init];
	/* for task */
	[cfg setObject:[NSNumber numberWithInt:[[o_dsdFormat selectedItem] tag]] forKey:@"DSDFormat"];
	[cfg setObject:[NSNumber numberWithInt:[[o_dsmType selectedItem] tag]] forKey:@"DSMType"];
	[cfg setObject:[NSNumber numberWithInt:[[o_dsdType selectedItem] tag]] forKey:@"DSDSamplerate"];
	/* desc */
	NSMutableString *desc = [NSMutableString string];
	if([[o_dsdType selectedItem] tag] == 2822400) {
		[desc appendString:@"DSD64"];
	}
	else if([[o_dsdType selectedItem] tag] == 5644800) {
		[desc appendString:@"DSD128"];
	}
	if([[o_dsdFormat selectedItem] tag] == DSDFileFormatDSF) {
		[desc appendString:@", DSF"];
	}
	else if([[o_dsdFormat selectedItem] tag] == DSDFileFormatDSDIFF) {
		[desc appendString:@", DSDIFF"];
	}
	[cfg setObject:desc forKey:@"ShortDesc"];
	return [cfg autorelease];
}

- (void)loadConfigurations:(id)cfg
{
	id obj;
	if(obj=[cfg objectForKey:@"XLDDSDOutput_DSDType"]) {
		[o_dsdType selectItemWithTag:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDDSDOutput_DSDFormat"]) {
		[o_dsdFormat selectItemWithTag:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDDSDOutput_DSMType"]) {
		[o_dsmType selectItemWithTag:[obj intValue]];
	}
}

@end
