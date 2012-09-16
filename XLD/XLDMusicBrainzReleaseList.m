//
//  XLDMusicBrainzReleaseList.m
//  XLD
//
//  Created by tmkk on 11/05/28.
//  Copyright 2011 tmkk. All rights reserved.
//

#import "XLDMusicBrainzReleaseList.h"
#import "XLDCustomClasses.h"

@implementation XLDMusicBrainzReleaseList

- (id)initWithDiscID:(NSString *)discid
{
	self = [super init];
	if(!self) return nil;
	
	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://musicbrainz.org/ws/2/discid/%@?inc=artist-credits",discid]];
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
	releases = [[NSMutableArray alloc] init];
	NSArray *arr = [xml nodesForXPath:@"/metadata/disc/release-list/release" error:nil];
	int i;
	for(i=0;i<[arr count];i++) {
		NSMutableDictionary *dic = [NSMutableDictionary dictionary];
		id rel = [arr objectAtIndex:i];
		NSArray *objs = [rel nodesForXPath:@"./@id" error:nil];
		if([objs count]) [dic setObject:[[objs objectAtIndex:0] stringValue] forKey:@"ReleaseID"];
		objs = [rel nodesForXPath:@"./title" error:nil];
		if([objs count]) {
			if([arr count] == 1) [dic setObject:[[objs objectAtIndex:0] stringValue] forKey:@"Title"];
			else {
				NSString *title = [[objs objectAtIndex:0] stringValue];
				NSString *country = nil;
				NSString *date = nil;
				NSString *disambiguation = nil;
				objs = [rel nodesForXPath:@"./country" error:nil];
				if([objs count]) country = [[objs objectAtIndex:0] stringValue];
				objs = [rel nodesForXPath:@"./date" error:nil];
				if([objs count]) date = [[objs objectAtIndex:0] stringValue];
				objs = [rel nodesForXPath:@"./disambiguation" error:nil];
				if([objs count]) disambiguation = [[objs objectAtIndex:0] stringValue];
				if(disambiguation) {
					if(title && country && date) [dic setObject:[NSString stringWithFormat:@"%@ (%@, %@, %@)",title,disambiguation,date,country] forKey:@"Title"];
					else if(title && country) [dic setObject:[NSString stringWithFormat:@"%@ (%@, %@)",title,disambiguation,country] forKey:@"Title"];
					else if(title && date) [dic setObject:[NSString stringWithFormat:@"%@ (%@, %@)",title,disambiguation,date] forKey:@"Title"];
					else if(title) [dic setObject:[NSString stringWithFormat:@"%@ (%@)",title,disambiguation] forKey:@"Title"];
				}
				else {
					if(title && country && date) [dic setObject:[NSString stringWithFormat:@"%@ (%@, %@)",title,date,country] forKey:@"Title"];
					else if(title && country) [dic setObject:[NSString stringWithFormat:@"%@ (%@)",title,country] forKey:@"Title"];
					else if(title && date) [dic setObject:[NSString stringWithFormat:@"%@ (%@)",title,date] forKey:@"Title"];
					else if(title) [dic setObject:title forKey:@"Title"];
				}
			}
		}
		objs = [rel nodesForXPath:@"./artist-credit/name-credit/artist/name" error:nil];
		if([objs count]) {
			if([objs count] == 1) [dic setObject:[[objs objectAtIndex:0] stringValue] forKey:@"Artist"];
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
				[dic setObject:str forKey:@"Artist"];
			}
		}
		[releases addObject:dic];
	}
	//NSLog(@"%@",[releases description]);
	return self;
}

- (void)dealloc
{
	[releases release];
	[super dealloc];
}

- (NSArray *)releaseList
{
	return releases;
}

@end
