//
//  XLDWavOutput.h
//  XLD
//
//  Created by tmkk on 10/11/03.
//  Copyright 2010 tmkk. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "XLDDefaultOutput.h"

@interface XLDWavOutput : XLDDefaultOutput <XLDOutput> {
	IBOutlet id o_addTags;
	IBOutlet id o_tagFormat;
	IBOutlet id o_tagEncoding;
	IBOutlet id o_text1;
	IBOutlet id o_text2;
	IBOutlet id o_text3;
}

@end
