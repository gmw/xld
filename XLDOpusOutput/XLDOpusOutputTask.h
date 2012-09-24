//
//  XLDOpusOutputTask.h
//  XLDOpusOutput
//
//  Created by tmkk on 12/08/09.
//  Copyright 2012 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "XLDOutputTask.h"
#import <opus/opus.h>
#import <opus/opus_multistream.h>
#import <ogg/ogg.h>
#import "speex_resampler.h"

#define XLD_METADATA_TITLE		@"Title"
#define XLD_METADATA_ARTIST		@"Artist"
#define XLD_METADATA_ALBUM		@"Album"
#define XLD_METADATA_GENRE		@"Genre"
#define XLD_METADATA_TRACK		@"Track"
#define XLD_METADATA_DISC		@"Disc"
#define XLD_METADATA_YEAR		@"Year"
#define XLD_METADATA_DATE		@"Date"
#define XLD_METADATA_COMPOSER	@"Composer"
#define XLD_METADATA_CUESHEET	@"Cuesheet"
#define XLD_METADATA_COMMENT	@"Comment"
#define XLD_METADATA_TOTALTRACKS	@"Totaltracks"
#define XLD_METADATA_TOTALDISCS	@"Totaldiscs"
#define XLD_METADATA_LYRICS		@"Lyrics"
#define XLD_METADATA_COVER		@"Cover"
#define XLD_METADATA_ALBUMARTIST	@"AlbumArtist"
#define XLD_METADATA_COMPILATION	@"Compilation"
#define XLD_METADATA_GROUP		@"Group"
#define XLD_METADATA_GRACENOTE		@"Gracenote"
#define XLD_METADATA_GRACENOTE2		@"Gracenote2"
#define XLD_METADATA_BPM		@"BPM"
#define XLD_METADATA_COPYRIGHT	@"Copyright"
#define XLD_METADATA_GAPLESSALBUM	@"GaplessAlbum"
#define XLD_METADATA_TITLESORT	@"TitleSort"
#define XLD_METADATA_ARTISTSORT	@"ArtistSort"
#define XLD_METADATA_ALBUMSORT	@"AlbumSort"
#define XLD_METADATA_ALBUMARTISTSORT	@"AlbumArtistSort"
#define XLD_METADATA_COMPOSERSORT	@"ComposerSort"
#define XLD_METADATA_MB_TRACKID		@"MusicBrainz_TrackID"
#define XLD_METADATA_MB_ALBUMID	@"MusicBrainz_AlbumID"
#define XLD_METADATA_MB_ARTISTID	@"MusicBrainz_ArtistID"
#define XLD_METADATA_MB_ALBUMARTISTID	@"MusicBrainz_AlbumArtistID"
#define XLD_METADATA_MB_DISCID	@"MusicBrainz_DiscID"
#define XLD_METADATA_PUID		@"MusicIP_PUID"
#define XLD_METADATA_MB_ALBUMSTATUS	@"MusicBrainz_AlbumStatus"
#define XLD_METADATA_MB_ALBUMTYPE	@"MusicBrainz_AlbumType"
#define XLD_METADATA_MB_RELEASECOUNTRY	@"MusicBrainz_ReleaseCountry"
#define XLD_METADATA_MB_RELEASEGROUPID	@"MusicBrainz_ReleaseGroupID"
#define XLD_METADATA_MB_WORKID	@"MusicBrainz_WorkID"
#define XLD_METADATA_TOTALSAMPLES	@"TotalSamples"
#define XLD_METADATA_TRACKLIST	@"XLDTrackList"
#define XLD_METADATA_ISRC		@"ISRC"
#define XLD_METADATA_CATALOG		@"Catalog"

typedef struct {
	int version;
	int channels; /* Number of channels: 1..255 */
	int preskip;
	ogg_uint32_t input_sample_rate;
	int gain; /* in dB S7.8 should be zero whenever possible */
	int channel_mapping;
	/* The rest is only used if channel_mapping != 0 */
	int nb_streams;
	int nb_coupled;
	unsigned char stream_map[255];
} OpusHeader;

@interface XLDOpusOutputTask : NSObject <XLDOutputTask> {
	FILE *fp;
	XLDFormat format;
	ogg_stream_state os;
	ogg_page         og;
	ogg_packet       op;
	OpusMSEncoder *st;
	OpusHeader header;
	BOOL addTag;
	NSDictionary *configurations;
	int                max_frame_bytes;
	unsigned char      *packet;
	opus_int32         coding_rate;
	opus_int32         frame_size;
	ogg_int32_t        pid;
	float *input;
	opus_int64         original_samples;
	ogg_int64_t        enc_granulepos;
	int                last_segments;
	ogg_int64_t        last_granulepos;
	int bufferedSamples;
	int bufferSize;
	SpeexResamplerState *resampler;
	float *resamplerBuffer;
	int bufferedResamplerSamples;
}

- (BOOL)setOutputFormat:(XLDFormat)fmt;
- (BOOL)openFileForOutput:(NSString *)str withTrackData:(id)track;
- (NSString *)extensionStr;
- (BOOL)writeBuffer:(int *)buffer frames:(int)counts;
- (void)finalize;
- (void)closeFile;
- (void)setEnableAddTag:(BOOL)flag;

- (id)initWithConfigurations:(NSDictionary *)cfg;

@end
