//
//  XLDLogChecker.h
//  XLDLogChecker
//
//  Created by tmkk on 12/10/27.
//  Copyright 2012 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>

typedef enum
{
	XLDLogCheckerOK = 0,
	XLDLogCheckerSignatureNotFound = -1,
	XLDLogCheckerNotLogFile = -2,
	XLDLogCheckerUnknownVersion = -3,
	XLDLogCheckerInvalidHash = -4,
	XLDLogCheckerMalformed = -5,
} XLDLogCheckerResult;

@interface XLDLogChecker : NSObject {
	NSString *msg;
}

+ (void)appendSignature:(NSMutableString *)str;
- (void)logChecker;
- (XLDLogCheckerResult)validateData:(NSData *)dat;

@end
