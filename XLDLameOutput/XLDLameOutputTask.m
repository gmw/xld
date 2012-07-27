//
//  XLDLameOutputTask.m
//  XLDLameOutput
//
//  Created by tmkk on 06/09/08.
//  Copyright 2006 tmkk. All rights reserved.
//

#import "XLDLameOutputTask.h"
#import "XLDLameOutput.h"

typedef int64_t xldoffset_t;

#import "XLDTrack.h"

//extern int id3tag_set_lyrics_utf16(lame_global_flags * gfp, char const *lang, unsigned short const *desc, unsigned short const *text);
extern int id3v2_add_ucs2(lame_t gfp, uint32_t frame_id, char const *lang, unsigned short const *desc, unsigned short const *text);

#define FRAME_ID(a, b, c, d) \
( ((unsigned long)(a) << 24) \
| ((unsigned long)(b) << 16) \
| ((unsigned long)(c) <<  8) \
| ((unsigned long)(d) <<  0) )

void swap_utf16(unsigned short *str)
{
	if(*str == 0xfffe) return;
	while(*str != 0) {
		*str = ((*str >> 8) & 0xff) | (*str << 8);
		str++;
	}
}

@implementation XLDLameOutputTask

- (id)init
{
	[super init];
	
	fp = NULL;
	gfp = NULL;
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
	if(gfp) lame_close(gfp);
	if(configurations) [configurations release];
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
	char *buffer;
	unsigned short desc[2];
	desc[0] = 0xfeff;
	desc[1] = 0;
	fp = fopen([str UTF8String],"w+b");
	if(!fp) return NO;
	
	gfp = lame_init();
	if(!gfp) return NO;
	
	lame_set_in_samplerate(gfp, format.samplerate);
	lame_set_out_samplerate(gfp,[[configurations objectForKey:@"SampleRate"] intValue]);
	lame_set_num_channels(gfp, format.channels);
	if([[configurations objectForKey:@"AppendTLEN"] boolValue]) {
		//NSLog(@"length:%d",[track frames]);
		if([track frames] != -1) lame_set_num_samples(gfp,[track frames]);
		else lame_set_num_samples(gfp,format.samplerate*[track seconds]);
	}
	int lame_quality = [[configurations objectForKey:@"Quality"] intValue];
				
	lame_set_quality(gfp, lame_quality);
	lame_set_findReplayGain(gfp, [[configurations objectForKey:@"UseReplayGain"] boolValue]);
	
	if([[configurations objectForKey:@"EncodeMode"] intValue] == 0) {
		lame_set_VBR(gfp, ([[configurations objectForKey:@"VbrMethod"] intValue] == 0) ? vbr_mtrh : vbr_rh);
		lame_set_VBR_quality(gfp,[[configurations objectForKey:@"VbrQuality"] floatValue]);
	}
	else if([[configurations objectForKey:@"EncodeMode"] intValue] == 2) {
		lame_set_brate(gfp,[[configurations objectForKey:@"Bitrate"] intValue]);
	}
	else {
		if([[configurations objectForKey:@"AbrBitrate"] intValue] > 320) {
			lame_set_free_format(gfp,1);
			lame_set_brate(gfp,[[configurations objectForKey:@"AbrBitrate"] intValue]);
		}
		else {
			lame_set_VBR(gfp, vbr_abr);
			lame_set_VBR_mean_bitrate_kbps(gfp, [[configurations objectForKey:@"AbrBitrate"] intValue]);
		}
	}
	
	if(format.channels == 2 && [[configurations objectForKey:@"StereoMode"] intValue] != XLDLameAutoStereoMode) {
		if([[configurations objectForKey:@"StereoMode"] intValue] == XLDLameJointStereoMode)
			lame_set_mode(gfp, 1);
		else if([[configurations objectForKey:@"StereoMode"] intValue] == XLDLameSimpleStereoMode)
			lame_set_mode(gfp, 0);
		else if([[configurations objectForKey:@"StereoMode"] intValue] == XLDLameMonoStereoMode)
			lame_set_mode(gfp, 3);
	}
	
	if(addTag) {
		id3tag_init(gfp);
		id3tag_v2_only(gfp);
		lame_set_write_id3tag_automatic(gfp, 0);
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLE]) {
			NSData *dat = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLE] dataUsingEncoding:NSUnicodeStringEncoding];
			buffer = (char *)malloc([dat length]+10);
			[dat getBytes:buffer];
			buffer[[dat length]] = 0;
			buffer[[dat length]+1] = 0;
			swap_utf16((unsigned short*)buffer);
			id3tag_set_textinfo_utf16(gfp,"TIT2",(unsigned short *)buffer);
			free(buffer);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTIST]) {
			NSData *dat = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTIST] dataUsingEncoding:NSUnicodeStringEncoding];
			buffer = (char *)malloc([dat length]+10);
			[dat getBytes:buffer];
			buffer[[dat length]] = 0;
			buffer[[dat length]+1] = 0;
			swap_utf16((unsigned short*)buffer);
			id3tag_set_textinfo_utf16(gfp,"TPE1",(unsigned short *)buffer);
			free(buffer);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUM]) {
			NSData *dat = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUM] dataUsingEncoding:NSUnicodeStringEncoding];
			buffer = (char *)malloc([dat length]+10);
			[dat getBytes:buffer];
			buffer[[dat length]] = 0;
			buffer[[dat length]+1] = 0;
			swap_utf16((unsigned short*)buffer);
			id3tag_set_textinfo_utf16(gfp,"TALB",(unsigned short *)buffer);
			free(buffer);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GENRE]) {
			//id3tag_set_genre(gfp,[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GENRE] UTF8String]);
			NSData *dat = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GENRE] dataUsingEncoding:NSUnicodeStringEncoding];
			buffer = (char *)malloc([dat length]+10);
			[dat getBytes:buffer];
			buffer[[dat length]] = 0;
			buffer[[dat length]+1] = 0;
			swap_utf16((unsigned short*)buffer);
			id3tag_set_textinfo_utf16(gfp,"TCON",(unsigned short *)buffer);
			free(buffer);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPOSER]) {
			NSData *dat = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPOSER] dataUsingEncoding:NSUnicodeStringEncoding];
			buffer = (char *)malloc([dat length]+10);
			[dat getBytes:buffer];
			buffer[[dat length]] = 0;
			buffer[[dat length]+1] = 0;
			swap_utf16((unsigned short*)buffer);
			id3tag_set_textinfo_utf16(gfp,"TCOM",(unsigned short *)buffer);
			free(buffer);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TRACK]) {
			if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALTRACKS])
				id3tag_set_track(gfp,[[NSString stringWithFormat:@"%d/%d",[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TRACK] intValue],[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALTRACKS] intValue]] UTF8String]);
			else
				id3tag_set_track(gfp,[[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TRACK] stringValue] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DISC]) {
			if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALDISCS])
				id3tag_set_fieldvalue(gfp,[[NSString stringWithFormat:@"TPOS=%d/%d",[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DISC] intValue],[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALDISCS] intValue]] UTF8String]);
			else
				id3tag_set_fieldvalue(gfp,[[NSString stringWithFormat:@"TPOS=%d",[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DISC] intValue]] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_YEAR]) {
			id3tag_set_year(gfp,[[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_YEAR] stringValue] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMARTIST]) {
			NSData *dat = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMARTIST] dataUsingEncoding:NSUnicodeStringEncoding];
			buffer = (char *)malloc([dat length]+10);
			[dat getBytes:buffer];
			buffer[[dat length]] = 0;
			buffer[[dat length]+1] = 0;
			swap_utf16((unsigned short*)buffer);
			id3tag_set_textinfo_utf16(gfp,"TPE2",(unsigned short *)buffer);
			free(buffer);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GROUP]) {
			NSData *dat = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GROUP] dataUsingEncoding:NSUnicodeStringEncoding];
			buffer = (char *)malloc([dat length]+10);
			[dat getBytes:buffer];
			buffer[[dat length]] = 0;
			buffer[[dat length]+1] = 0;
			swap_utf16((unsigned short*)buffer);
			id3tag_set_textinfo_utf16(gfp,"TIT1",(unsigned short *)buffer);
			free(buffer);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ISRC]) {
			id3tag_set_fieldvalue(gfp,[[NSString stringWithFormat:@"TSRC=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ISRC]] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_BPM]) {
			id3tag_set_fieldvalue(gfp,[[NSString stringWithFormat:@"TBPM=%u",[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_BPM] unsignedIntValue]] UTF8String]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPILATION]) {
			if([[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPILATION] boolValue])
				id3tag_set_fieldvalue(gfp,"TCMP=1");
		}
#if 0
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GAPLESSALBUM] && [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GAPLESSALBUM] boolValue]) {
			id3tag_set_comment_latin1(gfp,"eng","iTunPGAP","1");
		}
#endif
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMMENT]) {
			NSData *dat = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMMENT] dataUsingEncoding:NSUnicodeStringEncoding];
			buffer = (char *)malloc([dat length]+10);
			[dat getBytes:buffer];
			buffer[[dat length]] = 0;
			buffer[[dat length]+1] = 0;
			swap_utf16((unsigned short*)buffer);
			id3tag_set_comment_utf16(gfp,"eng",desc,(unsigned short *)buffer);
			free(buffer);
		}
#ifdef USE_ID3TAG_CUSTOMIZED_LAME
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_LYRICS]) {
			NSData *dat = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_LYRICS] dataUsingEncoding:NSUnicodeStringEncoding];
			buffer = (char *)malloc([dat length]+10);
			[dat getBytes:buffer];
			buffer[[dat length]] = 0;
			buffer[[dat length]+1] = 0;
			swap_utf16((unsigned short*)buffer);
			//id3tag_set_lyrics_utf16(gfp,"eng",desc,(unsigned short *)buffer);
			id3v2_add_ucs2(gfp, FRAME_ID('U', 'S', 'L', 'T'), "eng", desc, (unsigned short *)buffer);
			free(buffer);
		}
#endif
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLESORT]) {
			NSData *dat = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLESORT] dataUsingEncoding:NSUnicodeStringEncoding];
			buffer = (char *)malloc([dat length]+10);
			[dat getBytes:buffer];
			buffer[[dat length]] = 0;
			buffer[[dat length]+1] = 0;
			swap_utf16((unsigned short*)buffer);
			id3tag_set_textinfo_utf16(gfp,"TSOT",(unsigned short *)buffer);
			free(buffer);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTISTSORT]) {
			NSData *dat = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTISTSORT] dataUsingEncoding:NSUnicodeStringEncoding];
			buffer = (char *)malloc([dat length]+10);
			[dat getBytes:buffer];
			buffer[[dat length]] = 0;
			buffer[[dat length]+1] = 0;
			swap_utf16((unsigned short*)buffer);
			id3tag_set_textinfo_utf16(gfp,"TSOP",(unsigned short *)buffer);
			free(buffer);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMSORT]) {
			NSData *dat = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMSORT] dataUsingEncoding:NSUnicodeStringEncoding];
			buffer = (char *)malloc([dat length]+10);
			[dat getBytes:buffer];
			buffer[[dat length]] = 0;
			buffer[[dat length]+1] = 0;
			swap_utf16((unsigned short*)buffer);
			id3tag_set_textinfo_utf16(gfp,"TSOA",(unsigned short *)buffer);
			free(buffer);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMARTISTSORT]) {
			NSData *dat = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMARTISTSORT] dataUsingEncoding:NSUnicodeStringEncoding];
			buffer = (char *)malloc([dat length]+10);
			[dat getBytes:buffer];
			buffer[[dat length]] = 0;
			buffer[[dat length]+1] = 0;
			swap_utf16((unsigned short*)buffer);
			id3tag_set_textinfo_utf16(gfp,"TSO2",(unsigned short *)buffer);
			free(buffer);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPOSERSORT]) {
			NSData *dat = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPOSERSORT] dataUsingEncoding:NSUnicodeStringEncoding];
			buffer = (char *)malloc([dat length]+10);
			[dat getBytes:buffer];
			buffer[[dat length]] = 0;
			buffer[[dat length]+1] = 0;
			swap_utf16((unsigned short*)buffer);
			id3tag_set_textinfo_utf16(gfp,"TSOC",(unsigned short *)buffer);
			free(buffer);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GRACENOTE2]) {
			NSString *value = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GRACENOTE2];
			NSData *dat = [value dataUsingEncoding:NSISOLatin1StringEncoding];
			buffer = (char *)malloc([dat length]+10);
			[dat getBytes:buffer];
			buffer[[dat length]] = 0;
			id3tag_set_comment_latin1(gfp,"eng","iTunes_CDDB_1",buffer);
			free(buffer);
			if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TRACK]) {
				NSString *value = [NSString stringWithFormat:@"%d",[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TRACK] intValue]];
				NSData *dat = [value dataUsingEncoding:NSISOLatin1StringEncoding];
				buffer = (char *)malloc([dat length]+10);
				[dat getBytes:buffer];
				buffer[[dat length]] = 0;
				id3tag_set_comment_latin1(gfp,"eng","iTunes_CDDB_TrackNumber",buffer);
				free(buffer);
			}
		}
#ifdef USE_ID3TAG_CUSTOMIZED_LAME
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_TRACKID]) {
			NSString *value = [NSString stringWithFormat:@"UFID=http://musicbrainz.org=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_TRACKID]];
			NSData *dat = [value dataUsingEncoding:NSISOLatin1StringEncoding];
			buffer = (char *)malloc([dat length]+10);
			[dat getBytes:buffer];
			buffer[[dat length]] = 0;
			id3tag_set_fieldvalue(gfp,buffer);
			free(buffer);
		}
#else
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_TRACKID]) {
			NSString *value = [NSString stringWithFormat:@"TXXX=MusicBrainz Track Id=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_TRACKID]];
			NSData *dat = [value dataUsingEncoding:NSISOLatin1StringEncoding];
			buffer = (char *)malloc([dat length]+10);
			[dat getBytes:buffer];
			buffer[[dat length]] = 0;
			id3tag_set_fieldvalue(gfp,buffer);
			free(buffer);
		}
#endif
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMID]) {
			NSString *value = [NSString stringWithFormat:@"TXXX=MusicBrainz Album Id=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMID]];
			NSData *dat = [value dataUsingEncoding:NSISOLatin1StringEncoding];
			buffer = (char *)malloc([dat length]+10);
			[dat getBytes:buffer];
			buffer[[dat length]] = 0;
			id3tag_set_fieldvalue(gfp,buffer);
			free(buffer);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ARTISTID]) {
			NSString *value = [NSString stringWithFormat:@"TXXX=MusicBrainz Artist Id=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ARTISTID]];
			NSData *dat = [value dataUsingEncoding:NSISOLatin1StringEncoding];
			buffer = (char *)malloc([dat length]+10);
			[dat getBytes:buffer];
			buffer[[dat length]] = 0;
			id3tag_set_fieldvalue(gfp,buffer);
			free(buffer);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMARTISTID]) {
			NSString *value = [NSString stringWithFormat:@"TXXX=MusicBrainz Album Artist Id=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMARTISTID]];
			NSData *dat = [value dataUsingEncoding:NSISOLatin1StringEncoding];
			buffer = (char *)malloc([dat length]+10);
			[dat getBytes:buffer];
			buffer[[dat length]] = 0;
			id3tag_set_fieldvalue(gfp,buffer);
			free(buffer);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_DISCID]) {
			NSString *value = [NSString stringWithFormat:@"TXXX=MusicBrainz Disc Id=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_DISCID]];
			NSData *dat = [value dataUsingEncoding:NSISOLatin1StringEncoding];
			buffer = (char *)malloc([dat length]+10);
			[dat getBytes:buffer];
			buffer[[dat length]] = 0;
			id3tag_set_fieldvalue(gfp,buffer);
			free(buffer);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_PUID]) {
			NSString *value = [NSString stringWithFormat:@"TXXX=MusicIP PUID=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_PUID]];
			NSData *dat = [value dataUsingEncoding:NSISOLatin1StringEncoding];
			buffer = (char *)malloc([dat length]+10);
			[dat getBytes:buffer];
			buffer[[dat length]] = 0;
			id3tag_set_fieldvalue(gfp,buffer);
			free(buffer);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMSTATUS]) {
			NSString *value = [NSString stringWithFormat:@"TXXX=MusicBrainz Album Status=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMSTATUS]];
			NSData *dat = [value dataUsingEncoding:NSUnicodeStringEncoding];
			buffer = (char *)malloc([dat length]+10);
			[dat getBytes:buffer];
			buffer[[dat length]] = 0;
			buffer[[dat length]+1] = 0;
			swap_utf16((unsigned short*)buffer);
			id3tag_set_fieldvalue_utf16(gfp,(unsigned short *)buffer);
			free(buffer);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMTYPE]) {
			NSString *value = [NSString stringWithFormat:@"TXXX=MusicBrainz Album Type=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMTYPE]];
			NSData *dat = [value dataUsingEncoding:NSUnicodeStringEncoding];
			buffer = (char *)malloc([dat length]+10);
			[dat getBytes:buffer];
			buffer[[dat length]] = 0;
			buffer[[dat length]+1] = 0;
			swap_utf16((unsigned short*)buffer);
			id3tag_set_fieldvalue_utf16(gfp,(unsigned short *)buffer);
			free(buffer);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASECOUNTRY]) {
			NSString *value = [NSString stringWithFormat:@"TXXX=MusicBrainz Album Release Country=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASECOUNTRY]];
			NSData *dat = [value dataUsingEncoding:NSUnicodeStringEncoding];
			buffer = (char *)malloc([dat length]+10);
			[dat getBytes:buffer];
			buffer[[dat length]] = 0;
			buffer[[dat length]+1] = 0;
			swap_utf16((unsigned short*)buffer);
			id3tag_set_fieldvalue_utf16(gfp,(unsigned short *)buffer);
			free(buffer);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASEGROUPID]) {
			NSString *value = [NSString stringWithFormat:@"TXXX=MusicBrainz Release Group Id=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASEGROUPID]];
			NSData *dat = [value dataUsingEncoding:NSISOLatin1StringEncoding];
			buffer = (char *)malloc([dat length]+10);
			[dat getBytes:buffer];
			buffer[[dat length]] = 0;
			id3tag_set_fieldvalue(gfp,buffer);
			free(buffer);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_WORKID]) {
			NSString *value = [NSString stringWithFormat:@"TXXX=MusicBrainz Work Id=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_WORKID]];
			NSData *dat = [value dataUsingEncoding:NSISOLatin1StringEncoding];
			buffer = (char *)malloc([dat length]+10);
			[dat getBytes:buffer];
			buffer[[dat length]] = 0;
			id3tag_set_fieldvalue(gfp,buffer);
			free(buffer);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COVER]) {
			NSData *imgDat = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COVER];
			id3tag_set_albumart(gfp, [imgDat bytes], [imgDat length]);
		}
	}
	
	int ret = lame_init_params(gfp);
	if(ret < 0) return NO;
	
	size_t id3v2_size = lame_get_id3v2_tag(gfp, 0, 0);
	if(id3v2_size > 0) {
		unsigned char *id3v2tag = malloc(id3v2_size);
		if(id3v2tag) {
			int ret = lame_get_id3v2_tag(gfp, id3v2tag, id3v2_size);
			fwrite(id3v2tag, 1, ret, fp);
			free(id3v2tag);
		}
	}
	
	return YES;
}

- (NSString *)extensionStr
{
	return @"mp3";
}

- (BOOL)writeBuffer:(int *)buffer frames:(int)counts
{
	int sizeof_buffer = 1.25*counts*2 + 7200;
	unsigned char *mp3buffer = (unsigned char *)malloc(sizeof_buffer);
	int *buffer_l = (int *)malloc(counts*4+3);
	int *buffer_r = (int *)malloc(counts*4+3);
	int i;
	
	if(format.isFloat) {
		for(i=0;i<counts*format.channels;i++) {
			*((float *)buffer+i) *= 32768.0f;
		}
	}
	
	if(format.channels == 1) {
		memcpy(buffer_l,buffer,counts*4);
	}
	else {
		for(i=0;i<counts;i++) {
			buffer_l[i] = buffer[i*2];
			buffer_r[i] = buffer[i*2+1];
		}
	}
	
	int ret;
	if(format.isFloat) ret = lame_encode_buffer_float(gfp,(float *)buffer_l,(float *)buffer_r,counts,mp3buffer,sizeof_buffer);
	else ret = lame_encode_buffer_int(gfp,buffer_l,buffer_r,counts,mp3buffer,sizeof_buffer);
	
	if(ret < 0) {
		free(mp3buffer);
		free(buffer_l);
		free(buffer_r);
		return NO;
	}
	
	fwrite(mp3buffer,1,ret,fp);
	
	free(mp3buffer);
	free(buffer_l);
	free(buffer_r);
	
	return YES;
}

- (void)finalize
{
	unsigned char *mp3buffer = (unsigned char *)malloc(10000);
	int ret = lame_encode_flush(gfp,mp3buffer,10000);
	
	fwrite(mp3buffer,1,ret,fp);
	lame_mp3_tags_fid(gfp,fp);
	
	free(mp3buffer);
}

- (void)closeFile
{
	if(fp) fclose(fp);
	fp = NULL;
	if(gfp) lame_close(gfp);
	gfp = NULL;
}

- (void)setEnableAddTag:(BOOL)flag
{
	addTag = flag;
}

@end
