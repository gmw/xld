#import <Foundation/Foundation.h>

typedef int64_t xldoffset_t;

#import "XLDTtaDecoder.h"

#ifdef _BIG_ENDIAN
#define	ENDSWAP_INT16(x)	(((((x)>>8)&0xFF)|(((x)&0xFF)<<8)))
#define	ENDSWAP_INT32(x)	(((((x)>>24)&0xFF)|(((x)>>8)&0xFF00)|(((x)&0xFF00)<<8)|(((x)&0xFF)<<24)))
#else
#define	ENDSWAP_INT16(x)	(x)
#define	ENDSWAP_INT32(x)	(x)
#endif

#define TTA1_SIGN		0x31415454

@implementation XLDTtaDecoder

+ (BOOL)canHandleFile:(char *)path
{
	FILE *fdin = fopen(path, "rb");
	if(fdin == NULL) return NO;
	
	struct {
		unsigned char id[3];
		unsigned short version;
		unsigned char flags;
		unsigned char size[4];
	} __attribute__((packed)) id3v2;
	
	struct {
		unsigned long TTAid;
		unsigned short AudioFormat;
		unsigned short NumChannels;
		unsigned short BitsPerSample;
		unsigned long SampleRate;
		unsigned long DataLength;
		unsigned long CRC32;
	} __attribute__((packed)) tta_hdr;
	
	// skip ID3V2 header
	if (fread(&id3v2, sizeof(id3v2), 1, fdin) == 0) {
		fclose(fdin);
		return NO;
	}
	
	if (!memcmp(id3v2.id, "ID3", 3)) {
		long len;

		if (id3v2.size[0] & 0x80) {
			fclose(fdin);
			return NO;
		}
		
		len = (id3v2.size[0] & 0x7f);
		len = (len << 7) | (id3v2.size[1] & 0x7f);
		len = (len << 7) | (id3v2.size[2] & 0x7f);
		len = (len << 7) | (id3v2.size[3] & 0x7f);
		len += 10;
		if (id3v2.flags & (1 << 4)) len += 10;
		
		fseek(fdin, len, SEEK_SET);
	} else fseek(fdin, 0, SEEK_SET);
	
	int input_byte_count = 0;
	
	// read TTA header
	if (fread(&tta_hdr, sizeof(tta_hdr), 1, fdin) == 0) {
		fclose(fdin);
		return NO;
	}
	else input_byte_count += sizeof(tta_hdr);

	// check for supported formats
	if (ENDSWAP_INT32(tta_hdr.TTAid) != TTA1_SIGN) {
		fclose(fdin);
		return NO;
	}
	
	fclose(fdin);
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
	info = (ttainfo *)malloc(sizeof(ttainfo));
	error = NO;
	srcPath = nil;
	return self;
}

- (BOOL)openFile:(char *)path
{
	int ret = decode_init(path, info);
	if(ret) {
		clean_tta_decoder(info);
		error = YES;
		return NO;
	}
	bps = info->bps;
	channels = info->channels_real;
	samplerate = info->samplerate;
	totalFrames = info->totalFrames;
	isFloat = info->isFloat;
	if(srcPath) [srcPath release];
	srcPath = [[NSString alloc] initWithUTF8String:path];
	currentPos = 0;
	return YES;
}

- (void)dealloc
{
	free(info);
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
	return isFloat;
}

- (int)decodeToBuffer:(int *)buffer frames:(int)count
{
	int i,j;
	if(currentPos + count >= totalFrames) {
		count = totalFrames - currentPos;
	}
	if(count) {
		int ret = decode_sample(info,(unsigned char *)buffer,count*4*channels);
		for(i=0;i<ret/4;i++) {
			j = *(buffer+i);
			*(buffer+i) = j << (32-bps*8);
		}
		if(ret == -1) error = YES;
		else currentPos += ret/4/channels;
		return ret/4/channels;
	}
	else return 0;
}

- (xldoffset_t)seekToFrame:(xldoffset_t)count
{
	xldoffset_t ret = seek_tta(info, count);
	if(ret == -1) error = YES;
	currentPos = ret;
	return ret;
}

- (void)closeFile
{
	clean_tta_decoder(info);
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