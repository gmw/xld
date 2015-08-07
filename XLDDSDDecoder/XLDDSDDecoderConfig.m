//
//  XLDDSDDecoderConfig.m
//  XLDDSDDecoder
//
//  Created by tmkk on 14/05/12.
//  Copyright 2014 tmkk. All rights reserved.
//

#import "XLDDSDDecoderConfig.h"


@implementation XLDDSDDecoderConfig

- (id)init
{
	[super init];
	NSDictionary *defaultValues = [NSDictionary dictionaryWithObjectsAndKeys:
								   [NSNumber numberWithInt:88200], @"XLDDSDDecoderSamplerate",
								   [NSNumber numberWithInt:4], @"XLDDSDDecoderSRCAlgorithm",
								   [NSNumber numberWithInt:0], @"XLDDSDDecoderQuantization",
								   [NSNumber numberWithInt:0], @"XLDDSDDecoderGain",nil];
	[[NSUserDefaultsController sharedUserDefaultsController] setInitialValues:defaultValues];
	[NSBundle loadNibNamed:@"XLDDSDDecoder" owner:self];
	[self statusChanged:nil];
	return self;
}

- (void)prefPane
{
	[o_prefPane makeKeyAndOrderFront:self];
}

- (IBAction)statusChanged:(id)sender
{
	if([[o_samplerate selectedItem] tag] > 0) {
		[o_srcAlgorithm setEnabled:YES];
		[o_text1 setTextColor:[NSColor blackColor]];
	}
	else {
		[o_srcAlgorithm setEnabled:NO];
		[o_text1 setTextColor:[NSColor lightGrayColor]];
	}
}

- (NSDictionary *)configurations
{
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
								   [pref objectForKey:@"XLDDSDDecoderSamplerate"], @"XLDDSDDecoderSamplerate",
								   [pref objectForKey:@"XLDDSDDecoderSRCAlgorithm"], @"XLDDSDDecoderSRCAlgorithm",
								   [pref objectForKey:@"XLDDSDDecoderQuantization"], @"XLDDSDDecoderQuantization",
								   [pref objectForKey:@"XLDDSDDecoderGain"], @"XLDDSDDecoderGain",nil];
	return dict;
}

- (void)loadConfigurations:(id)dict
{
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	[pref setObject:[dict objectForKey:@"XLDDSDDecoderSamplerate"] forKey:@"XLDDSDDecoderSamplerate"];
	[pref setObject:[dict objectForKey:@"XLDDSDDecoderSRCAlgorithm"] forKey:@"XLDDSDDecoderSRCAlgorithm"];
	[pref setObject:[dict objectForKey:@"XLDDSDDecoderQuantization"] forKey:@"XLDDSDDecoderQuantization"];
	[pref setObject:[dict objectForKey:@"XLDDSDDecoderGain"] forKey:@"XLDDSDDecoderGain"];
	[pref synchronize];
}

@end
