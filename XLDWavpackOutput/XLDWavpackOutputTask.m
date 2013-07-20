//
//  XLDWavpackOutputTask.m
//  XLDWavpackOutput
//
//  Created by tmkk on 08/05/20.
//  Copyright 2008 tmkk. All rights reserved.
//

#import "XLDWavpackOutputTask.h"
#import "XLDWavpackOutput.h"

typedef int64_t xldoffset_t;

#import "XLDTrack.h"

static int write_block (void *id, void *data, int32_t length)
{
	fileID *fid = (fileID *)id;
	fid->fp = fopen(fid->path,"ab");
	fwrite(data,1,length,fid->fp);
	fclose(fid->fp);
	if(fid->initial_frame_size == -1) fid->initial_frame_size = length;
	return 1;
}

@implementation XLDWavpackOutputTask

- (id)init
{
	[super init];
	wpc = NULL;
	fpwv = NULL;
	fpwvc = NULL;
	internalBuffer = NULL;
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
	if(wpc) [self closeFile];
	if(internalBuffer) free(internalBuffer);
	if(configurations) [configurations release];
	[super dealloc];
}

- (BOOL)setOutputFormat:(XLDFormat)fmt
{
	format = fmt;
	internalBufferSize = 16384*4*fmt.channels;
	internalBuffer = (int *)malloc(internalBufferSize);
	return YES;
}

- (BOOL)openFileForOutput:(NSString *)str withTrackData:(id)track
{
	int i;
	if(wpc) [self closeFile];
	WavpackConfig config;
	memset(&config,0,sizeof(config));
	fpwv = calloc(1,sizeof(fileID));
	fpwv->path = (char *)malloc(1+strlen([str UTF8String]));
	fpwv->initial_frame_size = -1;
	strcpy(fpwv->path,[str UTF8String]);
	if(([[configurations objectForKey:@"Mode"] intValue] == 1) && [[configurations objectForKey:@"CreateCorrectionFile"] boolValue]) {
		fpwvc = calloc(1,sizeof(fileID));
		fpwvc->path = (char *)malloc(1+strlen([[[str stringByDeletingPathExtension] stringByAppendingPathExtension:@"wvc"] UTF8String]));
		fpwvc->initial_frame_size = -1;
		strcpy(fpwvc->path,[[[str stringByDeletingPathExtension] stringByAppendingPathExtension:@"wvc"] UTF8String]);
	}
	wpc = WavpackOpenFileOutput(write_block,(void *)fpwv,(void *)fpwvc);
	if(!wpc) {
		[self closeFile];
		return NO;
	}
	
	config.bytes_per_sample = format.bps;
	config.bits_per_sample = format.bps << 3;
	if (format.channels <= 2)
		config.channel_mask = 0x5 - format.channels;
	else
		config.channel_mask = (1 << format.channels) - 1;
	config.num_channels = format.channels;
	config.sample_rate = format.samplerate;
	config.block_samples = 0;
	if(format.isFloat) config.float_norm_exp = 127;
	switch([[configurations objectForKey:@"Quality"] intValue]) {
		case 0:
			config.flags = CONFIG_FAST_FLAG | CONFIG_MD5_CHECKSUM ;
			break;
		case 2:
			config.flags = CONFIG_HIGH_FLAG | CONFIG_MD5_CHECKSUM ;
			break;
		case 3:
			config.flags = CONFIG_VERY_HIGH_FLAG | CONFIG_MD5_CHECKSUM ;
			break;
		default:
			config.flags = CONFIG_MD5_CHECKSUM;
			break;
	}
	if([[configurations objectForKey:@"Mode"] intValue] == 1) {
		config.flags |= CONFIG_HYBRID_FLAG;
		config.flags |= CONFIG_BITRATE_KBPS;
		if([[configurations objectForKey:@"CreateCorrectionFile"] boolValue]) config.flags |= CONFIG_CREATE_WVC;
		config.bitrate = [[configurations objectForKey:@"Bitrate"] intValue];
	}
	if([[configurations objectForKey:@"ExtraCompression"] boolValue]) {
		config.flags |= CONFIG_EXTRA_MODE;
		config.xmode = [[configurations objectForKey:@"ExtraValue"] intValue];
	}
	if([[configurations objectForKey:@"DynamicNoiseShaping"] boolValue]) {
		config.flags |= CONFIG_DYNAMIC_SHAPING;
	}
	WavpackSetConfiguration(wpc,&config,-1);
	
	WavpackPackInit (wpc);
	tagAdded = NO;
	if(addTag) {
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLE]) {
			const char *tag = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLE] UTF8String];
			WavpackAppendTagItem(wpc,"Title",tag,strlen(tag));
			tagAdded = YES;
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTIST]) {
			const char *tag = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTIST] UTF8String];
			WavpackAppendTagItem(wpc,"Artist",tag,strlen(tag));
			tagAdded = YES;
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUM]) {
			const char *tag = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUM] UTF8String];
			WavpackAppendTagItem(wpc,"Album",tag,strlen(tag));
			tagAdded = YES;
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMARTIST]) {
			const char *tag = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMARTIST] UTF8String];
			WavpackAppendTagItem(wpc,"Album Artist",tag,strlen(tag));
			WavpackAppendTagItem(wpc,"ALBUMARTIST",tag,strlen(tag));
			tagAdded = YES;
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GENRE]) {
			const char *tag = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GENRE] UTF8String];
			WavpackAppendTagItem(wpc,"Genre",tag,strlen(tag));
			tagAdded = YES;
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPOSER]) {
			const char *tag = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPOSER] UTF8String];
			WavpackAppendTagItem(wpc,"Composer",tag,strlen(tag));
			tagAdded = YES;
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TRACK]) {
			const char *tag;
			if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALTRACKS])
				tag = [[NSString stringWithFormat:@"%d/%d",[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TRACK] intValue],[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALTRACKS] intValue]] UTF8String];
			else tag = [[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TRACK] stringValue] UTF8String];
			WavpackAppendTagItem(wpc,"Track",tag,strlen(tag));
			tagAdded = YES;
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DISC]) {
			const char *tag;
			if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALDISCS])
				tag = [[NSString stringWithFormat:@"%d/%d",[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DISC] intValue],[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALDISCS] intValue]] UTF8String];
			else tag = [[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DISC] stringValue] UTF8String];
			WavpackAppendTagItem(wpc,"Disc",tag,strlen(tag));
			tagAdded = YES;
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_YEAR]) {
			const char *tag = [[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_YEAR] stringValue] UTF8String];
			WavpackAppendTagItem(wpc,"Year",tag,strlen(tag));
			tagAdded = YES;
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMMENT]) {
			const char *tag = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMMENT] UTF8String];
			WavpackAppendTagItem(wpc,"Comment",tag,strlen(tag));
			tagAdded = YES;
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_LYRICS]) {
			const char *tag = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_LYRICS] UTF8String];
			WavpackAppendTagItem(wpc,"Lyrics",tag,strlen(tag));
			tagAdded = YES;
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ISRC]) {
			const char *tag = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ISRC] UTF8String];
			WavpackAppendTagItem(wpc,"ISRC",tag,strlen(tag));
			tagAdded = YES;
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GRACENOTE2]) {
			const char *tag = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GRACENOTE2] UTF8String];
			WavpackAppendTagItem(wpc,"iTunes_CDDB_1",tag,strlen(tag));
			tagAdded = YES;
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_TRACKID]) {
			const char *tag = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_TRACKID] UTF8String];
			WavpackAppendTagItem(wpc,"MUSICBRAINZ_TRACKID",tag,strlen(tag));
			tagAdded = YES;
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMID]) {
			const char *tag = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMID] UTF8String];
			WavpackAppendTagItem(wpc,"MUSICBRAINZ_ALBUMID",tag,strlen(tag));
			tagAdded = YES;
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ARTISTID]) {
			const char *tag = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ARTISTID] UTF8String];
			WavpackAppendTagItem(wpc,"MUSICBRAINZ_ARTISTID",tag,strlen(tag));
			tagAdded = YES;
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMARTISTID]) {
			const char *tag = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMARTISTID] UTF8String];
			WavpackAppendTagItem(wpc,"MUSICBRAINZ_ALBUMARTISTID",tag,strlen(tag));
			tagAdded = YES;
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_DISCID]) {
			const char *tag = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_DISCID] UTF8String];
			WavpackAppendTagItem(wpc,"MUSICBRAINZ_DISCID",tag,strlen(tag));
			tagAdded = YES;
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_PUID]) {
			const char *tag = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_PUID] UTF8String];
			WavpackAppendTagItem(wpc,"MUSICIP_PUID",tag,strlen(tag));
			tagAdded = YES;
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMSTATUS]) {
			const char *tag = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMSTATUS] UTF8String];
			WavpackAppendTagItem(wpc,"MUSICBRAINZ_ALBUMSTATUS",tag,strlen(tag));
			tagAdded = YES;
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMTYPE]) {
			const char *tag = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMTYPE] UTF8String];
			WavpackAppendTagItem(wpc,"MUSICBRAINZ_ALBUMTYPE",tag,strlen(tag));
			tagAdded = YES;
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASECOUNTRY]) {
			const char *tag = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASECOUNTRY] UTF8String];
			WavpackAppendTagItem(wpc,"RELEASECOUNTRY",tag,strlen(tag));
			tagAdded = YES;
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASEGROUPID]) {
			const char *tag = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASEGROUPID] UTF8String];
			WavpackAppendTagItem(wpc,"MUSICBRAINZ_RELEASEGROUPID",tag,strlen(tag));
			tagAdded = YES;
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_WORKID]) {
			const char *tag = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_WORKID] UTF8String];
			WavpackAppendTagItem(wpc,"MUSICBRAINZ_WORKID",tag,strlen(tag));
			tagAdded = YES;
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_SMPTE_TIMECODE_START]) {
			const char *tag = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_SMPTE_TIMECODE_START] UTF8String];
			WavpackAppendTagItem(wpc,"SMPTE_TIMECODE_START",tag,strlen(tag));
			tagAdded = YES;
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_SMPTE_TIMECODE_DURATION]) {
			const char *tag = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_SMPTE_TIMECODE_DURATION] UTF8String];
			WavpackAppendTagItem(wpc,"SMPTE_TIMECODE_DURATION",tag,strlen(tag));
			tagAdded = YES;
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MEDIA_FPS]) {
			const char *tag = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MEDIA_FPS] UTF8String];
			WavpackAppendTagItem(wpc,"MEDIA_FPS",tag,strlen(tag));
			tagAdded = YES;
		}
		if(!(config.flags & CONFIG_HYBRID_FLAG)) {
			if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_REPLAYGAIN_TRACK_GAIN]) {
				const char *tag = [[NSString stringWithFormat:@"%+.2f dB",[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_REPLAYGAIN_TRACK_GAIN] floatValue]] UTF8String];
				WavpackAppendTagItem(wpc,"REPLAYGAIN_TRACK_GAIN",tag,strlen(tag));
				tagAdded = YES;
			}
			if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_REPLAYGAIN_TRACK_PEAK]) {
				const char *tag = [[NSString stringWithFormat:@"%.7f",[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_REPLAYGAIN_TRACK_PEAK] floatValue]] UTF8String];
				WavpackAppendTagItem(wpc,"REPLAYGAIN_TRACK_PEAK",tag,strlen(tag));
				tagAdded = YES;
			}
			if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_REPLAYGAIN_ALBUM_GAIN]) {
				const char *tag = [[NSString stringWithFormat:@"%+.2f dB",[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_REPLAYGAIN_ALBUM_GAIN] floatValue]] UTF8String];
				WavpackAppendTagItem(wpc,"REPLAYGAIN_ALBUM_GAIN",tag,strlen(tag));
				tagAdded = YES;
			}
			if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_REPLAYGAIN_ALBUM_PEAK]) {
				const char *tag = [[NSString stringWithFormat:@"%.7f",[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_REPLAYGAIN_ALBUM_PEAK] floatValue]] UTF8String];
				WavpackAppendTagItem(wpc,"REPLAYGAIN_ALBUM_PEAK",tag,strlen(tag));
				tagAdded = YES;
			}
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_CUESHEET] && [[configurations objectForKey:@"AllowEmbeddedCuesheet"] boolValue]) {
			const char *tag = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_CUESHEET] UTF8String];
			WavpackAppendTagItem(wpc,"CUESHEET",tag,strlen(tag));
			tagAdded = YES;
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COVER]) {
			NSMutableData *tagData = [[NSMutableData alloc] init];
			NSData *imageData = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COVER];
			if([imageData length] >= 8 && 0 == memcmp([imageData bytes], "\x89PNG\x0d\x0a\x1a\x0a", 8))
				[tagData appendBytes:"Cover Art (Front).png" length:22];
			else if([imageData length] >= 6 && (0 == memcmp([imageData bytes], "GIF87a", 6) || 0 == memcmp([imageData bytes], "GIF89a", 6)))
				[tagData appendBytes:"Cover Art (Front).gif" length:22];
			else if([imageData length] >= 2 && 0 == memcmp([imageData bytes], "\xff\xd8", 2))
				[tagData appendBytes:"Cover Art (Front).jpg" length:22];
			
			[tagData appendData:imageData];
			
			WavpackAppendBinaryTagItem(wpc,"Cover Art (Front)",[tagData bytes],[tagData length]);
			tagAdded = YES;
		}
		NSArray *keyArr = [[(XLDTrack *)track metadata] allKeys];
		for(i=[keyArr count]-1;i>=0;i--) {
			NSString *key = [keyArr objectAtIndex:i];
			NSRange range = [key rangeOfString:@"XLD_UNKNOWN_TEXT_METADATA_"];
			if(range.location != 0) continue;
			const char *idx = [[key substringFromIndex:range.length] UTF8String];
			const char *dat = [[[(XLDTrack *)track metadata] objectForKey:key] UTF8String];
			WavpackAppendTagItem(wpc,idx,dat,strlen(dat));
			tagAdded = YES;
		}
	}
	MD5_Init (&context);
	return YES;
}

- (NSString *)extensionStr
{
	return @"wv";
}

- (BOOL)writeBuffer:(int *)buffer frames:(int)counts
{
	int i,j;
	unsigned char *ptr;
	if(internalBufferSize < counts*format.channels*4) internalBuffer = realloc(internalBuffer, counts*format.channels*4);
	for(i=0;i<counts*format.channels;i++) {
		ptr = (unsigned char *)(internalBuffer + i);
		internalBuffer[i] = buffer[i] >> (32-format.bps*8);
#ifdef _BIG_ENDIAN
		for(j=0;j<format.bps;j++) MD5_Update (&context, ptr+3-j, 1);
#else
		for(j=0;j<format.bps;j++) MD5_Update (&context, ptr+j, 1);
#endif
	}
	WavpackPackSamples(wpc,internalBuffer,counts);
	return YES;
}

- (void)finalize
{
	unsigned char digest[16];
	MD5_Final(digest, &context);
	WavpackStoreMD5Sum(wpc,digest);
	WavpackFlushSamples(wpc);
	if(tagAdded) WavpackWriteTag(wpc);
	void *tmp;
	tmp = malloc(fpwv->initial_frame_size);
	fpwv->fp = fopen(fpwv->path,"r+");
	fread(tmp,1,fpwv->initial_frame_size,fpwv->fp);
	WavpackUpdateNumSamples(wpc,tmp);
	rewind(fpwv->fp);
	fwrite(tmp,1,fpwv->initial_frame_size,fpwv->fp);
	fclose(fpwv->fp);
	free(tmp);
	if(fpwvc) {
		tmp = malloc(fpwvc->initial_frame_size);
		fpwvc->fp = fopen(fpwvc->path,"r+");
		fread(tmp,1,fpwvc->initial_frame_size,fpwvc->fp);
		WavpackUpdateNumSamples(wpc,tmp);
		rewind(fpwvc->fp);
		fwrite(tmp,1,fpwvc->initial_frame_size,fpwvc->fp);
		fclose(fpwvc->fp);
		free(tmp);
	}
}

- (void)closeFile
{
	if(wpc) WavpackCloseFile(wpc);
	wpc = NULL;
	free(fpwv->path);
	free(fpwv);
	fpwv = NULL;
	if(fpwvc) {
		free(fpwvc->path);
		free(fpwvc);
		fpwvc = NULL;
	}
}

- (void)setEnableAddTag:(BOOL)flag
{
	addTag = flag;
}


@end
