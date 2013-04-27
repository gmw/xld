//
//  XLDDiscogsRelease.m
//  XLD
//
//  Created by tmkk on 11/12/30.
//  Copyright 2011 tmkk. All rights reserved.
//

#import "XLDDiscogsRelease.h"
#import "XLDCustomClasses.h"

static NSString *fixArtist(NSString *str)
{
	int i = [str length]-1;
	if(i<1) return str;
	if([str characterAtIndex:i] != ')') return str;
	for(i--;i>=0;i--) {
		if([str characterAtIndex:i] < '0' || [str characterAtIndex:i] > '9') break;
	}
	if([str characterAtIndex:i] != '(' || i==0 || i==[str length]-1) return str;
	if([str characterAtIndex:i-1] != ' ') return str;
	
	return [str substringToIndex:i-1];
}


@implementation XLDDiscogsRelease

- (id)initWithReleaseID:(NSString *)releaseid totalTracks:(int)totalTracks totalSectors:(int)sectors
{
	self = [super init];
	if(!self) return nil;
	
	if(!releaseid) {
		[super dealloc];
		return nil;
	}
	
	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://api.discogs.com/release/%@?f=xml",releaseid]];
	//NSLog(@"%@",[url description]);
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
	NSArray *arr = [xml nodesForXPath:@"/resp/release" error:nil];
	if(![arr count]) {
		[release release];
		[xml release];
		[super dealloc];
		return nil;
	}
	
	id rel = [arr objectAtIndex:0];
	NSArray *objs = [rel nodesForXPath:@"./title" error:nil];
	if([objs count] && ![[[objs objectAtIndex:0] stringValue] isEqualToString:@""])
		[release setObject:[[objs objectAtIndex:0] stringValue] forKey:@"Title"];
	NSArray *artists = [rel nodesForXPath:@"./artists/artist" error:nil];
	if([artists count]) {
		NSMutableString *str = [NSMutableString string];
		int j;
		for(j=0;j<[artists count];j++) {
			id node = [artists objectAtIndex:j];
			NSString *artist = nil;
			NSString *joinphrase = nil;
			objs = [node nodesForXPath:@"./join" error:nil];
			if([objs count] && ![[[objs objectAtIndex:0] stringValue] isEqualToString:@""])
				joinphrase = [[objs objectAtIndex:0] stringValue];
			objs = [node nodesForXPath:@"./name" error:nil];
			if([objs count] && ![[[objs objectAtIndex:0] stringValue] isEqualToString:@""])
				artist = [[objs objectAtIndex:0] stringValue];
			objs = [node nodesForXPath:@"./anv" error:nil];
			if([objs count] && ![[[objs objectAtIndex:0] stringValue] isEqualToString:@""])
				artist = [[objs objectAtIndex:0] stringValue];
			artist = fixArtist(artist);
			if(artist && joinphrase) [str appendFormat:@"%@ %@ ",artist,joinphrase];
			else if(artist) [str appendFormat:@"%@",artist];
		}
		if(![str isEqualToString:@""] && ![[str lowercaseString] hasPrefix:@"various"]) [release setObject:str forKey:@"Artist"];
	}
	objs = [rel nodesForXPath:@"./released" error:nil];
	if([objs count] && ![[[objs objectAtIndex:0] stringValue] isEqualToString:@""])
		[release setObject:[[objs objectAtIndex:0] stringValue] forKey:@"Date"];
	objs = [rel nodesForXPath:@"./identifiers/identifier" error:nil];
	if([objs count]) {
		int j;
		for(j=0;j<[objs count];j++) {
			id node = [objs objectAtIndex:j];
			NSString *nodeType = [[[[node nodesForXPath:@"./@type" error:nil] objectAtIndex:0] stringValue] lowercaseString];
			if([nodeType isEqualToString:@"asin"]) {
				[release setObject:[[[node nodesForXPath:@"./@value" error:nil] objectAtIndex:0] stringValue] forKey:@"ASIN"];
			}
			else if([nodeType isEqualToString:@"barcode"]) {
				NSArray *tmp = [[[[node nodesForXPath:@"./@value" error:nil] objectAtIndex:0] stringValue] componentsSeparatedByString:@" "];
				[release setObject:[tmp componentsJoinedByString:@""] forKey:@"Barcode"];
			}
		}
	}
	objs = [rel nodesForXPath:@"./images/image/@uri" error:nil];
	if([objs count]) [release setObject:[NSURL URLWithString:[[objs objectAtIndex:0] stringValue]] forKey:@"CoverURL"];
	objs = [rel nodesForXPath:@"./genres/genre" error:nil];
	if([objs count] && ![[[objs objectAtIndex:0] stringValue] isEqualToString:@""])
		[release setObject:[[objs objectAtIndex:0] stringValue] forKey:@"Genre"];
	
	NSMutableDictionary *trackList = [NSMutableDictionary dictionary];
	NSArray *tracks = [rel nodesForXPath:@"./tracklist/track" error:nil];
	NSString *alternateDiscTitle = nil;
	NSString *currentAlternateDiscTitle = nil;
	int i,j;
	int currentTrack = 0;
	int totalSeconds = 0;
	BOOL match = NO;
	for(i=0;i<[tracks count];i++) {
		NSMutableDictionary *track = [NSMutableDictionary dictionary];
		NSString *position = [[[[tracks objectAtIndex:i] nodesForXPath:@"./position" error:nil] objectAtIndex:0] stringValue];
		NSString *duration = [[[[tracks objectAtIndex:i] nodesForXPath:@"./duration" error:nil] objectAtIndex:0] stringValue];
		NSString *title = [[[[tracks objectAtIndex:i] nodesForXPath:@"./title" error:nil] objectAtIndex:0] stringValue];
		NSArray *artists = [[tracks objectAtIndex:i] nodesForXPath:@"./artists/artist" error:nil];

		int pos = 0;
		if(![position isEqualToString:@""]) {
			if([position length] > 2 && [[position substringToIndex:2] isEqualToString:@"CD"]) position = [position substringFromIndex:2];
			NSRange range = [position rangeOfString:@"-"];
			if(range.location != NSNotFound) {
				NSArray *tmp = [position componentsSeparatedByString:@"-"];
				if([tmp count] == 2) pos = [[tmp objectAtIndex:1] intValue];
			}
			else {
				range = [position rangeOfString:@"."];
				if(range.location != NSNotFound) {
					NSArray *tmp = [position componentsSeparatedByString:@"."];
					if([tmp count] == 2) pos = [[tmp objectAtIndex:1] intValue];
				}
				else pos = [position intValue];
			}
		}
		else {
			if(![title isEqualToString:@""]) {
				if(currentTrack == 0) alternateDiscTitle = title;
				else currentAlternateDiscTitle = title;
			}
			continue;
		}
		
		if(currentTrack > pos) {
			// disc change
			//NSLog(@"%d,%d,%d",currentTrack,totalSeconds,sectors/75);
			if([[trackList allKeys] count] == totalTracks && (!totalSeconds || abs(sectors/75 - totalSeconds) <= totalTracks)) {
				match = YES;
				break;
			}
			trackList = [NSMutableDictionary dictionary];
			alternateDiscTitle = currentAlternateDiscTitle;
			currentAlternateDiscTitle = nil;
			currentTrack = 0;
			totalSeconds = 0;
		}
		
		currentTrack = pos;
		if(![duration isEqualToString:@""]) {
			NSArray *tmp = [duration componentsSeparatedByString:@":"];
			if([tmp count] == 2) {
				totalSeconds += [[tmp objectAtIndex:0] intValue]*60+[[tmp objectAtIndex:1] intValue];
			}
		}
		
		if(![title isEqualToString:@""]) [track setObject:title forKey:@"Title"];
		if([release objectForKey:@"Artist"]) [track setObject:[release objectForKey:@"Artist"] forKey:@"Artist"];
		if([artists count]) {
			NSMutableString *str = [NSMutableString string];
			for(j=0;j<[artists count];j++) {
				id node = [artists objectAtIndex:j];
				NSString *artist = nil;
				NSString *joinphrase = nil;
				objs = [node nodesForXPath:@"./join" error:nil];
				if([objs count] && ![[[objs objectAtIndex:0] stringValue] isEqualToString:@""])
					joinphrase = [[objs objectAtIndex:0] stringValue];
				objs = [node nodesForXPath:@"./name" error:nil];
				if([objs count] && ![[[objs objectAtIndex:0] stringValue] isEqualToString:@""])
					artist = [[objs objectAtIndex:0] stringValue];
				objs = [node nodesForXPath:@"./anv" error:nil];
				if([objs count] && ![[[objs objectAtIndex:0] stringValue] isEqualToString:@""])
					artist = [[objs objectAtIndex:0] stringValue];
				artist = fixArtist(artist);
				if(artist && joinphrase) [str appendFormat:@"%@ %@ ",artist,joinphrase];
				else if(artist) [str appendFormat:@"%@",artist];
			}
			if(![str isEqualToString:@""]) [track setObject:str forKey:@"Artist"];
		}
		
		[trackList setObject:track forKey:[NSNumber numberWithInt:currentTrack]];
	}
	if(alternateDiscTitle && [release objectForKey:@"Title"]) {
		if(![alternateDiscTitle isEqualToString:[release objectForKey:@"Title"]])
			[release setObject:[NSString stringWithFormat:@"%@ (%@)",[release objectForKey:@"Title"],alternateDiscTitle] forKey:@"Title"];
	}
	[release setObject:trackList forKey:@"Tracks"];
	//NSLog(@"%@",[release description]);
	//NSLog(@"%d,%d",[[trackList allKeys] count],totalTracks);
	if(!match && [[trackList allKeys] count] != totalTracks) [release removeAllObjects];
	
	return self;
}

- (NSDictionary *)disc
{
	return release;
}

@end
