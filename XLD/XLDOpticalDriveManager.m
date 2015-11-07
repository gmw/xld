//
//  XLDOpticalDriveManager.m
//  XLD
//
//  Created by tmkk on 15/11/06.
//  Copyright 2015 tmkk. All rights reserved.
//

#import <DiskArbitration/DiskArbitration.h>
#include <sys/param.h>
#include <sys/ucred.h>
#include <sys/mount.h>
#import "XLDOpticalDriveManager.h"

static void DADoneCallback(DADiskRef DiskRef, DADissenterRef DissenterRef, void *context) 
{
	//NSLog(@"done");
    CFRunLoopStop(CFRunLoopGetCurrent());
}

@implementation XLDOpticalDriveManager

- (id)init
{
	self = [super init];
	if(!self) return nil;
	
	return self;
}

- (id)initWithDelegate:(id)obj
{
	self = [self init];
	if(!self) return nil;
	
	delegate = [obj retain];
	return self;
}

- (void)dealloc
{
	[delegate release];
	[super dealloc];
}

- (void)unmountDisc:(NSString *)dev
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	DASessionRef session = DASessionCreate(NULL);
	DASessionScheduleWithRunLoop(session, CFRunLoopGetCurrent(), MY_RUN_LOOP_MODE);
	DADiskRef disk = DADiskCreateFromBSDName(NULL,session,[dev UTF8String]);
	DADiskUnmount(disk,kDADiskUnmountOptionDefault,DADoneCallback,NULL);
	int ret = CFRunLoopRunInMode(MY_RUN_LOOP_MODE, 120.0, false);
	if (ret == kCFRunLoopRunStopped) {
		DASessionUnscheduleFromRunLoop(session, CFRunLoopGetCurrent(), MY_RUN_LOOP_MODE);
	}
	CFRelease(disk);
	CFRelease(session);
	
	[pool release];
}

- (void)unmountDiscAndNotify:(NSString *)dev
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	DASessionRef session = DASessionCreate(NULL);
	DASessionScheduleWithRunLoop(session, CFRunLoopGetCurrent(), MY_RUN_LOOP_MODE);
	DADiskRef disk = DADiskCreateFromBSDName(NULL,session,[dev UTF8String]);
	DADiskUnmount(disk,kDADiskUnmountOptionDefault,DADoneCallback,NULL);
	int ret = CFRunLoopRunInMode(MY_RUN_LOOP_MODE, 120.0, false);
	if (ret == kCFRunLoopRunStopped) {
		DASessionUnscheduleFromRunLoop(session, CFRunLoopGetCurrent(), MY_RUN_LOOP_MODE);
	}
	CFRelease(disk);
	CFRelease(session);
	
	SEL selector = @selector(unmountCompletedForDevice:);
	if([delegate respondsToSelector:selector]) {
		[delegate performSelectorOnMainThread:selector withObject:dev waitUntilDone:NO];
	}
	
	[pool release];
}

- (void)mountDisc:(NSString *)dev
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[dev retain];
	
	DASessionRef session = DASessionCreate(NULL);
	DADiskRef disk = DADiskCreateFromBSDName(NULL,session,[dev UTF8String]);
	DADiskMount(disk,NULL,kDADiskMountOptionDefault,NULL,NULL);
	CFRelease(disk);
	CFRelease(session);
	
	[dev release];
	[pool release];
}

- (void)ejectDisc:(NSString *)dev
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[dev retain];
	
	DASessionRef session = DASessionCreate(NULL);
	DADiskRef disk = DADiskCreateFromBSDName(NULL,session,[dev UTF8String]);
	DADiskUnmount(disk,kDADiskUnmountOptionWhole,NULL,NULL);
	DADiskEject(disk,kDADiskEjectOptionDefault,NULL,NULL);
	CFRelease(disk);
	CFRelease(session);
	
	[dev release];
	[pool release];
}

- (BOOL)isMounted:(NSString *)dev
{
	BOOL ret = NO;
	struct statfs *mountedDisks = malloc(sizeof(struct statfs) * 256);
	int numVolumes = getfsstat(mountedDisks, sizeof(struct statfs) * 256, MNT_NOWAIT);
	int i;
	const char *device = [dev UTF8String];
	for(i=0;i<numVolumes;i++) {
		if(!strcmp(mountedDisks[i].f_mntfromname, device)) {
			ret = YES;
			break;
		}
	}
	free(mountedDisks);
	return ret;
}

@end
