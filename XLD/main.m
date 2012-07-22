//
//  main.m
//  XLD
//
//  Created by tmkk on 06/06/08.
//  Copyright tmkk 2006. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "XLDCustomClasses.h"

extern int cmdline_main(int argc, char *argv[]);

int main(int argc, char *argv[])
{
	if(argc > 1 && !strncmp(argv[1],"--cmdline",9)) {
		[XLDBundle poseAsClass:[NSBundle class]];
		return cmdline_main(argc,argv);
	}
    return NSApplicationMain(argc,  (const char **) argv);
}
