#import <Foundation/Foundation.h>

typedef int64_t xldoffset_t;

#import "XLDFlacDecoder.h"
#import "XLDTrack.h"
#import <unistd.h>

typedef struct {
    unsigned char id[3];
    unsigned short version;
    unsigned char flags;
    unsigned char size[4];
} __attribute__ ((packed)) id3v2_t;

void metadata_callback_dummy(const FLAC__StreamDecoder *decoder, const FLAC__StreamMetadata *metadata, void *client_data)
{
	
}

void error_callback_dummy(const FLAC__StreamDecoder *decoder, FLAC__StreamDecoderErrorStatus status, void *client_data)
{
	
}

FLAC__StreamDecoderWriteStatus write_callback_dummy(const FLAC__StreamDecoder *decoder, const FLAC__Frame *frame, const FLAC__int32 *const buffer[], void *client_data)
{
	return FLAC__STREAM_DECODER_WRITE_STATUS_CONTINUE;
}

void metadata_callback(const FLAC__StreamDecoder *decoder, const FLAC__StreamMetadata *metadata, void *client_data)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	XLDFlacDecoder *delegate = (XLDFlacDecoder *)client_data;
	
	if(metadata->type == FLAC__METADATA_TYPE_STREAMINFO && !delegate->samplerate) {
		FLAC__StreamMetadata_StreamInfo info = metadata->data.stream_info;
		delegate->samplerate = info.sample_rate;
		delegate->channels = info.channels;
		delegate->bps = info.bits_per_sample >> 3;
		delegate->totalFrames = info.total_samples;
	}
	else if(metadata->type == FLAC__METADATA_TYPE_VORBIS_COMMENT) {
		FLAC__StreamMetadata_VorbisComment comment = metadata->data.vorbis_comment;
		if(comment.num_comments < 1) goto metadata_callback_end;
		int i;
		for(i=0;i<comment.num_comments;i++) {
			int nullFix = 0;
			while(comment.comments[i].length + nullFix > 0) {
				if(comment.comments[i].entry[comment.comments[i].length+nullFix-1] == 0) nullFix--;
				else break;
			}
			if(comment.comments[i].length + nullFix == 0) continue;
			if(!strncasecmp((char *)comment.comments[i].entry,"cuesheet=",9)) {
				delegate->cueData = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+9 length:comment.comments[i].length-9+nullFix] encoding:NSUTF8StringEncoding];
				if(delegate->cueData) [delegate->metadataDic setObject:delegate->cueData forKey:XLD_METADATA_CUESHEET];
			}
			else if(!strncasecmp((char *)comment.comments[i].entry,"title=",6)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+6 length:comment.comments[i].length-6+nullFix] encoding:NSUTF8StringEncoding];
				if(dat) {
					[delegate->metadataDic setObject:dat forKey:XLD_METADATA_TITLE];
					[dat release];
				}
			}
			else if(!strncasecmp((char *)comment.comments[i].entry,"artist=",7)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+7 length:comment.comments[i].length-7+nullFix] encoding:NSUTF8StringEncoding];
				if(dat) {
					[delegate->metadataDic setObject:dat forKey:XLD_METADATA_ARTIST];
					[dat release];
				}
			}
			else if(!strncasecmp((char *)comment.comments[i].entry,"album=",6)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+6 length:comment.comments[i].length-6+nullFix] encoding:NSUTF8StringEncoding];
				if(dat) {
					[delegate->metadataDic setObject:dat forKey:XLD_METADATA_ALBUM];
					[dat release];
				}
			}
			else if(!strncasecmp((char *)comment.comments[i].entry,"albumartist=",12)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+12 length:comment.comments[i].length-12+nullFix] encoding:NSUTF8StringEncoding];
				if(dat) {
					[delegate->metadataDic setObject:dat forKey:XLD_METADATA_ALBUMARTIST];
					[dat release];
				}
			}
			else if(!strncasecmp((char *)comment.comments[i].entry,"tracknumber=",12)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+12 length:comment.comments[i].length-12+nullFix] encoding:NSUTF8StringEncoding];
				if(dat) {
					int track = [dat intValue];
					if(track > 0) [delegate->metadataDic setObject:[NSNumber numberWithInt:track] forKey:XLD_METADATA_TRACK];
					[dat release];
				}
			}
			else if(!strncasecmp((char *)comment.comments[i].entry,"tracktotal=",11)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+11 length:comment.comments[i].length-11+nullFix] encoding:NSUTF8StringEncoding];
				if(dat) {
					int track_total = [dat intValue];
					if(track_total > 0) [delegate->metadataDic setObject:[NSNumber numberWithInt:track_total] forKey:XLD_METADATA_TOTALTRACKS];
					[dat release];
				}
			}
			else if(!strncasecmp((char *)comment.comments[i].entry,"totaltracks=",12)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+12 length:comment.comments[i].length-12+nullFix] encoding:NSUTF8StringEncoding];
				if(dat) {
					int track_total = [dat intValue];
					if(track_total > 0) [delegate->metadataDic setObject:[NSNumber numberWithInt:track_total] forKey:XLD_METADATA_TOTALTRACKS];
					[dat release];
				}
			}
			else if(!strncasecmp((char *)comment.comments[i].entry,"discnumber=",11)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+11 length:comment.comments[i].length-11+nullFix] encoding:NSUTF8StringEncoding];
				if(dat) {
					int disc = [dat intValue];
					if(disc > 0) [delegate->metadataDic setObject:[NSNumber numberWithInt:disc] forKey:XLD_METADATA_DISC];
					[dat release];
				}
			}
			else if(!strncasecmp((char *)comment.comments[i].entry,"disctotal=",10)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+10 length:comment.comments[i].length-10+nullFix] encoding:NSUTF8StringEncoding];
				if(dat) {
					int disc_total = [dat intValue];
					if(disc_total > 0) [delegate->metadataDic setObject:[NSNumber numberWithInt:disc_total] forKey:XLD_METADATA_TOTALDISCS];
					[dat release];
				}
			}
			else if(!strncasecmp((char *)comment.comments[i].entry,"totaldiscs=",11)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+11 length:comment.comments[i].length-11+nullFix] encoding:NSUTF8StringEncoding];
				if(dat) {
					int disc_total = [dat intValue];
					if(disc_total > 0) [delegate->metadataDic setObject:[NSNumber numberWithInt:disc_total] forKey:XLD_METADATA_TOTALDISCS];
					[dat release];
				}
			}
			else if(!strncasecmp((char *)comment.comments[i].entry,"genre=",6)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+6 length:comment.comments[i].length-6+nullFix] encoding:NSUTF8StringEncoding];
				if(dat) {
					[delegate->metadataDic setObject:dat forKey:XLD_METADATA_GENRE];
					[dat release];
				}
			}
			else if(!strncasecmp((char *)comment.comments[i].entry,"composer=",9)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+9 length:comment.comments[i].length-9+nullFix] encoding:NSUTF8StringEncoding];
				if(dat) {
					[delegate->metadataDic setObject:dat forKey:XLD_METADATA_COMPOSER];
					[dat release];
				}
			}
			else if(!strncasecmp((char *)comment.comments[i].entry,"date=",5)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+5 length:comment.comments[i].length-5+nullFix] encoding:NSUTF8StringEncoding];
				if(dat) {
					[delegate->metadataDic setObject:dat forKey:XLD_METADATA_DATE];
					int year = [dat intValue];
					if(year >=1000 && year < 3000) [delegate->metadataDic setObject:[NSNumber numberWithInt:year] forKey:XLD_METADATA_YEAR];
					[dat release];
				}
			}
			else if(!strncasecmp((char *)comment.comments[i].entry,"comment=",8)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+8 length:comment.comments[i].length-8+nullFix] encoding:NSUTF8StringEncoding];
				if(dat) {
					[delegate->metadataDic setObject:dat forKey:XLD_METADATA_COMMENT];
					[dat release];
				}
			}
			else if(!strncasecmp((char *)comment.comments[i].entry,"description=",12)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+12 length:comment.comments[i].length-12+nullFix] encoding:NSUTF8StringEncoding];
				if(dat) {
					[delegate->metadataDic setObject:dat forKey:XLD_METADATA_COMMENT];
					[dat release];
				}
			}
			else if(!strncasecmp((char *)comment.comments[i].entry,"ISRC=",5)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+5 length:comment.comments[i].length-5+nullFix] encoding:NSUTF8StringEncoding];
				if(dat) {
					[delegate->metadataDic setObject:dat forKey:XLD_METADATA_ISRC];
					[dat release];
				}
			}
			else if(!strncasecmp((char *)comment.comments[i].entry,"MCN=",4)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+4 length:comment.comments[i].length-4+nullFix] encoding:NSUTF8StringEncoding];
				if(dat) {
					[delegate->metadataDic setObject:dat forKey:XLD_METADATA_CATALOG];
					[dat release];
				}
			}
			else if(!strncasecmp((char *)comment.comments[i].entry,"compilation=",12)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+12 length:comment.comments[i].length-12+nullFix] encoding:NSUTF8StringEncoding];
				if(dat) {
					[delegate->metadataDic setObject:[NSNumber numberWithBool:[dat intValue]] forKey:XLD_METADATA_COMPILATION];
					[dat release];
				}
			}
			else if(!strncasecmp((char *)comment.comments[i].entry,"grouping=",9)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+9 length:comment.comments[i].length-9+nullFix] encoding:NSUTF8StringEncoding];
				if(dat) {
					[delegate->metadataDic setObject:dat forKey:XLD_METADATA_GROUP];
					[dat release];
				}
			}
			else if(!strncasecmp((char *)comment.comments[i].entry,"contentgroup=",13)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+13 length:comment.comments[i].length-13+nullFix] encoding:NSUTF8StringEncoding];
				if(dat) {
					[delegate->metadataDic setObject:dat forKey:XLD_METADATA_GROUP];
					[dat release];
				}
			}
			else if(!strncasecmp((char *)comment.comments[i].entry,"titlesort=",10)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+10 length:comment.comments[i].length-10+nullFix] encoding:NSUTF8StringEncoding];
				if(dat) {
					[delegate->metadataDic setObject:dat forKey:XLD_METADATA_TITLESORT];
					[dat release];
				}
			}
			else if(!strncasecmp((char *)comment.comments[i].entry,"artistsort=",11)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+11 length:comment.comments[i].length-11+nullFix] encoding:NSUTF8StringEncoding];
				if(dat) {
					[delegate->metadataDic setObject:dat forKey:XLD_METADATA_ARTISTSORT];
					[dat release];
				}
			}
			else if(!strncasecmp((char *)comment.comments[i].entry,"albumsort=",10)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+10 length:comment.comments[i].length-10+nullFix] encoding:NSUTF8StringEncoding];
				if(dat) {
					[delegate->metadataDic setObject:dat forKey:XLD_METADATA_ALBUMSORT];
					[dat release];
				}
			}
			else if(!strncasecmp((char *)comment.comments[i].entry,"albumartistsort=",16)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+16 length:comment.comments[i].length-16+nullFix] encoding:NSUTF8StringEncoding];
				if(dat) {
					[delegate->metadataDic setObject:dat forKey:XLD_METADATA_ALBUMARTISTSORT];
					[dat release];
				}
			}
			else if(!strncasecmp((char *)comment.comments[i].entry,"composersort=",13)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+13 length:comment.comments[i].length-13+nullFix] encoding:NSUTF8StringEncoding];
				if(dat) {
					[delegate->metadataDic setObject:dat forKey:XLD_METADATA_COMPOSERSORT];
					[dat release];
				}
			}
			else if(!strncasecmp((char *)comment.comments[i].entry,"iTunes_CDDB_1=",14)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+14 length:comment.comments[i].length-14+nullFix] encoding:NSUTF8StringEncoding];
				if(dat) {
					[delegate->metadataDic setObject:dat forKey:XLD_METADATA_GRACENOTE2];
					[dat release];
				}
			}
			else if(!strncasecmp((char *)comment.comments[i].entry,"MUSICBRAINZ_TRACKID=",20)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+20 length:comment.comments[i].length-20+nullFix] encoding:NSUTF8StringEncoding];
				if(dat) {
					[delegate->metadataDic setObject:dat forKey:XLD_METADATA_MB_TRACKID];
					[dat release];
				}
			}
			else if(!strncasecmp((char *)comment.comments[i].entry,"MUSICBRAINZ_ALBUMID=",20)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+20 length:comment.comments[i].length-20+nullFix] encoding:NSUTF8StringEncoding];
				if(dat) {
					[delegate->metadataDic setObject:dat forKey:XLD_METADATA_MB_ALBUMID];
					[dat release];
				}
			}
			else if(!strncasecmp((char *)comment.comments[i].entry,"MUSICBRAINZ_ARTISTID=",21)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+21 length:comment.comments[i].length-21+nullFix] encoding:NSUTF8StringEncoding];
				if(dat) {
					[delegate->metadataDic setObject:dat forKey:XLD_METADATA_MB_ARTISTID];
					[dat release];
				}
			}
			else if(!strncasecmp((char *)comment.comments[i].entry,"MUSICBRAINZ_ALBUMARTISTID=",26)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+26 length:comment.comments[i].length-26+nullFix] encoding:NSUTF8StringEncoding];
				if(dat) {
					[delegate->metadataDic setObject:dat forKey:XLD_METADATA_MB_ALBUMARTISTID];
					[dat release];
				}
			}
			else if(!strncasecmp((char *)comment.comments[i].entry,"MUSICBRAINZ_DISCID=",19)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+19 length:comment.comments[i].length-19+nullFix] encoding:NSUTF8StringEncoding];
				if(dat) {
					[delegate->metadataDic setObject:dat forKey:XLD_METADATA_MB_DISCID];
					[dat release];
				}
			}
			else if(!strncasecmp((char *)comment.comments[i].entry,"MUSICIP_PUID=",13)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+13 length:comment.comments[i].length-13+nullFix] encoding:NSUTF8StringEncoding];
				if(dat) {
					[delegate->metadataDic setObject:dat forKey:XLD_METADATA_PUID];
					[dat release];
				}
			}
			else if(!strncasecmp((char *)comment.comments[i].entry,"MUSICBRAINZ_ALBUMSTATUS=",24)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+24 length:comment.comments[i].length-24+nullFix] encoding:NSUTF8StringEncoding];
				if(dat) {
					[delegate->metadataDic setObject:dat forKey:XLD_METADATA_MB_ALBUMSTATUS];
					[dat release];
				}
			}
			else if(!strncasecmp((char *)comment.comments[i].entry,"MUSICBRAINZ_ALBUMTYPE=",22)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+22 length:comment.comments[i].length-22+nullFix] encoding:NSUTF8StringEncoding];
				if(dat) {
					[delegate->metadataDic setObject:dat forKey:XLD_METADATA_MB_ALBUMTYPE];
					[dat release];
				}
			}
			else if(!strncasecmp((char *)comment.comments[i].entry,"RELEASECOUNTRY=",15)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+15 length:comment.comments[i].length-15+nullFix] encoding:NSUTF8StringEncoding];
				if(dat) {
					[delegate->metadataDic setObject:dat forKey:XLD_METADATA_MB_RELEASECOUNTRY];
					[dat release];
				}
			}
			else if(!strncasecmp((char *)comment.comments[i].entry,"MUSICBRAINZ_RELEASEGROUPID=",27)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+27 length:comment.comments[i].length-27+nullFix] encoding:NSUTF8StringEncoding];
				if(dat) {
					[delegate->metadataDic setObject:dat forKey:XLD_METADATA_MB_RELEASEGROUPID];
					[dat release];
				}
			}
			else if(!strncasecmp((char *)comment.comments[i].entry,"MUSICBRAINZ_WORKID=",19)) {
				NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+19 length:comment.comments[i].length-19+nullFix] encoding:NSUTF8StringEncoding];
				if(dat) {
					[delegate->metadataDic setObject:dat forKey:XLD_METADATA_MB_WORKID];
					[dat release];
				}
			}
			else if(!strncasecmp((char *)comment.comments[i].entry,"encoder=",8)) {
				// do nothing
			}
			else { //unknown text metadata
				int len = strchr((char *)comment.comments[i].entry,'=') - (char *)comment.comments[i].entry;
				if(len > 0) {
					NSString *idx = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry length:len] encoding:NSUTF8StringEncoding];
					NSString *dat = [[NSString alloc] initWithData:[NSData dataWithBytes:comment.comments[i].entry+len+1 length:comment.comments[i].length-len-1+nullFix] encoding:NSUTF8StringEncoding];
					if(idx && dat) {
						[delegate->metadataDic setObject:dat forKey:[NSString stringWithFormat:@"XLD_UNKNOWN_TEXT_METADATA_%@",idx]];
					}
					if(idx) [idx release];
					if(dat) [dat release];
				}
			}
		}
	}
	else if(!delegate->trackArr && metadata->type == FLAC__METADATA_TYPE_CUESHEET) {
		if(delegate->cueData) goto metadata_callback_end;
		FLAC__StreamMetadata_CueSheet cuesheet = metadata->data.cue_sheet;
		if(cuesheet.num_tracks < 1) goto metadata_callback_end;
		int i;
		delegate->trackArr = [[NSMutableArray alloc] init];
		for(i=0;i<cuesheet.num_tracks;i++) {
			if(cuesheet.tracks[i].number == 170) continue;
			XLDTrack *track = [[objc_getClass("XLDTrack") alloc] init];
			[[track metadata] setObject:[NSNumber numberWithInt:i+1] forKey:XLD_METADATA_TRACK];
			[[track metadata] setObject:[NSNumber numberWithInt:cuesheet.num_tracks] forKey:XLD_METADATA_TOTALTRACKS];
			if(cuesheet.tracks[i].num_indices > 1) {
				[track setIndex:cuesheet.tracks[i].offset + cuesheet.tracks[i].indices[1].offset];
				[track setGap:cuesheet.tracks[i].indices[1].offset];
			}
			else [track setIndex:cuesheet.tracks[i].offset];
			if(i != 0) {
				if([track gap] != 0) [[delegate->trackArr objectAtIndex:i-1] setFrames:[(XLDTrack *)track index] - [track gap] - [(XLDTrack *)[delegate->trackArr objectAtIndex:i-1] index]];
				else [[delegate->trackArr objectAtIndex:i-1] setFrames:[(XLDTrack *)track index] - [(XLDTrack *)[delegate->trackArr objectAtIndex:i-1] index]];
			}
			[delegate->trackArr addObject:track];
			[track release];
		}
		if([delegate->trackArr count] < 1) {
			[delegate->trackArr release];
			delegate->trackArr = nil;
		}
	}
	else if(metadata->type == FLAC__METADATA_TYPE_PICTURE) {
		FLAC__StreamMetadata_Picture picture = metadata->data.picture;
		if(picture.type != FLAC__STREAM_METADATA_PICTURE_TYPE_FRONT_COVER) {
			if([delegate->metadataDic objectForKey:XLD_METADATA_COVER]) goto metadata_callback_end;
		}
		NSData *imgData = [NSData dataWithBytes:picture.data length:picture.data_length];
		[delegate->metadataDic setObject:imgData forKey:XLD_METADATA_COVER];
	}
  metadata_callback_end:
	[pool release];
}

void error_callback(const FLAC__StreamDecoder *decoder, FLAC__StreamDecoderErrorStatus status, void *client_data)
{
	XLDFlacDecoder *delegate = (XLDFlacDecoder *)client_data;
	delegate->error = YES;
}

FLAC__StreamDecoderWriteStatus write_callback(const FLAC__StreamDecoder *decoder, const FLAC__Frame *frame, const FLAC__int32 *const buffer[], void *client_data)
{
	XLDFlacDecoder *delegate = (XLDFlacDecoder *)client_data;
	int channels = frame->header.channels;
	int samples = frame->header.blocksize;
	
	if(!delegate->writeCallbackBuffer) {
		delegate->writeCallbackBuffer = (int *)malloc(samples*4*channels);
		delegate->writeCallbackBufferSize = samples*4*channels;
	}
	else if (delegate->writeCallbackBufferSize < samples*4*channels) {
		delegate->writeCallbackBuffer = (int *)realloc(delegate->writeCallbackBuffer,samples*4*channels);
		delegate->writeCallbackBufferSize = samples*4*channels;
	}
	
	int i,j,k;
	for(i=0,k=0;i<samples;i++) {
		for(j=0;j<channels;j++) {
			*(delegate->writeCallbackBuffer+k++) = *(buffer[j]+i) << (32 - (delegate->bps<<3));
		}
	}
	delegate->writeCallbackDecodedSample = samples;
	return FLAC__STREAM_DECODER_WRITE_STATUS_CONTINUE;
}

@implementation XLDFlacDecoder

+ (BOOL)canHandleFile:(char *)path
{
	FILE *fp = fopen(path,"rb");
	if(!fp) return NO;
	
	id3v2_t id3v2;
	fread(&id3v2, sizeof(id3v2), 1, fp);
	
	if (!memcmp(id3v2.id, "ID3", 3)) {
		long len;
		
		len = (id3v2.size[0] & 0x7f);
		len = (len << 7) | (id3v2.size[1] & 0x7f);
		len = (len << 7) | (id3v2.size[2] & 0x7f);
		len = (len << 7) | (id3v2.size[3] & 0x7f);
		len += 10;
		if (id3v2.flags & (1 << 4)) len += 10;
		
		fseeko(fp, len, SEEK_SET);
	} else fseeko(fp, 0, SEEK_SET);
	
	char temp[4];
	fread(temp,1,4,fp);
	
	if(memcmp(temp,"OggS",4) && memcmp(temp,"fLaC",4)) {
		fclose(fp);
		return NO;
	}
	
	FLAC__StreamDecoder *flac_tmp = FLAC__stream_decoder_new();
	if(!flac_tmp) return NO;
	
	if(!memcmp(temp,"OggS",4)) {
		fseeko(fp, 0x19, SEEK_CUR);
		fread(temp,1,4,fp);
		if(memcmp(temp,"FLAC",4)) {
			FLAC__stream_decoder_delete(flac_tmp);
			fclose(fp);
			return NO;
		}
		if(FLAC__stream_decoder_init_ogg_file(flac_tmp,path,write_callback_dummy,NULL,error_callback_dummy,NULL) != FLAC__STREAM_DECODER_INIT_STATUS_OK) {
			FLAC__stream_decoder_delete(flac_tmp);
			fclose(fp);
			return NO;
		}
	}
	else if(!memcmp(temp,"fLaC",4)) {
		if(FLAC__stream_decoder_init_file(flac_tmp,path,write_callback_dummy,NULL,error_callback_dummy,NULL) != FLAC__STREAM_DECODER_INIT_STATUS_OK) {
			FLAC__stream_decoder_delete(flac_tmp);
			fclose(fp);
			return NO;
		}
	}
	fclose(fp);
	/*if(FLAC__stream_decoder_process_until_end_of_metadata(flac_tmp) == false) {
		FLAC__stream_decoder_delete(flac_tmp);
		return NO;
	}*/
	if(FLAC__stream_decoder_seek_absolute(flac_tmp,0) == false) {
		FLAC__stream_decoder_delete(flac_tmp);
		return NO;
	}
	FLAC__stream_decoder_delete(flac_tmp);
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
	trackArr = nil;
	cueData = nil;
	writeCallbackBuffer = NULL;
	tempBuffer = NULL;
	error = NO;
	metadataDic = [[NSMutableDictionary alloc] init];
	srcPath = nil;
	return self;
}

- (BOOL)openFile:(char *)path
{
	flac = FLAC__stream_decoder_new();
	if(!flac) {
		error = YES;
		return NO;
	}
	
	if(FLAC__stream_decoder_set_metadata_respond_all(flac) == false) {
		error = YES;
		FLAC__stream_decoder_delete(flac);
		flac = NULL;
		return NO;
	}
	
	FILE *fp = fopen(path,"rb");
	char temp[4];
	fread(temp,1,4,fp);
	fclose(fp);
	
	if(!memcmp(temp,"OggS",4)) {
		if(FLAC__stream_decoder_init_ogg_file(flac,path,write_callback,metadata_callback,error_callback,self) != FLAC__STREAM_DECODER_INIT_STATUS_OK) {
			error = YES;
			FLAC__stream_decoder_delete(flac);
			flac = NULL;
			return NO;
		}
	}
	else {
		if(FLAC__stream_decoder_init_file(flac,path,write_callback,metadata_callback,error_callback,self) != FLAC__STREAM_DECODER_INIT_STATUS_OK) {
			error = YES;
			FLAC__stream_decoder_delete(flac);
			flac = NULL;
			return NO;
		}
	}
	
	samplerate = 0;
	if(FLAC__stream_decoder_process_until_end_of_metadata(flac) == false) {
		error = YES;
		FLAC__stream_decoder_delete(flac);
		flac = NULL;
		return NO;
	}
	
	writeCallbackDecodedSample = 0;
	tempBuffer = (int *)malloc(16384*4*channels);
	tempBufferPtr = tempBuffer;
	tempBufferSample = 0;
	samplesConsumpted = 0;
	if(srcPath) [srcPath release];
	srcPath = [[NSString alloc] initWithUTF8String:path];
	return YES;
}

- (void)dealloc
{
	if(flac) FLAC__stream_decoder_delete(flac);
	if(trackArr) [trackArr release];
	if(cueData) [cueData release];
	if(writeCallbackBuffer) free(writeCallbackBuffer);
	if(tempBuffer) free(tempBuffer);
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
	if(totalFrames == samplesConsumpted) return 0;
	
	
	
	int samplesToRead;
	int rest;
	if(totalFrames - samplesConsumpted < count) {
		samplesToRead = totalFrames - samplesConsumpted;
	}
	else samplesToRead = count;
	
	rest = samplesToRead;
	
	if(tempBufferSample) {
		if(rest < tempBufferSample) {
			memcpy(buffer,tempBufferPtr,rest*4*channels);
			buffer += rest*channels;
			tempBufferPtr += rest*channels;
			tempBufferSample -= rest;
			rest = 0;
		}
		else { 
			memcpy(buffer,tempBufferPtr,tempBufferSample*4*channels);
			buffer += tempBufferSample*channels;
			rest -= tempBufferSample;
			tempBufferPtr = tempBuffer;
			tempBufferSample = 0;
		}
	}
	
	while(rest) {
		if(writeCallbackDecodedSample) {
			if(rest < writeCallbackDecodedSample) {
				memcpy(buffer,writeCallbackBuffer,rest*4*channels);
				buffer += rest*channels;
				memcpy(tempBuffer,writeCallbackBuffer+rest*channels,(writeCallbackDecodedSample-rest)*4*channels);
				tempBufferSample = writeCallbackDecodedSample-rest;
				rest = 0;
			}
			else { 
				memcpy(buffer,writeCallbackBuffer,writeCallbackDecodedSample*4*channels);
				buffer += writeCallbackDecodedSample*channels;
				rest -= writeCallbackDecodedSample;
			}
		}
		writeCallbackDecodedSample = 0;
		if(rest) {
			FLAC__stream_decoder_process_single(flac);
			if(!writeCallbackDecodedSample) {
				samplesToRead -= rest;
				break;
			}
		}
	}
	
	
	samplesConsumpted += samplesToRead;
	
	return samplesToRead;
}

- (xldoffset_t)seekToFrame:(xldoffset_t)count
{
	tempBufferPtr = tempBuffer;
	tempBufferSample = 0;
	FLAC__bool ret = FLAC__stream_decoder_seek_absolute(flac,count);
	if(ret == false) {
		FLAC__stream_decoder_flush(flac);
		return -1;
	}
	samplesConsumpted = count;
	return count;
}

- (void)closeFile
{
	if(flac) {
		FLAC__stream_decoder_finish(flac);
		FLAC__stream_decoder_delete(flac);
		flac = NULL;
	}
	if(trackArr) [trackArr release];
	trackArr = nil;
	if(cueData) [cueData release];
	cueData = nil;
	[metadataDic removeAllObjects];
	if(writeCallbackBuffer) free(writeCallbackBuffer);
	writeCallbackBuffer = NULL;
	if(tempBuffer) free(tempBuffer);
	tempBuffer = NULL;
	error = NO;
	decodeError = NO;
	samplesConsumpted = 0;
}

- (BOOL)error
{
	return error;
}

- (XLDEmbeddedCueSheetType)hasCueSheet
{
	if(cueData) return XLDTextTypeCueSheet;
	else if(trackArr) return XLDTrackTypeCueSheet;
	else return XLDNoCueSheet;
}

- (id)cueSheet
{
	if(cueData) return cueData;
	else if(trackArr) return trackArr;
	else return nil;
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