//
//  XLDSparkleUpdater.h
//  XLDSparkleUpdater
//
//  Created by tmkk on 08/09/06.
//  Copyright 2008 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <Sparkle/SUUpdater.h>

@interface XLDSparkleUpdater : NSObject {
	SUUpdater *updater;
}

+ (BOOL)canLoadThisBundle;
- (void)checkForUpdates:(id)sender;
- (void)setAutomaticallyChecksForUpdates:(BOOL)automaticallyChecks;

@end
