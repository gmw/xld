//
//  XLDLMAXMLLoader.m
//  XLD
//
//  Created by tmkk on 13/07/03.
//  Copyright 2013 tmkk. All rights reserved.
//

#import "XLDLMAXMLLoader.h"
#import <regex.h>

@implementation XLDLMAXMLLoader

- (id)init
{
	self = [super init];
	if(!self) return nil;
	fileList = [[NSMutableArray alloc] init];
	metadataList = [[NSMutableArray alloc] init];
	return self;
}

- (void)dealloc
{
	[fileList release];
	[metadataList release];
	[super dealloc];
}

- (NSDictionary *)parseAlbumMetadataXML:(NSString *)xmlFile
{
	NSData *data = [NSData dataWithContentsOfFile:xmlFile];
	if(!data || [data length] == 0) {
		return nil;
	}
	NSXMLDocument *xml = [[NSXMLDocument alloc] initWithData:data options:NSXMLNodePreserveWhitespace error:nil];
	if(!xml) {
		return nil;
	}
	id objs = [xml nodesForXPath:@"./metadata" error:nil];
	if(![objs count]) {
		[xml release];
		return nil;
	}
	id metadata = [objs objectAtIndex:0];
	NSMutableDictionary *metadataDic = [NSMutableDictionary dictionary];
	objs = [metadata nodesForXPath:@"./title" error:nil];
	if([objs count]) [metadataDic setObject:[[objs objectAtIndex:0] stringValue] forKey:XLD_METADATA_ALBUM];
	objs = [metadata nodesForXPath:@"./creator" error:nil];
	if([objs count]) [metadataDic setObject:[[objs objectAtIndex:0] stringValue] forKey:XLD_METADATA_ALBUMARTIST];
	objs = [metadata nodesForXPath:@"./date" error:nil];
	if([objs count]) [metadataDic setObject:[[objs objectAtIndex:0] stringValue] forKey:XLD_METADATA_DATE];
	objs = [metadata nodesForXPath:@"./year" error:nil];
	if([objs count]) [metadataDic setObject:[[objs objectAtIndex:0] stringValue] forKey:XLD_METADATA_YEAR];
	
	[xml release];
	if([metadataDic count]) return metadataDic;
	return nil;
}

- (BOOL)openFile:(NSString *)xmlFile
{
	NSData *data = [NSData dataWithContentsOfFile:xmlFile];
	if(!data || [data length] == 0) {
		return NO;
	}
	NSXMLDocument *xml = [[NSXMLDocument alloc] initWithData:data options:NSXMLNodePreserveWhitespace error:nil];
	if(!xml) {
		return NO;
	}
	
	NSArray *files = [xml nodesForXPath:@"./files/file" error:nil];
	NSMutableDictionary *tracks = [NSMutableDictionary dictionary];
	NSFileManager *fm = [NSFileManager defaultManager];
	NSDictionary *albumMetadata = nil;
	NSData *coverArt = nil;
	int maxDiscNo = 1;
	int i;
	regex_t regex;
	regmatch_t match[3];
	regcomp(&regex,"d([0-9]+)\\.?t([0-9]+)",REG_EXTENDED);
	for(i=0;i<[files count];i++) {
		id file = [files objectAtIndex:i];
		id objs = [file nodesForXPath:@"./@source" error:nil];
		if(![objs count]) continue;
		if([[[[objs objectAtIndex:0] stringValue] lowercaseString] isEqualToString:@"original"]) {
			objs = [file nodesForXPath:@"./format" error:nil];
			if(![objs count]) continue;
			NSString *format = [[[objs objectAtIndex:0] stringValue] lowercaseString];
			if([format isEqualToString:@"jpeg"]) {
				if(coverArt) continue;
				objs = [file nodesForXPath:@"./@name" error:nil];
				if(![objs count]) continue;
				NSString *path = [[xmlFile stringByDeletingLastPathComponent] stringByAppendingPathComponent:[[objs objectAtIndex:0] stringValue]];
				if(![fm fileExistsAtPath:path]) continue;
				coverArt = [NSData dataWithContentsOfFile:path];
				continue;
			}
			else if(![format isEqualToString:@"flac"] && ![format isEqualToString:@"shorten"]) continue;
			objs = [file nodesForXPath:@"./@name" error:nil];
			if(![objs count]) continue;
			NSString *name = [[[objs objectAtIndex:0] stringValue] lowercaseString];
			NSString *path = [[xmlFile stringByDeletingLastPathComponent] stringByAppendingPathComponent:[[objs objectAtIndex:0] stringValue]];
			if(![fm fileExistsAtPath:path]) continue;
			NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
			NSString *trackID = nil;
			if(regexec(&regex, [name UTF8String], 3, match, 0) == 0) {
				int discNum = strtol([name UTF8String]+match[1].rm_so, NULL, 10);
				int trackNum = strtol([name UTF8String]+match[2].rm_so, NULL, 10);
				trackID = [NSString stringWithFormat:@"%02d-%03d",discNum,trackNum];
				//NSLog(@"%@,%@",name,trackID);
				if([tracks objectForKey:trackID]) continue;
				if(discNum > 1) maxDiscNo = discNum;
				[metadata setObject:[NSNumber numberWithInt:discNum] forKey:XLD_METADATA_DISC];
				[metadata setObject:[NSNumber numberWithInt:trackNum] forKey:XLD_METADATA_TRACK];
			}
			else {
				objs = [file nodesForXPath:@"./track" error:nil];
				if(![objs count]) continue;
				int trackNum = [[[objs objectAtIndex:0] stringValue] intValue];
				trackID = [NSString stringWithFormat:@"01-%03d",trackNum];
				if([tracks objectForKey:trackID]) continue;
				[metadata setObject:[NSNumber numberWithInt:trackNum] forKey:XLD_METADATA_TRACK];
			}
			objs = [file nodesForXPath:@"./title" error:nil];
			if([objs count]) [metadata setObject:[[objs objectAtIndex:0] stringValue] forKey:XLD_METADATA_TITLE];
			objs = [file nodesForXPath:@"./creator" error:nil];
			if([objs count]) [metadata setObject:[[objs objectAtIndex:0] stringValue] forKey:XLD_METADATA_ARTIST];
			objs = [file nodesForXPath:@"./album" error:nil];
			if([objs count]) [metadata setObject:[[objs objectAtIndex:0] stringValue] forKey:XLD_METADATA_ALBUM];
			NSMutableDictionary *track = [NSMutableDictionary dictionary];
			[track setObject:path forKey:@"Path"];
			[track setObject:metadata forKey:@"Metadata"];
			[tracks setObject:track forKey:trackID];
		}
		else if([[[[objs objectAtIndex:0] stringValue] lowercaseString] isEqualToString:@"metadata"]) {
			if(albumMetadata) continue;
			objs = [file nodesForXPath:@"./format" error:nil];
			if(![objs count]) continue;
			NSString *format = [[[objs objectAtIndex:0] stringValue] lowercaseString];
			if(![format isEqualToString:@"metadata"]) continue;
			objs = [file nodesForXPath:@"./@name" error:nil];
			if(![objs count]) continue;
			NSString *path = [[xmlFile stringByDeletingLastPathComponent] stringByAppendingPathComponent:[[objs objectAtIndex:0] stringValue]];
			if(![fm fileExistsAtPath:path]) continue;
			albumMetadata = [self parseAlbumMetadataXML:path];
		}
	}
	regfree(&regex);
	if(![tracks count]) {
		[xml release];
		return NO;
	}
	
	NSArray *keys = [[tracks allKeys] sortedArrayUsingSelector:@selector(compare:)];
	for(i=0;i<[keys count];i++) {
		NSDictionary *track = [tracks objectForKey:[keys objectAtIndex:i]];
		NSString *path = [track objectForKey:@"Path"];
		NSMutableDictionary *metadata = [track objectForKey:@"Metadata"];
		if(albumMetadata) [metadata addEntriesFromDictionary:albumMetadata];
		if(coverArt) [metadata setObject:coverArt forKey:XLD_METADATA_COVER];
		if(maxDiscNo == 1) [metadata removeObjectForKey:XLD_METADATA_DISC];
		else [metadata setObject:[NSNumber numberWithInt:maxDiscNo] forKey:XLD_METADATA_TOTALDISCS];
		[fileList addObject:path];
		[metadataList addObject:metadata];
	}
	
	//NSLog(@"%@",[fileList description]);
	//NSLog(@"%@",[metadataList description]);
	
	[xml release];
	return YES;
}

- (NSArray *)fileList
{
	return fileList;
}

- (NSArray *)metadataList
{
	return metadataList;
}

@end
