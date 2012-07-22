//
//  XLDTrackProducer.h
//  XLD
//
//  Created by tmkk on 11/05/07.
//  Copyright 2011 tmkk. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "XLDMultipleFileWrappedDecoder.h"

@interface XLDTrackProducer : NSObject {
	id delegate;
	unsigned int decodeBufferSize;
	unsigned int verifyBufferSize;
	int *decodeBuffer;
	char *verifyBuffer;
	XLDMultipleFileWrappedDecoder *decoder;
	int ignoredBytesAtTheBeginning;
	int ignoredBytesAtTheEnd;
	int trackNumber;
	xldoffset_t trackIndex;
	xldoffset_t trackLength;
	int gapLength;
	FILE *fp,*fp2;
	uint64_t written;
	uint64_t gapWritten;
	uint64_t verified;
	uint64_t gapVerified;
	unsigned int difference;
}
- (id)initWithDelegate:(id)del;
@end
