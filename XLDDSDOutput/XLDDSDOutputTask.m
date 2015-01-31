//
//  XLDDSDOutputTask.m
//  XLDDSDOutput
//
//  Created by tmkk on 15/01/24.
//  Copyright 2015 tmkk. All rights reserved.
//

#import "XLDDSDOutputTask.h"

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
#define XLD_METADATA_DCP		@"DCP"
#define XLD_METADATA_FREEDBDISCID	@"DISCID"
#define XLD_METADATA_BPM		@"BPM"
#define XLD_METADATA_COPYRIGHT	@"Copyright"
#define XLD_METADATA_GAPLESSALBUM	@"GaplessAlbum"
#define XLD_METADATA_CREATIONDATE	@"CreationDate"
#define XLD_METADATA_MODIFICATIONDATE	@"ModificationDate"
#define XLD_METADATA_ORIGINALFILENAME	@"OriginalFilename"
#define XLD_METADATA_ORIGINALFILEPATH	@"OriginalFilepath"
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
#define XLD_METADATA_TOTALSAMPLES	@"TotalSamples"
#define XLD_METADATA_TRACKLIST	@"XLDTrackList"
#define XLD_METADATA_SMPTE_TIMECODE_START	@"SMTPE Timecode Start"
#define XLD_METADATA_SMPTE_TIMECODE_DURATION	@"SMTPE Timecode Duration"
#define XLD_METADATA_MEDIA_FPS	@"Media FPS"

static void appendTextTag(NSMutableData *tagData, char *field, NSString *tagStr, int encoding)
{
	unsigned int tmp;
	unsigned short tmp2;
	unsigned char tmp3;
	if(encoding > 1) encoding = 1;
	NSData *dat = [tagStr dataUsingEncoding:(encoding==1)?NSUnicodeStringEncoding:NSISOLatin1StringEncoding];
	tmp = [dat length]+2+encoding;
	tmp = NSSwapHostIntToBig(tmp);
	tmp2 = 0;
	tmp3 = encoding;
	[tagData appendBytes:field length:4]; //ID
	[tagData appendBytes:&tmp length:4]; //length
	[tagData appendBytes:&tmp2 length:2]; //flag
	[tagData appendBytes:&tmp3 length:1]; //char code (UCS-2 or ISO-8859-1)
	[tagData appendData:dat];
	[tagData appendBytes:&tmp2 length:1+encoding]; //termination
}

static void appendCommentTag(NSMutableData *tagData, char *field, char *lang, NSString *descStr, NSString *tagStr, int encoding)
{
	unsigned int tmp;
	unsigned short tmp2;
	unsigned char tmp3;
	if(encoding > 1) encoding = 1;
	NSData *dat = [tagStr dataUsingEncoding:(encoding==1)?NSUnicodeStringEncoding:NSISOLatin1StringEncoding];
	NSData *dat2 = [descStr dataUsingEncoding:(encoding==1)?NSUnicodeStringEncoding:NSISOLatin1StringEncoding];
	tmp = [dat length]+[dat2 length]+1+(1+encoding)*2+(lang?3:0);
	tmp = NSSwapHostIntToBig(tmp);
	tmp2 = 0;
	tmp3 = encoding;
	[tagData appendBytes:field length:4]; //ID
	[tagData appendBytes:&tmp length:4]; //length
	[tagData appendBytes:&tmp2 length:2]; //flag
	[tagData appendBytes:&tmp3 length:1]; //char code (UCS-2 or ISO-8859-1)
	if(lang) [tagData appendBytes:lang length:3]; //lang
	[tagData appendData:dat2]; //desc
	[tagData appendBytes:&tmp2 length:1+encoding]; //termination
	[tagData appendData:dat];
	[tagData appendBytes:&tmp2 length:1+encoding]; //termination
}

static void setupID3Tag(NSMutableData *tagData, NSDictionary *metadata)
{
	int tmp;
	short tmp2;
	char tmp3;
	char atomID[4];
	BOOL added = NO;
	
	/* id3 header */
	tmp = 0;
	tmp3 = 3; // version 2.3
	memcpy(atomID,"ID3",3);
	[tagData appendBytes:atomID length:3];
	[tagData appendBytes:&tmp3 length:1]; // version (major)
	tmp3 = 0;
	[tagData appendBytes:&tmp3 length:1]; // version (minor)
	[tagData appendBytes:&tmp3 length:1]; // flag
	[tagData appendBytes:&tmp length:4]; // length (unknown atm)
	
	/* TIT2 */
	if([metadata objectForKey:XLD_METADATA_TITLE]) {
		added = YES;
		appendTextTag(tagData, "TIT2", [metadata objectForKey:XLD_METADATA_TITLE], 1);
	}
	
	/* TPE1 */
	if([metadata objectForKey:XLD_METADATA_ARTIST]) {
		added = YES;
		appendTextTag(tagData, "TPE1", [metadata objectForKey:XLD_METADATA_ARTIST], 1);
	}
	
	/* TPE2 */
	if([metadata objectForKey:XLD_METADATA_ALBUMARTIST]) {
		added = YES;
		appendTextTag(tagData, "TPE2", [metadata objectForKey:XLD_METADATA_ALBUMARTIST], 1);
	}
	
	/* TALB */
	if([metadata objectForKey:XLD_METADATA_ALBUM]) {
		added = YES;
		appendTextTag(tagData, "TALB", [metadata objectForKey:XLD_METADATA_ALBUM], 1);
	}
	
	/* TCON */
	if([metadata objectForKey:XLD_METADATA_GENRE]) {
		added = YES;
		appendTextTag(tagData, "TCON", [metadata objectForKey:XLD_METADATA_GENRE], 1);
	}
	
	/* TCOM */
	if([metadata objectForKey:XLD_METADATA_COMPOSER]) {
		added = YES;
		appendTextTag(tagData, "TCOM", [metadata objectForKey:XLD_METADATA_COMPOSER], 1);
	}
	
	/* TRCK */
	if([metadata objectForKey:XLD_METADATA_TRACK]) {
		added = YES;
		NSString *str;
		if([metadata objectForKey:XLD_METADATA_TOTALTRACKS])
			str = [NSString stringWithFormat:@"%d/%d",[[metadata objectForKey:XLD_METADATA_TRACK] intValue],[[metadata objectForKey:XLD_METADATA_TOTALTRACKS] intValue]];
		else
			str = [NSString stringWithFormat:@"%d",[[metadata objectForKey:XLD_METADATA_TRACK] intValue]];
		appendTextTag(tagData, "TRCK", str, 0);
	}
	
	/* TPOS */
	if([metadata objectForKey:XLD_METADATA_DISC] || [metadata objectForKey:XLD_METADATA_TOTALDISCS]) {
		added = YES;
		NSString *str;
		if([metadata objectForKey:XLD_METADATA_TOTALDISCS])
			str = [NSString stringWithFormat:@"%d/%d",[[metadata objectForKey:XLD_METADATA_DISC] intValue],[[metadata objectForKey:XLD_METADATA_TOTALDISCS] intValue]];
		else
			str = [NSString stringWithFormat:@"%d",[[metadata objectForKey:XLD_METADATA_DISC] intValue]];
		appendTextTag(tagData, "TPOS", str, 0);
	}
	
	/* TYER */
	if([metadata objectForKey:XLD_METADATA_DATE]) {
		added = YES;
		appendTextTag(tagData, "TYER", [metadata objectForKey:XLD_METADATA_DATE], 1);
	}
	else if([metadata objectForKey:XLD_METADATA_YEAR]) {
		added = YES;
		NSString *str = [[metadata objectForKey:XLD_METADATA_YEAR] stringValue];
		appendTextTag(tagData, "TYER", str, 0);
	}
	
	/* TIT1 */
	if([metadata objectForKey:XLD_METADATA_GROUP]) {
		added = YES;
		appendTextTag(tagData, "TIT1", [metadata objectForKey:XLD_METADATA_GROUP], 1);
	}
	
	/* TSOT */
	if([metadata objectForKey:XLD_METADATA_TITLESORT]) {
		added = YES;
		appendTextTag(tagData, "TSOT", [metadata objectForKey:XLD_METADATA_TITLESORT], 1);
	}
	
	/* TSOP */
	if([metadata objectForKey:XLD_METADATA_ARTISTSORT]) {
		added = YES;
		appendTextTag(tagData, "TSOP", [metadata objectForKey:XLD_METADATA_ARTISTSORT], 1);
	}
	
	/* TSOA */
	if([metadata objectForKey:XLD_METADATA_ALBUMSORT]) {
		added = YES;
		appendTextTag(tagData, "TSOA", [metadata objectForKey:XLD_METADATA_ALBUMSORT], 1);
	}
	
	/* TSO2 */
	if([metadata objectForKey:XLD_METADATA_ALBUMARTISTSORT]) {
		added = YES;
		appendTextTag(tagData, "TSO2", [metadata objectForKey:XLD_METADATA_ALBUMARTISTSORT], 1);
	}
	
	/* TSOC */
	if([metadata objectForKey:XLD_METADATA_COMPOSERSORT]) {
		added = YES;
		appendTextTag(tagData, "TSOC", [metadata objectForKey:XLD_METADATA_COMPOSERSORT], 1);
	}
	
	/* TBPM */
	if([metadata objectForKey:XLD_METADATA_BPM]) {
		added = YES;
		unsigned int bpm = [[metadata objectForKey:XLD_METADATA_BPM] unsignedShortValue];
		NSString *str = [NSString stringWithFormat:@"%u",bpm];
		appendTextTag(tagData, "TBPM", str, 0);
	}
	
	/* TCMP */
	if([metadata objectForKey:XLD_METADATA_COMPILATION]) {
		if([[metadata objectForKey:XLD_METADATA_COMPILATION] boolValue]) {
			added = YES;
			appendTextTag(tagData, "TCMP", [NSString stringWithString:@"1"], 0);
		}
	}
	
	/* TSRC */
	if([metadata objectForKey:XLD_METADATA_ISRC]) {
		added = YES;
		appendTextTag(tagData, "TSRC", [metadata objectForKey:XLD_METADATA_ISRC], 0);
	}
	
	/* COMM (gapless album) */
	if([metadata objectForKey:XLD_METADATA_GAPLESSALBUM] && [[metadata objectForKey:XLD_METADATA_GAPLESSALBUM] boolValue]) {
		added = YES;
		appendCommentTag(tagData, "COMM", "eng", [NSString stringWithString:@"iTunPGAP"], [NSString stringWithString:@"1"], 0);
	}
	
	/* COMM */
	if([metadata objectForKey:XLD_METADATA_COMMENT]) {
		added = YES;
		appendCommentTag(tagData, "COMM", "eng", [NSString stringWithString:@""], [metadata objectForKey:XLD_METADATA_COMMENT], 1);
	}
	
	/* USLT */
	if([metadata objectForKey:XLD_METADATA_LYRICS]) {
		added = YES;
		appendCommentTag(tagData, "USLT", "eng", [NSString stringWithString:@""], [metadata objectForKey:XLD_METADATA_LYRICS], 1);
	}
	
	/* COMM (iTunes_CDDB_1) */
	if([metadata objectForKey:XLD_METADATA_GRACENOTE2]) {
		added = YES;
		appendCommentTag(tagData, "COMM", "eng", [NSString stringWithString:@"iTunes_CDDB_1"], [metadata objectForKey:XLD_METADATA_GRACENOTE2], 0);
		if([metadata objectForKey:XLD_METADATA_TRACK]) {
			NSString *str = [[metadata objectForKey:XLD_METADATA_TRACK] stringValue];
			appendCommentTag(tagData, "COMM", "eng", [NSString stringWithString:@"iTunes_CDDB_TrackNumber"], str, 0);
		}
	}
	
	/* MusicBrainz related tags */
	if([metadata objectForKey:XLD_METADATA_MB_TRACKID]) {
		added = YES;
		NSData *dat = [[metadata objectForKey:XLD_METADATA_MB_TRACKID] dataUsingEncoding:NSISOLatin1StringEncoding];
		NSData *dat2 = [@"http://musicbrainz.org" dataUsingEncoding:NSISOLatin1StringEncoding];
		tmp = [dat length]+[dat2 length]+1;
		tmp = OSSwapHostToBigInt32(tmp);
		tmp2 = 0;
		tmp3 = 0;
		[tagData appendBytes:"UFID" length:4]; //ID
		[tagData appendBytes:&tmp length:4]; //length
		[tagData appendBytes:&tmp2 length:2]; //flag
		[tagData appendData:dat2]; //description
		[tagData appendBytes:&tmp3 length:1]; //termination
		[tagData appendData:dat];
	}
	if([metadata objectForKey:XLD_METADATA_MB_ALBUMID]) {
		added = YES;
		appendCommentTag(tagData, "TXXX", NULL, [NSString stringWithString:@"MusicBrainz Album Id"], [metadata objectForKey:XLD_METADATA_MB_ALBUMID], 0);
	}
	if([metadata objectForKey:XLD_METADATA_MB_ARTISTID]) {
		added = YES;
		appendCommentTag(tagData, "TXXX", NULL, [NSString stringWithString:@"MusicBrainz Artist Id"], [metadata objectForKey:XLD_METADATA_MB_ARTISTID], 0);
	}
	if([metadata objectForKey:XLD_METADATA_MB_ALBUMARTISTID]) {
		added = YES;
		appendCommentTag(tagData, "TXXX", NULL, [NSString stringWithString:@"MusicBrainz Album Artist Id"], [metadata objectForKey:XLD_METADATA_MB_ALBUMARTISTID], 0);
	}
	if([metadata objectForKey:XLD_METADATA_MB_DISCID]) {
		added = YES;
		appendCommentTag(tagData, "TXXX", NULL, [NSString stringWithString:@"MusicBrainz Disc Id"], [metadata objectForKey:XLD_METADATA_MB_DISCID], 0);
	}
	if([metadata objectForKey:XLD_METADATA_PUID]) {
		added = YES;
		appendCommentTag(tagData, "TXXX", NULL, [NSString stringWithString:@"MusicIP PUID"], [metadata objectForKey:XLD_METADATA_PUID], 0);
	}
	if([metadata objectForKey:XLD_METADATA_MB_ALBUMSTATUS]) {
		added = YES;
		appendCommentTag(tagData, "TXXX", NULL, [NSString stringWithString:@"MusicBrainz Album Status"], [metadata objectForKey:XLD_METADATA_MB_ALBUMSTATUS], 1);
	}
	if([metadata objectForKey:XLD_METADATA_MB_ALBUMTYPE]) {
		added = YES;
		appendCommentTag(tagData, "TXXX", NULL, [NSString stringWithString:@"MusicBrainz Album Type"], [metadata objectForKey:XLD_METADATA_MB_ALBUMTYPE], 1);
	}
	if([metadata objectForKey:XLD_METADATA_MB_RELEASECOUNTRY]) {
		added = YES;
		appendCommentTag(tagData, "TXXX", NULL, [NSString stringWithString:@"MusicBrainz Album Release Country"], [metadata objectForKey:XLD_METADATA_MB_RELEASECOUNTRY], 1);
	}
	if([metadata objectForKey:XLD_METADATA_MB_RELEASEGROUPID]) {
		added = YES;
		appendCommentTag(tagData, "TXXX", NULL, [NSString stringWithString:@"MusicBrainz Release Group Id"], [metadata objectForKey:XLD_METADATA_MB_RELEASEGROUPID], 0);
	}
	if([metadata objectForKey:XLD_METADATA_MB_WORKID]) {
		added = YES;
		appendCommentTag(tagData, "TXXX", NULL, [NSString stringWithString:@"MusicBrainz Work Id"], [metadata objectForKey:XLD_METADATA_MB_WORKID], 0);
	}
	
	/* Timecode related tags */
	if([metadata objectForKey:XLD_METADATA_SMPTE_TIMECODE_START]) {
		added = YES;
		appendCommentTag(tagData, "TXXX", NULL, [NSString stringWithString:@"SMPTE_TIMECODE_START"], [metadata objectForKey:XLD_METADATA_SMPTE_TIMECODE_START], 0);
	}
	if([metadata objectForKey:XLD_METADATA_SMPTE_TIMECODE_DURATION]) {
		added = YES;
		appendCommentTag(tagData, "TXXX", NULL, [NSString stringWithString:@"SMPTE_TIMECODE_DURATION"], [metadata objectForKey:XLD_METADATA_SMPTE_TIMECODE_DURATION], 0);
	}
	if([metadata objectForKey:XLD_METADATA_MEDIA_FPS]) {
		added = YES;
		appendCommentTag(tagData, "TXXX", NULL, [NSString stringWithString:@"MEDIA_FPS"], [metadata objectForKey:XLD_METADATA_MEDIA_FPS], 0);
	}
	
	/* APIC */
	if([metadata objectForKey:XLD_METADATA_COVER]) {
		NSData *imgData = [metadata objectForKey:XLD_METADATA_COVER];
		char *mime = NULL;
		int size = [imgData length];
		const unsigned char *data = [imgData bytes];
		if (2 < size && data[0] == 0xFF && data[1] == 0xD8) {
			mime = "image/jpeg";
		}
		else if (4 < size && data[0] == 0x89 && strncmp((const char *) &data[1], "PNG", 3) == 0) {
			mime = "image/png";
		}
		else if (4 < size && strncmp((const char *) data, "GIF8", 4) == 0) {
			mime = "image/gif";
		}
		if(mime) {
			added = YES;
			tmp = [imgData length] + strlen(mime) + 4;
			tmp = OSSwapHostToBigInt32(tmp);
			tmp2 = 0;
			tmp3 = 0;
			memcpy(atomID,"APIC",4);
			[tagData appendBytes:atomID length:4]; //ID
			[tagData appendBytes:&tmp length:4]; //length
			[tagData appendBytes:&tmp2 length:2]; //flag
			[tagData appendBytes:&tmp3 length:1]; //char code (ISO-8859-1)
			[tagData appendBytes:mime length:strlen(mime)+1];
			tmp3 = 3;
			[tagData appendBytes:&tmp3 length:1]; //picture type
			tmp3 = 0;
			[tagData appendBytes:&tmp3 length:1]; //description
			[tagData appendData:imgData];
		}
	}
	
	if(added) {
		/* update length of ID3 header */
		tmp = [tagData length] - 10;
		tmp3 = tmp & 0x7f;
		[tagData replaceBytesInRange:NSMakeRange(9,1) withBytes:&tmp3];
		tmp3 = (tmp >> 7) & 0x7f;
		[tagData replaceBytesInRange:NSMakeRange(8,1) withBytes:&tmp3];
		tmp3 = (tmp >> 14) & 0x7f;
		[tagData replaceBytesInRange:NSMakeRange(7,1) withBytes:&tmp3];
		tmp3 = (tmp >> 21) & 0x7f;
		[tagData replaceBytesInRange:NSMakeRange(6,1) withBytes:&tmp3];
	}
	else [tagData setLength:0];
}

@implementation XLDDSDOutputTask

- (id)init
{
	[super init];
	addTag = YES;
	tagData = [[NSMutableData alloc] init];
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
	if(configurations) [configurations release];
	[tagData release];
	if(soxr) soxr_delete(soxr);
	if(resampleBuffer) free(resampleBuffer);
	if(dsdBuffer) free(dsdBuffer);
	if(dsfWriteBuffer) {
		int i;
		for(i=0;i<format.channels;i++) {
			free(dsfWriteBuffer[i]);
		}
		free(dsfWriteBuffer);
	}
	if(dsm) {
		int i;
		for(i=0;i<format.channels;i++) {
			deltasigma_free(dsm[i]);
		}
		free(dsm);
	}
	[super dealloc];
}

- (BOOL)setOutputFormat:(XLDFormat)fmt
{
	if(fmt.channels > 2) return NO;
	format = fmt;
	
	dsdSamplerate = [[configurations objectForKey:@"DSDSamplerate"] intValue];
	dsdFormat = [[configurations objectForKey:@"DSDFormat"] intValue];
	dsmType = [[configurations objectForKey:@"DSMType"] intValue];
	upRatio = (int)ceil(dsdSamplerate/fmt.samplerate);
	
	soxr_error_t err;
	soxr_io_spec_t spec;
	soxr_quality_spec_t qspec = soxr_quality_spec(SOXR_VHQ, 0);
	if(fmt.isFloat) {
		spec = soxr_io_spec(SOXR_FLOAT32_I, SOXR_FLOAT32_I);
	}
	else {
		spec = soxr_io_spec(SOXR_INT32_I, SOXR_FLOAT32_I);
	}
	soxr = soxr_create(fmt.samplerate,dsdSamplerate,fmt.channels,&err,&spec,&qspec,NULL);
	if(err) {
		fprintf(stderr,"sox resampler initialization error\n");
		return NO;
	}
	
	return YES;
}

- (BOOL)openFileForOutput:(NSString *)str withTrackData:(id)track
{
	[tagData setLength:0];
	
	uint64_t tmp64;
	unsigned int tmp32;
	unsigned short tmp16;
	unsigned char tmp8;
	fpw = fopen([str UTF8String],"wb");
	if(dsdFormat == DSDFileFormatDSDIFF) {
		fwrite("FRM8",1,4,fpw);
		tmp32 = 0;
		fwrite(&tmp32,4,1,fpw);
		fwrite(&tmp32,4,1,fpw);
		fwrite("DSD ",1,4,fpw);
		fwrite("FVER",1,4,fpw);
		fwrite(&tmp32,4,1,fpw);
		tmp32 = OSSwapHostToBigInt32(4);
		fwrite(&tmp32,4,1,fpw);
		tmp32 = OSSwapHostToBigInt32(0x01040000);
		fwrite(&tmp32,4,1,fpw);
		fwrite("PROP",1,4,fpw);
		tmp32 = 0;
		fwrite(&tmp32,4,1,fpw);
		tmp32 = OSSwapHostToBigInt32(format.channels == 1 ? 0x46 : 0x4A);
		fwrite(&tmp32,4,1,fpw);
		fwrite("SND ",1,4,fpw);
		fwrite("FS  ",1,4,fpw);
		tmp32 = 0;
		fwrite(&tmp32,4,1,fpw);
		tmp32 = OSSwapHostToBigInt32(4);
		fwrite(&tmp32,4,1,fpw);
		tmp32 = OSSwapHostToBigInt32(dsdSamplerate);
		fwrite(&tmp32,4,1,fpw);
		fwrite("CHNL",1,4,fpw);
		tmp32 = 0;
		fwrite(&tmp32,4,1,fpw);
		tmp32 = OSSwapHostToBigInt32(format.channels == 1 ? 6 : 0xA);
		fwrite(&tmp32,4,1,fpw);
		tmp16 = OSSwapHostToBigInt16(format.channels);
		fwrite(&tmp16,2,1,fpw);
		if(format.channels == 1)
			fwrite("C	",1,4,fpw);
		else
			fwrite("SLFTSRGT",1,8,fpw);
		fwrite("CMPR",1,4,fpw);
		tmp32 = 0;
		fwrite(&tmp32,4,1,fpw);
		tmp32 = OSSwapHostToBigInt32(0x14);
		fwrite(&tmp32,4,1,fpw);
		fwrite("DSD ",1,4,fpw);
		tmp8 = 0xe;
		fwrite(&tmp8,1,1,fpw);
		fwrite("not compressed",1,15,fpw);
		fwrite("DSD ",1,4,fpw);
		tmp32 = 0;
		fwrite(&tmp32,4,1,fpw);
		fwrite(&tmp32,4,1,fpw);
	}
	else {
		fwrite("DSD ",1,4,fpw);
		tmp64 = OSSwapHostToLittleInt64(28);
		fwrite(&tmp64,8,1,fpw);
		tmp32 = 0;
		fwrite(&tmp32,4,1,fpw);
		fwrite(&tmp32,4,1,fpw);
		fwrite(&tmp32,4,1,fpw);
		fwrite(&tmp32,4,1,fpw);
		fwrite("fmt ",1,4,fpw);
		tmp64 = OSSwapHostToLittleInt64(52);
		fwrite(&tmp64,8,1,fpw);
		tmp32 = OSSwapHostToLittleInt32(1);
		fwrite(&tmp32,4,1,fpw);
		tmp32 = 0;
		fwrite(&tmp32,4,1,fpw);
		tmp32 = OSSwapHostToLittleInt32(format.channels);
		fwrite(&tmp32,4,1,fpw);
		fwrite(&tmp32,4,1,fpw);
		tmp32 = OSSwapHostToLittleInt32(dsdSamplerate);
		fwrite(&tmp32,4,1,fpw);
		tmp32 = OSSwapHostToLittleInt32(1);
		fwrite(&tmp32,4,1,fpw);
		tmp32 = 0;
		fwrite(&tmp32,4,1,fpw);
		fwrite(&tmp32,4,1,fpw);
		tmp32 = OSSwapHostToLittleInt32(4096);
		fwrite(&tmp32,4,1,fpw);
		tmp32 = 0;
		fwrite(&tmp32,4,1,fpw);
		fwrite("data",1,4,fpw);
		fwrite(&tmp32,4,1,fpw);
		fwrite(&tmp32,4,1,fpw);
		
		dsfWriteBuffer = malloc(sizeof(unsigned char*)*format.channels);
		dsfBufferBytes = 0;
		dsfBlocksWritten = 0;
		
		if(addTag) setupID3Tag(tagData, [track metadata]);
	}
	
	int i;
	dsm = malloc(sizeof(xld_deltasigma_t *) * format.channels);
	for(i=0;i<format.channels;i++) {
		dsm[i] = deltasigma_init(dsdFormat, dsmType);
		if(dsfWriteBuffer) dsfWriteBuffer[i] = malloc(4096+4);
	}
	return YES;
}

- (NSString *)extensionStr
{
	DSDFileFormat fileFmt = [[configurations objectForKey:@"DSDFormat"] intValue];
	switch(fileFmt) {
		case DSDFileFormatDSDIFF:
			return @"dff";
		case DSDFileFormatDSF:
			return @"dsf";
	}
	return nil;
}

- (BOOL)writeBuffer:(int *)buffer frames:(int)counts
{
	if(bufferSize < counts) {
		resampleBuffer = realloc(resampleBuffer, counts*sizeof(float)*format.channels*upRatio);
		dsdBuffer = realloc(dsdBuffer, counts*format.channels*upRatio/8);
		bufferSize = counts;
	}
	
	int i, dsdOut;
	size_t done = 0;
	soxr_process(soxr,buffer,counts,NULL,resampleBuffer,counts*upRatio,&done);
	if(dsdFormat == DSDFileFormatDSDIFF) {
		for(i=0;i<format.channels;i++) {
			dsdOut = dsm[i]->modulate(dsm[i],resampleBuffer+i,dsdBuffer+i,done,format.channels);
		}
		dsdSamples += dsdOut;
		fwrite(dsdBuffer,1,dsdOut*format.channels,fpw);
	}
	else {
		for(i=0;i<format.channels;i++) {
			dsdOut = dsm[i]->modulate(dsm[i],resampleBuffer+i,dsdBuffer+counts*i*upRatio/8,done,format.channels);
		}
		dsdSamples += dsdOut;
		unsigned char *ptr = dsdBuffer;
		while(dsdOut + dsfBufferBytes >= 4096) {
			for(i=0;i<format.channels;i++) {
				if(dsfBufferBytes) {
					fwrite(dsfWriteBuffer[i],1,dsfBufferBytes,fpw);
				}
				fwrite(ptr+counts*i*upRatio/8,1,4096-dsfBufferBytes,fpw);
				dsfBlocksWritten++;
			}
			dsdOut -= 4096-dsfBufferBytes;
			ptr += 4096-dsfBufferBytes;
			dsfBufferBytes = 0;
		}
		if(dsdOut) {
			for(i=0;i<format.channels;i++) {
				memcpy(dsfWriteBuffer[i]+dsfBufferBytes, ptr+counts*i*upRatio/8,dsdOut);
			}
			dsfBufferBytes += dsdOut;
		}
	}
	return YES;
}

- (void)finalize
{
	int i, dsdOut;
	size_t done = 0;
	uint64_t tmp64;
	soxr_process(soxr,NULL,0,NULL,resampleBuffer,bufferSize*upRatio,&done);
	if(dsdFormat == DSDFileFormatDSDIFF) {
		for(i=0;i<format.channels;i++) {
			dsdOut = dsm[i]->modulate(dsm[i],resampleBuffer+i,dsdBuffer+i,done,format.channels);
		}
		dsdSamples += dsdOut;
		fwrite(dsdBuffer,1,dsdOut*format.channels,fpw);
		for(i=0;i<format.channels;i++) {
			dsdOut = dsm[i]->finalize(dsm[i],dsdBuffer+i);
		}
		dsdSamples += dsdOut;
		fwrite(dsdBuffer,1,dsdOut*format.channels,fpw);
		//sf_writef_float(sf_w, resampleBuffer, done);
		
		//fprintf(stderr,"total %lld DSD samples",dsdSamples*8);
		
		fseeko(fpw,4,SEEK_SET);
		tmp64 = OSSwapHostToBigInt64(0x6e + format.channels*4 + dsdSamples*format.channels);
		fwrite(&tmp64,8,1,fpw);
		fseeko(fpw,0x72 + format.channels*4,SEEK_SET);
		tmp64 = OSSwapHostToBigInt64(dsdSamples*format.channels);
		fwrite(&tmp64,8,1,fpw);
	}
	else {
		for(i=0;i<format.channels;i++) {
			dsdOut = dsm[i]->modulate(dsm[i],resampleBuffer+i,dsdBuffer+bufferSize*i*upRatio/8,done,format.channels);
		}
		dsdSamples += dsdOut;
		unsigned char *ptr = dsdBuffer;
		while(dsdOut + dsfBufferBytes >= 4096) {
			for(i=0;i<format.channels;i++) {
				if(dsfBufferBytes) {
					fwrite(dsfWriteBuffer[i],1,dsfBufferBytes,fpw);
				}
				fwrite(ptr+bufferSize*i*upRatio/8,1,4096-dsfBufferBytes,fpw);
				dsfBlocksWritten++;
			}
			dsdOut -= 4096-dsfBufferBytes;
			ptr += 4096-dsfBufferBytes;
			dsfBufferBytes = 0;
		}
		if(dsdOut) {
			for(i=0;i<format.channels;i++) {
				memcpy(dsfWriteBuffer[i]+dsfBufferBytes, ptr+bufferSize*i*upRatio/8,dsdOut);
			}
			dsfBufferBytes += dsdOut;
		}
		for(i=0;i<format.channels;i++) {
			dsdOut = dsm[i]->finalize(dsm[i],dsdBuffer+bufferSize*i*upRatio/8);
		}
		dsdSamples += dsdOut;
		ptr = dsdBuffer;
		while(dsdOut + dsfBufferBytes >= 4096) {
			for(i=0;i<format.channels;i++) {
				if(dsfBufferBytes) {
					fwrite(dsfWriteBuffer[i],1,dsfBufferBytes,fpw);
				}
				fwrite(ptr+bufferSize*i*upRatio/8,1,4096-dsfBufferBytes,fpw);
				dsfBlocksWritten++;
			}
			dsdOut -= 4096-dsfBufferBytes;
			ptr += 4096-dsfBufferBytes;
			dsfBufferBytes = 0;
		}
		if(dsdOut) {
			for(i=0;i<format.channels;i++) {
				memcpy(dsfWriteBuffer[i]+dsfBufferBytes, ptr+bufferSize*i*upRatio/8,dsdOut);
			}
			dsfBufferBytes += dsdOut;
		}
		if(dsfBufferBytes) {
			int remaining = 4096 - dsfBufferBytes;
			float *silence = calloc(remaining*8, sizeof(float));
			for(i=0;i<format.channels;i++) {
				dsdOut = dsm[i]->modulate(dsm[i],silence,dsfWriteBuffer[i]+dsfBufferBytes,remaining*8,1);
				fwrite(dsfWriteBuffer[i],1,4096,fpw);
				//fprintf(stderr,"required %d, returned %d\n",remaining,dsdOut);
				dsfBlocksWritten++;
			}
			free(silence);
		}
		fseeko(fpw,12,SEEK_SET);
		tmp64 = OSSwapHostToLittleInt64(0x5c + dsfBlocksWritten*4096 + [tagData length]);
		fwrite(&tmp64,8,1,fpw);
		fseeko(fpw,0x40,SEEK_SET);
		tmp64 = OSSwapHostToLittleInt64(dsdSamples*8);
		fwrite(&tmp64,8,1,fpw);
		fseeko(fpw,0x54,SEEK_SET);
		tmp64 = OSSwapHostToLittleInt64(dsfBlocksWritten*4096+12);
		fwrite(&tmp64,8,1,fpw);
		if([tagData length]) {
			fseeko(fpw,20,SEEK_SET);
			tmp64 = OSSwapHostToLittleInt64(0x5c + dsfBlocksWritten*4096);
			fwrite(&tmp64,8,1,fpw);
			fseeko(fpw,0,SEEK_END);
			fwrite([tagData bytes],1,[tagData length],fpw);
		}
	}
}

- (void)closeFile
{
	if(fpw) fclose(fpw);
	fpw = NULL;
	if(soxr) soxr_delete(soxr);
	soxr = NULL;
	if(resampleBuffer) free(resampleBuffer);
	resampleBuffer = NULL;
	if(dsdBuffer) free(dsdBuffer);
	dsdBuffer = NULL;
	if(dsfWriteBuffer) {
		int i;
		for(i=0;i<format.channels;i++) {
			free(dsfWriteBuffer[i]);
		}
		free(dsfWriteBuffer);
		dsfWriteBuffer = NULL;
	}
	if(dsm) {
		int i;
		for(i=0;i<format.channels;i++) {
			deltasigma_free(dsm[i]);
		}
		free(dsm);
		dsm = NULL;
	}
	bufferSize = 0;
}

- (void)setEnableAddTag:(BOOL)flag
{
	addTag = flag;
}

@end
