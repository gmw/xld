//
//  XLDDDPParser.h
//  XLD
//
//  Created by tmkk on 09/03/13.
//  Copyright 2009 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface XLDDDPParser : NSObject {
	int offsetBytes;
	NSString *dataFile;
	NSString *pqDescrFile;
}
- (int)offsetBytes;
- (int)getNumberInStr:(char *)str;
- (NSString *)pcmFile;
- (NSMutableArray *)trackListArray;
- (BOOL)openDDPMS:(NSString *)path;
@end
