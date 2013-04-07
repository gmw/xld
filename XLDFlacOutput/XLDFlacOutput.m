//
//  XLDFlacOutput.m
//  XLDFlacOutput
//
//  Created by tmkk on 06/09/15.
//  Copyright 2006 tmkk. All rights reserved.
//

#import "XLDFlacOutput.h"
#import "XLDFlacOutputTask.h"

@implementation XLDFlacOutput

+ (NSString *)pluginName
{
	return @"FLAC";
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
	[NSBundle loadNibNamed:@"XLDFlacOutput" owner:self];
	srand(time(NULL));
	return self;
}

- (NSView *)prefPane
{
	return o_prefView;
}

- (void)savePrefs
{
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	[pref setInteger:[o_compressionLevel intValue] forKey:@"XLDFlacOutput_CompressionLevel"];
	[pref setInteger:[o_oggFlacCheckBox state] forKey:@"XLDFlacOutput_OggFLAC"];
	[pref setInteger:[o_padding intValue] forKey:@"XLDFlacOutput_Padding"];
	[pref setInteger:[o_allowEmbeddedCuesheet intValue] forKey:@"XLDFlacOutput_AllowEmbeddedCueSheet"];
	[pref setInteger:[o_setOggS intValue] forKey:@"XLDFlacOutput_SetOggS"];
	[pref setInteger:[o_useCustomApodization state] forKey:@"XLDFlacOutput_UseCustomApodization"];
	[pref setObject:[o_apodization stringValue] forKey:@"XLDFlacOutput_Apodization"];
	[pref setInteger:[o_writeRGTags state] forKey:@"XLDFlacOutput_WriteRGTags"];
	[pref synchronize];
}

- (void)loadPrefs
{
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	[self loadConfigurations:pref];
}

- (id)createTaskForOutput
{
	return [[XLDFlacOutputTask alloc] initWithConfigurations:[self configurations]];
}

- (id)createTaskForOutputWithConfigurations:(NSDictionary *)cfg
{
	return [[XLDFlacOutputTask alloc] initWithConfigurations:cfg];
}

- (int)compressionLevel
{
	return [o_compressionLevel intValue];
}

- (BOOL)oggFlac
{
	return [o_oggFlacCheckBox state] == NSOnState ? YES : NO;
}

- (int)padding
{
	if([o_padding intValue] < 1) return 1;
	return [o_padding intValue];
}

- (BOOL)allowEmbeddedCuesheet
{
	return ([o_allowEmbeddedCuesheet state] == NSOnState);
}

- (BOOL)setOggS
{
	return ([o_setOggS state] == NSOnState);
}

- (BOOL)writeRGTags
{
	return ([o_writeRGTags state] == NSOnState);
}

- (NSMutableDictionary *)configurations
{
	NSMutableDictionary *cfg = [[NSMutableDictionary alloc] init];
	/* for GUI */
	[cfg setObject:[NSNumber numberWithInt:[o_compressionLevel intValue]] forKey:@"XLDFlacOutput_CompressionLevel"];
	[cfg setObject:[NSNumber numberWithInt:[o_oggFlacCheckBox state]] forKey:@"XLDFlacOutput_OggFLAC"];
	[cfg setObject:[NSNumber numberWithInt:[o_padding intValue]] forKey:@"XLDFlacOutput_Padding"];
	[cfg setObject:[NSNumber numberWithInt:[o_allowEmbeddedCuesheet intValue]] forKey:@"XLDFlacOutput_AllowEmbeddedCueSheet"];
	[cfg setObject:[NSNumber numberWithInt:[o_setOggS intValue]] forKey:@"XLDFlacOutput_SetOggS"];
	[cfg setObject:[NSNumber numberWithInt:[o_useCustomApodization state]] forKey:@"XLDFlacOutput_UseCustomApodization"];
	[cfg setObject:[o_apodization stringValue] forKey:@"XLDFlacOutput_Apodization"];
	[cfg setObject:[NSNumber numberWithInt:[o_writeRGTags state]] forKey:@"XLDFlacOutput_WriteRGTags"];
	/* for task */
	[cfg setObject:[NSNumber numberWithInt:[self compressionLevel]] forKey:@"CompressionLevel"];
	[cfg setObject:[NSNumber numberWithBool:[self oggFlac]] forKey:@"OggFlac"];
	[cfg setObject:[NSNumber numberWithInt:[self padding]] forKey:@"Padding"];
	[cfg setObject:[NSNumber numberWithBool:[self allowEmbeddedCuesheet]] forKey:@"AllowEmbeddedCuesheet"];
	[cfg setObject:[NSNumber numberWithBool:[self setOggS]] forKey:@"SetOggS"];
	if([o_useCustomApodization state] == NSOnState) [cfg setObject:[o_apodization stringValue] forKey:@"Apodization"];
	[cfg setObject:[NSNumber numberWithBool:[self writeRGTags]] forKey:@"WriteRGTags"];
	/* desc */
	if([self oggFlac]) {
		if([self compressionLevel] >= 0) [cfg setObject:[NSString stringWithFormat:@"level %d, ogg wrapped",[self compressionLevel]] forKey:@"ShortDesc"];
		else  [cfg setObject:@"uncompressed, ogg wrapped" forKey:@"ShortDesc"];
	}
	else {
		if([self compressionLevel] >= 0) [cfg setObject:[NSString stringWithFormat:@"level %d",[self compressionLevel]] forKey:@"ShortDesc"];
		else  [cfg setObject:@"uncompressed" forKey:@"ShortDesc"];
	}
	return [cfg autorelease];
}

- (void)loadConfigurations:(id)cfg
{
	id obj;
	if(obj=[cfg objectForKey:@"XLDFlacOutput_CompressionLevel"]) {
		[o_compressionLevel setIntValue:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDFlacOutput_OggFLAC"]) {
		[o_oggFlacCheckBox setState:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDFlacOutput_Padding"]) {
		[o_padding setIntValue:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDFlacOutput_AllowEmbeddedCueSheet"]) {
		[o_allowEmbeddedCuesheet setIntValue:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDFlacOutput_SetOggS"]) {
		[o_setOggS setIntValue:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDFlacOutput_UseCustomApodization"]) {
		[o_useCustomApodization setState:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDFlacOutput_Apodization"]) {
		[o_apodization setStringValue:obj];
	}
	if(obj=[cfg objectForKey:@"XLDFlacOutput_WriteRGTags"]) {
		[o_writeRGTags setIntValue:[obj intValue]];
	}
	[self statusChanged:nil];
}

- (IBAction)statusChanged:(id)sender
{
	if([o_useCustomApodization state] == NSOnState) [o_apodization setEnabled:YES];
	else [o_apodization setEnabled:NO];
}

@end
