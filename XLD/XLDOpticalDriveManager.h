//
//  XLDOpticalDriveManager.h
//  XLD
//
//  Created by tmkk on 15/11/06.
//  Copyright 2015 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface XLDOpticalDriveManager : NSObject {
	id delegate;
}

- (id)initWithDelegate:(id)obj;
- (void)unmountDisc:(NSString *)dev;
- (void)unmountDiscAndNotify:(NSString *)dev;
- (void)mountDisc:(NSString *)dev;
- (void)ejectDisc:(NSString *)dev;
- (BOOL)isMounted:(NSString *)dev;

@end
