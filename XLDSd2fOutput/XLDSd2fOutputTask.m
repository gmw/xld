//
//  XLDSd2fOutputTask.m
//  XLD
//
//  Created by tmkk on 13/02/11.
//  Copyright 2013 tmkk. All rights reserved.
//

typedef int64_t xldoffset_t;

#import "XLDSd2fOutputTask.h"
#import "XLDSd2fOutput.h"
#import "XLDTrack.h"

@implementation XLDSd2fOutputTask

- (id)init
{
	[super init];
	memset(&sfinfo,0,sizeof(SF_INFO));
	addTag = YES;
	regionData = [[NSMutableData alloc] init];
	return self;
}

- (id)initWithConfigurations:(NSDictionary *)cfg
{
	[self init];
	configurations = [cfg retain];
	sfinfo.format = [[configurations objectForKey:@"SFFormat"] unsignedIntValue];
	return self;
}

- (void)dealloc
{
	if(sf_w) sf_close(sf_w);
	if(path) [path release];
	if(configurations) [configurations release];
	[regionData release];
	[super dealloc];
}

- (BOOL)setOutputFormat:(XLDFormat)fmt
{
	outFormat = fmt;
	sfinfo.samplerate = fmt.samplerate;
	sfinfo.channels = fmt.channels;
	
	/* BitDepth == 0 if same as original */
	int bps = [[configurations objectForKey:@"BitDepth"] intValue] ? [[configurations objectForKey:@"BitDepth"] intValue] : fmt.bps;
	outFormat.bps = bps;
	
	switch(bps) {
		case 1:
			sfinfo.format |= SF_FORMAT_PCM_S8;
			break;
		case 2:
			sfinfo.format |= SF_FORMAT_PCM_16;
			break;
		case 3:
			sfinfo.format |= SF_FORMAT_PCM_24;
			break;
		default:
			return NO;
	}
	
	return YES;
}

- (BOOL)openFileForOutput:(NSString *)str withTrackData:(id)track
{
	sf_w = sf_open([str UTF8String], SFM_WRITE, &sfinfo);
	if(!sf_w) {
		return NO;
	}
	if(sf_error(sf_w)) {
		return NO;
	}
	sf_command(sf_w, SFC_SET_SCALE_INT_FLOAT_WRITE, NULL, SF_TRUE) ;
	path = [str retain];
	
	[regionData setLength:0];
	
	if([[track metadata] objectForKey:XLD_METADATA_TRACKLIST] && [[track metadata] objectForKey:XLD_METADATA_TOTALSAMPLES]) {
		int tmp, i;
		short tmp2;
		char tmp3;
		NSArray *trackList = [[track metadata] objectForKey:XLD_METADATA_TRACKLIST];
		
		/* version */
		tmp2 = NSSwapHostShortToBig(1);
		[regionData appendBytes:&tmp2 length:2];
		/* header size */
		tmp = NSSwapHostIntToBig(0xc);
		[regionData appendBytes:&tmp length:4];
		/* region size */
		tmp = NSSwapHostIntToBig(0x38);
		[regionData appendBytes:&tmp length:4];
		/* timestamp */
		tmp = NSSwapHostIntToBig([[NSDate date] timeIntervalSince1970] + 2082844800);
		[regionData appendBytes:&tmp length:4];
		/* next region number */
		tmp = NSSwapHostIntToBig([trackList count]);
		[regionData appendBytes:&tmp length:4];
		
		for(i=0;i<[trackList count];i++) {
			XLDTrack *currentTrack = [trackList objectAtIndex:i];
			/* region number */
			tmp = NSSwapHostIntToBig(i+1);
			[regionData appendBytes:&tmp length:4];
			/* region start */
			tmp = NSSwapHostIntToBig([currentTrack index]);
			[regionData appendBytes:&tmp length:4];
			/* region end */
			if(i==[trackList count]-1) {
				tmp = [[[track metadata] objectForKey:XLD_METADATA_TOTALSAMPLES] unsignedIntValue];
			}
			else tmp = [(XLDTrack *)[trackList objectAtIndex:i+1] index];
			tmp = NSSwapHostIntToBig(tmp);
			[regionData appendBytes:&tmp length:4];
			/* region absolute start */
			tmp = NSSwapHostIntToBig([(XLDTrack *)[trackList objectAtIndex:i] index]);
			[regionData appendBytes:&tmp length:4];
			/* timestamp */
			tmp = 0;
			[regionData appendBytes:&tmp length:4];
			[regionData appendBytes:&tmp length:4];
			/* track name length */
			tmp3 = 8;
			[regionData appendBytes:&tmp3 length:1];
			/* track name*/
			char title[32];
			sprintf(title,"Track %02d",i+1);
			[regionData appendBytes:title length:8];
			/* padding */
			[regionData increaseLengthBy:23];
		}
	}
	
	return YES;
}

- (NSString *)extensionStr
{
	return @"Sd2f";
}

- (BOOL)writeBuffer:(int *)buffer frames:(int)counts
{
	sf_writef_int(sf_w,buffer,counts);
	
	if(sf_error(sf_w)) {
		return NO;
	}
	return YES;
}

- (void)finalize
{
	FSRef fsRef;
	OSErr err;
	if(sf_w) sf_close(sf_w);
	sf_w = NULL;

	if(!FSPathMakeRef((UInt8*)[path fileSystemRepresentation], &fsRef, NULL)) {
		ResFileRefNum resourceRef;
		HFSUniStr255 resourceForkName;
		UniCharCount forkNameLength;
		UniChar *forkName;
		Handle rsrc;
		err = FSGetResourceForkName(&resourceForkName);
		if(err) goto last;
		forkNameLength = resourceForkName.length;
		forkName = resourceForkName.unicode;
		err = FSCreateResourceFork(&fsRef, forkNameLength, forkName, 0);
		if(err) goto last;
		err = FSOpenResourceFile(&fsRef, forkNameLength, forkName, (SInt8)fsRdWrPerm, &resourceRef);
		if(err) goto last;
		UseResFile(resourceRef);
		
		/* STR resource */
		char buf[32];
		buf[0] = 1;
		buf[1] = '0' + outFormat.bps;
		rsrc = NewHandle(2);
		memcpy(*rsrc,buf,2);
		AddResource(rsrc, 'STR ', 1000, "\psample-size");
		sprintf(buf+1,"%d",outFormat.samplerate);
		buf[0] = strlen(buf+1);
		rsrc = NewHandle(buf[0]+1);
		memcpy(*rsrc,buf,buf[0]+1);
		AddResource(rsrc, 'STR ', 1001, "\psample-rate");
		buf[0] = 1;
		buf[1] = '0' + outFormat.channels;
		rsrc = NewHandle(2);
		memcpy(*rsrc,buf,2);
		AddResource(rsrc, 'STR ', 1002, "\pchannels");
		
		/* sdML resource */
		rsrc = NewHandleClear(8);
		*((char*)*rsrc+1) = 1;
		AddResource(rsrc, 'sdML', 1000, "\p");
		
		/*ddRL resource */
		if(regionData && [regionData length]) {
			Handle rsrc = NewHandle([regionData length]);
			[regionData getBytes:*rsrc length:[regionData length]];
			AddResource(rsrc, 'ddRL', 1000, "\p");
		}
		CloseResFile(resourceRef);
		
		FSCatalogInfoBitmap	myInfoWanted = kFSCatInfoFinderInfo;
		FSCatalogInfo		myInfoReceived;
		FSGetCatalogInfo(&fsRef, myInfoWanted, &myInfoReceived, NULL, NULL, NULL);
		((FileInfo *)&myInfoReceived.finderInfo)->fileType = 'Sd2f';
		FSSetCatalogInfo(&fsRef, myInfoWanted, &myInfoReceived);
	}
last:
	return;
}

- (void)closeFile
{
	if(sf_w) sf_close(sf_w);
	sf_w = NULL;
	if(path) [path release];
	path = NULL;
	[regionData release];
	regionData = nil;
}

- (void)setEnableAddTag:(BOOL)flag
{
	addTag = flag;
}

@end
