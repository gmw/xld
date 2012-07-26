#import <Foundation/Foundation.h>
#import "XLDApeDecoder.h"
#import "APETag.h"

extern "C"	{
	int getApeTag(CAPETag *tag, wchar_t *field, char *buf, int *length);
}

int getApeTag(CAPETag *tag, wchar_t *field, char *buf, int *length)
{
	return tag->GetFieldBinary(field, buf, length);
}

@implementation XLDApeDecoder

+ (BOOL)canHandleFile:(char *)path
{
	char header[3];
	FILE *fp = fopen(path, "rb");
	if(!fp) return NO;
	if(fread(header, 1, 3, fp) != 3) {
		fclose(fp);
		return NO;
	}
	fclose(fp);
	if(memcmp(header,"ID3",3) && memcmp(header,"MAC",3)) return NO;
	
	int errnum = -1;
	IAPEDecompress *mac_tmp = CreateIAPEDecompress(path, &errnum);
	if(errnum != 0 || !mac_tmp) return NO;
	delete(mac_tmp);
	return YES;
}

+ (BOOL)canLoadThisBundle
{
	if (floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_2 ) {
		return NO;
	}
	else return YES;
}

- (id)init
{
	[super init];
	mac = NULL;
	error = NO;
	cueData = nil;
	internal_buffer = NULL;
	internalBufferBytes = 0;
	metadataDic = [[NSMutableDictionary alloc] init];
	srcPath = nil;
	return self;
}

- (BOOL)openFile:(char *)path
{
	int errnum = -1;
	mac = CreateIAPEDecompress(path, &errnum);
	if(errnum != 0 || !mac) {
		if(mac) delete mac;
		mac = NULL;
		error = YES;
		return NO;
	}
	channels = mac->GetInfo(APE_INFO_CHANNELS,0,0);
	bps = mac->GetInfo(APE_INFO_BYTES_PER_SAMPLE,0,0);
	samplerate = mac->GetInfo(APE_INFO_SAMPLE_RATE,0,0);
	totalFrames = mac->GetInfo(APE_INFO_TOTAL_BLOCKS,0,0);
	
	CAPETag *tag = (CAPETag *)mac->GetInfo(APE_INFO_TAG,0,0);
	int len = 1;
	char buf_tmp[1];
	getApeTag(tag, L"cuesheet", buf_tmp, &len);
	if(len) {
		char *buf = (char *)malloc(len+10);
		getApeTag(tag, L"cuesheet", buf, &len);
		if(buf[len-1]==0) len--;
		cueData = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSUTF8StringEncoding];
		[metadataDic setObject:cueData forKey:XLD_METADATA_CUESHEET];
		free(buf);
	}
	len = 1;
	getApeTag(tag, L"title", buf_tmp, &len);
	if(len) {
		char *buf = (char *)malloc(len+10);
		getApeTag(tag, L"title", buf, &len);
		if(buf[len-1]==0) len--;
		NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSUTF8StringEncoding];
		if(!str) str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSISOLatin1StringEncoding];
		if(str) {
			[metadataDic setObject:str forKey:XLD_METADATA_TITLE];
			[str release];
		}
		free(buf);
	}
	len = 1;
	getApeTag(tag, L"artist", buf_tmp, &len);
	if(len) {
		char *buf = (char *)malloc(len+10);
		getApeTag(tag, L"artist", buf, &len);
		if(buf[len-1]==0) len--;
		NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSUTF8StringEncoding];
		if(!str) str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSISOLatin1StringEncoding];
		if(str) {
			[metadataDic setObject:str forKey:XLD_METADATA_ARTIST];
			[str release];
		}
		free(buf);
	}
	len = 1;
	getApeTag(tag, L"album", buf_tmp, &len);
	if(len) {
		char *buf = (char *)malloc(len+10);
		getApeTag(tag, L"album", buf, &len);
		if(buf[len-1]==0) len--;
		NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSUTF8StringEncoding];
		if(!str) str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSISOLatin1StringEncoding];
		if(str) {
			[metadataDic setObject:str forKey:XLD_METADATA_ALBUM];
			[str release];
		}
		free(buf);
	}
	len = 1;
	getApeTag(tag, L"genre", buf_tmp, &len);
	if(len) {
		char *buf = (char *)malloc(len+10);
		getApeTag(tag, L"genre", buf, &len);
		if(buf[len-1]==0) len--;
		NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSUTF8StringEncoding];
		if(!str) str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSISOLatin1StringEncoding];
		if(str) {
			[metadataDic setObject:str forKey:XLD_METADATA_GENRE];
			[str release];
		}
		free(buf);
	}
	len = 1;
	getApeTag(tag, L"year", buf_tmp, &len);
	if(len) {
		char *buf = (char *)malloc(len+10);
		getApeTag(tag, L"year", buf, &len);
		if(buf[len-1]==0) len--;
		NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSUTF8StringEncoding];
		if(!str) str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSISOLatin1StringEncoding];
		if(str) {
			int year = [str intValue];
			if(year >= 1000 && year < 3000) [metadataDic setObject:[NSNumber numberWithInt:year] forKey:XLD_METADATA_YEAR];
			[str release];
		}
		free(buf);
	}
	len = 1;
	getApeTag(tag, L"track", buf_tmp, &len);
	if(len) {
		char *buf = (char *)malloc(len+10);
		getApeTag(tag, L"track", buf, &len);
		if(buf[len-1]==0) len--;
		NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSUTF8StringEncoding];
		if(!str) str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSISOLatin1StringEncoding];
		if(str) {
			int track = [str intValue];
			if(track > 0) [metadataDic setObject:[NSNumber numberWithInt:track] forKey:XLD_METADATA_TRACK];
			[str release];
		}
		free(buf);
	}
	len = 1;
	getApeTag(tag, L"disc", buf_tmp, &len);
	if(len) {
		char *buf = (char *)malloc(len+10);
		getApeTag(tag, L"disc", buf, &len);
		if(buf[len-1]==0) len--;
		NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSUTF8StringEncoding];
		if(!str) str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSISOLatin1StringEncoding];
		if(str) {
			int disc = [str intValue];
			if(disc > 0) [metadataDic setObject:[NSNumber numberWithInt:disc] forKey:XLD_METADATA_DISC];
			[str release];
		}
		free(buf);
	}
	len = 1;
	getApeTag(tag, L"composer", buf_tmp, &len);
	if(len) {
		char *buf = (char *)malloc(len+10);
		getApeTag(tag, L"composer", buf, &len);
		if(buf[len-1]==0) len--;
		NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSUTF8StringEncoding];
		if(!str) str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSISOLatin1StringEncoding];
		if(str) {
			[metadataDic setObject:str forKey:XLD_METADATA_COMPOSER];
			[str release];
		}
		free(buf);
	}
	len = 1;
	getApeTag(tag, L"comment", buf_tmp, &len);
	if(len) {
		char *buf = (char *)malloc(len+10);
		getApeTag(tag, L"comment", buf, &len);
		if(buf[len-1]==0) len--;
		NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSUTF8StringEncoding];
		if(!str) str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSISOLatin1StringEncoding];
		if(str) {
			[metadataDic setObject:str forKey:XLD_METADATA_COMMENT];
			[str release];
		}
		free(buf);
	}
	len = 1;
	getApeTag(tag, L"lyrics", buf_tmp, &len);
	if(len) {
		char *buf = (char *)malloc(len+10);
		getApeTag(tag, L"lyrics", buf, &len);
		if(buf[len-1]==0) len--;
		NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSUTF8StringEncoding];
		if(!str) str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSISOLatin1StringEncoding];
		if(str) {
			[metadataDic setObject:str forKey:XLD_METADATA_LYRICS];
			[str release];
		}
		free(buf);
	}
	len = 1;
	getApeTag(tag, L"ISRC", buf_tmp, &len);
	if(len) {
		char *buf = (char *)malloc(len+10);
		getApeTag(tag, L"ISRC", buf, &len);
		if(buf[len-1]==0) len--;
		NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSUTF8StringEncoding];
		if(!str) str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSISOLatin1StringEncoding];
		if(str) {
			[metadataDic setObject:str forKey:XLD_METADATA_ISRC];
			[str release];
		}
		free(buf);
	}
	len = 1;
	getApeTag(tag, L"MUSICBRAINZ_TRACKID", buf_tmp, &len);
	if(len) {
		char *buf = (char *)malloc(len+10);
		getApeTag(tag, L"MUSICBRAINZ_TRACKID", buf, &len);
		if(buf[len-1]==0) len--;
		NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSUTF8StringEncoding];
		if(!str) str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSISOLatin1StringEncoding];
		if(str) {
			[metadataDic setObject:str forKey:XLD_METADATA_MB_TRACKID];
			[str release];
		}
		free(buf);
	}
	len = 1;
	getApeTag(tag, L"MUSICBRAINZ_ALBUMID", buf_tmp, &len);
	if(len) {
		char *buf = (char *)malloc(len+10);
		getApeTag(tag, L"MUSICBRAINZ_ALBUMID", buf, &len);
		if(buf[len-1]==0) len--;
		NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSUTF8StringEncoding];
		if(!str) str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSISOLatin1StringEncoding];
		if(str) {
			[metadataDic setObject:str forKey:XLD_METADATA_MB_ALBUMID];
			[str release];
		}
		free(buf);
	}
	len = 1;
	getApeTag(tag, L"MUSICBRAINZ_ARTISTID", buf_tmp, &len);
	if(len) {
		char *buf = (char *)malloc(len+10);
		getApeTag(tag, L"MUSICBRAINZ_ARTISTID", buf, &len);
		if(buf[len-1]==0) len--;
		NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSUTF8StringEncoding];
		if(!str) str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSISOLatin1StringEncoding];
		if(str) {
			[metadataDic setObject:str forKey:XLD_METADATA_MB_ARTISTID];
			[str release];
		}
		free(buf);
	}
	len = 1;
	getApeTag(tag, L"MUSICBRAINZ_ALBUMARTISTID", buf_tmp, &len);
	if(len) {
		char *buf = (char *)malloc(len+10);
		getApeTag(tag, L"MUSICBRAINZ_ALBUMARTISTID", buf, &len);
		if(buf[len-1]==0) len--;
		NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSUTF8StringEncoding];
		if(!str) str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSISOLatin1StringEncoding];
		if(str) {
			[metadataDic setObject:str forKey:XLD_METADATA_MB_ALBUMARTISTID];
			[str release];
		}
		free(buf);
	}
	len = 1;
	getApeTag(tag, L"MUSICBRAINZ_DISCID", buf_tmp, &len);
	if(len) {
		char *buf = (char *)malloc(len+10);
		getApeTag(tag, L"MUSICBRAINZ_DISCID", buf, &len);
		if(buf[len-1]==0) len--;
		NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSUTF8StringEncoding];
		if(!str) str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSISOLatin1StringEncoding];
		if(str) {
			[metadataDic setObject:str forKey:XLD_METADATA_MB_DISCID];
			[str release];
		}
		free(buf);
	}
	len = 1;
	getApeTag(tag, L"MUSICIP_PUID", buf_tmp, &len);
	if(len) {
		char *buf = (char *)malloc(len+10);
		getApeTag(tag, L"MUSICIP_PUID", buf, &len);
		if(buf[len-1]==0) len--;
		NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSUTF8StringEncoding];
		if(!str) str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSISOLatin1StringEncoding];
		if(str) {
			[metadataDic setObject:str forKey:XLD_METADATA_PUID];
			[str release];
		}
		free(buf);
	}
	len = 1;
	getApeTag(tag, L"MUSICBRAINZ_ALBUMSTATUS", buf_tmp, &len);
	if(len) {
		char *buf = (char *)malloc(len+10);
		getApeTag(tag, L"MUSICBRAINZ_ALBUMSTATUS", buf, &len);
		if(buf[len-1]==0) len--;
		NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSUTF8StringEncoding];
		if(!str) str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSISOLatin1StringEncoding];
		if(str) {
			[metadataDic setObject:str forKey:XLD_METADATA_MB_ALBUMSTATUS];
			[str release];
		}
		free(buf);
	}
	len = 1;
	getApeTag(tag, L"MUSICBRAINZ_ALBUMTYPE", buf_tmp, &len);
	if(len) {
		char *buf = (char *)malloc(len+10);
		getApeTag(tag, L"MUSICBRAINZ_ALBUMTYPE", buf, &len);
		if(buf[len-1]==0) len--;
		NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSUTF8StringEncoding];
		if(!str) str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSISOLatin1StringEncoding];
		if(str) {
			[metadataDic setObject:str forKey:XLD_METADATA_MB_ALBUMTYPE];
			[str release];
		}
		free(buf);
	}
	len = 1;
	getApeTag(tag, L"RELEASECOUNTRY", buf_tmp, &len);
	if(len) {
		char *buf = (char *)malloc(len+10);
		getApeTag(tag, L"RELEASECOUNTRY", buf, &len);
		if(buf[len-1]==0) len--;
		NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSUTF8StringEncoding];
		if(!str) str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSISOLatin1StringEncoding];
		if(str) {
			[metadataDic setObject:str forKey:XLD_METADATA_MB_RELEASECOUNTRY];
			[str release];
		}
		free(buf);
	}
	len = 1;
	getApeTag(tag, L"MUSICBRAINZ_RELEASEGROUPID", buf_tmp, &len);
	if(len) {
		char *buf = (char *)malloc(len+10);
		getApeTag(tag, L"MUSICBRAINZ_RELEASEGROUPID", buf, &len);
		if(buf[len-1]==0) len--;
		NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSUTF8StringEncoding];
		if(!str) str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSISOLatin1StringEncoding];
		if(str) {
			[metadataDic setObject:str forKey:XLD_METADATA_MB_RELEASEGROUPID];
			[str release];
		}
		free(buf);
	}
	len = 1;
	getApeTag(tag, L"MUSICBRAINZ_WORKID", buf_tmp, &len);
	if(len) {
		char *buf = (char *)malloc(len+10);
		getApeTag(tag, L"MUSICBRAINZ_WORKID", buf, &len);
		if(buf[len-1]==0) len--;
		NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSUTF8StringEncoding];
		if(!str) str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:len] encoding:NSISOLatin1StringEncoding];
		if(str) {
			[metadataDic setObject:str forKey:XLD_METADATA_MB_WORKID];
			[str release];
		}
		free(buf);
	}
	len = 1;
	getApeTag(tag, L"Cover Art (front)", buf_tmp, &len);
	if(len) {
		char *buf = (char *)malloc(len+10);
		getApeTag(tag, L"Cover Art (front)", buf, &len);
		int i=0;
		while(buf[i] != 0) i++;
		i++;
		NSData *imgData = [NSData dataWithBytes:buf+i length:len-i];
		[metadataDic setObject:imgData forKey:XLD_METADATA_COVER];
		free(buf);
	}
	
	if(srcPath) [srcPath release];
	srcPath = [[NSString alloc] initWithUTF8String:path];
	return YES;
}

- (void)dealloc
{
	if(mac) delete(mac);
	if(cueData) [cueData release];
	if(internal_buffer) free(internal_buffer);
	[metadataDic release];
	if(srcPath) [srcPath release];
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
	int ret,i,j;
	unsigned char *buffer_p = (unsigned char*)buffer;
	if(!internal_buffer) {
		internal_buffer = (unsigned char *)malloc(count*channels*bps);
		internalBufferBytes = count*bps*channels;
	}
	else if(internalBufferBytes < count*bps*channels) {
		internal_buffer = (unsigned char *)realloc(internal_buffer,count*bps*channels);
		internalBufferBytes = count*bps*channels;
	}
	mac->GetData((char *)internal_buffer, count, &ret);
	
#ifdef _BIG_ENDIAN
	switch(bps) {
	  case 1:
		for(i=0,j=0;i<ret*channels;i++,j+=4) {
			if(*(buffer_p+i) <= 127)
					*(buffer_p+j) = *(internal_buffer+i) + 128;
			else
					*(buffer_p+j) = *(internal_buffer+i) - 128;
			*(buffer_p+j+1) = 0;
			*(buffer_p+j+2) = 0;
			*(buffer_p+j+3) = 0;
		}
		break;
	  case 2:
		for(i=0,j=0;i<ret*2*channels;i=i+2,j+=4) {
			*(buffer_p+j) = *(internal_buffer+i);
			*(buffer_p+j+1) = *(internal_buffer+i+1);
			*(buffer_p+j+2) = 0;
			*(buffer_p+j+3) = 0;
		}
		break;
	  case 3:
		for(i=0,j=0;i<ret*3*channels;i=i+3,j+=4) {
			*(buffer_p+j) = *(internal_buffer+i);
			*(buffer_p+j+1) = *(internal_buffer+i+1);
			*(buffer_p+j+2) = *(internal_buffer+i+2);
			*(buffer_p+j+3) = 0;
		}
		break;
	  case 4:
		for(i=0,j=0;i<ret*4*channels;i=i+4,j+=4) {
			*(buffer_p+j) = *(internal_buffer+i);
			*(buffer_p+j+1) = *(internal_buffer+i+1);
			*(buffer_p+j+2) = *(internal_buffer+i+2);
			*(buffer_p+j+3) = *(internal_buffer+i+3);
		}
		break;
	}
#else
	switch(bps) {
	  case 1:
		for(i=0,j=0;i<ret*channels;i++,j+=4) {
			if(*(buffer_p+i) <= 127)
					*(buffer_p+j+3) = *(internal_buffer+i) + 128;
			else
					*(buffer_p+j+3) = *(internal_buffer+i) - 128;
			*(buffer_p+j+2) = 0;
			*(buffer_p+j+1) = 0;
			*(buffer_p+j) = 0;
		}
		break;
	  case 2:
		for(i=0,j=0;i<ret*2*channels;i=i+2,j+=4) {
			*(buffer_p+j+3) = *(internal_buffer+i+1);
			*(buffer_p+j+2) = *(internal_buffer+i);
			*(buffer_p+j+1) = 0;
			*(buffer_p+j) = 0;
		}
		break;
	  case 3:
		for(i=0,j=0;i<ret*3*channels;i=i+3,j+=4) {
			*(buffer_p+j+3) = *(internal_buffer+i+2);
			*(buffer_p+j+2) = *(internal_buffer+i+1);
			*(buffer_p+j+1) = *(internal_buffer+i);
			*(buffer_p+j) = 0;
		}
		break;
	  case 4:
		for(i=0,j=0;i<ret*4*channels;i=i+4,j+=4) {
			*(buffer_p+j+3) = *(internal_buffer+i+3);
			*(buffer_p+j+2) = *(internal_buffer+i+2);
			*(buffer_p+j+1) = *(internal_buffer+i+1);
			*(buffer_p+j) = *(internal_buffer+i);
		}
		break;
	}
#endif
	
	if(ret < 0) error = YES;
	
	return ret;
}

- (xldoffset_t)seekToFrame:(xldoffset_t)count
{
	int ret = mac->Seek((int)count);
	if(ret < 0) error = YES;
	return ret;
}

- (void)closeFile
{
	if(mac) delete(mac);
	if(cueData) [cueData release];
	if(internal_buffer) free(internal_buffer);
	mac = NULL;
	cueData = nil;
	internal_buffer = NULL;
	internalBufferBytes = 0;
	[metadataDic removeAllObjects];
	error = NO;
}

- (BOOL)error
{
	return error;
}

- (XLDEmbeddedCueSheetType)hasCueSheet
{
	if(cueData) return XLDTextTypeCueSheet;
	else return XLDNoCueSheet;
}

- (id)cueSheet
{
	return cueData;
}

- (id)metadata
{
	return metadataDic;
}

- (NSString *)srcPath
{
	return srcPath;
}

@end
