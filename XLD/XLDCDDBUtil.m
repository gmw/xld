//
//  XLDCDDBUtil.m
//  XLD
//
//  Created by tmkk on 06/08/25.
//  Copyright 2006 tmkk. All rights reserved.
//

#import "XLDCustomClasses.h"
#import "XLDCDDBUtil.h"
#import "XLDTrack.h"
#import "XLDController.h"
#import "XLDAmazonSearcher.h"
#import "XLDMusicBrainzReleaseList.h"
#import "XLDMusicBrainzRelease.h"
#import "XLDDiscogsRelease.h"
#import <openssl/sha.h>
#import <openssl/bio.h>
#import <openssl/evp.h>
#import <openssl/buffer.h>

static char *base64enc(const unsigned  char *input, int length)
{
	BIO *bmem, *b64;
	BUF_MEM *bptr;
	int i;
	
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
	for(i=0;i<bptr->length;i++) {
		if(buff[i] == '+') buff[i] = '.';
		else if(buff[i] == '/') buff[i] = '_';
		else if(buff[i] == '=') buff[i] = '-';
	}
	
	BIO_free_all(b64);
	
	return buff;
}

@implementation XLDCDDBUtil

- (id)init
{
	[super init];
	disc = cddb_disc_new();
	conn = cddb_new();
	queryResult = [[NSMutableArray alloc] init];
	preferredService = XLDCDDBFreeDBPreferred;
	return self;
}

- (id)initWithDelegate:(id)del
{
	[self init];
	delegate = [del retain];
	return self;
}

- (void)dealloc
{
	if(disc) cddb_disc_destroy(disc);
	if(conn) cddb_destroy(conn);
	if(delegate) [delegate release];
	if(trackArr) [trackArr release];
	[queryResult release];
	if(asin) [asin release];
	if(coverURL) [coverURL release];
	[super dealloc];
}

- (void)setTracks:(NSArray *)tracks totalFrame:(int)frames
{
	SHA_CTX	sha;
	unsigned char	digest[20];
	char *base64;
	char		tmp[17];
	int i;
	
	int totalAudioFrames = frames;
	totalAudioTrack = [tracks count];
	if((totalAudioTrack > 1) && ![[tracks objectAtIndex:totalAudioTrack-1] enabled]) {
		int tmp1,tmp2;
		tmp1 = [(XLDTrack *)[tracks objectAtIndex:totalAudioTrack-1] index];
		tmp2 = [(XLDTrack *)[tracks objectAtIndex:totalAudioTrack-2] index] + [(XLDTrack *)[tracks objectAtIndex:totalAudioTrack-2] frames];
		if((tmp1 - tmp2) == 11400*588) {
			totalAudioTrack--;
			totalAudioFrames = tmp2;
		}
	}
	totalSectors = totalAudioFrames / 588;
	
	cddb_disc_set_length(disc, 2+(unsigned int)(frames/44100.0));
	for (i = 0; i < [tracks count]; i++) {
		cddb_track_t *track = cddb_track_new();
		if (track == NULL) {
			fprintf(stderr, "out of memory, unable to create track");
		}
		cddb_track_set_frame_offset(track, (unsigned int)([(XLDTrack *)[tracks objectAtIndex:i] index]*75.0/44100.0)+150);
		cddb_disc_add_track(disc, track);
	}
	
	SHA1_Init(&sha);
	sprintf(tmp, "%02X", 1);
	SHA1_Update(&sha, (unsigned char *) tmp, strlen(tmp));
	sprintf(toc,"%d",1);
	sprintf(tmp, "%02X", totalAudioTrack);
	SHA1_Update(&sha, (unsigned char *) tmp, strlen(tmp));
	sprintf(toc,"%s+%d",toc,totalAudioTrack);
	sprintf(tmp, "%08X", (unsigned int)((totalAudioFrames*75.0/44100.0)+150));
	SHA1_Update(&sha, (unsigned char *) tmp, strlen(tmp));
	sprintf(toc,"%s+%d",toc,(unsigned int)((totalAudioFrames*75.0/44100.0)+150));
	for (i = 1; i <= totalAudioTrack; i++) {
		sprintf(tmp, "%08X", (unsigned int)([(XLDTrack *)[tracks objectAtIndex:i-1] index]*75.0/44100.0)+150);
		SHA1_Update(&sha, (unsigned char *) tmp, strlen(tmp));
		sprintf(toc,"%s+%d",toc,(unsigned int)([(XLDTrack *)[tracks objectAtIndex:i-1] index]*75.0/44100.0)+150);
	}
	for (; i < 100; i++) {
		sprintf(tmp, "%08X", 0);
		SHA1_Update(&sha, (unsigned char *) tmp, strlen(tmp));
	}
	SHA1_Final(digest, &sha);
	base64 = base64enc(digest, sizeof(digest));
	strcpy(discid, base64);
	free(base64);
	//NSLog(@"%s,%s",discid,toc);
	
	trackArr = [tracks retain];
}

- (void)setUseProxy:(BOOL)flag
{
	useProxy = flag;
}

- (void)setUseCache:(BOOL)flag
{
	if(flag) cddb_cache_enable(conn);
	else cddb_cache_disable(conn);
}

- (void)setServer:(NSString *)server port:(int)port path:(NSString *)path
{
	if(!useProxy) cddb_http_enable(conn);
	else cddb_http_proxy_enable(conn);
	cddb_set_server_port(conn, port);
	cddb_set_server_name(conn, [server UTF8String]);
	cddb_set_http_path_query(conn, [path UTF8String]);
}

- (void)setProxyServer:(NSString *)server port:(int)port user:(NSString *)user passwd:(NSString *)passwd
{
	cddb_set_http_proxy_server_name(conn, [server UTF8String]);
	cddb_set_http_proxy_server_port(conn, port);
	if(user && passwd && [user length] && [passwd length]) {
		cddb_set_http_proxy_credentials(conn, [user UTF8String], [passwd UTF8String]);
	}
}

- (int)query
{
	int i;
	int matches = cddb_query(conn, disc);
	int matchesMB = -1;
	XLDMusicBrainzReleaseList *releases = [[XLDMusicBrainzReleaseList alloc] initWithDiscID:[NSString stringWithUTF8String:discid]];
	NSArray *releaseList = nil;
	if(!releases) matchesMB = 0;
	else {
		releaseList = [releases releaseList];
		matchesMB = [releaseList count];
	}
	//NSLog(@"%d,%d",matches,matchesMB);
	if(matches < 1 && matchesMB < 1) {
		if(matches == -1 && matchesMB == -1) return -1;
		return 0;
	}
	if(matches == -1) matches = 0;
	if(matchesMB == -1) matchesMB = 0;
	
	for(i=0;i<matches;i++) {
		if(cddb_disc_get_artist(disc) && strlen(cddb_disc_get_artist(disc)) > 0 && cddb_disc_get_title(disc) && strlen(cddb_disc_get_title(disc)) > 0) {
			[queryResult addObject:
				[NSArray arrayWithObjects:
					@"FreeDB",
					[NSString stringWithUTF8String:cddb_disc_get_category_str(disc)],
					[NSNumber numberWithUnsignedInt:cddb_disc_get_discid(disc)],
					[NSString stringWithUTF8String:cddb_disc_get_title(disc)],
					[NSString stringWithUTF8String:cddb_disc_get_artist(disc)],
					nil]];
		}
		else if(cddb_disc_get_title(disc) && strlen(cddb_disc_get_title(disc)) > 0) {
			[queryResult addObject:
				[NSArray arrayWithObjects:
					@"FreeDB",
					[NSString stringWithUTF8String:cddb_disc_get_category_str(disc)],
					[NSNumber numberWithUnsignedInt:cddb_disc_get_discid(disc)],
					[NSString stringWithUTF8String:cddb_disc_get_title(disc)],
					nil]];
		}
		else if(cddb_disc_get_artist(disc) && strlen(cddb_disc_get_artist(disc)) > 0) {
			[queryResult addObject:
				[NSArray arrayWithObjects:
					@"FreeDB",
					[NSString stringWithUTF8String:cddb_disc_get_category_str(disc)],
					[NSNumber numberWithUnsignedInt:cddb_disc_get_discid(disc)],
					@"Unknown Title",
					[NSString stringWithUTF8String:cddb_disc_get_artist(disc)],
					nil]];
		}
		else {
			[queryResult addObject:
				[NSArray arrayWithObjects:
					@"FreeDB",
					[NSString stringWithUTF8String:cddb_disc_get_category_str(disc)],
					[NSNumber numberWithUnsignedInt:cddb_disc_get_discid(disc)],
					@"Unknown Title",
					nil]];
		}
		if(i<matches) cddb_query_next(conn,disc);
	}
	
	for(i=0;i<matchesMB;i++) {
		NSDictionary *release = [releaseList objectAtIndex:i];
		NSString *title = [release objectForKey:@"Title"];
		NSString *artist = [release objectForKey:@"Artist"];
		NSString *releaseID = [release objectForKey:@"ReleaseID"];
		if(title && artist) {
			[queryResult addObject:
			 [NSArray arrayWithObjects:
			  @"MusicBrainz",
			  @"dummy",
			  releaseID,
			  title,
			  artist,
			  nil]];
		}
		else if(title) {
			[queryResult addObject:
			 [NSArray arrayWithObjects:
			  @"MusicBrainz",
			  @"dummy",
			  releaseID,
			  title,
			  nil]];
		}
		else if(artist) {
			[queryResult addObject:
			 [NSArray arrayWithObjects:
			  @"MusicBrainz",
			  @"dummy",
			  releaseID,
			  @"Unknown Title",
			  artist,
			  nil]];
		}
		else {
			[queryResult addObject:
			 [NSArray arrayWithObjects:
			  @"MusicBrainz",
			  @"dummy",
			  releaseID,
			  @"Unknown Title",
			  nil]];
		}
		
	}
	
	if(matches && matchesMB && preferredService == XLDCDDBMusicBrainzPreferred) {
		NSArray *arr = [queryResult subarrayWithRange:NSMakeRange(0, matches)];
		[queryResult removeObjectsInRange:NSMakeRange(0, matches)];
		[queryResult addObjectsFromArray:arr];
	}
	
	if(releases) [releases release];
	//NSLog(@"%x",cddb_disc_get_discid(disc));
	return matches+matchesMB;
}

- (NSArray *)queryResult
{
	return queryResult;
}

- (XLDCDDBResult)readCDDBWithInfo:(NSArray *)info
{
	XLDCDDBResult result = XLDCDDBSuccess;
	int i;
	const char *tmp;
	NSString *mcn = nil;
	int flag = [delegate cddbQueryFlag];
	XLDAmazonSearcher *searcher = nil;
	BOOL getCover = NO;
	if(flag&XLDCDDBQueryCoverArtMask) {
		if(!(flag&XLDCDDBQueryEmptyOnlyMask) || ((flag&XLDCDDBQueryEmptyOnlyMask) && ![[[trackArr objectAtIndex:0] metadata] objectForKey:XLD_METADATA_COVER])) {
			getCover = YES;
		}
	}
	
	//XLDDiscogsRelease *discogs = [[XLDDiscogsRelease alloc] initWithReleaseID:@"883337" totalTracks:totalAudioTrack totalSectors:totalSectors];
	//[discogs release];
	
	if(info && [[info objectAtIndex:0] isEqualToString:@"FreeDB"]) {
		cddb_disc_set_category_str(disc,[[info objectAtIndex:1] UTF8String]);
		cddb_disc_set_discid(disc,[[info objectAtIndex:2] unsignedIntValue]);
		if(cddb_read(conn, disc) != 1) {
			result = XLDCDDBConnectionFailure;
			goto GetCover;
		}
		
		for (i = 0; i < [trackArr count]; i++) {
			XLDTrack *trk = [trackArr objectAtIndex:i];
			cddb_track_t *track = cddb_disc_get_track(disc, i);
			if(flag&XLDCDDBQueryTrackTitleMask) {
				tmp = cddb_track_get_title(track);
				int j;
				fprintf(stderr,"track %d\n",i+1);
				for(j=0;j<strlen(tmp);j++) {
					fprintf(stderr,"%02x ",(unsigned char)tmp[j]);
				}
				putchar('\n');
				if(tmp && (strlen(tmp) > 0)) {
					if(!(flag&XLDCDDBQueryEmptyOnlyMask) || ((flag&XLDCDDBQueryEmptyOnlyMask) && ![[trk metadata] objectForKey:XLD_METADATA_TITLE]))
						[[trk metadata] setObject:[NSString stringWithUTF8String:tmp] forKey:XLD_METADATA_TITLE];
				}
			}
			if(flag&XLDCDDBQueryArtistMask) {
				tmp = cddb_track_get_artist(track);
				if(tmp && (strlen(tmp) > 0)) {
					if(!(flag&XLDCDDBQueryEmptyOnlyMask) || ((flag&XLDCDDBQueryEmptyOnlyMask) && ![[trk metadata] objectForKey:XLD_METADATA_ARTIST]))
						[[trk metadata] setObject:[NSString stringWithUTF8String:tmp] forKey:XLD_METADATA_ARTIST];
				}
			}
			if(flag&XLDCDDBQueryDiscTitleMask) {
				tmp = cddb_disc_get_title(disc);
				if(tmp && (strlen(tmp) > 0)) {
					if(!(flag&XLDCDDBQueryEmptyOnlyMask) || ((flag&XLDCDDBQueryEmptyOnlyMask) && ![[trk metadata] objectForKey:XLD_METADATA_ALBUM]))
						[[trk metadata] setObject:[NSString stringWithUTF8String:tmp] forKey:XLD_METADATA_ALBUM];
				}
			}
			if(flag&XLDCDDBQueryGenreMask) {
				tmp = cddb_disc_get_genre(disc);
				if(tmp && (strlen(tmp) > 0)) {
					if(!(flag&XLDCDDBQueryEmptyOnlyMask) || ((flag&XLDCDDBQueryEmptyOnlyMask) && ![[trk metadata] objectForKey:XLD_METADATA_GENRE]))
						[[trk metadata] setObject:[NSString stringWithUTF8String:tmp] forKey:XLD_METADATA_GENRE];
				}
			}
			if(flag&XLDCDDBQueryYearMask) {
				int year = cddb_disc_get_year(disc);
				if(year > 0) {
					if(!(flag&XLDCDDBQueryEmptyOnlyMask) || ((flag&XLDCDDBQueryEmptyOnlyMask) && ![[trk metadata] objectForKey:XLD_METADATA_YEAR]))
						[[trk metadata] setObject:[NSNumber numberWithInt:year] forKey:XLD_METADATA_YEAR];
				}
			}
		}
	}
	else if(info && ([[info objectAtIndex:0] isEqualToString:@"MusicBrainz"] || [[info objectAtIndex:0] isEqualToString:@"MusicBrainz_fromURL"] || [[info objectAtIndex:0] isEqualToString:@"Discogs"])) {
		id release;
		if([[info objectAtIndex:0] isEqualToString:@"Discogs"])
			release = [[XLDDiscogsRelease alloc] initWithReleaseID:[info objectAtIndex:2] totalTracks:totalAudioTrack totalSectors:totalSectors];
		else
			release = [[XLDMusicBrainzRelease alloc] initWithReleaseID:[info objectAtIndex:2] discID:[NSString stringWithUTF8String:discid] totalTracks:totalAudioTrack totalSectors:totalSectors ambiguous:![[info objectAtIndex:0] isEqualToString:@"MusicBrainz"]];
		if(release) {
			NSDictionary *dic = [release disc];
			if(![[dic allKeys] count]) {
				[release release];
				return XLDCDDBInvalidDisc;
			}
			for(i=0;i<[trackArr count];i++) {
				XLDTrack *trk = [trackArr objectAtIndex:i];
				NSDictionary *currentTrack = [[dic objectForKey:@"Tracks"] objectForKey:[NSNumber numberWithInt:i+1]];
				if(!currentTrack) continue;
				if(flag&XLDCDDBQueryTrackTitleMask) {
					NSString *title = [currentTrack objectForKey:@"Title"];
					if(title) {
						if(!(flag&XLDCDDBQueryEmptyOnlyMask) || ((flag&XLDCDDBQueryEmptyOnlyMask) && ![[trk metadata] objectForKey:XLD_METADATA_TITLE]))
							[[trk metadata] setObject:title forKey:XLD_METADATA_TITLE];
					}
				}
				if(flag&XLDCDDBQueryArtistMask) {
					NSString *artist = [currentTrack objectForKey:@"Artist"];
					if(artist) {
						if(!(flag&XLDCDDBQueryEmptyOnlyMask) || ((flag&XLDCDDBQueryEmptyOnlyMask) && ![[trk metadata] objectForKey:XLD_METADATA_ARTIST]))
							[[trk metadata] setObject:artist forKey:XLD_METADATA_ARTIST];
					}
				}
				if(flag&XLDCDDBQueryDiscTitleMask) {
					NSString *discTitle = [dic objectForKey:@"Title"];
					if(discTitle) {
						if(!(flag&XLDCDDBQueryEmptyOnlyMask) || ((flag&XLDCDDBQueryEmptyOnlyMask) && ![[trk metadata] objectForKey:XLD_METADATA_ALBUM]))
							[[trk metadata] setObject:discTitle forKey:XLD_METADATA_ALBUM];
					}
				}
				if(flag&XLDCDDBQueryArtistMask) {
					NSString *artist = [dic objectForKey:@"Artist"];
					if(artist) {
						if(!(flag&XLDCDDBQueryEmptyOnlyMask) || ((flag&XLDCDDBQueryEmptyOnlyMask) && ![[trk metadata] objectForKey:XLD_METADATA_ALBUMARTIST]))
							[[trk metadata] setObject:artist forKey:XLD_METADATA_ALBUMARTIST];
					}
				}
				if(flag&XLDCDDBQueryYearMask) {
					NSString *date = [dic objectForKey:@"Date"];
					int year = 0;
					if(date) year = [date intValue];
					if(date) {
						if(!(flag&XLDCDDBQueryEmptyOnlyMask) || ((flag&XLDCDDBQueryEmptyOnlyMask) && ![[trk metadata] objectForKey:XLD_METADATA_DATE] && ![[trk metadata] objectForKey:XLD_METADATA_YEAR]))
							[[trk metadata] setObject:date forKey:XLD_METADATA_DATE];
					}
					if(year > 0) {
						if(!(flag&XLDCDDBQueryEmptyOnlyMask) || ((flag&XLDCDDBQueryEmptyOnlyMask) && ![[trk metadata] objectForKey:XLD_METADATA_DATE] && ![[trk metadata] objectForKey:XLD_METADATA_YEAR]))
							[[trk metadata] setObject:[NSNumber numberWithInt:year] forKey:XLD_METADATA_YEAR];
					}
				}
				if(flag&XLDCDDBQueryComposerMask) {
					NSString *discTitle = [currentTrack objectForKey:@"Composer"];
					if(discTitle) {
						if(!(flag&XLDCDDBQueryEmptyOnlyMask) || ((flag&XLDCDDBQueryEmptyOnlyMask) && ![[trk metadata] objectForKey:XLD_METADATA_COMPOSER]))
							[[trk metadata] setObject:discTitle forKey:XLD_METADATA_COMPOSER];
					}
				}
				if(flag&XLDCDDBQueryGenreMask) {
					NSString *genre = [dic objectForKey:@"Genre"];
					if(genre) {
						if(!(flag&XLDCDDBQueryEmptyOnlyMask) || ((flag&XLDCDDBQueryEmptyOnlyMask) && ![[trk metadata] objectForKey:XLD_METADATA_GENRE]))
							[[trk metadata] setObject:genre forKey:XLD_METADATA_GENRE];
					}
				}
				/* MusicBrainz related tags */
				if([dic objectForKey:@"DiscID"]) {
					[[trk metadata] setObject:[dic objectForKey:@"DiscID"] forKey:XLD_METADATA_MB_DISCID];
				}
				if([dic objectForKey:@"ReleaseID"]) {
					[[trk metadata] setObject:[dic objectForKey:@"ReleaseID"] forKey:XLD_METADATA_MB_ALBUMID];
				}
				if([dic objectForKey:@"ArtistID"]) {
					[[trk metadata] setObject:[dic objectForKey:@"ArtistID"] forKey:XLD_METADATA_MB_ALBUMARTISTID];
				}
				if([currentTrack objectForKey:@"RecordingID"]) {
					[[trk metadata] setObject:[currentTrack objectForKey:@"RecordingID"] forKey:XLD_METADATA_MB_TRACKID];
				}
				if([currentTrack objectForKey:@"ArtistID"]) {
					[[trk metadata] setObject:[currentTrack objectForKey:@"ArtistID"] forKey:XLD_METADATA_MB_ARTISTID];
				}
				if([currentTrack objectForKey:@"ISRC"] && ![[trk metadata] objectForKey:XLD_METADATA_ISRC]) {
					[[trk metadata] setObject:[currentTrack objectForKey:@"ISRC"] forKey:XLD_METADATA_ISRC];
				}
			}
			asin = [[dic objectForKey:@"ASIN"] retain];
			mcn = [dic objectForKey:@"Barcode"];
			coverURL = [[dic objectForKey:@"CoverURL"] retain];
			if(coverURL && asin) {
				[asin release];
				asin = nil;
			}
			[release release];
		}
		else {
			result = XLDCDDBConnectionFailure;
			goto GetCover;
		}
	}
	
GetCover:
	if(getCover && !coverURL) {
		if(info && ![[info objectAtIndex:0] isEqualToString:@"MusicBrainz"]) {
			for(i=0;!asin&&!mcn&&i<[queryResult count];i++) { // check if mb query exists for image download
				if(![[[queryResult objectAtIndex:i] objectAtIndex:0] isEqualToString:@"MusicBrainz"]) continue;
				XLDMusicBrainzRelease *release = [[XLDMusicBrainzRelease alloc] initWithReleaseID:[[queryResult objectAtIndex:i] objectAtIndex:2] discID:[NSString stringWithUTF8String:discid] totalTracks:totalAudioTrack totalSectors:totalSectors ambiguous:NO];
				if(release) {
					NSDictionary *dic = [release disc];
					asin = [[dic objectForKey:@"ASIN"] retain];
					mcn = [dic objectForKey:@"Barcode"];
					[release release];
				}
			}
		}
		
		if(!asin) {
			if(!mcn) mcn = [[[trackArr objectAtIndex:0] metadata] objectForKey:XLD_METADATA_CATALOG];
			NSDictionary *dic = [delegate awsKeys];
			if(mcn && dic) {
				searcher = [[XLDAmazonSearcher alloc] initWithDomain:[delegate awsDomain]];
				[searcher setBarcode:mcn];
				[searcher setAccessKey:[dic objectForKey:@"Key"] andSecretKey:[dic objectForKey:@"SecretKey"]];
				[searcher doSearch];
				asin = [[searcher ASIN] retain];
				//NSLog(asin);
			}
		}
		
		if(!searcher && asin) {
			NSDictionary *dic = [delegate awsKeys];
			if(dic) {
				searcher = [[XLDAmazonSearcher alloc] initWithDomain:[delegate awsDomain]];
				[searcher setASIN:asin];
				[searcher setAccessKey:[dic objectForKey:@"Key"] andSecretKey:[dic objectForKey:@"SecretKey"]];
				[searcher doSearch];
			}
		}
		
		if(searcher) coverURL = [[searcher imageURL] retain];
		if(!coverURL && asin) {
			coverURL = [[NSURL alloc] initWithString:[NSString stringWithFormat:@"http://ecx.images-amazon.com/images/P/%@.00.LZZZZZZZ.jpg",asin]];
			ambiguous = YES;
		}
		//NSLog(@"%@",coverURL);
	}
	if(searcher) [searcher release];
	return result;
}

- (NSData *)coverData
{
	if(!asin && !coverURL) return nil;
	if(asin) {
		NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://ecx.images-amazon.com/images/P/%@.00._SCRMZZZZZZ_.jpg",asin]];
		NSData *data = [NSData fastDataWithContentsOfURL:url];
		if([data length] > 10000) return data;
	}
	
	if(coverURL) {
		NSData *data = [NSData fastDataWithContentsOfURL:coverURL];
		NSImage *img = [[NSImage alloc] initWithData:data];
		if(img && [img isValid]) {
			if(ambiguous && ([img size].width < 50) && ([img size].height < 50)) {
				[img release];
				return nil;
			}
			[img release];
			return data;
		}
		if(img) [img release];
		return nil;
	}
	
	return nil;
}

- (void)setPreferredService:(XLDCDDBPreferredService)s
{
	preferredService = s;
}

- (NSString *)asin
{
	return asin;
}

- (NSURL *)coverURL
{
	return coverURL;
}

- (BOOL)associateMBDiscID
{
	int matchesMB = 0;
	XLDMusicBrainzReleaseList *releases = [[XLDMusicBrainzReleaseList alloc] initWithDiscID:[NSString stringWithUTF8String:discid]];
	NSArray *releaseList = nil;
	if(!releases) matchesMB = 0;
	else {
		releaseList = [releases releaseList];
		matchesMB = [releaseList count];
		[releases release];
	}
	
	if(!matchesMB) {
		NSString *album = [[[trackArr objectAtIndex:0] metadata] objectForKey:XLD_METADATA_ALBUM];
		NSURL *url;
		if(album) url = [NSURL URLWithString:[NSString stringWithFormat:@"http://musicbrainz.org/cdtoc/attach?toc=%s&filter-release.query=%@",toc,[album stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]];
		else url = [NSURL URLWithString:[NSString stringWithFormat:@"http://musicbrainz.org/cdtoc/attach?toc=%s",toc]];
		[[NSWorkspace sharedWorkspace] openURL:url];
		return YES;
	}
	else return NO;
}

@end
