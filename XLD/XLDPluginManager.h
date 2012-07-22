//
//  XLDPluginManager.h
//  XLD
//
//  Created by tmkk on 11/08/18.
//  Copyright 2011 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface XLDPluginManager : NSObject {
	NSMutableArray *plugins;
}

- (NSArray *)plugins;

@end
