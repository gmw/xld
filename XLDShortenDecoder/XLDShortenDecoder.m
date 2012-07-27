//
//  XLDShortenDecoder.m
//  XLDShortenDecoder
//
//  Created by tmkk on 09/11/23.
//  Copyright 2009 tmkk. All rights reserved.
//

#import "XLDShortenDecoder.h"

@implementation XLDShortenDecoder

+ (BOOL)canHandleFile:(char *)path
{
	shn_config cfg;
	cfg.error_output_method = ERROR_OUTPUT_DEVNULL;
	cfg.seek_tables_path = NULL;
	cfg.relative_seek_tables_path = NULL;
	cfg.verbose = 0;
	cfg.swap_bytes = 0;
	shn_file *sf = shn_load(path, cfg);
	if(!sf) return NO;
	if(!shn_seekable(sf)) {
		shn_unload(sf);
		return NO;
	}
	shn_unload(sf);
	return YES;
}

+ (BOOL)canLoadThisBundle
{
	return YES;
}

- (id)init
{
	[super init];
	shn = NULL;
	error = NO;
	srcPath = nil;
	tmpBuf = (unsigned char *)malloc(OUT_BUFFER_SIZE);
	return self;
}

- (BOOL)openFile:(char *)path
{
	shn_config cfg;
	cfg.error_output_method = ERROR_OUTPUT_DEVNULL;
	cfg.seek_tables_path = NULL;
	cfg.relative_seek_tables_path = NULL;
	cfg.verbose = 0;
#ifdef _BIG_ENDIAN
	cfg.swap_bytes = 1;
#else
	cfg.swap_bytes = 0;
#endif
	shn = shn_load(path, cfg);
	if(!shn) {
		error = YES;
		return NO;
	}
	
	totalFrames = shn_get_frame_length(shn);
	channels = shn_get_channels(shn);
	samplerate = shn_get_samplerate(shn);
	bps = shn_get_bitspersample(shn)/8;
	if(shn_seekable(shn)) seekable = YES;
	else seekable = NO;
	
	if(srcPath) [srcPath release];
	srcPath = [[NSString alloc] initWithUTF8String:path];
	
	shn_init_decoder(shn);
	
	return YES;
}

- (void)dealloc
{
	if(shn) {
		shn_cleanup_decoder(shn);
		shn_unload(shn);
	}
	if(srcPath) [srcPath release];
	if(tmpBuf) free(tmpBuf);
	[super dealloc];
}

- (int)samplerate
{
	return samplerate;
}

- (int)bytesPerSample
{
	return bps;
}

- (int)channels
{
	return channels;
}

- (xldoffset_t)totalFrames
{
	return totalFrames;
}

- (int)isFloat
{
	return 0;
}

- (int)decodeToBuffer:(int *)buffer frames:(int)count
{
	int i,j,bytesOut=0;
	unsigned int bytesToRead = count*channels*bps;

	if(bytesToRead > OUT_BUFFER_SIZE) {
		int request = OUT_BUFFER_SIZE;
		j=0;
		for(;bytesToRead;bytesToRead-=request) {
			if(bytesToRead < request) request = bytesToRead;
			int ret = shn_read(shn, tmpBuf, request);
			for(i=0;i<ret;i+=bps,j++) {
				switch(bps) {
					case 1:
						buffer[j] = (tmpBuf[i]+0x80) << 24;
						break;
					case 2:
						buffer[j] = (*(short *)(tmpBuf+i)) << 16;
						break;
					case 3:
#ifdef _BIG_ENDIAN
						buffer[j] = ((tmpBuf[i] << 16) | (tmpBuf[i+1] << 8) | tmpBuf[i+2])<<8;
#else
						buffer[j] = (tmpBuf[i] | (tmpBuf[i+1] << 8) | (tmpBuf[i+2] << 16))<<8;
#endif
						break;
					case 4:
						buffer[j] = *(int *)(tmpBuf+i);
						break;
				}
			}
			bytesOut += ret;
			if(ret < request) break;
		}
	}
	else {
		bytesOut = shn_read(shn, tmpBuf, bytesToRead);
		for(i=0,j=0;i<bytesOut;i+=bps,j++) {
			switch(bps) {
				case 1:
					buffer[j] = (tmpBuf[i]+0x80) << 24;
					break;
				case 2:
					buffer[j] = (*(short *)(tmpBuf+i)) << 16;
					break;
#ifdef _BIG_ENDIAN
					buffer[j] = ((tmpBuf[i] << 16) | (tmpBuf[i+1] << 8) | tmpBuf[i+2])<<8;
#else
					buffer[j] = (tmpBuf[i] | (tmpBuf[i+1] << 8) | (tmpBuf[i+2] << 16))<<8;
#endif
					break;
				case 4:
					buffer[j] = *(int *)(tmpBuf+i);
					break;
			}
		}
	}
	return bytesOut/channels/bps;
}

- (xldoffset_t)seekToFrame:(xldoffset_t)count
{
	if(!seekable) return 0;
	//NSLog(@"seek request:%lld",count);
	int ret = shn_seek(shn,(int)count);
	if(ret < 0) {
		error = YES;
		return 0;
	}
	//NSLog(@"seek actual:%d",ret);
	if(count-ret) {
		int bytesToRead = (count-ret)*channels*bps;
		int request = OUT_BUFFER_SIZE;
		for(;bytesToRead;bytesToRead-=request) {
			if(bytesToRead < request) request = bytesToRead;
			shn_read(shn, tmpBuf, request);
		}
	}
	return count;
}

- (void)closeFile
{
	if(shn) {
		shn_cleanup_decoder(shn);
		shn_unload(shn);
	}
	shn = NULL;
	error = NO;
}

- (BOOL)error
{
	return error;
}

- (XLDEmbeddedCueSheetType)hasCueSheet
{
	return XLDNoCueSheet;
}

- (id)cueSheet
{
	return nil;
}

- (id)metadata
{
	return nil;
}

- (NSString *)srcPath
{
	return srcPath;
}
	
@end
