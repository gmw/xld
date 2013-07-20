//
//  XLDVorbisOutputTask.m
//  XLDVorbisOutput
//
//  Created by tmkk on 06/09/08.
//  Copyright 2006 tmkk. All rights reserved.
//

#import <openssl/bio.h>
#import <openssl/evp.h>
#import <openssl/buffer.h>
#import "XLDVorbisOutputTask.h"
#import "XLDVorbisOutput.h"

typedef int64_t xldoffset_t;

#import "XLDTrack.h"

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

@implementation XLDVorbisOutputTask

- (id)init
{
	[super init];
	eos = 0;
	fp = NULL;
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
	[super dealloc];
}

- (BOOL)setOutputFormat:(XLDFormat)fmt
{
	format = fmt;
	
	if(format.bps > 4) return NO;
	vorbis_info_init(&vi);
	int ret = vorbis_encode_init_vbr(&vi,format.channels,format.samplerate,[[configurations objectForKey:@"Quality"] floatValue]);
	vorbis_info_clear(&vi);
	if(ret){
		return NO;
	}
	
	return YES;
}

- (BOOL)openFileForOutput:(NSString *)str withTrackData:(id)track
{
	int i;
	fp = fopen([str UTF8String], "wb");
	if(!fp) {
		return NO;
	}
	vorbis_info_init(&vi);
	int ret = vorbis_encode_init_vbr(&vi,format.channels,format.samplerate,[[configurations objectForKey:@"Quality"] floatValue]);
	if(ret){
		return NO;
	}
	
	vorbis_comment_init(&vc);
	vorbis_comment_add_tag(&vc,"ENCODER",(char *)[[NSString stringWithFormat:@"X Lossless Decoder %@",[[NSBundle mainBundle] objectForInfoDictionaryKey: @"CFBundleShortVersionString"]] UTF8String]);
	if(addTag) {
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLE]) {
			vorbis_comment_add_tag(&vc,"TITLE",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLE] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTIST]) {
			vorbis_comment_add_tag(&vc,"ARTIST",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTIST] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUM]) {
			vorbis_comment_add_tag(&vc,"ALBUM",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUM] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMARTIST]) {
			vorbis_comment_add_tag(&vc,"ALBUMARTIST",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMARTIST] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GENRE]) {
			vorbis_comment_add_tag(&vc,"GENRE",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GENRE] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPOSER]) {
			vorbis_comment_add_tag(&vc,"COMPOSER",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPOSER] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TRACK]) {
			vorbis_comment_add_tag(&vc,"TRACKNUMBER",(char *)[[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TRACK] stringValue] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALTRACKS]) {
			vorbis_comment_add_tag(&vc,"TRACKTOTAL",(char *)[[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALTRACKS] stringValue] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DISC]) {
			vorbis_comment_add_tag(&vc,"DISCNUMBER",(char *)[[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DISC] stringValue] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALDISCS]) {
			vorbis_comment_add_tag(&vc,"DISCTOTAL",(char *)[[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALDISCS] stringValue] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DATE]) {
			vorbis_comment_add_tag(&vc,"DATE",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DATE] UTF8String]);
		}
		else if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_YEAR]) {
			vorbis_comment_add_tag(&vc,"DATE",(char *)[[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_YEAR] stringValue] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GROUP]) {
			vorbis_comment_add_tag(&vc,"CONTENTGROUP",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GROUP] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMMENT]) {
			vorbis_comment_add_tag(&vc,"COMMENT",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMMENT] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ISRC]) {
			vorbis_comment_add_tag(&vc,"ISRC",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ISRC] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_CATALOG]) {
			vorbis_comment_add_tag(&vc,"MCN",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_CATALOG] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPILATION]) {
			vorbis_comment_add_tag(&vc,"COMPILATION",(char *)[[NSString stringWithFormat:@"%d",[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPILATION] intValue]] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLESORT]) {
			vorbis_comment_add_tag(&vc,"TITLESORT",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLESORT] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTISTSORT]) {
			vorbis_comment_add_tag(&vc,"ARTISTSORT",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTISTSORT] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMSORT]) {
			vorbis_comment_add_tag(&vc,"ALBUMSORT",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMSORT] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMARTISTSORT]) {
			vorbis_comment_add_tag(&vc,"ALBUMARTISTSORT",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMARTISTSORT] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPOSERSORT]) {
			vorbis_comment_add_tag(&vc,"COMPOSERSORT",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPOSERSORT] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GRACENOTE2]) {
			vorbis_comment_add_tag(&vc,"iTunes_CDDB_1",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GRACENOTE2] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_TRACKID]) {
			vorbis_comment_add_tag(&vc,"MUSICBRAINZ_TRACKID",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_TRACKID] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMID]) {
			vorbis_comment_add_tag(&vc,"MUSICBRAINZ_ALBUMID",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMID] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ARTISTID]) {
			vorbis_comment_add_tag(&vc,"MUSICBRAINZ_ARTISTID",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ARTISTID] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMARTISTID]) {
			vorbis_comment_add_tag(&vc,"MUSICBRAINZ_ALBUMARTISTID",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMARTISTID] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_DISCID]) {
			vorbis_comment_add_tag(&vc,"MUSICBRAINZ_DISCID",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_DISCID] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_PUID]) {
			vorbis_comment_add_tag(&vc,"MUSICIP_PUID",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_PUID] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMSTATUS]) {
			vorbis_comment_add_tag(&vc,"MUSICBRAINZ_ALBUMSTATUS",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMSTATUS] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMTYPE]) {
			vorbis_comment_add_tag(&vc,"MUSICBRAINZ_ALBUMTYPE",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMTYPE] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASECOUNTRY]) {
			vorbis_comment_add_tag(&vc,"RELEASECOUNTRY",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASECOUNTRY] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASEGROUPID]) {
			vorbis_comment_add_tag(&vc,"MUSICBRAINZ_RELEASEGROUPID",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASEGROUPID] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_WORKID]) {
			vorbis_comment_add_tag(&vc,"MUSICBRAINZ_WORKID",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_WORKID] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_SMPTE_TIMECODE_START]) {
			vorbis_comment_add_tag(&vc,"SMPTE_TIMECODE_START",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_SMPTE_TIMECODE_START] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_SMPTE_TIMECODE_DURATION]) {
			vorbis_comment_add_tag(&vc,"SMPTE_TIMECODE_DURATION",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_SMPTE_TIMECODE_DURATION] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MEDIA_FPS]) {
			vorbis_comment_add_tag(&vc,"MEDIA_FPS",(char *)[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MEDIA_FPS] UTF8String]);
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
					vorbis_comment_add_tag(&vc,"METADATA_BLOCK_PICTURE",encodedData);
					free(encodedData);
				}
			}
		}
		NSArray *keyArr = [[(XLDTrack *)track metadata] allKeys];
		for(i=[keyArr count]-1;i>=0;i--) {
			NSString *key = [keyArr objectAtIndex:i];
			NSRange range = [key rangeOfString:@"XLD_UNKNOWN_TEXT_METADATA_"];
			if(range.location != 0) continue;
			const char *idx = [[key substringFromIndex:range.length] UTF8String];
			const char *dat = [[[(XLDTrack *)track metadata] objectForKey:key] UTF8String];
			vorbis_comment_add_tag(&vc,(char *)idx,(char *)dat);
		}
	}
	vorbis_analysis_init(&vd,&vi);
	vorbis_block_init(&vd,&vb);
	ogg_stream_init(&os,rand());
	
	ogg_packet header;
	ogg_packet header_comm;
	ogg_packet header_code;
	
	vorbis_analysis_headerout(&vd,&vc,&header,&header_comm,&header_code);
	ogg_stream_packetin(&os,&header);
	ogg_stream_packetin(&os,&header_comm);
	ogg_stream_packetin(&os,&header_code);
	
	while(1){
		int result=ogg_stream_flush(&os,&og);
		if(result==0) break;
		fwrite(og.header,1,og.header_len,fp);
		fwrite(og.body,1,og.body_len,fp);
	}
	
	return YES;
}

- (NSString *)extensionStr
{
	return @"ogg";
}

- (BOOL)writeBuffer:(int *)buffer frames:(int)counts
{
	if(eos) return NO;
	float **buffer_converted;
	int i,j,k;
	buffer_converted = vorbis_analysis_buffer(&vd,counts);
	for(i=0,k=0;i<counts;i++){
		for(j=0;j<format.channels;j++) {
			switch(format.bps) {
				case 1:
					buffer_converted[j][i] = (buffer[k++] >> 24)/128.0f;
					break;
				case 2:
					buffer_converted[j][i] = (buffer[k++] >> 16)/32768.0f;
					break;
				case 3:
					buffer_converted[j][i] = (buffer[k++] >> 8)/8388608.0f;
					break;
				case 4:
					if(format.isFloat) buffer_converted[j][i] = *((float *)buffer+(k++));
					else buffer_converted[j][i] = buffer[k++]/2147483648.0f;
					break;
			}
		}
	}
	vorbis_analysis_wrote(&vd,counts);
	
	while(vorbis_analysis_blockout(&vd,&vb)==1){
		vorbis_analysis(&vb,NULL);
		vorbis_bitrate_addblock(&vb);
		while(vorbis_bitrate_flushpacket(&vd,&op)){
			ogg_stream_packetin(&os,&op);
			while(!eos){
				int result=ogg_stream_pageout(&os,&og);
				if(result==0)break;
				fwrite(og.header,1,og.header_len,fp);
				fwrite(og.body,1,og.body_len,fp);
				if(ogg_page_eos(&og))eos=1;
			}
		}
	}
	return YES;
}

- (void)finalize
{
	vorbis_analysis_wrote(&vd,0);
	while(vorbis_analysis_blockout(&vd,&vb)==1){
		vorbis_analysis(&vb,NULL);
		vorbis_bitrate_addblock(&vb);
		while(vorbis_bitrate_flushpacket(&vd,&op)){
			ogg_stream_packetin(&os,&op);
			while(!eos){
				int result=ogg_stream_pageout(&os,&og);
				if(result==0)break;
				fwrite(og.header,1,og.header_len,fp);
				fwrite(og.body,1,og.body_len,fp);
				if(ogg_page_eos(&og))eos=1;
			}
		}
	}
	
	ogg_stream_clear(&os);
	vorbis_block_clear(&vb);
	vorbis_dsp_clear(&vd);
	vorbis_comment_clear(&vc);
	vorbis_info_clear(&vi);
}

- (void)closeFile
{
	if(fp) fclose(fp);
	fp = NULL;
	eos = 0;
}

- (void)setEnableAddTag:(BOOL)flag
{
	addTag = flag;
}

@end
