//
//  main.m
//  XLD @ sourceforge
//
//  Created by tmkk on 06/06/08.
//  Copyright tmkk 2006. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "XLDCustomClasses.h"
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_5
#import <objc/runtime.h>
#endif

extern int cmdline_main(int argc, char *argv[]);

int main(int argc, char *argv[])
{
	if(argc > 1 && !strncmp(argv[1],"--cmdline",9)) {
#if MAC_OS_X_VERSION_MAX_ALLOWED < MAC_OS_X_VERSION_10_5
		[XLDBundle poseAsClass:[NSBundle class]];
#else
		Method fromMethod = class_getInstanceMethod([NSBundle class],@selector(infoDictionary));
		Method toMethod   = class_getInstanceMethod([NSBundle class],@selector(mod_infoDictionary));
		method_exchangeImplementations(fromMethod, toMethod);
#endif
		return cmdline_main(argc,argv);
	}
    return NSApplicationMain(argc,  (const char **) argv);
}
