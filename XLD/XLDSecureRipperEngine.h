//
//  XLDSecureRipperEngine.h
//  XLD
//
//  Created by tmkk on 10/11/13.
//  Copyright 2010 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "XLDCDDABackend.h"

typedef enum
{
	XLDSecureRipperNoErr = 0x0,
	XLDSecureRipperReadErr = 0x1,
	XLDSecureRipperJitterErr = 0x2,
	XLDSecureRipperRetry = 0x4,
	XLDSecureRipperDamaged = 0x8,
} XLDSecureRipperResult;


@interface XLDSecureRipperEngine : NSObject {
	xld_cdread_t *cdread;
	int currentLSN;
	int bufferedSectorBegin;
	int bufferedSectorSize;
	unsigned char *firstReadBufRaw;
	unsigned char *firstReadBuf;
	unsigned char *secondReadBuf;
	unsigned char *overlapBuffer;
	unsigned char *zeroSector;
	BOOL *verified;
	int maxRetryCount;
	BOOL jitterDetect;
	BOOL overlapBufferIsValid;
	XLDRipperMode ripperMode;
}

- (id)initWithReader:(xld_cdread_t *)reader;
- (void *)readSector:(XLDSecureRipperResult *)reuslt;
- (void)seekToSector:(int)sector;
- (void)setMaxRetryCount:(int)count;
- (void)setRipperMode:(XLDRipperMode)mode;

@end
