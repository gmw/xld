//
//  XLDDiscogsRelease.m
//  XLD
//
//  Created by tmkk on 11/12/30.
//  Copyright 2011 tmkk. All rights reserved.
//

#import "XLDDiscogsRelease.h"
#import "XLDCustomClasses.h"

#define SKIP_TO_NEXT(str) while(*str == ' ' || *str == '\t' || *str == '\n') str++; \
if(*str == 0) break;

#define SEARCHING_OBJECT 0
#define SEARCHING_DICTIONARY_HEADER 1
#define SEARCHING_DICTIONARY_VALUE 2
#define SEARCHING_DICTIONARY_NEXT 3
#define SEARCHING_ARRAY_VALUE 4
#define SEARCHING_ARRAY_NEXT 5

static NSString *parseString(const char *str, const char **last)
{
	char *tmp = malloc(2048);
	char *ptr = tmp;
	while(1) {
		if(*str == '\\' && *(str+1) == '"') {
			*ptr++ = '&';
			*ptr++ = 'q';
			*ptr++ = 'u';
			*ptr++ = 'o';
			*ptr++ = 't';
			*ptr++ = ';';
			str += 2;
		}
		else if(*str == '\\' && *(str+1) == '\\') {
			*ptr++ = '\\';
			str += 2;
		}
		else if(*str == '\\' && *(str+1) == '/') {
			*ptr++ = '/';
			str += 2;
		}
		else if(*str == '"' || *str == 0) break;
		else if(*str == '&') {
			*ptr++ = '&';
			*ptr++ = 'a';
			*ptr++ = 'm';
			*ptr++ = 'p';
			*ptr++ = ';';
			str++;
		}
		else if(*str == '>') {
			*ptr++ = '&';
			*ptr++ = 'g';
			*ptr++ = 't';
			*ptr++ = ';';
			str++;
		}
		else if(*str == '<') {
			*ptr++ = '&';
			*ptr++ = 'l';
			*ptr++ = 't';
			*ptr++ = ';';
			str++;
		}
		else if(*str == '\'') {
			*ptr++ = '&';
			*ptr++ = 'a';
			*ptr++ = 'p';
			*ptr++ = 'o';
			*ptr++ = 's';
			*ptr++ = ';';
			str++;
		}
		else *ptr++ = *str++;
	}
	*last = str;
	*ptr = 0;
	NSString *ret = [NSMutableString stringWithUTF8String:tmp];
	CFStringRef transform = CFSTR("Any-Hex/Java");
	CFStringTransform((CFMutableStringRef)ret, NULL, transform, YES);
	free(tmp);
	return ret;
}

NSData *json2xml(NSData *json)
{
	NSMutableString *xml = [NSMutableString string];
	NSString *str = [[NSString alloc] initWithData: json encoding: NSUTF8StringEncoding];
	const char *cstr = [str UTF8String];
	[xml appendString:@"<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n<root>\n"];
	
	int indent = 0;
	int state = SEARCHING_OBJECT;
	NSMutableArray *headerStack = [NSMutableArray array];
	NSMutableArray *stateStack = [NSMutableArray array];
	while(1) {
		SKIP_TO_NEXT(cstr);
		if(state == SEARCHING_OBJECT) {
			if(*cstr == '{') {
				[stateStack insertObject: [NSNumber numberWithInt:state] atIndex:0];
				state = SEARCHING_DICTIONARY_HEADER;
				cstr++;
				continue;
			}
			cstr++;
			continue;
		}
		else if(state == SEARCHING_DICTIONARY_HEADER) {
			if(*cstr == '"') {
				cstr++;
				NSString *header = parseString(cstr, &cstr);
				if(*cstr == 0) break;
				[headerStack insertObject: header atIndex: 0];
				cstr++;
				SKIP_TO_NEXT(cstr);
				if(*cstr++ != ':') break;
				state = SEARCHING_DICTIONARY_VALUE;
				continue;
			}
			else break;
		}
		else if(state == SEARCHING_DICTIONARY_VALUE) {
			if(*cstr == '"') {
				cstr++;
				NSString *value = parseString(cstr, &cstr);
				if(*cstr == 0) break;
				NSString *header = [headerStack objectAtIndex:0];
				int i;
				for(i=0;i<indent;i++) {
					[xml appendString:@"\t"];
				}
				[xml appendFormat:@"<%@>%@</%@>\n",header,value,header];
				cstr++;
				state = SEARCHING_DICTIONARY_NEXT;
				continue;
			}
			else if(*cstr == '[') {
				[stateStack insertObject: [NSNumber numberWithInt:SEARCHING_DICTIONARY_NEXT] atIndex:0];
				state = SEARCHING_ARRAY_VALUE;
				cstr++;
				continue;
			}
			else if(*cstr == '{') {
				NSString *header = [headerStack objectAtIndex:0];
				int i;
				for(i=0;i<indent;i++) {
					[xml appendString:@"\t"];
				}
				[xml appendFormat:@"<%@>\n",header];
				[stateStack insertObject: [NSNumber numberWithInt:SEARCHING_DICTIONARY_NEXT] atIndex:0];
				state = SEARCHING_DICTIONARY_HEADER;
				indent++;
				cstr++;
				continue;
			}
			else {
				const char *ptr = cstr;
				while(*cstr != ',' && *cstr != '}' && *cstr != 0) cstr++;
				if(*cstr == 0) break;
				NSString *value = [[NSString alloc] initWithBytes:ptr length:cstr-ptr encoding:NSUTF8StringEncoding];
				NSString *header = [headerStack objectAtIndex:0];
				int i;
				for(i=0;i<indent;i++) {
					[xml appendString:@"\t"];
				}
				[xml appendFormat:@"<%@>%@</%@>\n",header,value,header];
				[value release];
				state = SEARCHING_DICTIONARY_NEXT;
				continue;
			}
		}
		else if(state == SEARCHING_DICTIONARY_NEXT) {
			if(*cstr == ',') {
				cstr++;
				[headerStack removeObjectAtIndex:0];
				state = SEARCHING_DICTIONARY_HEADER;
				continue;
			}
			else if(*cstr == '}') {
				cstr++;
				state = [[stateStack objectAtIndex:0] intValue];
				if(state == SEARCHING_OBJECT) break;
				indent--;
				[stateStack removeObjectAtIndex:0];
				[headerStack removeObjectAtIndex:0];
				NSString *header = [headerStack objectAtIndex:0];
				int i;
				for(i=0;i<indent;i++) {
					[xml appendString:@"\t"];
				}
				[xml appendFormat:@"</%@>\n",header];
				if(state == SEARCHING_OBJECT) break;
				continue;
			}
		}
		else if(state == SEARCHING_ARRAY_VALUE) {
			if(*cstr == '"') {
				cstr++;
				NSString *value = parseString(cstr, &cstr);
				if(*cstr == 0) break;
				NSString *header = [headerStack objectAtIndex:0];
				int i;
				for(i=0;i<indent;i++) {
					[xml appendString:@"\t"];
				}
				[xml appendFormat:@"<%@>%@</%@>\n",header,value,header];
				cstr++;
				state = SEARCHING_ARRAY_NEXT;
				continue;
			}
			else if(*cstr == '{') {
				NSString *header = [headerStack objectAtIndex:0];
				int i;
				for(i=0;i<indent;i++) {
					[xml appendString:@"\t"];
				}
				[xml appendFormat:@"<%@>\n",header];
				[stateStack insertObject: [NSNumber numberWithInt:SEARCHING_ARRAY_NEXT] atIndex:0];
				state = SEARCHING_DICTIONARY_HEADER;
				cstr++;
				indent++;
				continue;
			}
			else if(*cstr == ']') {
				cstr++;
				state = [[stateStack objectAtIndex:0] intValue];
				[stateStack removeObjectAtIndex:0];
				continue;
			}
			else {
				const char *ptr = cstr;
				while(*cstr != ',' && *cstr != ']' && *cstr != 0) cstr++;
				if(*cstr == 0) break;
				NSString *value = [[NSString alloc] initWithBytes:ptr length:cstr-ptr encoding:NSUTF8StringEncoding];
				NSString *header = [headerStack objectAtIndex:0];
				int i;
				for(i=0;i<indent;i++) {
					[xml appendString:@"\t"];
				}
				[xml appendFormat:@"<%@>%@</%@>\n",header,value,header];
				[value release];
				state = SEARCHING_ARRAY_NEXT;
				continue;
			}
		}
		else if(state == SEARCHING_ARRAY_NEXT) {
			if(*cstr == ',') {
				cstr++;
				state = SEARCHING_ARRAY_VALUE;
				continue;
			}
			else if(*cstr == ']') {
				cstr++;
				state = [[stateStack objectAtIndex:0] intValue];
				[stateStack removeObjectAtIndex:0];
				continue;
			}
		}
	}
	[xml appendString:@"</root>\n"];
	[str release];
	return [xml dataUsingEncoding:NSUTF8StringEncoding];
}

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
	
	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://api.discogs.com/releases/%@",releaseid]];
	//NSLog(@"%@",[url description]);
	NSData *data = [NSData fastDataWithContentsOfURL:url];
	if(!data || [data length] == 0) {
		[super dealloc];
		return nil;
	}
	NSXMLDocument *xml = [[NSXMLDocument alloc] initWithData:json2xml(data) options:NSXMLNodePreserveWhitespace error:nil];
	if(!xml) {
		[super dealloc];
		return nil;
	}
	
	release = [[NSMutableDictionary alloc] init];
	NSArray *arr = [xml nodesForXPath:@"/root" error:nil];
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
	NSArray *artists = [rel nodesForXPath:@"./artists" error:nil];
	if([artists count]) {
		NSMutableString *str = [NSMutableString string];
		NSString *joinphrase = nil;
		int j;
		for(j=0;j<[artists count];j++) {
			id node = [artists objectAtIndex:j];
			NSString *artist = nil;
			objs = [node nodesForXPath:@"./name" error:nil];
			if([objs count] && ![[[objs objectAtIndex:0] stringValue] isEqualToString:@""])
				artist = [[objs objectAtIndex:0] stringValue];
			objs = [node nodesForXPath:@"./anv" error:nil];
			if([objs count] && ![[[objs objectAtIndex:0] stringValue] isEqualToString:@""])
				artist = [[objs objectAtIndex:0] stringValue];
			artist = fixArtist(artist);
			if(artist && joinphrase) [str appendFormat:@" %@ %@",joinphrase,artist];
			else if(artist) [str appendFormat:@"%@",artist];
			objs = [node nodesForXPath:@"./join" error:nil];
			if([objs count] && ![[[objs objectAtIndex:0] stringValue] isEqualToString:@""])
				joinphrase = [[objs objectAtIndex:0] stringValue];
			else joinphrase = nil;
		}
		if(![str isEqualToString:@""] && ![[str lowercaseString] hasPrefix:@"various"]) [release setObject:str forKey:@"Artist"];
	}
	objs = [rel nodesForXPath:@"./released" error:nil];
	if([objs count] && ![[[objs objectAtIndex:0] stringValue] isEqualToString:@""])
		[release setObject:[[objs objectAtIndex:0] stringValue] forKey:@"Date"];
	objs = [rel nodesForXPath:@"./identifiers" error:nil];
	if([objs count]) {
		int j;
		for(j=0;j<[objs count];j++) {
			id node = [objs objectAtIndex:j];
			NSString *nodeType = [[[[node nodesForXPath:@"./type" error:nil] objectAtIndex:0] stringValue] lowercaseString];
			if([nodeType isEqualToString:@"asin"]) {
				[release setObject:[[[node nodesForXPath:@"./value" error:nil] objectAtIndex:0] stringValue] forKey:@"ASIN"];
			}
			else if([nodeType isEqualToString:@"barcode"]) {
				NSArray *tmp = [[[[node nodesForXPath:@"./value" error:nil] objectAtIndex:0] stringValue] componentsSeparatedByString:@" "];
				[release setObject:[tmp componentsJoinedByString:@""] forKey:@"Barcode"];
			}
		}
	}
	//objs = [rel nodesForXPath:@"./images/image/@uri" error:nil];
	//if([objs count]) [release setObject:[NSURL URLWithString:[[objs objectAtIndex:0] stringValue]] forKey:@"CoverURL"];
	objs = [rel nodesForXPath:@"./genres" error:nil];
	if([objs count] && ![[[objs objectAtIndex:0] stringValue] isEqualToString:@""])
		[release setObject:[[objs objectAtIndex:0] stringValue] forKey:@"Genre"];
	
	NSMutableDictionary *trackList = [NSMutableDictionary dictionary];
	NSArray *tracks = [rel nodesForXPath:@"./tracklist" error:nil];
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
		NSArray *artists = [[tracks objectAtIndex:i] nodesForXPath:@"./artists" error:nil];

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
			NSString *joinphrase = nil;
			for(j=0;j<[artists count];j++) {
				id node = [artists objectAtIndex:j];
				NSString *artist = nil;
				objs = [node nodesForXPath:@"./name" error:nil];
				if([objs count] && ![[[objs objectAtIndex:0] stringValue] isEqualToString:@""])
					artist = [[objs objectAtIndex:0] stringValue];
				objs = [node nodesForXPath:@"./anv" error:nil];
				if([objs count] && ![[[objs objectAtIndex:0] stringValue] isEqualToString:@""])
					artist = [[objs objectAtIndex:0] stringValue];
				artist = fixArtist(artist);
				if(artist && joinphrase) [str appendFormat:@" %@ %@",joinphrase,artist];
				else if(artist) [str appendFormat:@"%@",artist];
				objs = [node nodesForXPath:@"./join" error:nil];
				if([objs count] && ![[[objs objectAtIndex:0] stringValue] isEqualToString:@""])
					joinphrase = [[objs objectAtIndex:0] stringValue];
				else joinphrase = nil;
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
