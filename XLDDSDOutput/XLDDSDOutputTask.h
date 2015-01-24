//
//  XLDDSDOutputTask.h
//  XLDDSDOutput
//
//  Created by tmkk on 15/01/24.
//  Copyright 2015 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <soxr.h>
#import "XLDOutputTask.h"
#import "deltasigma.h"

@interface XLDDSDOutputTask : NSObject <XLDOutputTask> {
	BOOL addTag;
	XLDFormat format;
	NSDictionary *configurations;
	soxr_t soxr;
	NSMutableData *tagData;
	int dsdSamplerate;
	int upRatio;
	FILE *fpw;
	uint64_t dsdSamples;
	DSDFileFormat dsdFormat;
	DSMNoiseShapingType dsmType;
	xld_deltasigma_t **dsm;
	int bufferSize;
	float *resampleBuffer;
	unsigned char *dsdBuffer;
	unsigned char **dsfWriteBuffer;
	int dsfBufferBytes;
	int dsfBlocksWritten;
}

- (id)initWithConfigurations:(NSDictionary *)cfg;

@end
