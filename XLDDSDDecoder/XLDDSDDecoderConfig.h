//
//  XLDDSDDecoderConfig.h
//  XLDDSDDecoder
//
//  Created by tmkk on 14/05/12.
//  Copyright 2014 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface XLDDSDDecoderConfig : NSObject {
	IBOutlet id o_prefPane;
	IBOutlet id o_samplerate;
	IBOutlet id o_srcAlgorithm;
	IBOutlet id o_gain;
	IBOutlet id o_text1;
}

- (IBAction)statusChanged:(id)sender;
- (NSDictionary *)configurations;

@end
