//
//  XLDMetadataTextParser.h
//  XLD
//
//  Created by tmkk on 10/09/07.
//  Copyright 2010 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface XLDMetadataTextParser: NSObject {
	NSArray *acceptedFormats;
	NSMutableArray *formatArray;
}
- (id)initWithFormatString:(NSString *)format;
- (NSMutableDictionary *)parse:(NSString *)str;
@end

