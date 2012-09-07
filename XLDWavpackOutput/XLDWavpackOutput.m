#import "XLDWavpackOutput.h"
#import "XLDWavpackOutputTask.h"

@implementation XLDWavpackOutput

+ (NSString *)pluginName
{
	return @"WavPack";
}

+ (BOOL)canLoadThisBundle
{
	return YES;
}

- (id)init
{
	[super init];
	[NSBundle loadNibNamed:@"XLDWavpackOutput" owner:self];
	return self;
}

- (NSView *)prefPane
{
	return o_prefView;
}

- (void)savePrefs
{
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	[pref setInteger:[o_bitrate intValue] forKey:@"XLDWavpackOutput_BitRate"];
	[pref setInteger:[o_mode indexOfSelectedItem] forKey:@"XLDWavpackOutput_Mode"];
	[pref setInteger:[o_quality indexOfSelectedItem] forKey:@"XLDWavpackOutput_Quality"];
	[pref setInteger:[o_createCorrectionFile state] forKey:@"XLDWavpackOutput_CreateCorrectionFile"];
	[pref setInteger:[o_extraCompression state] forKey:@"XLDWavpackOutput_ExtraCompression"];
	[pref setInteger:[o_extraValue intValue] forKey:@"XLDWavpackOutput_ExtraValue"];
	[pref setInteger:[o_dns state] forKey:@"XLDWavpackOutput_DNS"];
	[pref setInteger:[o_allowEmbeddedCuesheet intValue] forKey:@"XLDWavpackOutput_AllowEmbeddedCueSheet"];
	[pref synchronize];
}

- (void)loadPrefs
{
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	[self loadConfigurations:pref];
}

- (id)createTaskForOutput
{
	return [[XLDWavpackOutputTask alloc] initWithConfigurations:[self configurations]];
}

- (id)createTaskForOutputWithConfigurations:(NSDictionary *)cfg
{
	return [[XLDWavpackOutputTask alloc] initWithConfigurations:cfg];
}

- (IBAction)modeChanged:(id)sender
{
	NSBundle *bundle = [NSBundle bundleForClass:[self class]];
	if([o_mode indexOfSelectedItem] == 0) {
		[o_bitrate setEnabled:NO];
		[o_createCorrectionFile setEnabled:NO];
		[o_dns setEnabled:NO];
		[o_text1 setTextColor:[NSColor grayColor]];
		[o_text2 setTextColor:[NSColor grayColor]];
		[o_text3 setStringValue:[bundle localizedStringForKey:@"Compresion Ratio" value:nil table:nil]];
	}
	else {
		[o_bitrate setEnabled:YES];
		[o_createCorrectionFile setEnabled:YES];
		[o_dns setEnabled:YES];
		[o_text1 setTextColor:[NSColor blackColor]];
		[o_text2 setTextColor:[NSColor blackColor]];
		[o_text3 setStringValue:[bundle localizedStringForKey:@"Quality" value:nil table:nil]];
	}
}

- (IBAction)extraChecked:(id)sender
{
	if([o_extraCompression state] == NSOnState) {
		[o_extraValue setEnabled:YES];
		[o_text4 setTextColor:[NSColor blackColor]];
		[o_text5 setTextColor:[NSColor blackColor]];
	}
	else {
		[o_extraValue setEnabled:NO];
		[o_text4 setTextColor:[NSColor grayColor]];
		[o_text5 setTextColor:[NSColor grayColor]];
	}
}

- (BOOL)createCorrectionFile
{
	return ([o_createCorrectionFile state] == NSOnState) ? YES : NO;
}

- (BOOL)extraCompression
{
	return ([o_extraCompression state] == NSOnState) ? YES : NO;
}

- (BOOL)dynamicNoiseShaping
{
	return ([o_dns state] == NSOnState) ? YES : NO;
}

- (int)mode
{
	return [o_mode indexOfSelectedItem];
}

- (int)quality
{
	return [o_quality indexOfSelectedItem];
}

- (int)bitrate
{
	return [o_bitrate intValue];
}

- (int)extraValue
{
	return [o_extraValue intValue];
}

- (BOOL)allowEmbeddedCuesheet
{
	return ([o_allowEmbeddedCuesheet state] == NSOnState);
}

- (NSMutableDictionary *)configurations
{
	NSMutableDictionary *cfg = [[NSMutableDictionary alloc] init];
	/* for GUI */
	[cfg setObject:[NSNumber numberWithInt:[o_bitrate intValue]] forKey:@"XLDWavpackOutput_BitRate"];
	[cfg setObject:[NSNumber numberWithInt:[o_mode indexOfSelectedItem]] forKey:@"XLDWavpackOutput_Mode"];
	[cfg setObject:[NSNumber numberWithInt:[o_quality indexOfSelectedItem]] forKey:@"XLDWavpackOutput_Quality"];
	[cfg setObject:[NSNumber numberWithInt:[o_createCorrectionFile state]] forKey:@"XLDWavpackOutput_CreateCorrectionFile"];
	[cfg setObject:[NSNumber numberWithInt:[o_extraCompression state]] forKey:@"XLDWavpackOutput_ExtraCompression"];
	[cfg setObject:[NSNumber numberWithInt:[o_extraValue intValue]] forKey:@"XLDWavpackOutput_ExtraValue"];
	[cfg setObject:[NSNumber numberWithInt:[o_dns state]] forKey:@"XLDWavpackOutput_DNS"];
	[cfg setObject:[NSNumber numberWithInt:[o_allowEmbeddedCuesheet intValue]] forKey:@"XLDWavpackOutput_AllowEmbeddedCueSheet"];
	/* for task */
	[cfg setObject:[NSNumber numberWithBool:[self createCorrectionFile]] forKey:@"CreateCorrectionFile"];
	[cfg setObject:[NSNumber numberWithBool:[self extraCompression]] forKey:@"ExtraCompression"];
	[cfg setObject:[NSNumber numberWithBool:[self dynamicNoiseShaping]] forKey:@"DynamicNoiseShaping"];
	[cfg setObject:[NSNumber numberWithInt:[self mode]] forKey:@"Mode"];
	[cfg setObject:[NSNumber numberWithInt:[self quality]] forKey:@"Quality"];
	[cfg setObject:[NSNumber numberWithInt:[self bitrate]] forKey:@"Bitrate"];
	[cfg setObject:[NSNumber numberWithInt:[self extraValue]] forKey:@"ExtraValue"];
	[cfg setObject:[NSNumber numberWithBool:[self allowEmbeddedCuesheet]] forKey:@"AllowEmbeddedCuesheet"];
	/* desc */
	if([self mode]) {
		NSString *modeStr;
		if([self quality] == 0) modeStr = @"lossy, fast quality";
		else if([self quality] == 1) modeStr = @"lossy, normal quality";
		else if([self quality] == 2) modeStr = @"lossy, high quality";
		else if([self quality] == 3) modeStr = @"lossy, max quality";
		if([self extraCompression])
			[cfg setObject:[NSString stringWithFormat:@"%@, %dkbps, extra %d",modeStr,[self bitrate],[self extraValue]] forKey:@"ShortDesc"];
		else
			[cfg setObject:[NSString stringWithFormat:@"%@, %dkbps",modeStr,[self bitrate]] forKey:@"ShortDesc"];
	}
	else {
		NSString *modeStr;
		if([self quality] == 0) modeStr = @"fast";
		else if([self quality] == 1) modeStr = @"normal";
		else if([self quality] == 2) modeStr = @"high";
		else if([self quality] == 3) modeStr = @"max";
		if([self extraCompression])
			[cfg setObject:[NSString stringWithFormat:@"%@, extra %d",modeStr,[self extraValue]] forKey:@"ShortDesc"];
		else
			[cfg setObject:modeStr forKey:@"ShortDesc"];
	}
	return [cfg autorelease];
}

- (void)loadConfigurations:(id)cfg
{
	id obj;
	if(obj=[cfg objectForKey:@"XLDWavpackOutput_BitRate"]) {
		[o_bitrate setIntValue:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDWavpackOutput_Mode"]) {
		int i = [obj intValue];
		if(i < [o_mode numberOfItems]) {
			[o_mode selectItemAtIndex:i];
		}
	}
	if(obj=[cfg objectForKey:@"XLDWavpackOutput_Quality"]) {
		int i = [obj intValue];
		if(i < [o_quality numberOfItems]) {
			[o_quality selectItemAtIndex:i];
		}
	}
	if(obj=[cfg objectForKey:@"XLDWavpackOutput_CreateCorrectionFile"]) {
		[o_createCorrectionFile setState:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDWavpackOutput_ExtraCompression"]) {
		[o_extraCompression setState:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDWavpackOutput_ExtraValue"]) {
		[o_extraValue setIntValue:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDWavpackOutput_DNS"]) {
		[o_dns setState:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDWavpackOutput_AllowEmbeddedCueSheet"]) {
		[o_allowEmbeddedCuesheet setIntValue:[obj intValue]];
	}
	[self modeChanged:nil];
	[self extraChecked:nil];
}

@end
