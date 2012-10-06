//
//  XLDWavpackOutputTask.h
//  XLDWavpackOutput
//
//  Created by tmkk on 08/05/20.
//  Copyright 2008 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "XLDOutputTask.h"
#import <wavpack/wavpack.h>
#import <openssl/md5.h>

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
#define XLD_METADATA_ISRC		@"ISRC"
#define XLD_METADATA_COVER		@"Cover"
#define XLD_METADATA_ALBUMARTIST	@"AlbumArtist"
#define XLD_METADATA_REPLAYGAIN_TRACK_GAIN	@"RGTrackGain"
#define XLD_METADATA_REPLAYGAIN_ALBUM_GAIN	@"RGAlbumGain"
#define XLD_METADATA_REPLAYGAIN_TRACK_PEAK	@"RGTrackPeak"
#define XLD_METADATA_REPLAYGAIN_ALBUM_PEAK	@"RGAlbumPeak"
#define XLD_METADATA_COMPILATION	@"Compilation"
#define XLD_METADATA_GROUP		@"Group"
#define XLD_METADATA_GRACENOTE		@"Gracenote"
#define XLD_METADATA_CATALOG		@"Catalog"
#define XLD_METADATA_PREEMPHASIS	@"Emphasis"
#define XLD_METADATA_FREEDBDISCID	@"DISCID"
#define XLD_METADATA_BPM		@"BPM"
#define XLD_METADATA_COPYRIGHT	@"Copyright"
#define XLD_METADATA_GAPLESSALBUM	@"GaplessAlbum"
#define XLD_METADATA_CREATIONDATE	@"CreationDate"
#define XLD_METADATA_MODIFICATIONDATE	@"ModificationDate"
#define XLD_METADATA_ORIGINALFILENAME	@"OriginalFilename"
#define XLD_METADATA_DATATRACK @"DataTrack"
#define XLD_METADATA_TITLESORT	@"TitleSort"
#define XLD_METADATA_ARTISTSORT	@"ArtistSort"
#define XLD_METADATA_ALBUMSORT	@"AlbumSort"
#define XLD_METADATA_ALBUMARTISTSORT	@"AlbumArtistSort"
#define XLD_METADATA_COMPOSERSORT	@"ComposerSort"
#define XLD_METADATA_GRACENOTE2		@"Gracenote2"
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

typedef struct
{
	FILE *fp;
	int initial_frame_size;
	char *path;
} fileID;

@interface XLDWavpackOutputTask : NSObject <XLDOutputTask> {
	WavpackContext *wpc;
	BOOL addTag;
	BOOL tagAdded;
	XLDFormat format;
	fileID *fpwv;
	fileID *fpwvc;
	int *internalBuffer;
	int internalBufferSize;
	MD5_CTX context;
	NSDictionary *configurations;
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
