//
//  XLDLMAXMLLoader.h
//  XLD
//
//  Created by tmkk on 13/07/03.
//  Copyright 2013 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface XLDLMAXMLLoader : NSObject {
	NSMutableArray *fileList;
	NSMutableArray *metadataList;
}

- (BOOL)openFile:(NSString *)xmlFile;
- (NSArray *)fileList;
- (NSArray *)metadataList;

@end
