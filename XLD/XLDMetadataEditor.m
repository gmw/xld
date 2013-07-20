//
//  XLDMetadataEditor.m
//  XLD
//
//  Created by tmkk on 08/07/05.
//  Copyright 2008 tmkk. All rights reserved.
//

#import "XLDMetadataEditor.h"
#import "XLDController.h"
#import "XLDTrack.h"
//#import "XLDDragImageView.h"
#import "XLDShadowedImageView.h"
#import "XLDCustomClasses.h"
#import "XLDMetadataTextParser.h"
#import "XLDCueParser.h"
#import "XLDDiscView.h"

static const char* ID3v1GenreList[] = {
    "Blues", "Classic Rock", "Country", "Dance", "Disco", "Funk",
    "Grunge", "Hip-Hop", "Jazz", "Metal", "New Age", "Oldies",
    "Other", "Pop", "R&B", "Rap", "Reggae", "Rock",
    "Techno", "Industrial", "Alternative", "Ska", "Death Metal", "Pranks",
    "Soundtrack", "Euro-Techno", "Ambient", "Trip-Hop", "Vocal", "Jazz+Funk",
    "Fusion", "Trance", "Classical", "Instrumental", "Acid", "House",
    "Game", "Sound Clip", "Gospel", "Noise", "AlternRock", "Bass",
    "Soul", "Punk", "Space", "Meditative", "Instrumental Pop", "Instrumental Rock",
    "Ethnic", "Gothic", "Darkwave", "Techno-Industrial", "Electronic", "Pop-Folk",
    "Eurodance", "Dream", "Southern Rock", "Comedy", "Cult", "Gangsta",
    "Top 40", "Christian Rap", "Pop/Funk", "Jungle", "Native American", "Cabaret",
    "New Wave", "Psychadelic", "Rave", "Showtunes", "Trailer", "Lo-Fi",
    "Tribal", "Acid Punk", "Acid Jazz", "Polka", "Retro", "Musical",
    "Rock & Roll", "Hard Rock", "Folk", "Folk/Rock", "National Folk", "Swing",
    "Fast-Fusion", "Bebob", "Latin", "Revival", "Celtic", "Bluegrass", "Avantgarde",
    "Gothic Rock", "Progressive Rock", "Psychedelic Rock", "Symphonic Rock", "Slow Rock", "Big Band",
    "Chorus", "Easy Listening", "Acoustic", "Humour", "Speech", "Chanson",
    "Opera", "Chamber Music", "Sonata", "Symphony", "Booty Bass", "Primus",
    "Porn Groove", "Satire", "Slow Jam", "Club", "Tango", "Samba",
    "Folklore", "Ballad", "Power Ballad", "Rhythmic Soul", "Freestyle", "Duet",
    "Punk Rock", "Drum Solo", "A capella", "Euro-House", "Dance Hall",
    "Goa", "Drum & Bass", "Club House", "Hardcore", "Terror",
    "Indie", "BritPop", "NegerPunk", "Polsk Punk", "Beat",
    "Christian Gangsta", "Heavy Metal", "Black Metal", "Crossover", "Contemporary C",
    "Christian Rock", "Merengue", "Salsa", "Thrash Metal", "Anime", "JPop",
    "SynthPop", "Bootleg",
};

@implementation XLDMetadataEditor

- (id)init
{
	[super init];
	[NSBundle loadNibNamed:@"MetadataEditor" owner:self];
	NSMutableArray *arr = [[NSMutableArray alloc] init];
	int i;
	for(i=0;i<sizeof(ID3v1GenreList)/sizeof(*ID3v1GenreList);i++) {
		[arr addObject:[NSString stringWithUTF8String:ID3v1GenreList[i]]];
	}
	[o_genre addItemsWithObjectValues:[arr sortedArrayUsingSelector:@selector(compare:)]];
	[o_allGenre addItemsWithObjectValues:[arr sortedArrayUsingSelector:@selector(compare:)]];
	[o_singleGenre addItemsWithObjectValues:[arr sortedArrayUsingSelector:@selector(compare:)]];
	[arr release];
	//[o_picture setAutoResize:NO];
	//[o_picture setAcceptDrag:YES];
	[o_picture setShadowColor:[NSColor clearColor]];
	[o_singleTitle setTag:0];
	[o_singleArtist setTag:1];
	[o_singleAlbum setTag:2];
	[o_singleAlbumArtist setTag:3];
	[o_singleGenre setTag:4];
	[o_singleComposer setTag:5];
	[o_singleYear setTag:6];
	[o_track setTag:7];
	[o_totalTrack setTag:8];
	[o_singleDisc setTag:9];
	[o_singleTotalDisc setTag:10];
	[o_picture setTag:11];
	[o_singleComment setTag:12];
	[o_singleCompilation setTag:13];
	[o_title setTag:100];
	[o_artist setTag:101];
	[o_album setTag:102];
	[o_albumArtist setTag:103];
	[o_genre setTag:104];
	[o_composer setTag:105];
	[o_year setTag:106];
	[o_disc setTag:109];
	[o_totalDisc setTag:110];
	[o_comment setTag:112];
	[o_compilation setTag:113];
	
	NSMenu *menu = [[NSMenu alloc] init];
	NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:LS(@"Apply This Item for All Files") action:@selector(applyForAll:) keyEquivalent:@""];
	[item setTarget:self];
	[item setTag:[o_singleCompilation tag]];
	[menu insertItem:item atIndex:0];
	[item release];
	item = [[NSMenuItem alloc] initWithTitle:LS(@"Apply This Item for the Same Album") action:@selector(applyForAlbum:) keyEquivalent:@""];
	[item setTarget:self];
	[item setTag:[o_singleCompilation tag]];
	[menu insertItem:item atIndex:1];
	[item release];
	[o_singleCompilation setMenu:menu];
	[menu release];
	
	menu = [[NSMenu alloc] init];
	item = [[NSMenuItem alloc] initWithTitle:LS(@"Apply This Item for All Tracks") action:@selector(applyForAll:) keyEquivalent:@""];
	[item setTarget:self];
	[item setTag:[o_compilation tag]];
	[menu insertItem:item atIndex:0];
	[item release];
	[o_compilation setMenu:menu];
	[menu release];
	
	[o_trackEditor setDelegate:self];
	
	[o_textParserText setFont:[NSFont systemFontOfSize:12]];
	[o_textParserMatching setAutoenablesItems:NO];
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
	if(delegate) [delegate release];
	if(fieldEditor) [fieldEditor release];
	[super dealloc];
}

- (void)getMetadataForIndex:(int)index
{
	XLDTrack *track = [currentTracks objectAtIndex:index];
	
	id obj;
	if(obj=[[track metadata] objectForKey:XLD_METADATA_TITLE]) {
		[o_title setStringValue:obj];
	}
	else [o_title setStringValue:@""];
	if(obj=[[track metadata] objectForKey:XLD_METADATA_ARTIST]) {
		[o_artist setStringValue:obj];
	}
	else [o_artist setStringValue:@""];
	if(obj=[[track metadata] objectForKey:XLD_METADATA_ALBUM]) {
		[o_album setStringValue:obj];
	}
	else [o_album setStringValue:@""];
	if(obj=[[track metadata] objectForKey:XLD_METADATA_ALBUMARTIST]) {
		[o_albumArtist setStringValue:obj];
	}
	else [o_albumArtist setStringValue:@""];
	if(obj=[[track metadata] objectForKey:XLD_METADATA_GENRE]) {
		[o_genre setStringValue:obj];
	}
	else [o_genre setStringValue:@""];
	if(obj=[[track metadata] objectForKey:XLD_METADATA_COMPOSER]) {
		[o_composer setStringValue:obj];
	}
	else [o_composer setStringValue:@""];
	if(obj=[[track metadata] objectForKey:XLD_METADATA_COMMENT]) {
		[o_comment setStringValue:obj];
	}
	else [o_comment setStringValue:@""];
	if(obj=[[track metadata] objectForKey:XLD_METADATA_DISC]) {
		[o_disc setIntValue:[obj intValue]];
	}
	else [o_disc setStringValue:@""];
	if(obj=[[track metadata] objectForKey:XLD_METADATA_TOTALDISCS]) {
		[o_totalDisc setIntValue:[obj intValue]];
	}
	else [o_totalDisc setStringValue:@""];
	if(obj=[[track metadata] objectForKey:XLD_METADATA_DATE]) {
		[o_year setStringValue:obj];
	}
	else if(obj=[[track metadata] objectForKey:XLD_METADATA_YEAR]) {
		[o_year setIntValue:[obj intValue]];
	}
	else [o_year setStringValue:@""];
	if(obj=[[track metadata] objectForKey:XLD_METADATA_COMPILATION]) {
		if([obj boolValue]) [o_compilation setState:NSOnState];
		else [o_compilation setState:NSOffState];
	}
	else [o_compilation setState:NSOffState];
}

- (void)setMetadataForIndex:(int)index
{
	XLDTrack *track = [currentTracks objectAtIndex:index];
	
	if([[o_title stringValue] isEqualToString:@""]) {
		[[track metadata] removeObjectForKey:XLD_METADATA_TITLE];
	}
	else {
		[[track metadata] setObject:[o_title stringValue] forKey:XLD_METADATA_TITLE];
	}
	if([[o_artist stringValue] isEqualToString:@""]) {
		[[track metadata] removeObjectForKey:XLD_METADATA_ARTIST];
	}
	else {
		[[track metadata] setObject:[o_artist stringValue] forKey:XLD_METADATA_ARTIST];
	}
	if([[o_album stringValue] isEqualToString:@""]) {
		[[track metadata] removeObjectForKey:XLD_METADATA_ALBUM];
	}
	else {
		[[track metadata] setObject:[o_album stringValue] forKey:XLD_METADATA_ALBUM];
	}
	if([[o_albumArtist stringValue] isEqualToString:@""]) {
		[[track metadata] removeObjectForKey:XLD_METADATA_ALBUMARTIST];
	}
	else {
		[[track metadata] setObject:[o_albumArtist stringValue] forKey:XLD_METADATA_ALBUMARTIST];
	}
	if([[o_genre stringValue] isEqualToString:@""]) {
		[[track metadata] removeObjectForKey:XLD_METADATA_GENRE];
	}
	else {
		[[track metadata] setObject:[o_genre stringValue] forKey:XLD_METADATA_GENRE];
	}
	if([[o_composer stringValue] isEqualToString:@""]) {
		[[track metadata] removeObjectForKey:XLD_METADATA_COMPOSER];
	}
	else {
		[[track metadata] setObject:[o_composer stringValue] forKey:XLD_METADATA_COMPOSER];
	}
	if([[o_comment stringValue] isEqualToString:@""]) {
		[[track metadata] removeObjectForKey:XLD_METADATA_COMMENT];
	}
	else {
		[[track metadata] setObject:[o_comment stringValue] forKey:XLD_METADATA_COMMENT];
	}
	if([[o_disc stringValue] isEqualToString:@""]) {
		[[track metadata] removeObjectForKey:XLD_METADATA_DISC];
	}
	else {
		[[track metadata] setObject:[NSNumber numberWithInt:[o_disc intValue]] forKey:XLD_METADATA_DISC];
	}
	if([[o_totalDisc stringValue] isEqualToString:@""]) {
		[[track metadata] removeObjectForKey:XLD_METADATA_TOTALDISCS];
	}
	else {
		[[track metadata] setObject:[NSNumber numberWithInt:[o_totalDisc intValue]] forKey:XLD_METADATA_TOTALDISCS];
	}
	if([[o_year stringValue] isEqualToString:@""]) {
		[[track metadata] removeObjectForKey:XLD_METADATA_YEAR];
		[[track metadata] removeObjectForKey:XLD_METADATA_DATE];
	}
	else {
		int year = [o_year intValue];
		if(year >= 1000 && year < 3000)
			[[track metadata] setObject:[NSNumber numberWithInt:year] forKey:XLD_METADATA_YEAR];
		[[track metadata] setObject:[o_year stringValue] forKey:XLD_METADATA_DATE];
	}
	if([o_compilation state] == NSOffState) {
		[[track metadata] removeObjectForKey:XLD_METADATA_COMPILATION];
	}
	else {
		[[track metadata] setObject:[NSNumber numberWithBool:YES] forKey:XLD_METADATA_COMPILATION];
	}
}

- (void)setMetadataForAllTracksWithTag:(int)tag
{
	int i;
	id obj=nil,key=nil;
	BOOL remove = NO;
	if(tag==100) {
		key = XLD_METADATA_TITLE;
		obj = [o_title stringValue];
		if([[o_title stringValue] isEqualToString:@""]) {
			remove = YES;
		}
	}
	else if(tag==101) {
		key = XLD_METADATA_ARTIST;
		obj = [o_artist stringValue];
		if([[o_artist stringValue] isEqualToString:@""]) {
			remove = YES;
		}
	}
	else if(tag==102) {
		key = XLD_METADATA_ALBUM;
		obj = [o_album stringValue];
		if([[o_album stringValue] isEqualToString:@""]) {
			remove = YES;
		}
	}
	else if(tag==103) {
		key = XLD_METADATA_ALBUMARTIST;
		obj = [o_albumArtist stringValue];
		if([[o_albumArtist stringValue] isEqualToString:@""]) {
			remove = YES;
		}
	}
	else if(tag==104) {
		key = XLD_METADATA_GENRE;
		obj = [o_genre stringValue];
		if([[o_genre stringValue] isEqualToString:@""]) {
			remove = YES;
		}
	}
	else if(tag==105) {
		key = XLD_METADATA_COMPOSER;
		obj = [o_composer stringValue];
		if([[o_composer stringValue] isEqualToString:@""]) {
			remove = YES;
		}
	}
	else if(tag==106) {
		key = XLD_METADATA_DATE;
		obj = [o_year stringValue];
		if([[o_year stringValue] isEqualToString:@""]) {
			remove = YES;
		}
	}
	else if(tag==109) {
		key = XLD_METADATA_DISC;
		obj = [NSNumber numberWithInt:[o_disc intValue]];
		if([[o_disc stringValue] isEqualToString:@""]) {
			remove = YES;
		}
	}
	else if(tag==110) {
		key = XLD_METADATA_TOTALDISCS;
		obj = [NSNumber numberWithInt:[o_totalDisc intValue]];
		if([[o_totalDisc stringValue] isEqualToString:@""]) {
			remove = YES;
		}
	}
	else if(tag==112) {
		key = XLD_METADATA_COMMENT;
		obj = [o_comment stringValue];
		if([[o_comment stringValue] isEqualToString:@""]) {
			remove = YES;
		}
	}
	else if(tag==113) {
		key = XLD_METADATA_COMPILATION;
		obj = [NSNumber numberWithBool:YES];
		if([o_compilation state] == NSOffState) {
			remove = YES;
		}
	}
	
	for(i=0;i<[currentTracks count];i++) {
		XLDTrack *currentTrack = [currentTracks objectAtIndex:i];
		if(remove) {
			[[currentTrack metadata] removeObjectForKey:key];
			if([key isEqualToString:XLD_METADATA_DATE]) [[currentTrack metadata] removeObjectForKey:XLD_METADATA_YEAR];
		}
		else {
			if(obj && key) [[currentTrack metadata] setObject:obj forKey:key];
			if([key isEqualToString:XLD_METADATA_DATE]) {
				int year = [o_year intValue];
				if(year >= 1000 && year < 3000)
					[[currentTrack metadata] setObject:[NSNumber numberWithInt:year] forKey:XLD_METADATA_YEAR];
			}
		}
	}
}

- (void)getSingleMetadataForIndex:(int)index
{
	XLDTrack *track = [currentSingleTracks objectAtIndex:index];
	
	id obj;
	if(obj=[[track metadata] objectForKey:XLD_METADATA_TITLE]) {
		[o_singleTitle setStringValue:obj];
	}
	else [o_singleTitle setStringValue:@""];
	if(obj=[[track metadata] objectForKey:XLD_METADATA_ARTIST]) {
		[o_singleArtist setStringValue:obj];
	}
	else [o_singleArtist setStringValue:@""];
	if(obj=[[track metadata] objectForKey:XLD_METADATA_ALBUM]) {
		[o_singleAlbum setStringValue:obj];
	}
	else [o_singleAlbum setStringValue:@""];
	if(obj=[[track metadata] objectForKey:XLD_METADATA_ALBUMARTIST]) {
		[o_singleAlbumArtist setStringValue:obj];
	}
	else [o_singleAlbumArtist setStringValue:@""];
	if(obj=[[track metadata] objectForKey:XLD_METADATA_GENRE]) {
		[o_singleGenre setStringValue:obj];
	}
	else [o_singleGenre setStringValue:@""];
	if(obj=[[track metadata] objectForKey:XLD_METADATA_COMPOSER]) {
		[o_singleComposer setStringValue:obj];
	}
	else [o_singleComposer setStringValue:@""];
	if(obj=[[track metadata] objectForKey:XLD_METADATA_COMMENT]) {
		[o_singleComment setStringValue:obj];
	}
	else [o_singleComment setStringValue:@""];
	if(obj=[[track metadata] objectForKey:XLD_METADATA_DISC]) {
		[o_singleDisc setIntValue:[obj intValue]];
	}
	else [o_singleDisc setStringValue:@""];
	if(obj=[[track metadata] objectForKey:XLD_METADATA_TOTALDISCS]) {
		[o_singleTotalDisc setIntValue:[obj intValue]];
	}
	else [o_singleTotalDisc setStringValue:@""];
	if(obj=[[track metadata] objectForKey:XLD_METADATA_TRACK]) {
		[o_track setIntValue:[obj intValue]];
	}
	else [o_track setStringValue:@""];
	if(obj=[[track metadata] objectForKey:XLD_METADATA_TOTALTRACKS]) {
		[o_totalTrack setIntValue:[obj intValue]];
	}
	else [o_totalTrack setStringValue:@""];
	if(obj=[[track metadata] objectForKey:XLD_METADATA_DATE]) {
		[o_singleYear setStringValue:obj];
	}
	else if(obj=[[track metadata] objectForKey:XLD_METADATA_YEAR]) {
		[o_singleYear setIntValue:[obj intValue]];
	}
	else [o_singleYear setStringValue:@""];
	if(obj=[[track metadata] objectForKey:XLD_METADATA_COVER]) {
		/*NSImage *img = [[NSImage alloc] initWithData:obj];
		NSImageRep *rep = [img bestRepresentationForDevice:nil];
		NSSize size;
		size.width = [rep pixelsWide];
		size.height = [rep pixelsHigh];
		[o_picture setImage:img];
		[img release];
		[o_picture clearData];*/
		[o_picture setImageData:obj];
	}
	else {
		/*[o_picture setImage:nil];
		[o_picture clearData];*/
		[o_picture clearImage];
	}
	if(obj=[[track metadata] objectForKey:XLD_METADATA_COMPILATION]) {
		if([obj boolValue]) [o_singleCompilation setState:NSOnState];
		else [o_singleCompilation setState:NSOffState];
	}
	else [o_singleCompilation setState:NSOffState];
}

- (void)setSingleMetadataForAllTracksWithTag:(int)tag album:(BOOL)albumFlag
{
	
	int i;
	NSString *album = [o_singleAlbum stringValue];
	
	id obj=nil,key=nil;
	BOOL remove = NO;
	if(tag==0) {
		key = XLD_METADATA_TITLE;
		obj = [o_singleTitle stringValue];
		if([[o_singleTitle stringValue] isEqualToString:@""]) {
			remove = YES;
		}
	}
	else if(tag==1) {
		key = XLD_METADATA_ARTIST;
		obj = [o_singleArtist stringValue];
		if([[o_singleArtist stringValue] isEqualToString:@""]) {
			remove = YES;
		}
	}
	else if(tag==2) {
		key = XLD_METADATA_ALBUM;
		obj = [o_singleAlbum stringValue];
		if([[o_singleAlbum stringValue] isEqualToString:@""]) {
			remove = YES;
		}
	}
	else if(tag==3) {
		key = XLD_METADATA_ALBUMARTIST;
		obj = [o_singleAlbumArtist stringValue];
		if([[o_singleAlbumArtist stringValue] isEqualToString:@""]) {
			remove = YES;
		}
	}
	else if(tag==4) {
		key = XLD_METADATA_GENRE;
		obj = [o_singleGenre stringValue];
		if([[o_singleGenre stringValue] isEqualToString:@""]) {
			remove = YES;
		}
	}
	else if(tag==5) {
		key = XLD_METADATA_COMPOSER;
		obj = [o_singleComposer stringValue];
		if([[o_singleComposer stringValue] isEqualToString:@""]) {
			remove = YES;
		}
	}
	else if(tag==6) {
		key = XLD_METADATA_DATE;
		obj = [o_singleYear stringValue];
		if([[o_singleYear stringValue] isEqualToString:@""]) {
			remove = YES;
		}
	}
	else if(tag==7) {
		key = XLD_METADATA_TRACK;
		obj = [NSNumber numberWithInt:[o_track intValue]];
		if([[o_track stringValue] isEqualToString:@""]) {
			remove = YES;
		}
	}
	else if(tag==8) {
		key = XLD_METADATA_TOTALTRACKS;
		obj = [NSNumber numberWithInt:[o_totalTrack intValue]];
		if([[o_totalTrack stringValue] isEqualToString:@""]) {
			remove = YES;
		}
	}
	else if(tag==9) {
		key = XLD_METADATA_DISC;
		obj = [NSNumber numberWithInt:[o_singleDisc intValue]];
		if([[o_singleDisc stringValue] isEqualToString:@""]) {
			remove = YES;
		}
	}
	else if(tag==10) {
		key = XLD_METADATA_TOTALDISCS;
		obj = [NSNumber numberWithInt:[o_singleTotalDisc intValue]];
		if([[o_singleTotalDisc stringValue] isEqualToString:@""]) {
			remove = YES;
		}
	}
	else if(tag==11) {
		key = XLD_METADATA_COVER;
		if(![o_picture imageData]) {
		//if(![o_picture image] && ![o_picture imgData]) {
			remove = YES;
		}
		/*else if([o_picture imgData]) {
			obj = [o_picture imgData];
		}*/
		else {
			obj = [o_picture imageData];
			//obj = [[[currentSingleTracks objectAtIndex:currentIndex] metadata] objectForKey:XLD_METADATA_COVER];
		}
	}
	else if(tag==12) {
		key = XLD_METADATA_COMMENT;
		obj = [o_singleComment stringValue];
		if([[o_singleComment stringValue] isEqualToString:@""]) {
			remove = YES;
		}
	}
	else if(tag==13) {
		key = XLD_METADATA_COMPILATION;
		obj = [NSNumber numberWithBool:YES];
		if([o_singleCompilation state] == NSOffState) {
			remove = YES;
		}
	}
	
	for(i=0;i<[currentSingleTracks count];i++) {
		XLDTrack *currentTrack = [currentSingleTracks objectAtIndex:i];
		if(albumFlag && ![album isEqualToString:[[currentTrack metadata] objectForKey:XLD_METADATA_ALBUM]]) continue;
		if(remove) {
			[[currentTrack metadata] removeObjectForKey:key];
			if([key isEqualToString:XLD_METADATA_DATE]) [[currentTrack metadata] removeObjectForKey:XLD_METADATA_YEAR];
		}
		else {
			if(obj && key) [[currentTrack metadata] setObject:obj forKey:key];
			if([key isEqualToString:XLD_METADATA_DATE]) {
				int year = [o_singleYear intValue];
				if(year >= 1000 && year < 3000)
					[[currentTrack metadata] setObject:[NSNumber numberWithInt:year] forKey:XLD_METADATA_YEAR];
			}
		}
	}
}

- (void)setSingleMetadataForIndex:(int)index
{
	XLDTrack *track = [currentSingleTracks objectAtIndex:index];
	
	if([[o_singleTitle stringValue] isEqualToString:@""]) {
		[[track metadata] removeObjectForKey:XLD_METADATA_TITLE];
	}
	else {
		[[track metadata] setObject:[o_singleTitle stringValue] forKey:XLD_METADATA_TITLE];
	}
	if([[o_singleArtist stringValue] isEqualToString:@""]) {
		[[track metadata] removeObjectForKey:XLD_METADATA_ARTIST];
	}
	else {
		[[track metadata] setObject:[o_singleArtist stringValue] forKey:XLD_METADATA_ARTIST];
	}
	if([[o_singleAlbum stringValue] isEqualToString:@""]) {
		[[track metadata] removeObjectForKey:XLD_METADATA_ALBUM];
	}
	else {
		[[track metadata] setObject:[o_singleAlbum stringValue] forKey:XLD_METADATA_ALBUM];
	}
	if([[o_singleAlbumArtist stringValue] isEqualToString:@""]) {
		[[track metadata] removeObjectForKey:XLD_METADATA_ALBUMARTIST];
	}
	else {
		[[track metadata] setObject:[o_singleAlbumArtist stringValue] forKey:XLD_METADATA_ALBUMARTIST];
	}
	if([[o_singleGenre stringValue] isEqualToString:@""]) {
		[[track metadata] removeObjectForKey:XLD_METADATA_GENRE];
	}
	else {
		[[track metadata] setObject:[o_singleGenre stringValue] forKey:XLD_METADATA_GENRE];
	}
	if([[o_singleComposer stringValue] isEqualToString:@""]) {
		[[track metadata] removeObjectForKey:XLD_METADATA_COMPOSER];
	}
	else {
		[[track metadata] setObject:[o_singleComposer stringValue] forKey:XLD_METADATA_COMPOSER];
	}
	if([[o_singleComment stringValue] isEqualToString:@""]) {
		[[track metadata] removeObjectForKey:XLD_METADATA_COMMENT];
	}
	else {
		[[track metadata] setObject:[o_singleComment stringValue] forKey:XLD_METADATA_COMMENT];
	}
	if([[o_singleDisc stringValue] isEqualToString:@""]) {
		[[track metadata] removeObjectForKey:XLD_METADATA_DISC];
	}
	else {
		[[track metadata] setObject:[NSNumber numberWithInt:[o_singleDisc intValue]] forKey:XLD_METADATA_DISC];
	}
	if([[o_singleTotalDisc stringValue] isEqualToString:@""]) {
		[[track metadata] removeObjectForKey:XLD_METADATA_TOTALDISCS];
	}
	else {
		[[track metadata] setObject:[NSNumber numberWithInt:[o_singleTotalDisc intValue]] forKey:XLD_METADATA_TOTALDISCS];
	}
	if([[o_track stringValue] isEqualToString:@""]) {
		[[track metadata] removeObjectForKey:XLD_METADATA_TRACK];
	}
	else {
		[[track metadata] setObject:[NSNumber numberWithInt:[o_track intValue]] forKey:XLD_METADATA_TRACK];
	}
	if([[o_totalTrack stringValue] isEqualToString:@""]) {
		[[track metadata] removeObjectForKey:XLD_METADATA_TOTALTRACKS];
	}
	else {
		[[track metadata] setObject:[NSNumber numberWithInt:[o_totalTrack intValue]] forKey:XLD_METADATA_TOTALTRACKS];
	}
	if([[o_singleYear stringValue] isEqualToString:@""]) {
		[[track metadata] removeObjectForKey:XLD_METADATA_YEAR];
		[[track metadata] removeObjectForKey:XLD_METADATA_DATE];
	}
	else {
		int year = [o_singleYear intValue];
		if(year >= 1000 && year < 3000) 
			[[track metadata] setObject:[NSNumber numberWithInt:year] forKey:XLD_METADATA_YEAR];
		[[track metadata] setObject:[o_singleYear stringValue] forKey:XLD_METADATA_DATE];
	}
	if(![o_picture imageData]) {
	//if(![o_picture image] && ![o_picture imgData]) {
		[[track metadata] removeObjectForKey:XLD_METADATA_COVER];
	}
	else {
	//else if([o_picture imgData]) {
		//[[track metadata] setObject:[o_picture imgData] forKey:XLD_METADATA_COVER];
		[[track metadata] setObject:[o_picture imageData] forKey:XLD_METADATA_COVER];
	}
	if([o_singleCompilation state] == NSOffState) {
		[[track metadata] removeObjectForKey:XLD_METADATA_COMPILATION];
	}
	else {
		[[track metadata] setObject:[NSNumber numberWithBool:YES] forKey:XLD_METADATA_COMPILATION];
	}
}

- (NSString *)stringForMetadata:(NSString *)key
{
	NSString *obj = nil;
	int i;
	for(i=0;i<[currentTracks count];i++) {
		NSString *str;
		if([key isEqualToString:XLD_METADATA_YEAR]
		   || [key isEqualToString:XLD_METADATA_DISC]
		   || [key isEqualToString:XLD_METADATA_TOTALDISCS]) {
			str = [[[[currentTracks objectAtIndex:i] metadata] objectForKey:key] stringValue];
		}
		else str = [[[currentTracks objectAtIndex:i] metadata] objectForKey:key];
		
		if(!str) return @"";
		else if([str isEqualToString:@""]) return @"";
		else if(!obj) obj = str;
		else if([obj isEqualToString:str]) continue;
		else return @"";
	}
	if(!obj) return @"";
	return obj;
}

- (void)editTracks:(NSArray *)tracks atIndex:(int)index
{
	if(currentTracks) [currentTracks release];
	currentTracks = [tracks retain];
	currentIndex = index;
	
	[self getMetadataForIndex:currentIndex];
	
	[o_prevButton setEnabled:YES];
	[o_nextButton setEnabled:YES];
	if(currentIndex == 0) [o_prevButton setEnabled:NO];
	if(currentIndex == [currentTracks count]-1)  [o_nextButton setEnabled:NO];
	[o_trackEditor setTitle:[NSString stringWithFormat:@"Track %d",currentIndex+1]];
	[o_trackEditor makeFirstResponder:o_title];
	
	modal = YES;
	int result = [NSApp runModalForWindow: o_trackEditor];
	if(result) {
		[currentTracks release];
		currentTracks = nil;
		[o_trackEditor close];
		return;
	}
	[self setMetadataForIndex:currentIndex];
	
	[currentTracks release];
	currentTracks = nil;
	[o_trackEditor close];
	return;
}

- (void)editAllTracks:(NSArray *)tracks
{
	if(currentTracks) [currentTracks release];
	currentTracks = [tracks retain];
	
	[o_allTitle setStringValue:[self stringForMetadata:XLD_METADATA_TITLE]];
	[o_allArtist setStringValue:[self stringForMetadata:XLD_METADATA_ARTIST]];
	[o_allAlbum setStringValue:[self stringForMetadata:XLD_METADATA_ALBUM]];
	[o_allAlbumArtist setStringValue:[self stringForMetadata:XLD_METADATA_ALBUMARTIST]];
	[o_allGenre setStringValue:[self stringForMetadata:XLD_METADATA_GENRE]];
	[o_allComposer setStringValue:[self stringForMetadata:XLD_METADATA_COMPOSER]];
	[o_allYear setStringValue:[self stringForMetadata:XLD_METADATA_DATE]];
	if([[o_allYear stringValue] isEqualToString:@""])
		[o_allYear setStringValue:[self stringForMetadata:XLD_METADATA_YEAR]];
	[o_allDisc setStringValue:[self stringForMetadata:XLD_METADATA_DISC]];
	[o_allTotalDisc setStringValue:[self stringForMetadata:XLD_METADATA_TOTALDISCS]];
	[o_allComment setStringValue:[self stringForMetadata:XLD_METADATA_COMMENT]];
	[o_allEditor makeFirstResponder:o_allTitle];
	[o_checkArray deselectAllCells];
	[o_totalDiscCheck setState:NSOffState];
	[o_compilationCheck setState:NSOffState];
	
	modal = YES;
	int result = [NSApp runModalForWindow: o_allEditor];
	if(result) {
		[currentTracks release];
		currentTracks = nil;
		[o_allEditor close];
		return;
	}
	
	int i;
	if([[o_checkArray cellWithTag:0] state] == NSOnState) {
		if([[o_allTitle stringValue] isEqualToString:@""]) {
			for(i=0;i<[currentTracks count];i++) [[[currentTracks objectAtIndex:i] metadata] removeObjectForKey:XLD_METADATA_TITLE];
		}
		else {
			for(i=0;i<[currentTracks count];i++) [[[currentTracks objectAtIndex:i] metadata] setObject:[o_allTitle stringValue] forKey:XLD_METADATA_TITLE];
		}
	}
	if([[o_checkArray cellWithTag:1] state] == NSOnState) {
		if([[o_allArtist stringValue] isEqualToString:@""]) {
			for(i=0;i<[currentTracks count];i++) [[[currentTracks objectAtIndex:i] metadata] removeObjectForKey:XLD_METADATA_ARTIST];
		}
		else {
			for(i=0;i<[currentTracks count];i++) [[[currentTracks objectAtIndex:i] metadata] setObject:[o_allArtist stringValue] forKey:XLD_METADATA_ARTIST];
		}
	}
	if([[o_checkArray cellWithTag:2] state] == NSOnState) {
		if([[o_allAlbum stringValue] isEqualToString:@""]) {
			for(i=0;i<[currentTracks count];i++) [[[currentTracks objectAtIndex:i] metadata] removeObjectForKey:XLD_METADATA_ALBUM];
		}
		else {
			for(i=0;i<[currentTracks count];i++) [[[currentTracks objectAtIndex:i] metadata] setObject:[o_allAlbum stringValue] forKey:XLD_METADATA_ALBUM];
		}
	}
	if([[o_checkArray cellWithTag:3] state] == NSOnState) {
		if([[o_allAlbumArtist stringValue] isEqualToString:@""]) {
			for(i=0;i<[currentTracks count];i++) [[[currentTracks objectAtIndex:i] metadata] removeObjectForKey:XLD_METADATA_ALBUMARTIST];
		}
		else {
			for(i=0;i<[currentTracks count];i++) [[[currentTracks objectAtIndex:i] metadata] setObject:[o_allAlbumArtist stringValue] forKey:XLD_METADATA_ALBUMARTIST];
		}
	}
	if([[o_checkArray cellWithTag:4] state] == NSOnState) {
		if([[o_allGenre stringValue] isEqualToString:@""]) {
			for(i=0;i<[currentTracks count];i++) [[[currentTracks objectAtIndex:i] metadata] removeObjectForKey:XLD_METADATA_GENRE];
		}
		else {
			for(i=0;i<[currentTracks count];i++) [[[currentTracks objectAtIndex:i] metadata] setObject:[o_allGenre stringValue] forKey:XLD_METADATA_GENRE];
		}
	}
	if([[o_checkArray cellWithTag:5] state] == NSOnState) {
		if([[o_allComposer stringValue] isEqualToString:@""]) {
			for(i=0;i<[currentTracks count];i++) [[[currentTracks objectAtIndex:i] metadata] removeObjectForKey:XLD_METADATA_COMPOSER];
		}
		else {
			for(i=0;i<[currentTracks count];i++) [[[currentTracks objectAtIndex:i] metadata] setObject:[o_allComposer stringValue] forKey:XLD_METADATA_COMPOSER];
		}
	}
	if([[o_checkArray cellWithTag:8] state] == NSOnState) {
		if([[o_allComment stringValue] isEqualToString:@""]) {
			for(i=0;i<[currentTracks count];i++) [[[currentTracks objectAtIndex:i] metadata] removeObjectForKey:XLD_METADATA_COMMENT];
		}
		else {
			for(i=0;i<[currentTracks count];i++) [[[currentTracks objectAtIndex:i] metadata] setObject:[o_allComment stringValue] forKey:XLD_METADATA_COMMENT];
		}
	}
	if([[o_checkArray cellWithTag:7] state] == NSOnState) {
		if([[o_allDisc stringValue] isEqualToString:@""]) {
			for(i=0;i<[currentTracks count];i++) [[[currentTracks objectAtIndex:i] metadata] removeObjectForKey:XLD_METADATA_DISC];
		}
		else {
			for(i=0;i<[currentTracks count];i++) [[[currentTracks objectAtIndex:i] metadata] setObject:[NSNumber numberWithInt:[o_allDisc intValue]] forKey:XLD_METADATA_DISC];
		}
	}
	if([o_totalDiscCheck state] == NSOnState) {
		if([[o_allTotalDisc stringValue] isEqualToString:@""]) {
			for(i=0;i<[currentTracks count];i++) [[[currentTracks objectAtIndex:i] metadata] removeObjectForKey:XLD_METADATA_TOTALDISCS];
		}
		else {
			for(i=0;i<[currentTracks count];i++) [[[currentTracks objectAtIndex:i] metadata] setObject:[NSNumber numberWithInt:[o_allTotalDisc intValue]] forKey:XLD_METADATA_TOTALDISCS];
		}
	}
	if([[o_checkArray cellWithTag:6] state] == NSOnState) {
		if([[o_allYear stringValue] isEqualToString:@""]) {
			for(i=0;i<[currentTracks count];i++) {
				[[[currentTracks objectAtIndex:i] metadata] removeObjectForKey:XLD_METADATA_YEAR];
				[[[currentTracks objectAtIndex:i] metadata] removeObjectForKey:XLD_METADATA_DATE];
			}
		}
		else {
			int year = [o_allYear intValue];
			for(i=0;i<[currentTracks count];i++) {
				if(year >= 1000 && year < 3000)
					[[[currentTracks objectAtIndex:i] metadata] setObject:[NSNumber numberWithInt:year] forKey:XLD_METADATA_YEAR];
				[[[currentTracks objectAtIndex:i] metadata] setObject:[o_allYear stringValue] forKey:XLD_METADATA_DATE];
			}
		}
	}
	if([o_compilationCheck state] == NSOnState) {
		if([o_allCompilation indexOfSelectedItem] == 1) {
			for(i=0;i<[currentTracks count];i++) [[[currentTracks objectAtIndex:i] metadata] removeObjectForKey:XLD_METADATA_COMPILATION];
		}
		else {
			for(i=0;i<[currentTracks count];i++) [[[currentTracks objectAtIndex:i] metadata] setObject:[NSNumber numberWithBool:YES] forKey:XLD_METADATA_COMPILATION];
		}
	}
	
	[currentTracks release];
	currentTracks = nil;
	[o_allEditor close];
	return;
}

- (BOOL)editSingleTracks:(NSArray *)tracks atIndex:(int)index
{
	if(currentSingleTracks) [currentSingleTracks release];
	currentSingleTracks = (NSMutableArray *)[tracks retain];
	currentSingleIndex = index;
	
	[self getSingleMetadataForIndex:currentSingleIndex];
	
	[o_singlePrevButton setEnabled:YES];
	[o_singleNextButton setEnabled:YES];
	if(currentSingleIndex == 0) [o_singlePrevButton setEnabled:NO];
	if(currentSingleIndex == [currentSingleTracks count]-1)  [o_singleNextButton setEnabled:NO];
	NSString *title = [[currentSingleTracks objectAtIndex:currentSingleIndex] desiredFileName] ? [[currentSingleTracks objectAtIndex:currentSingleIndex] desiredFileName] : @""; 
	NSString *path = [[[currentSingleTracks objectAtIndex:currentSingleIndex] metadata] objectForKey:XLD_METADATA_ORIGINALFILEPATH];
	[o_singleEditor setTitle:[NSString stringWithFormat:@"%@ (%d/%d)",title,currentSingleIndex+1,[currentSingleTracks count]]];
	if(path && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
		[o_singleEditor setRepresentedFilename:path];
	}
	else [o_singleEditor setRepresentedFilename:@""];
	[o_singleEditor makeFirstResponder:o_singleTitle];
	
	modal = YES;
	int result = [NSApp runModalForWindow: o_singleEditor];
	if(result) {
		[currentSingleTracks release];
		currentSingleTracks = nil;
		[o_singleEditor close];
		return NO;
	}
	[self setSingleMetadataForIndex:currentSingleIndex];
	
	[currentSingleTracks release];
	currentSingleTracks = nil;
	[o_singleEditor close];
	return YES;
}

- (void)inputTagsFromText
{
	[o_textParserWindow makeKeyAndOrderFront:nil];
}

- (void)editSingleTracks:(NSArray *)tracks withAlbumRanges:(NSArray *)ranges andDispatchTasks:(NSArray *)tasks
{
	if(currentSingleTracks) {
		int i;
		for(i=0;ranges && i<[ranges count];i++) {
			NSRange range = [[ranges objectAtIndex:i] rangeValue];
			range.location += [currentSingleTracks count];
			[currentRanges addObject:[NSValue valueWithRange:range]];
		}
		[currentSingleTracks addObjectsFromArray:tracks];
		[currentTasks addObjectsFromArray:tasks];
		[o_singleNextButton setEnabled:YES];
		if(currentSingleIndex == [currentSingleTracks count]-1)  [o_singleNextButton setEnabled:NO];
		NSString *title = [[currentSingleTracks objectAtIndex:currentSingleIndex] desiredFileName] ? [[currentSingleTracks objectAtIndex:currentSingleIndex] desiredFileName] : @""; 
		NSString *path = [[[currentSingleTracks objectAtIndex:currentSingleIndex] metadata] objectForKey:XLD_METADATA_ORIGINALFILEPATH];
		[o_singleEditor setTitle:[NSString stringWithFormat:@"%@ (%d/%d)",title,currentSingleIndex+1,[currentSingleTracks count]]];
		if(path && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
			[o_singleEditor setRepresentedFilename:path];
		}
		else [o_singleEditor setRepresentedFilename:@""];
		[o_singleEditor makeKeyAndOrderFront:nil];
	}
	else {
		currentSingleTracks = [[NSMutableArray alloc] initWithArray:tracks];
		if(ranges) currentRanges = [[NSMutableArray alloc] initWithArray:ranges];
		else currentRanges = [[NSMutableArray alloc] init];
		currentTasks = [[NSMutableArray alloc] initWithArray:tasks];
		currentSingleIndex = 0;

		[self getSingleMetadataForIndex:currentSingleIndex];
		[o_singlePrevButton setEnabled:YES];
		[o_singleNextButton setEnabled:YES];
		if(currentSingleIndex == 0) [o_singlePrevButton setEnabled:NO];
		if(currentSingleIndex == [currentSingleTracks count]-1)  [o_singleNextButton setEnabled:NO];
		NSString *title = [[currentSingleTracks objectAtIndex:currentSingleIndex] desiredFileName] ? [[currentSingleTracks objectAtIndex:currentSingleIndex] desiredFileName] : @""; 
		NSString *path = [[[currentSingleTracks objectAtIndex:currentSingleIndex] metadata] objectForKey:XLD_METADATA_ORIGINALFILEPATH];
		//NSLog(@"%@",path);
		[o_singleEditor setTitle:[NSString stringWithFormat:@"%@ (%d/%d)",title,currentSingleIndex+1,[currentSingleTracks count]]];
		if(path && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
			[o_singleEditor setRepresentedFilename:path];
		}
		else [o_singleEditor setRepresentedFilename:@""];
		[o_singleEditor makeFirstResponder:o_singleTitle];
		modal = NO;
		[o_singleEditor makeKeyAndOrderFront:nil];
	}
}

- (IBAction)endEdit:(id)sender
{
	if(modal) [NSApp stopModalWithCode:0];
	else {
		[self setSingleMetadataForIndex:currentSingleIndex];
		[delegate tagEditDidFinishForTracks:currentSingleTracks albumRanges:currentRanges tasks:currentTasks];
		[currentSingleTracks release];
		[currentTasks release];
		[currentRanges release];
		currentSingleTracks = nil;
		currentTasks = nil;
		currentRanges = nil;
		[o_singleEditor close];
	}
}

- (IBAction)cancelEdit:(id)sender
{
	if(modal) [NSApp stopModalWithCode:1];
	else {
		[currentSingleTracks release];
		[currentTasks release];
		[currentRanges release];
		currentSingleTracks = nil;
		currentTasks = nil;
		currentRanges = nil;
		[o_singleEditor close];
	}
}

- (IBAction)nextTrack:(id)sender
{
	[self setMetadataForIndex:currentIndex];
	
	currentIndex++;
	
	[o_trackEditor setTitle:[NSString stringWithFormat:@"Track %d",currentIndex+1]];
	[self getMetadataForIndex:currentIndex];
	
	[o_prevButton setEnabled:YES];
	[o_nextButton setEnabled:YES];
	if(currentIndex == 0) [o_prevButton setEnabled:NO];
	if(currentIndex == [currentTracks count]-1)  [o_nextButton setEnabled:NO];
}

- (IBAction)prevTrack:(id)sender
{
	[self setMetadataForIndex:currentIndex];
	
	currentIndex--;
	
	[o_trackEditor setTitle:[NSString stringWithFormat:@"Track %d",currentIndex+1]];
	[self getMetadataForIndex:currentIndex];
	
	[o_prevButton setEnabled:YES];
	[o_nextButton setEnabled:YES];
	if(currentIndex == 0) [o_prevButton setEnabled:NO];
	if(currentIndex == [currentTracks count]-1)  [o_nextButton setEnabled:NO];
}

- (IBAction)nextSingleTrack:(id)sender
{
	[self setSingleMetadataForIndex:currentSingleIndex];
	
	currentSingleIndex++;
	
	NSString *title = [[currentSingleTracks objectAtIndex:currentSingleIndex] desiredFileName] ? [[currentSingleTracks objectAtIndex:currentSingleIndex] desiredFileName] : @""; 
	NSString *path = [[[currentSingleTracks objectAtIndex:currentSingleIndex] metadata] objectForKey:XLD_METADATA_ORIGINALFILEPATH];
	[o_singleEditor setTitle:[NSString stringWithFormat:@"%@ (%d/%d)",title,currentSingleIndex+1,[currentSingleTracks count]]];
	if(path && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
		[o_singleEditor setRepresentedFilename:path];
	}
	else [o_singleEditor setRepresentedFilename:@""];
	[self getSingleMetadataForIndex:currentSingleIndex];
	
	[o_singlePrevButton setEnabled:YES];
	[o_singleNextButton setEnabled:YES];
	if(currentSingleIndex == 0) [o_singlePrevButton setEnabled:NO];
	if(currentSingleIndex == [currentSingleTracks count]-1)  [o_singleNextButton setEnabled:NO];
}

- (IBAction)prevSingleTrack:(id)sender
{
	[self setSingleMetadataForIndex:currentSingleIndex];
	
	currentSingleIndex--;
	
	NSString *title = [[currentSingleTracks objectAtIndex:currentSingleIndex] desiredFileName] ? [[currentSingleTracks objectAtIndex:currentSingleIndex] desiredFileName] : @""; 
	NSString *path = [[[currentSingleTracks objectAtIndex:currentSingleIndex] metadata] objectForKey:XLD_METADATA_ORIGINALFILEPATH];
	[o_singleEditor setTitle:[NSString stringWithFormat:@"%@ (%d/%d)",title,currentSingleIndex+1,[currentSingleTracks count]]];
	if(path && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
		[o_singleEditor setRepresentedFilename:path];
	}
	else [o_singleEditor setRepresentedFilename:@""];
	[self getSingleMetadataForIndex:currentSingleIndex];
	
	[o_singlePrevButton setEnabled:YES];
	[o_singleNextButton setEnabled:YES];
	if(currentSingleIndex == 0) [o_singlePrevButton setEnabled:NO];
	if(currentSingleIndex == [currentSingleTracks count]-1)  [o_singleNextButton setEnabled:NO];
}

- (IBAction)textModified:(id)sender
{
	/*
	if([[sender stringValue] isEqualToString:@""]) return;
	if([sender tag] < 9) [o_checkArray selectCellWithTag:[sender tag]];
	else if([sender tag] == 9) [o_totalDiscCheck setState:NSOnState];
	 */
}

- (IBAction)clearImage:(id)sender
{
	/*[o_picture setImage:nil];
	[o_picture clearData];*/
	[o_picture clearImage];
}

- (IBAction)openCoverImage:(id)sender
{
	NSOpenPanel *op = [NSOpenPanel openPanel];
	[op setCanChooseDirectories:NO];
	[op setCanChooseFiles:YES];
	[op setAllowsMultipleSelection:NO];
	
	int ret;
	ret = [op runModal];
	if(ret != NSOKButton) return;
	/*NSImage *img = [[NSImage alloc] initWithData:[NSData dataWithContentsOfFile:[op filename]]];
	if(!img) return;
	[o_picture setImage:img];
	[o_picture setImgData:[NSData dataWithContentsOfFile:[op filename]]];
	[img release];*/
	[o_picture setImageFromPath:[op filename]];
}

- (void)controlTextDidChange:(NSNotification *)aNotification
{
	id sender = [aNotification object];
	if([sender tag] < 9) [o_checkArray selectCellWithTag:[sender tag]];
	else if([sender tag] == 9) [o_totalDiscCheck setState:NSOnState];
}

- (void)comboBoxSelectionDidChange:(NSNotification *)aNotification
{
	id sender = [aNotification object];
	if([sender tag] < 9) [o_checkArray selectCellWithTag:[sender tag]];
	else if([sender tag] == 9) [o_totalDiscCheck setState:NSOnState];
}

- (IBAction)selectionChanged:(id)sender
{
	[o_compilationCheck setState:NSOnState];
}

- (IBAction)parse:(id)sender
{
	NSString *parsedString, *string;
	NSRange range, subrange;
	int length,i;
	
	string = [o_textParserText string];
	XLDMetadataTextParser *parser = [[XLDMetadataTextParser alloc] initWithFormatString:[o_textParserFormat stringValue]];
	
	length = [string length];
	range = NSMakeRange(0, length);
	
	NSArray *tracks = currentSingleTracks ? currentSingleTracks : [[[delegate discView] cueParser] trackList];
	while(range.length > 0 && tracks) {
		subrange = [string lineRangeForRange:NSMakeRange(range.location, 0)];
		parsedString = [string substringWithRange:subrange];
		if([parsedString characterAtIndex:subrange.length-1] == '\n')
			parsedString = [parsedString substringToIndex:subrange.length-1];
		if([parsedString length]) {
			NSMutableDictionary *dic = [parser parse:parsedString];
			if(tracks != currentSingleTracks) [dic removeObjectForKey:XLD_METADATA_TOTALTRACKS];
			if([[o_textParserMatching selectedItem] tag] == 0 && [dic objectForKey:XLD_METADATA_TRACK]) {
				[dic removeObjectForKey:XLD_METADATA_ORIGINALFILENAME];
				for(i=0;i<[tracks count];i++) {
					NSMutableDictionary *origDic = [[tracks objectAtIndex:i] metadata];
					if(![origDic objectForKey:XLD_METADATA_TRACK] || ![[origDic objectForKey:XLD_METADATA_TRACK] isEqual:[dic objectForKey:XLD_METADATA_TRACK]]) continue;
					if([o_textParserOverwrite state] == NSOnState)
						[origDic addEntriesFromDictionary:dic];
					else {
						NSEnumerator *enums = [dic keyEnumerator];
						NSString *key;
						while(key = [enums nextObject]) {
							if(![origDic objectForKey:key]) [origDic setObject:[dic objectForKey:key] forKey:key];
						}
					}
				}
			}
			else if([[o_textParserMatching selectedItem] tag] == 1 && [dic objectForKey:XLD_METADATA_ORIGINALFILENAME]) {
				for(i=0;i<[tracks count];i++) {
					NSMutableDictionary *origDic = [[tracks objectAtIndex:i] metadata];
					if(![origDic objectForKey:XLD_METADATA_ORIGINALFILENAME] || ![[origDic objectForKey:XLD_METADATA_ORIGINALFILENAME] isEqualToString:[dic objectForKey:XLD_METADATA_ORIGINALFILENAME]]) continue;
					if([o_textParserOverwrite state] == NSOnState)
						[origDic addEntriesFromDictionary:dic];
					else {
						NSEnumerator *enums = [dic keyEnumerator];
						NSString *key;
						while(key = [enums nextObject]) {
							if(![origDic objectForKey:key]) [origDic setObject:[dic objectForKey:key] forKey:key];
						}
					}
				}
			}
			else if([[o_textParserMatching selectedItem] tag] == 2 && [dic objectForKey:XLD_METADATA_TRACK] && [dic objectForKey:XLD_METADATA_ORIGINALFILENAME]) {
				for(i=0;i<[tracks count];i++) {
					NSMutableDictionary *origDic = [[tracks objectAtIndex:i] metadata];
					if(![origDic objectForKey:XLD_METADATA_TRACK]
					    || ![origDic objectForKey:XLD_METADATA_ORIGINALFILENAME]
					    || ![[origDic objectForKey:XLD_METADATA_TRACK] isEqual:[dic objectForKey:XLD_METADATA_TRACK]]
					    || ![[origDic objectForKey:XLD_METADATA_ORIGINALFILENAME] isEqualToString:[dic objectForKey:XLD_METADATA_ORIGINALFILENAME]]) continue;
					if([o_textParserOverwrite state] == NSOnState)
						[origDic addEntriesFromDictionary:dic];
					else {
						NSEnumerator *enums = [dic keyEnumerator];
						NSString *key;
						while(key = [enums nextObject]) {
							if(![origDic objectForKey:key]) [origDic setObject:[dic objectForKey:key] forKey:key];
						}
					}
				}
			}
			//NSLog([dic description]);
		}
		range.location = NSMaxRange(subrange);
		range.length -= subrange.length;
	}
	[parser release];
	if(tracks != currentSingleTracks) [[delegate discView] reloadData];
	else [self getSingleMetadataForIndex:currentSingleIndex];
}

- (id)windowWillReturnFieldEditor:(NSWindow *)sender toObject:(id)anObject
{
	if([anObject isKindOfClass:[NSTextField class]]) {
		if(!fieldEditor) {
			fieldEditor = [[XLDTextView alloc] init];
			[fieldEditor setFieldEditor:YES];
			[fieldEditor setActionTarget:self];
		}
		return fieldEditor;
	}
	else return nil;
}

- (IBAction)applyForAll:(id)sender
{
	if([sender tag] >= 100) [self setMetadataForAllTracksWithTag:[sender tag]];
	else [self setSingleMetadataForAllTracksWithTag:[sender tag] album:NO];
}

- (IBAction)applyForAlbum:(id)sender
{
	[self setSingleMetadataForAllTracksWithTag:[sender tag] album:YES];
}

- (void)windowDidBecomeKey:(NSNotification *)notification
{
	if([notification object] != o_textParserWindow) return;
	if(currentSingleTracks) {
		[[o_textParserMatching itemAtIndex:[o_textParserMatching indexOfItemWithTag:0]] setEnabled:YES];
		[[o_textParserMatching itemAtIndex:[o_textParserMatching indexOfItemWithTag:1]] setEnabled:YES];
		[[o_textParserMatching itemAtIndex:[o_textParserMatching indexOfItemWithTag:2]] setEnabled:YES];
	}
	else {
		[[o_textParserMatching itemAtIndex:[o_textParserMatching indexOfItemWithTag:0]] setEnabled:YES];
		[[o_textParserMatching itemAtIndex:[o_textParserMatching indexOfItemWithTag:1]] setEnabled:NO];
		[[o_textParserMatching itemAtIndex:[o_textParserMatching indexOfItemWithTag:2]] setEnabled:NO];
		[o_textParserMatching selectItemWithTag:0];
	}
}

- (BOOL)editingSingleTags
{
	return [o_singleEditor isVisible];
}

- (id)imageView
{
	if([o_singleEditor isVisible]) return o_picture;
	return nil;
}

- (void)imageLoaded
{
	if(![o_singleEditor isVisible]) return;
	[o_singleEditor makeKeyAndOrderFront:nil];
}

@end
