//
//  XLDSparkleUpdater.m
//  XLDSparkleUpdater
//
//  Created by tmkk on 08/09/06.
//  Copyright 2008 tmkk. All rights reserved.
//

#import "XLDSparkleUpdater.h"


@implementation XLDSparkleUpdater

+ (BOOL)canLoadThisBundle
{
	if (floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_3 ) {
		return NO;
	}
	else return YES;
}

- (id)init
{
	[super init];
	updater = [[SUUpdater alloc] init];
	return self;
}

- (void)dealloc
{
	[updater release];
	[super dealloc];
}

- (void)checkForUpdates:(id)sender
{
	[updater checkForUpdates:sender];
}

- (void)setAutomaticallyChecksForUpdates:(BOOL)automaticallyChecks
{
	[updater setAutomaticallyChecksForUpdates:automaticallyChecks];
}

@end
