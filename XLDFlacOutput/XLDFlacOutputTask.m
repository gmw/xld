//
//  XLDFlacOutputTask.m
//  XLDFlacOutput
//
//  Created by tmkk on 06/09/15.
//  Copyright 2006 tmkk. All rights reserved.
//

#import "XLDFlacOutputTask.h"
#import "XLDFlacOutput.h"

typedef int64_t xldoffset_t;

#import "XLDTrack.h"

@implementation XLDFlacOutputTask

- (id)init
{
	[super init];
	addTag = NO;
	internalBuffer = NULL;
	path = nil;
	encoder = NULL;
	tag = NULL;
	st = NULL;
	picture = NULL;
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
	if(tag) FLAC__metadata_object_delete(tag);
	if(st) FLAC__metadata_object_delete(st);
	if(encoder) FLAC__stream_encoder_delete(encoder);
	if(picture) FLAC__metadata_object_delete(picture);
	if(internalBuffer) free(internalBuffer);
	if(path) [path release];
	if(configurations) [configurations release];
	if(metadataDic) [metadataDic release];
	[super dealloc];
}

- (BOOL)setOutputFormat:(XLDFormat)fmt
{
	if(fmt.isFloat) return NO;
	if(fmt.channels <= 0 || fmt.channels > FLAC__MAX_CHANNELS) return NO;
	if(fmt.bps > FLAC__REFERENCE_CODEC_MAX_BITS_PER_SAMPLE/8) return NO;
	format = fmt;
	internalBufferSize = 16384*4*fmt.channels;
	if(internalBuffer) free(internalBuffer);
	internalBuffer = (int *)malloc(internalBufferSize);
	return YES;
}

- (BOOL)openFileForOutput:(NSString *)str withTrackData:(id)track
{
	int ret;
	encoder = FLAC__stream_encoder_new();
	
	FLAC__stream_encoder_set_channels(encoder, (unsigned)format.channels);
	FLAC__stream_encoder_set_bits_per_sample(encoder, (unsigned)format.bps*8);
	FLAC__stream_encoder_set_sample_rate(encoder, (unsigned)format.samplerate);
	if([(XLDTrack *)track frames] > 0)
		FLAC__stream_encoder_set_total_samples_estimate(encoder, [(XLDTrack *)track frames]);
	else FLAC__stream_encoder_set_total_samples_estimate(encoder, 0);
	
	/* set up metadata */
	FLAC__StreamMetadata *metadata[5];
	
	st = FLAC__metadata_object_new(FLAC__METADATA_TYPE_SEEKTABLE);
	int i;
	for(i=0;i<=[track seconds]/10;i++) {
		FLAC__metadata_object_seektable_template_append_point(st,i*10*format.samplerate);
	}
	FLAC__metadata_object_seektable_template_sort(st,true);
	metadata[0] = st;
	
	FLAC__StreamMetadata_VorbisComment_Entry entry;
	tag = FLAC__metadata_object_new(FLAC__METADATA_TYPE_VORBIS_COMMENT);
	entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"ENCODER=X Lossless Decoder %@",[[NSBundle mainBundle] objectForInfoDictionaryKey: @"CFBundleShortVersionString"]] UTF8String];
	entry.length = strlen((char *)entry.entry);
	FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
	if(addTag) {
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLE]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"TITLE=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLE]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTIST]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"ARTIST=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTIST]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUM]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"ALBUM=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUM]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GENRE]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"GENRE=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GENRE]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPOSER]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"COMPOSER=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPOSER]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMARTIST]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"ALBUMARTIST=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMARTIST]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TRACK]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"TRACKNUMBER=%d",[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TRACK] intValue]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALTRACKS]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"TRACKTOTAL=%d",[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALTRACKS] intValue]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALTRACKS]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"TOTALTRACKS=%d",[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALTRACKS] intValue]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DISC]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"DISCNUMBER=%d",[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DISC] intValue]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALDISCS]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"DISCTOTAL=%d",[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALDISCS] intValue]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALDISCS]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"TOTALDISCS=%d",[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALDISCS] intValue]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DATE]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"DATE=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DATE]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		else if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_YEAR]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"DATE=%d",[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_YEAR] intValue]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GROUP]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"CONTENTGROUP=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GROUP]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMMENT]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"COMMENT=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMMENT]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_CUESHEET] && [[configurations objectForKey:@"AllowEmbeddedCuesheet"] boolValue]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"CUESHEET=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_CUESHEET]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ISRC]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"ISRC=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ISRC]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_CATALOG]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"MCN=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_CATALOG]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPILATION]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"COMPILATION=%d",[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPILATION] intValue]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLESORT]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"TITLESORT=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLESORT]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTISTSORT]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"ARTISTSORT=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTISTSORT]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMSORT]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"ALBUMSORT=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMSORT]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMARTISTSORT]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"ALBUMARTISTSORT=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMARTISTSORT]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPOSERSORT]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"COMPOSERSORT=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPOSERSORT]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GRACENOTE2]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"iTunes_CDDB_1=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GRACENOTE2]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_TRACKID]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"MUSICBRAINZ_TRACKID=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_TRACKID]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMID]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"MUSICBRAINZ_ALBUMID=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMID]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ARTISTID]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"MUSICBRAINZ_ARTISTID=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ARTISTID]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMARTISTID]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"MUSICBRAINZ_ALBUMARTISTID=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMARTISTID]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_DISCID]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"MUSICBRAINZ_DISCID=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_DISCID]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_PUID]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"MUSICIP_PUID=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_PUID]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMSTATUS]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"MUSICBRAINZ_ALBUMSTATUS=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMSTATUS]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMTYPE]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"MUSICBRAINZ_ALBUMTYPE=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMTYPE]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASECOUNTRY]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"RELEASECOUNTRY=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASECOUNTRY]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASEGROUPID]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"MUSICBRAINZ_RELEASEGROUPID=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASEGROUPID]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_WORKID]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"MUSICBRAINZ_WORKID=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_WORKID]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_REPLAYGAIN_TRACK_GAIN]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"REPLAYGAIN_TRACK_GAIN=%+.2f dB",[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_REPLAYGAIN_TRACK_GAIN] floatValue]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_REPLAYGAIN_TRACK_PEAK]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"REPLAYGAIN_TRACK_PEAK=%.8f",[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_REPLAYGAIN_TRACK_PEAK] floatValue]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_REPLAYGAIN_ALBUM_GAIN]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"REPLAYGAIN_ALBUM_GAIN=%+.2f dB",[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_REPLAYGAIN_ALBUM_GAIN] floatValue]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_REPLAYGAIN_ALBUM_PEAK]) {
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"REPLAYGAIN_ALBUM_PEAK=%.8f",[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_REPLAYGAIN_ALBUM_PEAK] floatValue]] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COVER]) {
			NSData *imgData = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COVER];
			NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:imgData];
			if(rep) {
				picture = FLAC__metadata_object_new(FLAC__METADATA_TYPE_PICTURE);
				FLAC__metadata_object_picture_set_data(picture, (FLAC__byte *)[imgData bytes], [imgData length], true);
				picture->data.picture.width = [rep pixelsWide];
				picture->data.picture.height = [rep pixelsHigh];
				picture->data.picture.type = FLAC__STREAM_METADATA_PICTURE_TYPE_FRONT_COVER;
				picture->data.picture.depth = [rep bitsPerPixel];
				if(picture->data.picture.data_length >= 8 && 0 == memcmp(picture->data.picture.data, "\x89PNG\x0d\x0a\x1a\x0a", 8))
					FLAC__metadata_object_picture_set_mime_type(picture, "image/png", true);
				else if(picture->data.picture.data_length >= 6 && (0 == memcmp(picture->data.picture.data, "GIF87a", 6) || 0 == memcmp(picture->data.picture.data, "GIF89a", 6))) {
					FLAC__metadata_object_picture_set_mime_type(picture, "image/gif", true);
					picture->data.picture.colors = 256;
				}
				else if(picture->data.picture.data_length >= 2 && 0 == memcmp(picture->data.picture.data, "\xff\xd8", 2))
					FLAC__metadata_object_picture_set_mime_type(picture, "image/jpeg", true);
				//int ret = FLAC__metadata_object_picture_is_legal(picture,&mime);
				//NSLog(@"%d,%s",ret,mime);
			}
		}
		NSArray *keyArr = [[(XLDTrack *)track metadata] allKeys];
		for(i=[keyArr count]-1;i>=0;i--) {
			NSString *key = [keyArr objectAtIndex:i];
			NSRange range = [key rangeOfString:@"XLD_UNKNOWN_TEXT_METADATA_"];
			if(range.location != 0) continue;
			NSString *idx = [key substringFromIndex:range.length];
			NSString *dat = [[(XLDTrack *)track metadata] objectForKey:key];
			entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"%@=%@",idx,dat] UTF8String];
			entry.length = strlen((char *)entry.entry);
			FLAC__metadata_object_vorbiscomment_append_comment(tag,entry,true);
		}
	}
	metadata[1] = tag;
	
	FLAC__StreamMetadata padding;
	padding.is_last = false; /* the encoder will set this for us */
	padding.type = FLAC__METADATA_TYPE_PADDING;
	padding.length = [[configurations objectForKey:@"Padding"] intValue]*1024;
	metadata[2] = &padding;
	
	if(picture) {
		metadata[3] = picture;
	}
	
	metadataDic = [[(XLDTrack *)track metadata] retain];
	
	FLAC__stream_encoder_set_metadata(encoder,metadata,picture ? 4 : 3);
	
	int level = [[configurations objectForKey:@"CompressionLevel"] intValue];
	if(level >= 0) {
		FLAC__stream_encoder_set_compression_level(encoder,level);
		if(format.channels != 2) {
			FLAC__stream_encoder_set_do_mid_side_stereo(encoder, false);
			FLAC__stream_encoder_set_loose_mid_side_stereo(encoder, false);
		}
		NSString *apodization = [configurations objectForKey:@"Apodization"];
		if(apodization && ![apodization isEqualToString:@""]) {
			NSMutableString *str = [NSMutableString stringWithString:apodization];
			[str replaceOccurrencesOfString:@" " withString:@"" options:0 range:NSMakeRange(0, [str length])];
			FLAC__stream_encoder_set_apodization(encoder,[str UTF8String]);
		}
	}
	else {
		FLAC__stream_encoder_disable_constant_subframes(encoder,true);
		FLAC__stream_encoder_disable_fixed_subframes(encoder,true);
		FLAC__stream_encoder_disable_verbatim_subframes(encoder,false);
		FLAC__stream_encoder_set_do_mid_side_stereo(encoder, false);
		FLAC__stream_encoder_set_loose_mid_side_stereo(encoder, false);
	}
	
	if([[configurations objectForKey:@"OggFlac"] boolValue]) {
		FLAC__stream_encoder_set_ogg_serial_number(encoder,(long)rand());
		ret = FLAC__stream_encoder_init_ogg_file(encoder,[str UTF8String],NULL,NULL);
	}
	else ret = FLAC__stream_encoder_init_file(encoder,[str UTF8String],NULL,NULL);
	
	if(ret != FLAC__STREAM_ENCODER_INIT_STATUS_OK) return NO;
	
	path = [str retain];
	
	return YES;
}

- (NSString *)extensionStr
{
	if([[configurations objectForKey:@"OggFlac"] boolValue]) return @"oga";
	else return @"flac";
}

- (BOOL)writeBuffer:(int *)buffer frames:(int)counts
{
	int i;
	if(internalBufferSize < counts*format.channels*4) internalBuffer = realloc(internalBuffer, counts*format.channels*4);
	int samples = counts*format.channels;
	int shamt = 32-format.bps*8;
	for(i=0;i<samples;i++) {
		internalBuffer[i] = buffer[i] >> shamt;
	}
	int ret = FLAC__stream_encoder_process_interleaved(encoder, internalBuffer, counts);
	if(!ret) return NO;
	return YES;
}

- (void)finalize
{
	FLAC__stream_encoder_finish(encoder);
	
	/* update metadata */
	if(addTag && ([metadataDic objectForKey:XLD_METADATA_REPLAYGAIN_TRACK_GAIN] || [metadataDic objectForKey:XLD_METADATA_REPLAYGAIN_TRACK_PEAK])) {
		FLAC__Metadata_SimpleIterator *mi = FLAC__metadata_simple_iterator_new();
		if(mi) {
			if(encoder) FLAC__stream_encoder_delete(encoder);
			encoder = NULL;
			if(FLAC__metadata_simple_iterator_init(mi,[path fileSystemRepresentation],false,true) == false) goto end;
			do {
				if(FLAC__metadata_simple_iterator_get_block_type(mi) != FLAC__METADATA_TYPE_VORBIS_COMMENT) continue;
				FLAC__StreamMetadata *block = FLAC__metadata_simple_iterator_get_block(mi);
				int idx;
				FLAC__StreamMetadata_VorbisComment_Entry entry;
				if([metadataDic objectForKey:XLD_METADATA_REPLAYGAIN_TRACK_GAIN]) {
					idx = FLAC__metadata_object_vorbiscomment_find_entry_from(block,0,"REPLAYGAIN_TRACK_GAIN");
					entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"REPLAYGAIN_TRACK_GAIN=%+.2f dB",[[metadataDic objectForKey:XLD_METADATA_REPLAYGAIN_TRACK_GAIN] floatValue]] UTF8String];
					entry.length = strlen((char *)entry.entry);
					if(idx < 0) FLAC__metadata_object_vorbiscomment_append_comment(block,entry,true);
					else FLAC__metadata_object_vorbiscomment_set_comment(block,idx,entry,true);
				}
				if([metadataDic objectForKey:XLD_METADATA_REPLAYGAIN_TRACK_PEAK]) {
					idx = FLAC__metadata_object_vorbiscomment_find_entry_from(block,0,"REPLAYGAIN_TRACK_PEAK");
					entry.entry = (FLAC__byte *)[[NSString stringWithFormat:@"REPLAYGAIN_TRACK_PEAK=%.8f",[[metadataDic objectForKey:XLD_METADATA_REPLAYGAIN_TRACK_PEAK] floatValue]] UTF8String];
					entry.length = strlen((char *)entry.entry);
					if(idx < 0) FLAC__metadata_object_vorbiscomment_append_comment(block,entry,true);
					else FLAC__metadata_object_vorbiscomment_set_comment(block,idx,entry,true);
				}
				FLAC__metadata_simple_iterator_set_block(mi,block,true);
				FLAC__metadata_object_delete(block);
				goto end;
			} while(FLAC__metadata_simple_iterator_next(mi) != false);
		end:
			FLAC__metadata_simple_iterator_delete(mi);
		}
	}
	
	if(![[configurations objectForKey:@"SetOggS"] boolValue]) return;
	
	FSRef ref;
	OSErr err;
	FSCatalogInfoBitmap	myInfoWanted = kFSCatInfoFinderInfo;
	FSCatalogInfo		myInfoReceived;
	
	err = FSPathMakeRef((const UInt8*)[path fileSystemRepresentation], &ref, NULL);
	if(err != noErr) return;
	err = FSGetCatalogInfo(&ref, myInfoWanted, &myInfoReceived, NULL, NULL, NULL);
	if(err != noErr) return;
	((FileInfo *)&myInfoReceived.finderInfo)->fileType = 'OggS';
	FSSetCatalogInfo(&ref, myInfoWanted, &myInfoReceived);
}

- (void)closeFile
{
	if(tag) FLAC__metadata_object_delete(tag);
	tag = NULL;
	if(st) FLAC__metadata_object_delete(st);
	st = NULL;
	if(encoder) FLAC__stream_encoder_delete(encoder);
	encoder = NULL;
	if(picture) FLAC__metadata_object_delete(picture);
	picture = NULL;
	if(path) [path release];
	path = nil;
	if(metadataDic) [metadataDic release];
	metadataDic = nil;
}

- (void)setEnableAddTag:(BOOL)flag
{
	addTag = flag;
}

@end
