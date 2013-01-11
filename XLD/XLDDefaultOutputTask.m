//
//  XLDDefaultOutputTask.m
//  XLD
//
//  Created by tmkk on 06/09/08.
//  Copyright 2006 tmkk. All rights reserved.
//

#import "XLDDefaultOutputTask.h"
#import "XLDDefaultOutput.h"
#import "XLDTrack.h"

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

@implementation XLDDefaultOutputTask


- (id)init
{
	[super init];
	memset(&sfinfo,0,sizeof(SF_INFO));
	addTag = YES;
	tagData = [[NSMutableData alloc] init];
	return self;
}

- (id)initWithConfigurations:(NSDictionary *)cfg
{
	[self init];
	configurations = [cfg retain];
	sfinfo.format = [[configurations objectForKey:@"SFFormat"] unsignedIntValue];
	return self;
}

- (void)dealloc
{
	if(sf_w) sf_close(sf_w);
	if(path) [path release];
	if(configurations) [configurations release];
	[tagData release];
	[super dealloc];
}

- (BOOL)setOutputFormat:(XLDFormat)fmt
{
	inFormat = fmt;
	sfinfo.samplerate = fmt.samplerate;
	sfinfo.channels = fmt.channels;
	
	/* BitDepth == 0 if same as original */
	int bps = [[configurations objectForKey:@"BitDepth"] intValue] ? [[configurations objectForKey:@"BitDepth"] intValue] : fmt.bps;
	int isFloat = [[configurations objectForKey:@"BitDepth"] intValue] ? [[configurations objectForKey:@"IsFloat"] intValue] : fmt.isFloat;
	
	switch(bps) {
		case 1:
			if((sfinfo.format&SF_FORMAT_TYPEMASK) == SF_FORMAT_WAV) sfinfo.format |= SF_FORMAT_PCM_U8;
			else sfinfo.format |= SF_FORMAT_PCM_S8;
			break;
		case 2:
			sfinfo.format |= SF_FORMAT_PCM_16;
			break;
		case 3:
			sfinfo.format |= SF_FORMAT_PCM_24;
			break;
		case 4:
			if(isFloat) sfinfo.format |= SF_FORMAT_FLOAT;
			else sfinfo.format |= SF_FORMAT_PCM_32;
			break;
		default:
			return NO;
	}
	
	return YES;
}

- (BOOL)openFileForOutput:(NSString *)str withTrackData:(id)track
{
	sf_w = sf_open([str UTF8String], SFM_WRITE, &sfinfo);
	if(!sf_w) {
		return NO;
	}
	if(sf_error(sf_w)) {
		return NO;
	}
	sf_command(sf_w, SFC_SET_SCALE_INT_FLOAT_WRITE, NULL, SF_TRUE) ;
	path = [str retain];
	
	[tagData setLength:0];
	BOOL addId3Tag = NO;
	BOOL addWavInfoTag = NO;
	if((sfinfo.format&SF_FORMAT_TYPEMASK) == SF_FORMAT_AIFF) addId3Tag = YES;
	else if((sfinfo.format&SF_FORMAT_TYPEMASK) == SF_FORMAT_WAV) {
		if([configurations objectForKey:@"WavTagFormat"]) {
			int tagFormat = [[configurations objectForKey:@"WavTagFormat"] intValue];
			if(tagFormat >= 1) addId3Tag = YES;
			if(tagFormat == 0 || tagFormat == 2) addWavInfoTag = YES;
		}
	}
	if(addTag && addId3Tag) {
		int tmp;
		short tmp2;
		char tmp3;
		char atomID[4];
		BOOL added = NO;
		
		/* ID3  atom */
		tmp = 0;
		if((sfinfo.format&SF_FORMAT_TYPEMASK) == SF_FORMAT_AIFF)
			memcpy(atomID,"ID3 ",4);
		else memcpy(atomID,"id3 ",4);
		[tagData appendBytes:atomID length:4];
		[tagData appendBytes:&tmp length:4]; // chunk size (unknown atm)
		
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
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLE]) {
			added = YES;
			appendTextTag(tagData, "TIT2", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLE], 1);
		}
		
		/* TPE1 */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTIST]) {
			added = YES;
			appendTextTag(tagData, "TPE1", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTIST], 1);
		}
		
		/* TPE2 */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMARTIST]) {
			added = YES;
			appendTextTag(tagData, "TPE2", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMARTIST], 1);
		}
		
		/* TALB */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUM]) {
			added = YES;
			appendTextTag(tagData, "TALB", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUM], 1);
		}
		
		/* TCON */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GENRE]) {
			added = YES;
			appendTextTag(tagData, "TCON", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GENRE], 1);
		}
		
		/* TCOM */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPOSER]) {
			added = YES;
			appendTextTag(tagData, "TCOM", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPOSER], 1);
		}
		
		/* TRCK */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TRACK]) {
			added = YES;
			NSString *str;
			if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALTRACKS])
				str = [NSString stringWithFormat:@"%d/%d",[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TRACK] intValue],[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALTRACKS] intValue]];
			else
				str = [NSString stringWithFormat:@"%d",[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TRACK] intValue]];
			appendTextTag(tagData, "TRCK", str, 0);
		}
		
		/* TPOS */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DISC] || [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALDISCS]) {
			added = YES;
			NSString *str;
			if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALDISCS])
				str = [NSString stringWithFormat:@"%d/%d",[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DISC] intValue],[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALDISCS] intValue]];
			else
				str = [NSString stringWithFormat:@"%d",[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DISC] intValue]];
			appendTextTag(tagData, "TPOS", str, 0);
		}
		
		/* TYER */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DATE]) {
			added = YES;
			appendTextTag(tagData, "TYER", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DATE], 1);
		}
		else if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_YEAR]) {
			added = YES;
			NSString *str = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_YEAR] stringValue];
			appendTextTag(tagData, "TYER", str, 0);
		}
		
		/* TIT1 */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GROUP]) {
			added = YES;
			appendTextTag(tagData, "TIT1", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GROUP], 1);
		}
		
		/* TSOT */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLESORT]) {
			added = YES;
			appendTextTag(tagData, "TSOT", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLESORT], 1);
		}
		
		/* TSOP */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTISTSORT]) {
			added = YES;
			appendTextTag(tagData, "TSOP", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTISTSORT], 1);
		}
		
		/* TSOA */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMSORT]) {
			added = YES;
			appendTextTag(tagData, "TSOA", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMSORT], 1);
		}
		
		/* TSO2 */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMARTISTSORT]) {
			added = YES;
			appendTextTag(tagData, "TSO2", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMARTISTSORT], 1);
		}
		
		/* TSOC */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPOSERSORT]) {
			added = YES;
			appendTextTag(tagData, "TSOC", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPOSERSORT], 1);
		}
		
		/* TBPM */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_BPM]) {
			added = YES;
			unsigned int bpm = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_BPM] unsignedShortValue];
			NSString *str = [NSString stringWithFormat:@"%u",bpm];
			appendTextTag(tagData, "TBPM", str, 0);
		}
		
		/* TCMP */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPILATION]) {
			if([[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPILATION] boolValue]) {
				added = YES;
				appendTextTag(tagData, "TCMP", [NSString stringWithString:@"1"], 0);
			}
		}
		
		/* TSRC */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ISRC]) {
			added = YES;
			appendTextTag(tagData, "TSRC", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ISRC], 0);
		}
		
		/* COMM (gapless album) */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GAPLESSALBUM] && [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GAPLESSALBUM] boolValue]) {
			added = YES;
			appendCommentTag(tagData, "COMM", "eng", [NSString stringWithString:@"iTunPGAP"], [NSString stringWithString:@"1"], 0);
		}
		
		/* COMM */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMMENT]) {
			added = YES;
			appendCommentTag(tagData, "COMM", "eng", [NSString stringWithString:@""], [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMMENT], 1);
		}
		
		/* USLT */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_LYRICS]) {
			added = YES;
			appendCommentTag(tagData, "USLT", "eng", [NSString stringWithString:@""], [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_LYRICS], 1);
		}
		
		/* COMM (iTunes_CDDB_1) */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GRACENOTE2]) {
			added = YES;
			appendCommentTag(tagData, "COMM", "eng", [NSString stringWithString:@"iTunes_CDDB_1"], [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GRACENOTE2], 0);
			if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TRACK]) {
				NSString *str = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TRACK] stringValue];
				appendCommentTag(tagData, "COMM", "eng", [NSString stringWithString:@"iTunes_CDDB_TrackNumber"], str, 0);
			}
		}
		
		/* MusicBrainz related tags */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_TRACKID]) {
			added = YES;
			NSData *dat = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_TRACKID] dataUsingEncoding:NSISOLatin1StringEncoding];
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
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMID]) {
			added = YES;
			appendCommentTag(tagData, "TXXX", NULL, [NSString stringWithString:@"MusicBrainz Album Id"], [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMID], 0);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ARTISTID]) {
			added = YES;
			appendCommentTag(tagData, "TXXX", NULL, [NSString stringWithString:@"MusicBrainz Artist Id"], [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ARTISTID], 0);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMARTISTID]) {
			added = YES;
			appendCommentTag(tagData, "TXXX", NULL, [NSString stringWithString:@"MusicBrainz Album Artist Id"], [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMARTISTID], 0);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_DISCID]) {
			added = YES;
			appendCommentTag(tagData, "TXXX", NULL, [NSString stringWithString:@"MusicBrainz Disc Id"], [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_DISCID], 0);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_PUID]) {
			added = YES;
			appendCommentTag(tagData, "TXXX", NULL, [NSString stringWithString:@"MusicIP PUID"], [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_PUID], 0);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMSTATUS]) {
			added = YES;
			appendCommentTag(tagData, "TXXX", NULL, [NSString stringWithString:@"MusicBrainz Album Status"], [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMSTATUS], 1);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMTYPE]) {
			added = YES;
			appendCommentTag(tagData, "TXXX", NULL, [NSString stringWithString:@"MusicBrainz Album Type"], [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMTYPE], 1);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASECOUNTRY]) {
			added = YES;
			appendCommentTag(tagData, "TXXX", NULL, [NSString stringWithString:@"MusicBrainz Album Release Country"], [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASECOUNTRY], 1);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASEGROUPID]) {
			added = YES;
			appendCommentTag(tagData, "TXXX", NULL, [NSString stringWithString:@"MusicBrainz Release Group Id"], [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASEGROUPID], 0);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_WORKID]) {
			added = YES;
			appendCommentTag(tagData, "TXXX", NULL, [NSString stringWithString:@"MusicBrainz Work Id"], [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_WORKID], 0);
		}
		
		/* APIC */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COVER]) {
			NSData *imgData = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COVER];
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
			/* update length of ID3  atom */
			tmp = [tagData length] - 8;
			if((sfinfo.format&SF_FORMAT_TYPEMASK) == SF_FORMAT_AIFF)
				tmp = OSSwapHostToBigInt32(tmp);
			else tmp = OSSwapHostToLittleInt32(tmp);
			[tagData replaceBytesInRange:NSMakeRange(4,4) withBytes:&tmp];
			
			/* update length of ID3 header */
			tmp = [tagData length] - 18;
			tmp3 = tmp & 0x7f;
			[tagData replaceBytesInRange:NSMakeRange(17,1) withBytes:&tmp3];
			tmp3 = (tmp >> 7) & 0x7f;
			[tagData replaceBytesInRange:NSMakeRange(16,1) withBytes:&tmp3];
			tmp3 = (tmp >> 14) & 0x7f;
			[tagData replaceBytesInRange:NSMakeRange(15,1) withBytes:&tmp3];
			tmp3 = (tmp >> 21) & 0x7f;
			[tagData replaceBytesInRange:NSMakeRange(14,1) withBytes:&tmp3];
			
			/* odd byte length requires padding */
			if([tagData length] & 1) [tagData increaseLengthBy:1];
		}
		else [tagData setLength:0];
	}
	if(addTag && addWavInfoTag) {
		NSStringEncoding encoding = NSUTF8StringEncoding;
		if([configurations objectForKey:@"WavTagEncoding"]) {
			int tagEncoding = [[configurations objectForKey:@"WavTagEncoding"] intValue];
			if(tagEncoding == 0) encoding = NSUTF8StringEncoding;
			else if(tagEncoding == 1) encoding = NSISOLatin1StringEncoding;
			else if(tagEncoding == 2) encoding = [NSString defaultCStringEncoding];
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLE]) {
			sf_set_string(sf_w,SF_STR_TITLE,[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLE] cStringUsingEncoding:encoding]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTIST]) {
			sf_set_string(sf_w,SF_STR_ARTIST,[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTIST] cStringUsingEncoding:encoding]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DATE]) {
			sf_set_string(sf_w,SF_STR_DATE,[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DATE] cStringUsingEncoding:encoding]);
		}
		else if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_YEAR]) {
			sf_set_string(sf_w,SF_STR_DATE,[[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_YEAR] stringValue] cStringUsingEncoding:encoding]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GENRE]) {
			sf_set_string(sf_w,SF_STR_GENRE,[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GENRE] cStringUsingEncoding:encoding]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMMENT]) {
			sf_set_string(sf_w,SF_STR_COMMENT,[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMMENT] cStringUsingEncoding:encoding]);
		}
	}
	
	return YES;
}

- (NSString *)extensionStr
{
	switch(sfinfo.format&SF_FORMAT_TYPEMASK) {
		case SF_FORMAT_AIFF:
			return @"aiff";
		case SF_FORMAT_WAV:
			return @"wav";
		case SF_FORMAT_RAW:
			return @"pcm";
		case SF_FORMAT_W64:
			return @"w64";
	}
	return nil;
}

- (BOOL)writeBuffer:(int *)buffer frames:(int)counts
{
	if(inFormat.isFloat)
		sf_writef_float(sf_w,(float *)buffer,counts);
	else sf_writef_int(sf_w,buffer,counts);
	
	if(sf_error(sf_w)) {
		return NO;
	}
	return YES;
}

- (void)finalize
{
	if(!addTag || ![tagData length]) return;
	if(sf_w) sf_close(sf_w);
	sf_w = NULL;
	
	FILE *fp = fopen([path UTF8String], "r+");
	if(!fp) return;
	int tmp;
	char atom[4];
	
	if((sfinfo.format&SF_FORMAT_TYPEMASK) == SF_FORMAT_AIFF) {
		while(1) { //skip until FORM;
			if(fread(atom,1,4,fp) < 4) goto end;
			if(fread(&tmp,4,1,fp) < 1) goto end;
			tmp = OSSwapBigToHostInt32(tmp);
			if(!memcmp(atom,"FORM",4)) break;
			if(fseeko(fp,tmp,SEEK_CUR) != 0) goto end;
		}
		if(fseeko(fp,-4,SEEK_CUR) != 0) goto end;
		tmp = tmp + [tagData length];
		tmp = OSSwapHostToBigInt32(tmp);
		if(fwrite(&tmp,4,1,fp) < 1) goto end;
		
		tmp = OSSwapBigToHostInt32(tmp);
		tmp = tmp - [tagData length];
		if(fseeko(fp,tmp,SEEK_CUR) != 0) goto end;
		if(fwrite([tagData bytes],1,[tagData length],fp) < [tagData length]) goto end;
	}
	else {
		while(1) { //skip until RIFF;
			if(fread(atom,1,4,fp) < 4) goto end;
			if(fread(&tmp,4,1,fp) < 1) goto end;
			tmp = OSSwapLittleToHostInt32(tmp);
			if(!memcmp(atom,"RIFF",4)) break;
			if(fseeko(fp,tmp,SEEK_CUR) != 0) goto end;
		}
		if(fseeko(fp,-4,SEEK_CUR) != 0) goto end;
		tmp = tmp + [tagData length];
		tmp = OSSwapHostToLittleInt32(tmp);
		if(fwrite(&tmp,4,1,fp) < 1) goto end;
		
		tmp = OSSwapLittleToHostInt32(tmp);
		tmp = tmp - [tagData length];
		if(fseeko(fp,tmp,SEEK_CUR) != 0) goto end;
		if(fwrite([tagData bytes],1,[tagData length],fp) < [tagData length]) goto end;
	}
	
end:
		
	fclose(fp);
}

- (void)closeFile
{
	if(sf_w) sf_close(sf_w);
	sf_w = NULL;
	if(path) [path release];
	path = NULL;
	[tagData setLength:0];
}

- (void)setEnableAddTag:(BOOL)flag
{
	addTag = flag;
}

@end
