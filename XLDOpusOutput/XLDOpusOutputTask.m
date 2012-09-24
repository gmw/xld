//
//  XLDOpusOutputTask.m
//  XLDOpusOutput
//
//  Created by tmkk on 12/08/09.
//  Copyright 2012 tmkk. All rights reserved.
//

#import "XLDOpusOutputTask.h"

typedef int64_t xldoffset_t;
#import "XLDTrack.h"
#import "lpc.h"

#import <openssl/bio.h>
#import <openssl/evp.h>
#import <openssl/buffer.h>

static const int max_ogg_delay=48000;

typedef enum
{
	OpusEncoderModeVBR = 0,
	OpusEncoderModeCVBR = 1,
	OpusEncoderModeCBR = 2
} OpusEncoderMode;

static inline int oe_write_page(ogg_page *page, FILE *fp)
{
	int written;
	written=fwrite(page->header,1,page->header_len, fp);
	written+=fwrite(page->body,1,page->body_len, fp);
	return written;
}

#define readint(buf, base) (((buf[base+3]<<24)&0xff000000)| \
((buf[base+2]<<16)&0xff0000)| \
((buf[base+1]<<8)&0xff00)| \
(buf[base]&0xff))
#define writeint(buf, base, val) do{ buf[base+3]=((val)>>24)&0xff; \
buf[base+2]=((val)>>16)&0xff; \
buf[base+1]=((val)>>8)&0xff; \
buf[base]=(val)&0xff; \
}while(0)

static void comment_init(char **comments, int* length, const char *vendor_string)
{
	/*The 'vendor' field should be the actual encoding library used.*/
	int vendor_length=strlen(vendor_string);
	int user_comment_list_length=0;
	int len=8+4+vendor_length+4;
	char *p=(char*)malloc(len);
	if(p==NULL){
		fprintf(stderr, "malloc failed in comment_init()\n");
		exit(1);
	}
	memcpy(p, "OpusTags", 8);
	writeint(p, 8, vendor_length);
	memcpy(p+12, vendor_string, vendor_length);
	writeint(p, 12+vendor_length, user_comment_list_length);
	*length=len;
	*comments=p;
}

static void comment_add(char **comments, int* length, char *tag, char *val)
{
	char* p=*comments;
	int vendor_length=readint(p, 8);
	int user_comment_list_length=readint(p, 8+4+vendor_length);
	int tag_len=(tag?strlen(tag):0);
	int val_len=strlen(val);
	int len=(*length)+4+tag_len+val_len;
	
	p=(char*)realloc(p, len);
	if(p==NULL){
		fprintf(stderr, "realloc failed in comment_add()\n");
		exit(1);
	}
	
	writeint(p, *length, tag_len+val_len);      /* length of comment */
	if(tag) memcpy(p+*length+4, tag, tag_len);  /* comment */
	memcpy(p+*length+4+tag_len, val, val_len);  /* comment */
	writeint(p, 8+4+vendor_length, user_comment_list_length+1);
	*comments=p;
	*length=len;
}

static char *base64enc(const unsigned  char *input, int length)
{
	BIO *bmem, *b64;
	BUF_MEM *bptr;
	
	b64 = BIO_new(BIO_f_base64());
	BIO_set_flags(b64, BIO_FLAGS_BASE64_NO_NL);
	bmem = BIO_new(BIO_s_mem());
	b64 = BIO_push(b64, bmem);
	BIO_write(b64, input, length);
	BIO_flush(b64);
	BIO_get_mem_ptr(b64, &bptr);
	
	char *buff = (char *)malloc(bptr->length+1);
	memcpy(buff, bptr->data, bptr->length);
	buff[bptr->length] = 0;
	
	BIO_free_all(b64);
	
	return buff;
}

typedef struct {
	unsigned char *data;
	int maxlen;
	int pos;
} Packet;

static int write_uint32(Packet *p, ogg_uint32_t val)
{
	if (p->pos>p->maxlen-4)
		return 0;
	p->data[p->pos  ] = (val    ) & 0xFF;
	p->data[p->pos+1] = (val>> 8) & 0xFF;
	p->data[p->pos+2] = (val>>16) & 0xFF;
	p->data[p->pos+3] = (val>>24) & 0xFF;
	p->pos += 4;
	return 1;
}

static int write_uint16(Packet *p, ogg_uint16_t val)
{
	if (p->pos>p->maxlen-2)
		return 0;
	p->data[p->pos  ] = (val    ) & 0xFF;
	p->data[p->pos+1] = (val>> 8) & 0xFF;
	p->pos += 2;
	return 1;
}

static int write_chars(Packet *p, const unsigned char *str, int nb_chars)
{
	int i;
	if (p->pos>p->maxlen-nb_chars)
		return 0;
	for (i=0;i<nb_chars;i++)
		p->data[p->pos++] = str[i];
	return 1;
}

int opus_header_to_packet(const OpusHeader *h, unsigned char *packet, int len)
{
	int i;
	Packet p;
	unsigned char ch;
	
	p.data = packet;
	p.maxlen = len;
	p.pos = 0;
	if (len<19)return 0;
	if (!write_chars(&p, (const unsigned char*)"OpusHead", 8))
		return 0;
	/* Version is 1 */
	ch = 1;
	if (!write_chars(&p, &ch, 1))
		return 0;
	
	ch = h->channels;
	if (!write_chars(&p, &ch, 1))
		return 0;
	
	if (!write_uint16(&p, h->preskip))
		return 0;
	
	if (!write_uint32(&p, h->input_sample_rate))
		return 0;
	
	if (!write_uint16(&p, h->gain))
		return 0;
	
	ch = h->channel_mapping;
	if (!write_chars(&p, &ch, 1))
		return 0;
	
	if (h->channel_mapping != 0)
	{
		ch = h->nb_streams;
		if (!write_chars(&p, &ch, 1))
			return 0;
		
		ch = h->nb_coupled;
		if (!write_chars(&p, &ch, 1))
			return 0;
		
		/* Multi-stream support */
		for (i=0;i<h->channels;i++)
		{
			if (!write_chars(&p, &h->stream_map[i], 1))
				return 0;
		}
	}
	
	return p.pos;
}

@implementation XLDOpusOutputTask

- (id)init
{
	[super init];
	return self;
}

- (id)initWithConfigurations:(NSDictionary *)cfg
{
	[self init];
	configurations = [cfg retain];
	return self;
}

- (void)dealloc
{
	if(fp) fclose(fp);
	if(configurations) [configurations release];
	if(packet) free(packet);
	if(input) free(input);
	if(resamplerBuffer) free(resamplerBuffer);
	[super dealloc];
}

- (BOOL)setOutputFormat:(XLDFormat)fmt
{
	format = fmt;
	if(format.bps > 4) return NO;
	if(format.channels > 2) return NO;
	
	return YES;
}

- (BOOL)openFileForOutput:(NSString *)str withTrackData:(id)track
{
	int ret;
	unsigned char      mapping[256];
	int i;
	for(i=0;i<256;i++)mapping[i]=i;
	
	fp = fopen([str UTF8String], "wb");
	if(!fp) {
		return NO;
	}
	
	if(ogg_stream_init(&os, rand())==-1){
		fprintf(stderr,"Error: stream init failed\n");
		goto fail;
	}
	
	if(format.samplerate>24000)coding_rate=48000;
	else if(format.samplerate>16000)coding_rate=24000;
	else if(format.samplerate>12000)coding_rate=16000;
	else if(format.samplerate>8000)coding_rate=12000;
	else coding_rate=8000;
	
	frame_size = [[configurations objectForKey:@"FrameSize"] intValue];
	if(!frame_size) frame_size = 960;
	frame_size = frame_size/(48000/coding_rate);
	
	/* setup header */
	header.channels=format.channels;
	header.nb_coupled=format.channels>1?1:0;
	header.nb_streams=1;
	header.channel_mapping=0;
	header.gain=0;
	header.input_sample_rate=format.samplerate;
	
	/*Initialize OPUS encoder*/
	st = opus_multistream_encoder_create(coding_rate,format.channels,header.nb_streams,header.nb_coupled,mapping,frame_size<480/(48000/coding_rate)?OPUS_APPLICATION_RESTRICTED_LOWDELAY:OPUS_APPLICATION_AUDIO,&ret);
	if(ret != OPUS_OK) {
		fprintf(stderr, "opus_multistream_encoder_create failure\n");
		if(st) opus_multistream_encoder_destroy(st);
		st = NULL;
		return NO;
	}
	
	int bitrate = [[configurations objectForKey:@"Bitrate"] intValue];
	bitrate=bitrate>0?bitrate:64000*header.nb_streams+32000*header.nb_coupled;
	if(bitrate > 256000 * format.channels) bitrate = 256000 * format.channels;
	ret = opus_multistream_encoder_ctl(st, OPUS_SET_BITRATE(bitrate));
	if(ret != OPUS_OK) {
		goto fail;
	}
	
	int encoderMode = [[configurations objectForKey:@"EncoderMode"] intValue];
	ret = opus_multistream_encoder_ctl(st, OPUS_SET_VBR(encoderMode != OpusEncoderModeCBR));
	if(ret != OPUS_OK) {
		goto fail;
	}
	
	if(encoderMode != OpusEncoderModeCBR) {
		ret = opus_multistream_encoder_ctl(st, OPUS_SET_VBR_CONSTRAINT(encoderMode != OpusEncoderModeVBR));
		if(ret != OPUS_OK) {
			goto fail;
		}
	}
	
	ret = opus_multistream_encoder_ctl(st, OPUS_SET_COMPLEXITY(10));
	if(ret != OPUS_OK) {
		goto fail;
	}
	
	opus_int32 lookahead;
	ret = opus_multistream_encoder_ctl(st, OPUS_GET_LOOKAHEAD(&lookahead));
	if(ret != OPUS_OK) {
		goto fail;
	}
	
	/* setup resampler */
	if(coding_rate != format.samplerate) {
		resampler = speex_resampler_init(format.channels, format.samplerate, coding_rate, 5, &ret);
		if(ret!=0) fprintf(stderr, "resampler error: %s\n", speex_resampler_strerror(ret));
		lookahead += speex_resampler_get_output_latency(resampler);
	}
	
	header.preskip=lookahead*(48000./coding_rate);
	
	max_frame_bytes=(1275*3+7)*header.nb_streams;
	packet=malloc(sizeof(unsigned char)*max_frame_bytes);
	if(!packet) goto fail;
	
	/* setup tags */
	char *comments;
	int comments_length;
	const char *opus_version=opus_get_version_string();
	comment_init(&comments, &comments_length, opus_version);
	comment_add(&comments, &comments_length, "ENCODER=", (char *)[[NSString stringWithFormat:@"X Lossless Decoder %@",[[NSBundle mainBundle] objectForInfoDictionaryKey: @"CFBundleShortVersionString"]] UTF8String]);
	if(addTag) {
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLE]) {
			comment_add(&comments,&comments_length,"TITLE=",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLE] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTIST]) {
			comment_add(&comments,&comments_length,"ARTIST=",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTIST] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUM]) {
			comment_add(&comments,&comments_length,"ALBUM=",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUM] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMARTIST]) {
			comment_add(&comments,&comments_length,"ALBUMARTIST=",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMARTIST] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GENRE]) {
			comment_add(&comments,&comments_length,"GENRE=",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GENRE] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPOSER]) {
			comment_add(&comments,&comments_length,"COMPOSER=",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPOSER] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TRACK]) {
			comment_add(&comments,&comments_length,"TRACKNUMBER=",(char *)[[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TRACK] stringValue] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALTRACKS]) {
			comment_add(&comments,&comments_length,"TRACKTOTAL=",(char *)[[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALTRACKS] stringValue] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DISC]) {
			comment_add(&comments,&comments_length,"DISCNUMBER=",(char *)[[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DISC] stringValue] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALDISCS]) {
			comment_add(&comments,&comments_length,"DISCTOTAL=",(char *)[[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALDISCS] stringValue] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DATE]) {
			comment_add(&comments,&comments_length,"DATE=",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DATE] UTF8String]);
		}
		else if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_YEAR]) {
			comment_add(&comments,&comments_length,"DATE=",(char *)[[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_YEAR] stringValue] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GROUP]) {
			comment_add(&comments,&comments_length,"CONTENTGROUP=",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GROUP] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMMENT]) {
			comment_add(&comments,&comments_length,"COMMENT=",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMMENT] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ISRC]) {
			comment_add(&comments,&comments_length,"ISRC=",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ISRC] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_CATALOG]) {
			comment_add(&comments,&comments_length,"MCN=",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_CATALOG] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPILATION]) {
			comment_add(&comments,&comments_length,"COMPILATION=",(char *)[[NSString stringWithFormat:@"%d",[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPILATION] intValue]] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLESORT]) {
			comment_add(&comments,&comments_length,"TITLESORT=",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLESORT] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTISTSORT]) {
			comment_add(&comments,&comments_length,"ARTISTSORT=",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTISTSORT] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMSORT]) {
			comment_add(&comments,&comments_length,"ALBUMSORT=",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMSORT] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMARTISTSORT]) {
			comment_add(&comments,&comments_length,"ALBUMARTISTSORT=",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMARTISTSORT] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPOSERSORT]) {
			comment_add(&comments,&comments_length,"COMPOSERSORT=",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPOSERSORT] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GRACENOTE2]) {
			comment_add(&comments,&comments_length,"iTunes_CDDB_1=",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GRACENOTE2] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_TRACKID]) {
			comment_add(&comments,&comments_length,"MUSICBRAINZ_TRACKID=",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_TRACKID] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMID]) {
			comment_add(&comments,&comments_length,"MUSICBRAINZ_ALBUMID=",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMID] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ARTISTID]) {
			comment_add(&comments,&comments_length,"MUSICBRAINZ_ARTISTID=",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ARTISTID] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMARTISTID]) {
			comment_add(&comments,&comments_length,"MUSICBRAINZ_ALBUMARTISTID=",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMARTISTID] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_DISCID]) {
			comment_add(&comments,&comments_length,"MUSICBRAINZ_DISCID=",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_DISCID] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_PUID]) {
			comment_add(&comments,&comments_length,"MUSICIP_PUID=",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_PUID] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMSTATUS]) {
			comment_add(&comments,&comments_length,"MUSICBRAINZ_ALBUMSTATUS=",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMSTATUS] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMTYPE]) {
			comment_add(&comments,&comments_length,"MUSICBRAINZ_ALBUMTYPE=",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMTYPE] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASECOUNTRY]) {
			comment_add(&comments,&comments_length,"RELEASECOUNTRY=",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASECOUNTRY] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASEGROUPID]) {
			comment_add(&comments,&comments_length,"MUSICBRAINZ_RELEASEGROUPID=",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASEGROUPID] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_WORKID]) {
			comment_add(&comments,&comments_length,"MUSICBRAINZ_WORKID=",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_WORKID] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COVER]) {
			NSData *imgData = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COVER];
			NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:imgData];
			if(rep) {
				NSMutableData *pictureBlockData = [NSMutableData data];
				int type = OSSwapHostToBigInt32(3);
				int width = OSSwapHostToBigInt32([rep pixelsWide]);
				int height = OSSwapHostToBigInt32([rep pixelsHigh]);
				int depth = OSSwapHostToBigInt32([rep bitsPerPixel]);
				int indexedColor = 0;
				int descLength = 0;
				char *mime = 0;
				if([imgData length] >= 8 && 0 == memcmp([imgData bytes], "\x89PNG\x0d\x0a\x1a\x0a", 8))
					mime = "image/png";
				else if([imgData length] >= 6 && (0 == memcmp([imgData bytes], "GIF87a", 6) || 0 == memcmp([imgData bytes], "GIF89a", 6))) {
					mime = "image/gif";
					indexedColor = OSSwapHostToBigInt32(256);
				}
				else if([imgData length] >= 2 && 0 == memcmp([imgData bytes], "\xff\xd8", 2))
					mime = "image/jpeg";
				int mimeLength = mime ? OSSwapHostToBigInt32(strlen(mime)) : 0;
				int pictureLength = OSSwapHostToBigInt32([imgData length]);
				if(mime) {
					[pictureBlockData appendBytes:&type length:4];
					[pictureBlockData appendBytes:&mimeLength length:4];
					[pictureBlockData appendBytes:mime length:strlen(mime)];
					[pictureBlockData appendBytes:&descLength length:4];
					[pictureBlockData appendBytes:&width length:4];
					[pictureBlockData appendBytes:&height length:4];
					[pictureBlockData appendBytes:&depth length:4];
					[pictureBlockData appendBytes:&indexedColor length:4];
					[pictureBlockData appendBytes:&pictureLength length:4];
					[pictureBlockData appendData:imgData];
					char *encodedData = base64enc([pictureBlockData bytes], [pictureBlockData length]);
					comment_add(&comments,&comments_length,"METADATA_BLOCK_PICTURE=",encodedData);
					free(encodedData);
				}
			}
		}
		NSArray *keyArr = [[(XLDTrack *)track metadata] allKeys];
		for(i=[keyArr count]-1;i>=0;i--) {
			NSString *key = [keyArr objectAtIndex:i];
			NSRange range = [key rangeOfString:@"XLD_UNKNOWN_TEXT_METADATA_"];
			if(range.location != 0) continue;
			const char *idx = [[NSString stringWithFormat:@"%@=",[key substringFromIndex:range.length]] UTF8String];
			const char *dat = [[[(XLDTrack *)track metadata] objectForKey:key] UTF8String];
			comment_add(&comments,&comments_length,(char *)idx,(char *)dat);
		}
	}
	
	/*Write header*/
	{
		unsigned char header_data[100];
		int packet_size=opus_header_to_packet(&header, header_data, 100);
		op.packet=header_data;
		op.bytes=packet_size;
		op.b_o_s=1;
		op.e_o_s=0;
		op.granulepos=0;
		op.packetno=0;
		ogg_stream_packetin(&os, &op);
		
		while((ret=ogg_stream_flush(&os, &og))){
			if(!ret)break;
			ret=oe_write_page(&og, fp);
			if(ret!=og.header_len+og.body_len){
				fprintf(stderr,"Error: failed writing header to output stream\n");
				goto fail;
			}
		}
		op.packet=(unsigned char *)comments;
		op.bytes=comments_length;
		op.b_o_s=0;
		op.e_o_s=0;
		op.granulepos=0;
		op.packetno=1;
		ogg_stream_packetin(&os, &op);
	}
	
	/* writing the rest of the opus header packets */
	while((ret=ogg_stream_flush(&os, &og))){
		if(!ret)break;
		ret=oe_write_page(&og, fp);
		if(ret!=og.header_len + og.body_len){
			fprintf(stderr,"Error: failed writing header to output stream\n");
			goto fail;
		}
	}
	
	free(comments);
	
	pid = -1;
	original_samples = 0;
	enc_granulepos = 0;
	last_segments = 0;
	last_granulepos = 0;
	bufferedSamples = 0;
	bufferSize = 0;
	bufferedResamplerSamples = 0;
	return YES;
fail:
	if(st) opus_multistream_encoder_destroy(st);
	st = NULL;
	ogg_stream_clear(&os);
	return NO;
}

- (NSString *)extensionStr
{
	return @"opus";
}

- (BOOL)writeBuffer:(int *)buffer frames:(int)counts
{
	int pos=0,i;
	original_samples += counts;
	if(resampler) {
		int ratio = coding_rate/format.samplerate + 1;
		spx_uint32_t usedSamples=counts+bufferedResamplerSamples;
		if(usedSamples >= 2048) {
			usedSamples -= 1024;
			spx_uint32_t outSamples=usedSamples*ratio;
			if(!resamplerBuffer || bufferSize < counts) {
				resamplerBuffer = realloc(resamplerBuffer,sizeof(float)*(counts+2048)*format.channels);
				input = realloc(input,sizeof(float)*((counts+2048)*ratio+frame_size*2)*format.channels);
				bufferSize = counts;
			}
			if(format.isFloat) {
				memcpy(resamplerBuffer+bufferedResamplerSamples*format.channels, buffer, counts*format.channels*sizeof(float));
			}
			else {
				for(i=0;i<counts*format.channels;i++) {
					resamplerBuffer[bufferedResamplerSamples*format.channels+i] = buffer[i] / 2147483648.0;
				}
			}
			speex_resampler_process_interleaved_float(resampler,resamplerBuffer,&usedSamples,input+bufferedSamples*format.channels,&outSamples);
			
			if(usedSamples < counts+bufferedResamplerSamples) {
				bufferedResamplerSamples = counts+bufferedResamplerSamples-usedSamples;
				memmove(resamplerBuffer, resamplerBuffer+usedSamples*format.channels, bufferedResamplerSamples*sizeof(float)*format.channels);
			}
			bufferedSamples += outSamples;
		}
		else {
			if(format.isFloat) {
				memcpy(resamplerBuffer+bufferedResamplerSamples*format.channels, buffer, counts*format.channels*sizeof(float));
			}
			else {
				for(i=0;i<counts*format.channels;i++) {
					resamplerBuffer[bufferedResamplerSamples*format.channels+i] = buffer[i] / 2147483648.0;
				}
			}
			bufferedResamplerSamples += counts;
			return YES;
		}
	}
	else {
		if(!input || bufferSize < counts) {
			input = realloc(input,sizeof(float)*(counts+frame_size*2)*format.channels);
			bufferSize = counts;
		}
		if(format.isFloat) {
			memcpy(input+bufferedSamples*format.channels, buffer, counts*format.channels*sizeof(float));
		}
		else {
			for(i=0;i<counts*format.channels;i++) {
				input[bufferedSamples*format.channels+i] = buffer[i] / 2147483648.0;
			}
		}
		bufferedSamples += counts;
	}
	while(bufferedSamples >= frame_size*2) {
		int size_segments,cur_frame_size,nb_samples;
		pid++;
		
		nb_samples = frame_size;
		bufferedSamples -= nb_samples;
		if(nb_samples<frame_size) op.e_o_s=1;
		else op.e_o_s=0;
		
		cur_frame_size=frame_size;
		
		int nbBytes = opus_multistream_encode_float(st, input+pos, cur_frame_size, packet, max_frame_bytes);
		if(nbBytes < 0) return NO;
		
		pos += nb_samples*format.channels;
		
		enc_granulepos+=cur_frame_size*48000/coding_rate;
		size_segments=(nbBytes+255)/255;
		while((((size_segments<=255)&&(last_segments+size_segments>255))
			   ||(enc_granulepos-last_granulepos>max_ogg_delay))
			  &&ogg_stream_flush_fill(&os, &og,255*255)) {
			if(ogg_page_packets(&og)!=0)last_granulepos=ogg_page_granulepos(&og);
			last_segments-=og.header[26];
			int ret=oe_write_page(&og, fp);
			if(ret!=og.header_len+og.body_len){
				fprintf(stderr,"Error: failed writing data to output stream\n");
				return NO;
			}
		}
		
		op.packet=(unsigned char *)packet;
		op.bytes=nbBytes;
		op.b_o_s=0;
		op.granulepos=enc_granulepos;
		op.packetno=2+pid;
		ogg_stream_packetin(&os, &op);
		last_segments+=size_segments;
		
		while((op.e_o_s||(enc_granulepos+(frame_size*48000/coding_rate)-last_granulepos>max_ogg_delay)||
			   (last_segments>=255))?
			  ogg_stream_flush_fill(&os, &og,255*255):
			  ogg_stream_pageout_fill(&os, &og,255*255)){
			if(ogg_page_packets(&og)!=0)last_granulepos=ogg_page_granulepos(&og);
			last_segments-=og.header[26];
			int ret=oe_write_page(&og, fp);
			if(ret!=og.header_len+og.body_len){
				fprintf(stderr,"Error: failed writing data to output stream\n");
				return NO;
			}
		}
	}
	
	if(pos && bufferedSamples) memmove(input, input+pos, bufferedSamples*format.channels*sizeof(float));
	return YES;
}

- (void)finalize
{
	int pos=0,i,nb_samples=-1,eos=0;
	float *paddingBuffer = NULL;
	int extra_samples = (int)header.preskip*(format.samplerate/48000.);
	if(extra_samples) {
		float *lpc_in = resampler?resamplerBuffer:input;
		int lpc_samples = resampler?bufferedResamplerSamples:bufferedSamples;
		int lpc_order = 32;
		if(lpc_samples>lpc_order*2){
			paddingBuffer=calloc(format.channels * extra_samples, sizeof(float));
			float *lpc=alloca(lpc_order*sizeof(*lpc));
			for(i=0;i<format.channels;i++){
				vorbis_lpc_from_data(lpc_in+i,lpc,lpc_samples,lpc_order,format.channels);
				vorbis_lpc_predict(lpc,lpc_in+i+(lpc_samples-lpc_order)*format.channels,
								   lpc_order,paddingBuffer+i,extra_samples,format.channels);
			}
		}
	}
	if(resampler) {
		//fprintf(stderr, "buffered resampler samples: %d\n",bufferedResamplerSamples);
		int ratio = coding_rate/format.samplerate + 1;
		if(bufferedResamplerSamples) {
			float *ptr = resamplerBuffer;
			while(1) {
				spx_uint32_t usedSamples=bufferedResamplerSamples;
				spx_uint32_t outSamples=usedSamples*ratio;
				speex_resampler_process_interleaved_float(resampler,ptr,&usedSamples,input+bufferedSamples*format.channels,&outSamples);
				ptr += usedSamples*format.channels;
				bufferedResamplerSamples -= usedSamples;
				bufferedSamples += outSamples;
				if(!usedSamples || !bufferedResamplerSamples) break;
			}
		}
		if(paddingBuffer) {
			spx_uint32_t usedSamples=extra_samples;
			spx_uint32_t outSamples=extra_samples*ratio;
			speex_resampler_process_interleaved_float(resampler,paddingBuffer,&usedSamples,input+bufferedSamples*format.channels,&outSamples);
			int extra = frame_size - (bufferedSamples - (bufferedSamples/frame_size)*frame_size);
			if(extra>outSamples) extra = outSamples;
			//fprintf(stderr,"extra padding: %d(%d,%d)\n",extra,outSamples,usedSamples);
			bufferedSamples += extra;
			free(paddingBuffer);
		}
	}
	else {
		if(paddingBuffer) {
			int extra = frame_size - (bufferedSamples - (bufferedSamples/frame_size)*frame_size);
			if(extra>extra_samples) extra = extra_samples;
			//fprintf(stderr,"extra padding: %d(%d)\n",extra,extra_samples);
			if(extra) memcpy(input+bufferedSamples*format.channels,paddingBuffer,extra*format.channels*sizeof(float));
			bufferedSamples += extra;
			free(paddingBuffer);
		}
	}
	//fprintf(stderr, "%d,%d\n",bufferedSamples,frame_size);
	while(!op.e_o_s) {
		int size_segments,cur_frame_size;
		pid++;
		
		if(nb_samples<0){
			if(frame_size > bufferedSamples) nb_samples = bufferedSamples;
			else nb_samples = frame_size;
			bufferedSamples -= nb_samples;
			if(nb_samples<frame_size) op.e_o_s=1;
			else op.e_o_s=0;
		}
		op.e_o_s|=eos;
		
		cur_frame_size=frame_size;
		
		if(nb_samples<cur_frame_size)
			for(i=nb_samples*format.channels;i<cur_frame_size*format.channels;i++) input[pos+i]=0;
		
		int nbBytes = opus_multistream_encode_float(st, input+pos, cur_frame_size, packet, max_frame_bytes);
		if(nbBytes < 0) break;
		
		pos += nb_samples*format.channels;
		
		enc_granulepos+=cur_frame_size*48000/coding_rate;
		size_segments=(nbBytes+255)/255;
		while((((size_segments<=255)&&(last_segments+size_segments>255))
			   ||(enc_granulepos-last_granulepos>max_ogg_delay))
			  &&ogg_stream_flush_fill(&os, &og,255*255)) {
			if(ogg_page_packets(&og)!=0)last_granulepos=ogg_page_granulepos(&og);
			last_segments-=og.header[26];
			int ret=oe_write_page(&og, fp);
			if(ret!=og.header_len+og.body_len){
				fprintf(stderr,"Error: failed writing data to output stream\n");
				break;
			}
		}
		
		if((!op.e_o_s)&&max_ogg_delay>5760){
			if(frame_size > bufferedSamples) nb_samples = bufferedSamples;
			else nb_samples = frame_size;
			bufferedSamples -= nb_samples;
			if(nb_samples<frame_size)eos=1;
			if(nb_samples==0)op.e_o_s=1;
		} else nb_samples=-1;
		
		op.packet=(unsigned char *)packet;
		op.bytes=nbBytes;
		op.b_o_s=0;
		op.granulepos=enc_granulepos;
		if(op.e_o_s){
			op.granulepos=((original_samples*48000+format.samplerate-1)/format.samplerate)+header.preskip;
		}
		op.packetno=2+pid;
		ogg_stream_packetin(&os, &op);
		last_segments+=size_segments;
		
		while((op.e_o_s||(enc_granulepos+(frame_size*48000/coding_rate)-last_granulepos>max_ogg_delay)||
			   (last_segments>=255))?
			  ogg_stream_flush_fill(&os, &og,255*255):
			  ogg_stream_pageout_fill(&os, &og,255*255)){
			if(ogg_page_packets(&og)!=0)last_granulepos=ogg_page_granulepos(&og);
			last_segments-=og.header[26];
			int ret=oe_write_page(&og, fp);
			if(ret!=og.header_len+og.body_len){
				fprintf(stderr,"Error: failed writing data to output stream\n");
				break;
			}
		}
	}
	opus_multistream_encoder_destroy(st);
	st = NULL;
	ogg_stream_clear(&os);
}

- (void)closeFile
{
	if(resampler) speex_resampler_destroy(resampler);
	resampler = NULL;
	if(fp) fclose(fp);
	fp = NULL;
}

- (void)setEnableAddTag:(BOOL)flag
{
	addTag = flag;
}

@end
