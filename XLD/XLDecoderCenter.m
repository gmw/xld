//
//  XLDecoderCenter.m
//  XLD
//
//  Created by tmkk on 07/11/18.
//  Copyright 2007 tmkk. All rights reserved.
//

#import "XLDecoderCenter.h"
#import "XLDDecoder.h"
#import "XLDCDDARipper.h"

@implementation XLDecoderCenter

- (id)initWithPlugins:(NSArray *)bundleArr
{
	[super init];
	decoderArr = [[NSMutableArray alloc] init];
	
	int i;
	NSBundle *bundle = nil;
	
	for(i=0;i<[bundleArr count];i++) {
		bundle = [NSBundle bundleWithPath:[bundleArr objectAtIndex:i]];
		if(bundle) {
			if([bundle load]) {
				if([[bundle principalClass] conformsToProtocol:@protocol(XLDDecoder)] && [[bundle principalClass] canLoadThisBundle]) {
					//NSLog(@"%@",[bundle bundleIdentifier]);
					//decoder = [[[bundle principalClass] alloc] init];
					//[decoderArr addObject:decoder];
					//[decoder release];
					[decoderArr addObject:[bundle principalClass]];
				}
			}
		}
	}
	
	for(i=0;i<[decoderArr count];i++) {
		if([[[decoderArr objectAtIndex:i] description] isEqualToString:@"XLDApeDecoder"]) {
			[decoderArr addObject:[decoderArr objectAtIndex:i]];
			[decoderArr removeObjectAtIndex:i];
		}
#if 0
		if([[[decoderArr objectAtIndex:i] description] isEqualToString:@"XLDTakDecoder"]) {
			[decoderArr addObject:[decoderArr objectAtIndex:i]];
			[decoderArr removeObjectAtIndex:i];
		}
#endif
	}
	
	return self;
}

- (void)dealloc
{
	[decoderArr release];
	[super dealloc];
}

- (id)preferredDecoderForFile:(NSString *)file
{
	int i;
	if([file hasPrefix:@"/dev/disk"]) return [[[XLDCDDARipper alloc] init] autorelease];
	for(i=0;i<[decoderArr count];i++) {
		if([[decoderArr objectAtIndex:i] canHandleFile:(char *)[file UTF8String]]) {
			return [[[[decoderArr objectAtIndex:i] alloc] init] autorelease];
		}
	}
	return nil;
}

@end
