//
//  XLDMetadataTextParser.m
//  XLD
//
//  Created by tmkk on 10/09/07.
//  Copyright 2010 tmkk. All rights reserved.
//

#import "XLDMetadataTextParser.h"

@implementation XLDMetadataTextParser

- (id)initWithFormatString:(NSString *)format
{
	[super init];
	acceptedFormats = [[NSArray alloc] initWithObjects:@"%n",@"%N",@"%d",@"%D",@"%t",@"%T",@"%a",@"%A",@"%g",@"%G",@"%y",@"%c",@"%C",@"%o",nil];
	formatArray = [[NSMutableArray alloc] init];
	int index = 0;
	while([format length]) {
		NSString *tmp = [format substringWithRange:NSMakeRange(index,2)];
		if([acceptedFormats indexOfObject:tmp] != NSNotFound) {
			if(index) [formatArray addObject:[format substringWithRange:NSMakeRange(0,index)]];
			[formatArray addObject:tmp];
			format = [format substringFromIndex:index+2];
			index = 0;
			continue;
		}
		index++;
	}
	if(index) [formatArray addObject:[format substringWithRange:NSMakeRange(0,index)]];
	return self;
}

- (void)dealloc
{
	[acceptedFormats release];
	[formatArray release];
	[super dealloc];
}

- (NSMutableDictionary *)parse:(NSString *)str
{
	NSMutableDictionary *dic = [[NSMutableDictionary alloc] init];
	int formatIdx;
	for(formatIdx=0;[str length] && formatIdx < [formatArray count];formatIdx++) {
		NSString *key = [formatArray objectAtIndex:formatIdx];
		if([acceptedFormats indexOfObject:key] != NSNotFound) {
			NSString *read;
			if(formatIdx==[formatArray count]-1) {
				read = str;
			}
			else {
				NSRange range = [str rangeOfString:[formatArray objectAtIndex:formatIdx+1]];
				if(range.location == NSNotFound) read = str;
				else read = [str substringToIndex:range.location];
			}
			if(![read length]) {
				continue;
			}
			if([key isEqualToString:@"%n"]) {
				int num = [read intValue];
				if(num > 0) {
					[dic setObject:[NSNumber numberWithInt:num] forKey:XLD_METADATA_TRACK];
				}
			}
			else if([key isEqualToString:@"%N"]) {
				int num = [read intValue];
				if(num > 0) {
					[dic setObject:[NSNumber numberWithInt:num] forKey:XLD_METADATA_TOTALTRACKS];
				}
			}
			else if([key isEqualToString:@"%d"]) {
				int num = [read intValue];
				if(num > 0) {
					[dic setObject:[NSNumber numberWithInt:num] forKey:XLD_METADATA_DISC];
				}
			}
			else if([key isEqualToString:@"%D"]) {
				int num = [read intValue];
				if(num > 0) {
					[dic setObject:[NSNumber numberWithInt:num] forKey:XLD_METADATA_TOTALDISCS];
				}
			}
			else if([key isEqualToString:@"%y"]) {
				int num = [read intValue];
				if(num > 0) {
					[dic setObject:[NSNumber numberWithInt:num] forKey:XLD_METADATA_YEAR];
					[dic setObject:read forKey:XLD_METADATA_DATE];
				}
			}
			else if([key isEqualToString:@"%t"]) {
				[dic setObject:read forKey:XLD_METADATA_TITLE];
			}
			else if([key isEqualToString:@"%T"]) {
				[dic setObject:read forKey:XLD_METADATA_ALBUM];
			}
			else if([key isEqualToString:@"%a"]) {
				[dic setObject:read forKey:XLD_METADATA_ARTIST];
			}
			else if([key isEqualToString:@"%A"]) {
				[dic setObject:read forKey:XLD_METADATA_ALBUMARTIST];
			}
			else if([key isEqualToString:@"%g"]) {
				[dic setObject:read forKey:XLD_METADATA_GENRE];
			}
			else if([key isEqualToString:@"%G"]) {
				[dic setObject:read forKey:XLD_METADATA_GROUP];
			}
			else if([key isEqualToString:@"%c"]) {
				[dic setObject:read forKey:XLD_METADATA_COMPOSER];
			}
			else if([key isEqualToString:@"%C"]) {
				[dic setObject:read forKey:XLD_METADATA_COMMENT];
			}
			else if([key isEqualToString:@"%o"]) {
				[dic setObject:read forKey:XLD_METADATA_ORIGINALFILENAME];
			}
			str = [str substringFromIndex:[read length]];
		}
		else {
			NSRange range = [str rangeOfString:key];
			if(range.location != 0) break;
			str = [str substringFromIndex:range.length];
		}
	}
	return [dic autorelease];
}

@end

