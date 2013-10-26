//
//  XLDCCDLoader.h
//  XLD
//
//  Created by tmkk on 13/10/11.
//  Copyright 2013 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface XLDCCDLoader : NSObject {
	NSString *pcmFile;
	NSMutableArray *trackList;
}
- (BOOL)openFile:(NSString *)ccdFile;
- (NSMutableArray *)trackList;
- (NSString *)pcmFile;
@end
