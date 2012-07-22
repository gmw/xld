//
//  XLDMusicBrainzRelease.m
//  XLD
//
//  Created by tmkk on 11/05/28.
//  Copyright 2011 tmkk. All rights reserved.
//

#import "XLDMusicBrainzRelease.h"
#import "XLDCustomClasses.h"

@implementation XLDMusicBrainzRelease

- (NSString *)getComposerFromRecordingID:(NSString *)recordingid
{
	threads--;
	int i;
	id obj;
	NSString *workid = nil;
	NSMutableString *composer = nil;
	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://musicbrainz.org/ws/2/recording/%@?inc=work-rels",recordingid]];
	NSData *data = [NSData fastDataWithContentsOfURL:url];
	if(!data || [data length] == 0) return nil;
	NSXMLDocument *xml = [[NSXMLDocument alloc] initWithData:data options:NSXMLNodePreserveWhitespace error:nil];
	if(!xml) return nil;
	
	NSArray *relations = [xml nodesForXPath:@"/metadata/recording/relation-list/relation" error:nil];
	if(![relations count]) {
		[xml release];
		return nil;
	}
	
	for(i=0;i<[relations count];i++) {
		obj = [[relations objectAtIndex:i] nodesForXPath:@"./@type" error:nil];
		if([obj count] && [[[obj objectAtIndex:0] stringValue] isEqualToString:@"performance"]) {
			workid = [[[[relations objectAtIndex:i] nodesForXPath:@"./work/@id" error:nil] objectAtIndex:0] stringValue];
			break;
		}
	}
	
	if(!workid) {
		[xml release];
		return nil;
	}
	
	[xml release];
	
	url = [NSURL URLWithString:[NSString stringWithFormat:@"http://musicbrainz.org/ws/2/work/%@?inc=artist-rels",workid]];
	data = [NSData fastDataWithContentsOfURL:url];
	if(!data || [data length] == 0) return nil;
	xml = [[NSXMLDocument alloc] initWithData:data options:NSXMLNodePreserveWhitespace error:nil];
	if(!xml) return nil;
	
	relations = [xml nodesForXPath:@"/metadata/work/relation-list/relation" error:nil];
	if(![relations count]) {
		[xml release];
		return nil;
	}
	
	for(i=0;i<[relations count];i++) {
		obj = [[relations objectAtIndex:i] nodesForXPath:@"./@type" error:nil];
		if([obj count] && [[[obj objectAtIndex:0] stringValue] isEqualToString:@"composer"]) {
			obj = [[[[relations objectAtIndex:i] nodesForXPath:@"./artist/name" error:nil] objectAtIndex:0] stringValue];
			if(!composer) composer = [NSMutableString stringWithString:obj];
			else [composer appendFormat:@", %@",obj];
		}
	}
	
	NSLog(@"%@",composer);
	
	[xml release];
	return composer;
}

- (void)setComposerFromRecordingID:(id)args
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	int i;
	id obj;
	NSString *recordingid = [args objectAtIndex:0];
	NSMutableDictionary *dic = [args objectAtIndex:1];
	NSString *workid = nil;
	NSMutableString *composer = nil;
	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://musicbrainz.org/ws/2/recording/%@?inc=work-rels",recordingid]];
	NSData *data = [NSData fastDataWithContentsOfURL:url];
	if(!data || [data length] == 0) {
		goto last;
	}
	NSXMLDocument *xml = [[NSXMLDocument alloc] initWithData:data options:NSXMLNodePreserveWhitespace error:nil];
	if(!xml) {
		goto last;
	}
	
	NSArray *relations = [xml nodesForXPath:@"/metadata/recording/relation-list/relation" error:nil];
	if(![relations count]) {
		[xml release];
		goto last;
	}
	
	for(i=0;i<[relations count];i++) {
		obj = [[relations objectAtIndex:i] nodesForXPath:@"./@type" error:nil];
		if([obj count] && [[[obj objectAtIndex:0] stringValue] isEqualToString:@"performance"]) {
			workid = [[[[relations objectAtIndex:i] nodesForXPath:@"./work/@id" error:nil] objectAtIndex:0] stringValue];
			break;
		}
	}
	
	if(!workid) {
		[xml release];
		goto last;
	}
	
	[xml release];
	
	url = [NSURL URLWithString:[NSString stringWithFormat:@"http://musicbrainz.org/ws/2/work/%@?inc=artist-rels",workid]];
	data = [NSData fastDataWithContentsOfURL:url];
	if(!data || [data length] == 0) {
		goto last;
	}
	xml = [[NSXMLDocument alloc] initWithData:data options:NSXMLNodePreserveWhitespace error:nil];
	if(!xml) {
		goto last;
	}
	
	relations = [xml nodesForXPath:@"/metadata/work/relation-list/relation" error:nil];
	if(![relations count]) {
		[xml release];
		goto last;
	}
	
	for(i=0;i<[relations count];i++) {
		obj = [[relations objectAtIndex:i] nodesForXPath:@"./@type" error:nil];
		if([obj count] && [[[obj objectAtIndex:0] stringValue] isEqualToString:@"composer"]) {
			obj = [[[[relations objectAtIndex:i] nodesForXPath:@"./artist/name" error:nil] objectAtIndex:0] stringValue];
			if(!composer) composer = [NSMutableString stringWithString:obj];
			else [composer appendFormat:@", %@",obj];
		}
	}
	
	@synchronized(dic) {
		if(composer) [dic setObject:composer forKey:@"Composer"];
	}
	
	NSLog(@"%@",composer);
	
	[xml release];
	
last:
	@synchronized(self) {
		threads--;
	}
	[pool release];
}

- (id)initWithReleaseID:(NSString *)releaseid discID:(NSString *)discid totalTracks:(int)totalTracks totalSectors:(int)sectors ambiguous:(BOOL)ambiguous
{
	self = [super init];
	if(!self) return nil;
	
	if(!releaseid || !discid) {
		[super dealloc];
		return nil;
	}
	
	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://musicbrainz.org/ws/2/release/%@?inc=artist-credits+recordings+discids+isrcs+recording-level-rels+work-level-rels+work-rels+artist-rels",releaseid]];
	//NSLog(@"%@,%@",discid,[url description]);
	NSData *data = [NSData fastDataWithContentsOfURL:url];
	if(!data || [data length] == 0) {
		[super dealloc];
		return nil;
	}
	NSXMLDocument *xml = [[NSXMLDocument alloc] initWithData:data options:NSXMLNodePreserveWhitespace error:nil];
	if(!xml) {
		[super dealloc];
		return nil;
	}
	
	release = [[NSMutableDictionary alloc] init];
	NSArray *arr = [xml nodesForXPath:@"/metadata/release" error:nil];
	if(![arr count]) {
		[release release];
		[xml release];
		[super dealloc];
		return nil;
	}
	
	id rel = [arr objectAtIndex:0];
	NSArray *objs = [rel nodesForXPath:@"./title" error:nil];
	if([objs count]) [release setObject:[[objs objectAtIndex:0] stringValue] forKey:@"Title"];
	objs = [rel nodesForXPath:@"./artist-credit/name-credit/artist/name" error:nil];
	if([objs count] == 1) {
		[release setObject:[[objs objectAtIndex:0] stringValue] forKey:@"Artist"];
		objs = [rel nodesForXPath:@"./artist-credit/name-credit/artist/@id" error:nil];
		if([objs count]) [release setObject:[[objs objectAtIndex:0]  stringValue] forKey:@"ArtistID"];
	}
	else {
		NSArray *credits = [rel nodesForXPath:@"./artist-credit/name-credit" error:nil];
		NSMutableString *str = [NSMutableString string];
		int j;
		for(j=0;j<[credits count];j++) {
			id node = [credits objectAtIndex:j];
			NSString *artist = nil;
			NSString *joinphrase = nil;
			objs = [node nodesForXPath:@"./@joinphrase" error:nil];
			if([objs count]) joinphrase = [[objs objectAtIndex:0] stringValue];
			objs = [node nodesForXPath:@"./artist/name" error:nil];
			if([objs count]) artist = [[objs objectAtIndex:0] stringValue];
			if(artist && joinphrase) [str appendFormat:@"%@%@",artist,joinphrase];
			else if(artist) [str appendFormat:@"%@",artist];
		}
		[release setObject:str forKey:@"Artist"];
	}
	objs = [rel nodesForXPath:@"./date" error:nil];
	if([objs count]) [release setObject:[[objs objectAtIndex:0] stringValue] forKey:@"Date"];
	objs = [rel nodesForXPath:@"./asin" error:nil];
	if([objs count]) [release setObject:[[objs objectAtIndex:0] stringValue] forKey:@"ASIN"];
	objs = [rel nodesForXPath:@"./barcode" error:nil];
	if([objs count]) [release setObject:[[objs objectAtIndex:0] stringValue] forKey:@"Barcode"];
	[release setObject:releaseid forKey:@"ReleaseID"];
	[release setObject:discid forKey:@"DiscID"];
	
	NSArray *discs = [rel nodesForXPath:@"./medium-list/medium" error:nil];
	int i,j;
	for(i=0;i<[discs count];i++) {
		id disc = [discs objectAtIndex:i];
		objs = [disc nodesForXPath:@"./disc-list/disc/@id" error:nil];
		BOOL match = NO;
		if([objs count]) {
			for(j=0;j<[objs count];j++) {
				if([[[objs objectAtIndex:j] stringValue] isEqualToString:discid]) match = YES;
			}
		}
		if(!match && ambiguous) {
			if([discs count] == 1) {
				match = YES;
			}
			else {
				objs = [disc nodesForXPath:@"./track-list/@count" error:nil];
				if([objs count] && [[[objs objectAtIndex:0] stringValue] intValue] == totalTracks) {
					objs = [disc nodesForXPath:@"./track-list/track/length" error:nil];
					if([objs count] == totalTracks) {
						int total = 0;
						for(j=0;j<[objs count];j++) {
							total += [[[objs objectAtIndex:j] stringValue] intValue]/1000;
						}
						//NSLog(@"%d: %d,%d",i+1,sectors/75,total);
						if(abs(sectors/75 - total) <= totalTracks) match = YES;
					}
					else {
						// same track count but no length info - what should we do?
						// at the moment, accept the first match
						match = YES;
					}
				}
			}
		}
		
		if(!match) continue;
		
		objs = [disc nodesForXPath:@"./title" error:nil];
		if([objs count]) [release setObject:[[objs objectAtIndex:0] stringValue] forKey:@"Title"];
		
		NSArray *tracks = [disc nodesForXPath:@"./track-list/track" error:nil];
		NSMutableDictionary *trackList = [NSMutableDictionary dictionary];
		for(j=0;j<[tracks count];j++) {
			id tr = [tracks objectAtIndex:j];
			NSMutableDictionary *track = [NSMutableDictionary dictionary];
			objs = [tr nodesForXPath:@"./recording/title" error:nil];
			if([objs count]) [track setObject:[[objs objectAtIndex:0] stringValue] forKey:@"Title"];
			objs = [tr nodesForXPath:@"./recording/@id" error:nil];
			if([objs count]) {
				[track setObject:[[objs objectAtIndex:0] stringValue] forKey:@"RecordingID"];
				/*@synchronized(self) {
					threads++;
				}
				[NSThread detachNewThreadSelector:@selector(setComposerFromRecordingID:) toTarget:self withObject:[NSArray arrayWithObjects:[[objs objectAtIndex:0] stringValue], track, nil]];
				//[self getComposerFromRecordingID:[[objs objectAtIndex:0] stringValue]];*/
			}
			objs = [tr nodesForXPath:@"./recording/artist-credit/name-credit/artist/name" error:nil];
			if([objs count] == 1) {
				[track setObject:[[objs objectAtIndex:0] stringValue] forKey:@"Artist"];
				objs = [tr nodesForXPath:@"./recording/artist-credit/name-credit/artist/@id" error:nil];
				if([objs count]) [track setObject:[[objs objectAtIndex:0]  stringValue] forKey:@"ArtistID"];
			}
			else if([objs count]) {
				NSArray *credits = [tr nodesForXPath:@"./recording/artist-credit/name-credit" error:nil];
				NSMutableString *str = [NSMutableString string];
				int k;
				for(k=0;k<[credits count];k++) {
					id node = [credits objectAtIndex:k];
					NSString *artist = nil;
					NSString *joinphrase = nil;
					objs = [node nodesForXPath:@"./@joinphrase" error:nil];
					if([objs count]) joinphrase = [[objs objectAtIndex:0] stringValue];
					objs = [node nodesForXPath:@"./artist/name" error:nil];
					if([objs count]) artist = [[objs objectAtIndex:0] stringValue];
					if(artist && joinphrase) [str appendFormat:@"%@%@",artist,joinphrase];
					else if(artist) [str appendFormat:@"%@",artist];
				}
				[track setObject:str forKey:@"Artist"];
			}
			else {
				NSString *aartist = [release objectForKey:@"Artist"];
				if(aartist) [track setObject:aartist forKey:@"Artist"];
				aartist = [release objectForKey:@"ArtistID"];
				if(aartist) [track setObject:aartist forKey:@"ArtistID"];
			}
			id works = [tr nodesForXPath:@"./recording/relation-list/relation/work" error:nil];
			if([works count]) {
				int k;
				for(k=0;k<[works count];k++) {
					NSMutableString *composer = nil;
					objs = [[works objectAtIndex:k] nodesForXPath:@"./relation-list/relation" error:nil];
					int l;
					for(l=0;l<[objs count];l++) {
						NSString *type = [[[[objs objectAtIndex:l] nodesForXPath:@"./@type" error:nil] objectAtIndex:0] stringValue];
						if([type isEqualToString:@"composer"]) {
							NSString *str = [[[[objs objectAtIndex:l] nodesForXPath:@"./artist/name" error:nil] objectAtIndex:0] stringValue];
							if(!composer) composer = [NSMutableString stringWithString:str];
							else [composer appendFormat:@", %@",str];
						}
					}
					if(composer) {
						[track setObject:composer forKey:@"Composer"];
						//NSLog(@"%@",composer);
						break;
					}
				}
			}
			objs = [tr nodesForXPath:@"./recording/isrc-list/isrc/@id" error:nil];
			if([objs count]) [track setObject:[[objs objectAtIndex:0] stringValue] forKey:@"ISRC"];
			int trackNum = 0;
			objs = [tr nodesForXPath:@"./position" error:nil];
			if([objs count]) trackNum = [[[objs objectAtIndex:0] stringValue] intValue];
			if(trackNum) [trackList setObject:track forKey:[NSNumber numberWithInt:trackNum]];
		}
		[release setObject:trackList forKey:@"Tracks"];
		if(match) break;
	}
	
	if(![release objectForKey:@"Tracks"]) [release removeAllObjects];
	
	/*while(threads) {
		[NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
	}*/
	//NSLog(@"%@",[release description]);
	[xml release];
	return self;
}

- (void)dealloc
{
	[release release];
	[super dealloc];
}

- (NSDictionary *)disc
{
	return release;
}

@end
