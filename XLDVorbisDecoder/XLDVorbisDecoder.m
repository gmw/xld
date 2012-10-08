#import <Foundation/Foundation.h>

typedef int64_t xldoffset_t;

#import <openssl/bio.h>
#import <openssl/evp.h>
#import "XLDVorbisDecoder.h"

static unsigned char *base64dec(char *input, int length)
{
	BIO *b64, *bmem;
	
	unsigned char *buffer = (unsigned char *)malloc(length);
	memset(buffer, 0, length);
	
	b64 = BIO_new(BIO_f_base64());
	BIO_set_flags(b64, BIO_FLAGS_BASE64_NO_NL);
	bmem = BIO_new_mem_buf(input, length);
	bmem = BIO_push(b64, bmem);
	
	BIO_read(bmem, buffer, length);
	
	BIO_free_all(bmem);
	
	return buffer;
}

@implementation XLDVorbisDecoder

+ (BOOL)canHandleFile:(char *)path
{
	FILE *fp = fopen(path,"rb");
	if(!fp) return NO;
	OggVorbis_File vf_test;
	if(ov_open(fp, &vf_test, NULL, 0) < 0) {
		fclose(fp);
		return NO;
	}
	ov_clear(&vf_test);
	return YES;
}

+ (BOOL)canLoadThisBundle
{
	if (floor(NSAppKitVersionNumber) <= 620 ) {
		return NO;
	}
	else return YES;
}

- (id)init
{
	[super init];
	cueData = nil;
	tempBuffer = NULL;
	error = NO;
	metadataDic = [[NSMutableDictionary alloc] init];
	srcPath = nil;
	opened = NO;
	return self;
}

- (BOOL)openFile:(char *)path
{
	FILE *fp = fopen(path,"rb");
	if(!fp) return NO;
	if(ov_open(fp, &vf, NULL, 0) < 0) {
		fclose(fp);
		return NO;
	}
	vi=ov_info(&vf,-1);
	totalFrames = ov_pcm_total(&vf,-1);
	
	vorbis_comment *comments = ov_comment(&vf,-1);
	if(comments->comments > 0) {
		int i;
		for(i=0;i<comments->comments;i++) {
			if(!strncasecmp(comments->user_comments[i],"cuesheet=",9)) {
				cueData = [[NSString alloc] initWithData:[NSData dataWithBytes:comments->user_comments[i]+9 length:comments->comment_lengths[i]-9] encoding:NSUTF8StringEncoding];
				if(cueData) [metadataDic setObject:cueData forKey:XLD_METADATA_CUESHEET];
			}
			else if(!strncasecmp(comments->user_comments[i],"title=",6)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comments->user_comments[i]+6 length:comments->comment_lengths[i]-6] encoding:NSUTF8StringEncoding];
				if(dat) {
					[metadataDic setObject:dat forKey:XLD_METADATA_TITLE];
					[dat release];
				}
			}
			else if(!strncasecmp(comments->user_comments[i],"artist=",7)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comments->user_comments[i]+7 length:comments->comment_lengths[i]-7] encoding:NSUTF8StringEncoding];
				if(dat) {
					[metadataDic setObject:dat forKey:XLD_METADATA_ARTIST];
					[dat release];
				}
			}
			else if(!strncasecmp(comments->user_comments[i],"album=",6)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comments->user_comments[i]+6 length:comments->comment_lengths[i]-6] encoding:NSUTF8StringEncoding];
				if(dat) {
					[metadataDic setObject:dat forKey:XLD_METADATA_ALBUM];
					[dat release];
				}
			}
			else if(!strncasecmp(comments->user_comments[i],"albumartist=",12)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comments->user_comments[i]+12 length:comments->comment_lengths[i]-12] encoding:NSUTF8StringEncoding];
				if(dat) {
					[metadataDic setObject:dat forKey:XLD_METADATA_ALBUMARTIST];
					[dat release];
				}
			}
			else if(!strncasecmp(comments->user_comments[i],"tracknumber=",12)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comments->user_comments[i]+12 length:comments->comment_lengths[i]-12] encoding:NSUTF8StringEncoding];
				if(dat) {
					int track = [dat intValue];
					if(track > 0) [metadataDic setObject:[NSNumber numberWithInt:track] forKey:XLD_METADATA_TRACK];
					[dat release];
				}
			}
			else if(!strncasecmp(comments->user_comments[i],"tracktotal=",11)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comments->user_comments[i]+11 length:comments->comment_lengths[i]-11] encoding:NSUTF8StringEncoding];
				if(dat) {
					int track_total = [dat intValue];
					if(track_total > 0) [metadataDic setObject:[NSNumber numberWithInt:track_total] forKey:XLD_METADATA_TOTALTRACKS];
					[dat release];
				}
			}
			else if(!strncasecmp(comments->user_comments[i],"totaltracks=",12)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comments->user_comments[i]+12 length:comments->comment_lengths[i]-12] encoding:NSUTF8StringEncoding];
				if(dat) {
					int track_total = [dat intValue];
					if(track_total > 0) [metadataDic setObject:[NSNumber numberWithInt:track_total] forKey:XLD_METADATA_TOTALTRACKS];
					[dat release];
				}
			}
			else if(!strncasecmp(comments->user_comments[i],"discnumber=",11)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comments->user_comments[i]+11 length:comments->comment_lengths[i]-11] encoding:NSUTF8StringEncoding];
				if(dat) {
					int disc = [dat intValue];
					if(disc > 0) [metadataDic setObject:[NSNumber numberWithInt:disc] forKey:XLD_METADATA_DISC];
					[dat release];
				}
			}
			else if(!strncasecmp(comments->user_comments[i],"disctotal=",10)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comments->user_comments[i]+10 length:comments->comment_lengths[i]-10] encoding:NSUTF8StringEncoding];
				if(dat) {
					int disc_total = [dat intValue];
					if(disc_total > 0) [metadataDic setObject:[NSNumber numberWithInt:disc_total] forKey:XLD_METADATA_TOTALDISCS];
					[dat release];
				}
			}
			else if(!strncasecmp(comments->user_comments[i],"totaldiscs=",11)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comments->user_comments[i]+11 length:comments->comment_lengths[i]-11] encoding:NSUTF8StringEncoding];
				if(dat) {
					int disc_total = [dat intValue];
					if(disc_total > 0) [metadataDic setObject:[NSNumber numberWithInt:disc_total] forKey:XLD_METADATA_TOTALDISCS];
					[dat release];
				}
			}
			else if(!strncasecmp(comments->user_comments[i],"genre=",6)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comments->user_comments[i]+6 length:comments->comment_lengths[i]-6] encoding:NSUTF8StringEncoding];
				if(dat) {
					[metadataDic setObject:dat forKey:XLD_METADATA_GENRE];
					[dat release];
				}
			}
			else if(!strncasecmp(comments->user_comments[i],"composer=",9)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comments->user_comments[i]+9 length:comments->comment_lengths[i]-9] encoding:NSUTF8StringEncoding];
				if(dat) {
					[metadataDic setObject:dat forKey:XLD_METADATA_COMPOSER];
					[dat release];
				}
			}
			else if(!strncasecmp(comments->user_comments[i],"date=",5)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comments->user_comments[i]+5 length:comments->comment_lengths[i]-5] encoding:NSUTF8StringEncoding];
				if(dat) {
					[metadataDic setObject:dat forKey:XLD_METADATA_DATE];
					int year = [dat intValue];
					if(year >=1000 && year < 3000) [metadataDic setObject:[NSNumber numberWithInt:year] forKey:XLD_METADATA_YEAR];
					[dat release];
				}
			}
			else if(!strncasecmp(comments->user_comments[i],"comment=",8)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comments->user_comments[i]+8 length:comments->comment_lengths[i]-8] encoding:NSUTF8StringEncoding];
				if(dat) {
					[metadataDic setObject:dat forKey:XLD_METADATA_COMMENT];
					[dat release];
				}
			}
			else if(!strncasecmp(comments->user_comments[i],"description=",12)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comments->user_comments[i]+12 length:comments->comment_lengths[i]-12] encoding:NSUTF8StringEncoding];
				if(dat) {
					[metadataDic setObject:dat forKey:XLD_METADATA_COMMENT];
					[dat release];
				}
			}
			else if(!strncasecmp(comments->user_comments[i],"ISRC=",5)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comments->user_comments[i]+5 length:comments->comment_lengths[i]-5] encoding:NSUTF8StringEncoding];
				if(dat) {
					[metadataDic setObject:dat forKey:XLD_METADATA_ISRC];
					[dat release];
				}
			}
			else if(!strncasecmp(comments->user_comments[i],"MCN=",4)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comments->user_comments[i]+4 length:comments->comment_lengths[i]-4] encoding:NSUTF8StringEncoding];
				if(dat) {
					[metadataDic setObject:dat forKey:XLD_METADATA_CATALOG];
					[dat release];
				}
			}
			else if(!strncasecmp(comments->user_comments[i],"compilation=",12)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comments->user_comments[i]+12 length:comments->comment_lengths[i]-12] encoding:NSUTF8StringEncoding];
				if(dat) {
					[metadataDic setObject:[NSNumber numberWithBool:[dat intValue]] forKey:XLD_METADATA_COMPILATION];
					[dat release];
				}
			}
			else if(!strncasecmp(comments->user_comments[i],"titlesort=",10)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comments->user_comments[i]+10 length:comments->comment_lengths[i]-10] encoding:NSUTF8StringEncoding];
				if(dat) {
					[metadataDic setObject:[NSNumber numberWithBool:[dat intValue]] forKey:XLD_METADATA_TITLESORT];
					[dat release];
				}
			}
			else if(!strncasecmp(comments->user_comments[i],"artistsort=",11)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comments->user_comments[i]+11 length:comments->comment_lengths[i]-11] encoding:NSUTF8StringEncoding];
				if(dat) {
					[metadataDic setObject:[NSNumber numberWithBool:[dat intValue]] forKey:XLD_METADATA_ARTISTSORT];
					[dat release];
				}
			}
			else if(!strncasecmp(comments->user_comments[i],"albumsort=",10)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comments->user_comments[i]+10 length:comments->comment_lengths[i]-10] encoding:NSUTF8StringEncoding];
				if(dat) {
					[metadataDic setObject:[NSNumber numberWithBool:[dat intValue]] forKey:XLD_METADATA_ALBUMSORT];
					[dat release];
				}
			}
			else if(!strncasecmp(comments->user_comments[i],"albumartistsort=",16)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comments->user_comments[i]+16 length:comments->comment_lengths[i]-16] encoding:NSUTF8StringEncoding];
				if(dat) {
					[metadataDic setObject:[NSNumber numberWithBool:[dat intValue]] forKey:XLD_METADATA_ALBUMARTISTSORT];
					[dat release];
				}
			}
			else if(!strncasecmp(comments->user_comments[i],"composersort=",13)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comments->user_comments[i]+13 length:comments->comment_lengths[i]-13] encoding:NSUTF8StringEncoding];
				if(dat) {
					[metadataDic setObject:[NSNumber numberWithBool:[dat intValue]] forKey:XLD_METADATA_COMPOSERSORT];
					[dat release];
				}
			}
			else if(!strncasecmp(comments->user_comments[i],"METADATA_BLOCK_PICTURE=",23)) {
				unsigned char *buf = base64dec(comments->user_comments[i]+23, comments->comment_lengths[i]-23);
				int type = OSSwapBigToHostInt32(*(int *)(buf));
				int mimeLength = OSSwapBigToHostInt32(*(int *)(buf+4));
				int descLength = OSSwapBigToHostInt32(*(int *)(buf+8+mimeLength));
				int pictureLength = OSSwapBigToHostInt32(*(int *)(buf+28+mimeLength+descLength));
				NSData *pictData = [NSData dataWithBytes:buf+32+mimeLength+descLength length:pictureLength];
				if(pictData) {
					if(type == 3 || ![metadataDic objectForKey:XLD_METADATA_COVER])
						[metadataDic setObject:pictData forKey:XLD_METADATA_COVER];
				}
			}
			else if(!strncasecmp(comments->user_comments[i],"REPLAYGAIN_TRACK_GAIN=",22)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comments->user_comments[i]+22 length:comments->comment_lengths[i]-22] encoding:NSUTF8StringEncoding];
				if(dat) {
					[metadataDic setObject:[NSNumber numberWithFloat:[dat floatValue]] forKey:XLD_METADATA_REPLAYGAIN_TRACK_GAIN];
					[dat release];
				}
			}
			else if(!strncasecmp(comments->user_comments[i],"REPLAYGAIN_TRACK_PEAK=",22)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comments->user_comments[i]+22 length:comments->comment_lengths[i]-22] encoding:NSUTF8StringEncoding];
				if(dat) {
					[metadataDic setObject:[NSNumber numberWithFloat:[dat floatValue]] forKey:XLD_METADATA_REPLAYGAIN_TRACK_PEAK];
					[dat release];
				}
			}
			else if(!strncasecmp(comments->user_comments[i],"REPLAYGAIN_ALBUM_GAIN=",22)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comments->user_comments[i]+22 length:comments->comment_lengths[i]-22] encoding:NSUTF8StringEncoding];
				if(dat) {
					[metadataDic setObject:[NSNumber numberWithFloat:[dat floatValue]] forKey:XLD_METADATA_REPLAYGAIN_ALBUM_GAIN];
					[dat release];
				}
			}
			else if(!strncasecmp(comments->user_comments[i],"REPLAYGAIN_ALBUM_PEAK=",22)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comments->user_comments[i]+22 length:comments->comment_lengths[i]-22] encoding:NSUTF8StringEncoding];
				if(dat) {
					[metadataDic setObject:[NSNumber numberWithFloat:[dat floatValue]] forKey:XLD_METADATA_REPLAYGAIN_ALBUM_PEAK];
					[dat release];
				}
			}
			else if(!strncasecmp(comments->user_comments[i],"encoder=",8)) {
				// do nothing
			}
			else { //unknown text metadata
				int len = strchr(comments->user_comments[i],'=') - comments->user_comments[i];
				if(len > 0) {
					NSString *idx = [[NSString alloc] initWithData:[NSData dataWithBytes:comments->user_comments[i] length:len] encoding:NSUTF8StringEncoding];
					NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comments->user_comments[i]+len+1 length:comments->comment_lengths[i]-len-1] encoding:NSUTF8StringEncoding];
					if(idx && dat) {
						[metadataDic setObject:dat forKey:[NSString stringWithFormat:@"XLD_UNKNOWN_TEXT_METADATA_%@",idx]];
					}
					if(idx) [idx release];
					if(dat) [dat release];
				}
			}
		}
	}
	
	if(srcPath) [srcPath release];
	srcPath = [[NSString alloc] initWithUTF8String:path];
	if(tempBuffer) free(tempBuffer);
	tempBuffer = malloc(16384);
	tempBufferSize = 16384;
	opened = YES;
	return YES;
}

- (void)dealloc
{
	if(opened) ov_clear(&vf);
	if(tempBuffer) free(tempBuffer);
	[metadataDic release];
	if(srcPath) [srcPath release];
	[super dealloc];
}

- (int)samplerate
{
	return vi->rate;
}

- (int)bytesPerSample
{
	return 2;
}

- (int)channels
{
	return vi->channels;
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
	int i;
	int totalRead = 0;
	int current_section;
	if(tempBufferSize < count*2*vi->channels) {
		tempBuffer = realloc(tempBuffer, count*2*vi->channels);
		tempBufferSize = count*2*vi->channels;
	}
	short *ptr = tempBuffer;
	while(totalRead < count) {
#ifdef _BIG_ENDIAN
		int read = ov_read(&vf,(char *)ptr,(count-totalRead)*2*vi->channels,1,2,1,&current_section);
#else
		int read = ov_read(&vf,(char *)ptr,(count-totalRead)*2*vi->channels,0,2,1,&current_section);
#endif
		if(!read) break;
		if(read < 0) {
			error = YES;
			break;
		}
		totalRead += read/2/vi->channels;
		ptr += read/2;
	}
	for(i=0; i<totalRead*vi->channels;i++) {
		buffer[i] = tempBuffer[i] << 16;
	}
	return totalRead;
}

- (xldoffset_t)seekToFrame:(xldoffset_t)count
{
	if(ov_pcm_seek(&vf,count)) error = YES;
	return count;
}

- (void)closeFile
{
	if(opened) ov_clear(&vf);
	opened = NO;
	if(cueData) [cueData release];
	cueData = nil;
	[metadataDic removeAllObjects];
	if(tempBuffer) free(tempBuffer);
	tempBuffer = NULL;
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