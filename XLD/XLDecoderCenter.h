//
//  XLDecoderCenter.h
//  XLD
//
//  Created by tmkk on 07/11/18.
//  Copyright 2007 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface XLDecoderCenter : NSObject {
	NSMutableArray *decoderArr;
}

- (id)initWithPlugins:(NSArray *)bundleArr;
- (id)preferredDecoderForFile:(NSString *)file;

@end
