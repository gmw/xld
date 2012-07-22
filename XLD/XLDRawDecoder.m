//
//  XLDRawDecoder.m
//  XLD
//
//  Created by tmkk on 06/10/09.
//  Copyright 2006 tmkk. All rights reserved.
//

#import "XLDRawDecoder.h"
#import <sys/stat.h> 

@implementation XLDRawDecoder

+ (BOOL)canHandleFile:(char *)path
{
	return YES;
}

+ (BOOL)canLoadThisBundle
{
	return YES;
}

- (id)init
{
	[super init];
	return self;
}

- (id)initWithFormat:(XLDFormat)fmt endian:(XLDEndian)e
{
	[self init];
	format = fmt;
	endian = e;
	return self;
}

- (id)initWithFormat:(XLDFormat)fmt endian:(XLDEndian)e offset:(int)offset
{
	[self initWithFormat:fmt endian:e];
	offsetBytes = offset;
	return self;
}

- (BOOL)openFile:(char *)path
{
	fp = fopen(path, "rb");
	if(!fp) {
		error = YES;
		return NO;
	}
	if(offsetBytes) fseeko(fp,offsetBytes,SEEK_SET);
	struct stat st;
	stat(path,&st);
	totalFrames = (st.st_size - offsetBytes) / format.channels / format.bps;
	if(srcPath) [srcPath release];
	srcPath = [[NSString alloc] initWithUTF8String:path];
	
	return YES;
}

- (void)dealloc
{
	if(fp) fclose(fp);
	if(srcPath) [srcPath release];
	[super dealloc];
}

- (int)samplerate
{
	return format.samplerate;
}

- (int)bytesPerSample
{
	return format.bps;
}

- (int)channels
{
	return format.channels;
}

- (xldoffset_t)totalFrames
{
	return totalFrames;
}

- (int)isFloat
{
	return NO;
}

- (int)decodeToBuffer:(int *)buffer frames:(int)count
{
	int i,j;
	char *buffer_p = (char *)buffer;
	char *internal_buffer = (char *)malloc(count * format.bps * format.channels);
	int ret = fread(internal_buffer, format.bps * format.channels, count, fp);
	
#ifdef _BIG_ENDIAN
	switch(format.bps) {
		case 1:
			for(i=0,j=0;i<ret*format.channels;i++,j+=4) {
				*(buffer_p+j) = *(internal_buffer+i);
				*(buffer_p+j+1) = 0;
				*(buffer_p+j+2) = 0;
				*(buffer_p+j+3) = 0;
			}
			break;
		case 2:
			for(i=0,j=0;i<ret*2*format.channels;i=i+2,j+=4) {
				if(endian == XLDBigEndian) {
					*(buffer_p+j) = *(internal_buffer+i);
					*(buffer_p+j+1) = *(internal_buffer+i+1);
					*(buffer_p+j+2) = 0;
					*(buffer_p+j+3) = 0;
				}
				else {
					*(buffer_p+j) = *(internal_buffer+i+1);
					*(buffer_p+j+1) = *(internal_buffer+i);
					*(buffer_p+j+2) = 0;
					*(buffer_p+j+3) = 0;
				}
			}
			break;
		case 3:
			for(i=0,j=0;i<ret*3*format.channels;i=i+3,j+=4) {
				if(endian == XLDBigEndian) {
					*(buffer_p+j) = *(internal_buffer+i);
					*(buffer_p+j+1) = *(internal_buffer+i+1);
					*(buffer_p+j+2) = *(internal_buffer+i+2);
					*(buffer_p+j+3) = 0;
				}
				else {
					*(buffer_p+j) = *(internal_buffer+i+2);
					*(buffer_p+j+1) = *(internal_buffer+i+1);
					*(buffer_p+j+2) = *(internal_buffer+i);
					*(buffer_p+j+3) = 0;
				}
			}
			break;
		case 4:
			for(i=0,j=0;i<ret*4*format.channels;i=i+4,j+=4) {
				if(endian == XLDBigEndian) {
					*(buffer_p+j) = *(internal_buffer+i);
					*(buffer_p+j+1) = *(internal_buffer+i+1);
					*(buffer_p+j+2) = *(internal_buffer+i+2);
					*(buffer_p+j+3) = *(internal_buffer+i+3);
				}
				else {
					*(buffer_p+j) = *(internal_buffer+i+3);
					*(buffer_p+j+1) = *(internal_buffer+i+2);
					*(buffer_p+j+2) = *(internal_buffer+i+1);
					*(buffer_p+j+3) = *(internal_buffer+i);
				}
			}
			break;
	}
#else
	switch(format.bps) {
		case 1:
			for(i=0,j=0;i<ret*format.channels;i++,j+=4) {
				*(buffer_p+j+3) = *(internal_buffer+i);
				*(buffer_p+j+2) = 0;
				*(buffer_p+j+1) = 0;
				*(buffer_p+j) = 0;
			}
			break;
		case 2:
			for(i=0,j=0;i<ret*2*format.channels;i=i+2,j+=4) {
				if(endian == XLDLittleEndian) {
					*(buffer_p+j+3) = *(internal_buffer+i+1);
					*(buffer_p+j+2) = *(internal_buffer+i);
					*(buffer_p+j+1) = 0;
					*(buffer_p+j) = 0;
				}
				else {
					*(buffer_p+j+3) = *(internal_buffer+i);
					*(buffer_p+j+2) = *(internal_buffer+i+1);
					*(buffer_p+j+1) = 0;
					*(buffer_p+j) = 0;
				}
			}
			break;
		case 3:
			for(i=0,j=0;i<ret*3*format.channels;i=i+3,j+=4) {
				if(endian == XLDLittleEndian) {
					*(buffer_p+j+3) = *(internal_buffer+i+2);
					*(buffer_p+j+2) = *(internal_buffer+i+1);
					*(buffer_p+j+1) = *(internal_buffer+i);
					*(buffer_p+j) = 0;
				}
				else {
					*(buffer_p+j+3) = *(internal_buffer+i);
					*(buffer_p+j+2) = *(internal_buffer+i+1);
					*(buffer_p+j+1) = *(internal_buffer+i+2);
					*(buffer_p+j) = 0;
				}
			}
			break;
		case 4:
			for(i=0,j=0;i<ret*4*format.channels;i=i+4,j+=4) {
				if(endian == XLDLittleEndian) {
					*(buffer_p+j+3) = *(internal_buffer+i+3);
					*(buffer_p+j+2) = *(internal_buffer+i+2);
					*(buffer_p+j+1) = *(internal_buffer+i+1);
					*(buffer_p+j) = *(internal_buffer+i);
				}
				else {
					*(buffer_p+j+3) = *(internal_buffer+i);
					*(buffer_p+j+2) = *(internal_buffer+i+1);
					*(buffer_p+j+1) = *(internal_buffer+i+2);
					*(buffer_p+j) = *(internal_buffer+i+3);
				}
			}
			break;
	}
#endif
	
	free(internal_buffer);
	
	return ret;
}

- (xldoffset_t)seekToFrame:(xldoffset_t)count
{
	xldoffset_t ret = fseeko(fp,count * format.bps * format.channels + offsetBytes,SEEK_SET);
	if(ret != 0) error = YES;
	return count;
}

- (void)closeFile
{
	if(fp) fclose(fp);
	fp = NULL;
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

- (int)offset
{
	return offsetBytes;
}

- (XLDEndian)endian
{
	return endian;
}

@end
