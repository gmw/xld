//
//  XLDCustomClasses.m
//  XLD
//
//  Created by tmkk on 09/02/14.
//  Copyright 2009 tmkk. All rights reserved.
//

#import "XLDCustomClasses.h"
#import "XLDTrack.h"
#import <sys/sysctl.h>

#define NSAppKitVersionNumber10_4 824

static NSString *framesToMSFStr(xldoffset_t frames, int samplerate)
{
	int min = frames/samplerate/60;
	frames -= min*samplerate*60;
	int sec = frames/samplerate;
	frames -= sec*samplerate;
	int f = frames*75/samplerate;
	return [NSString stringWithFormat:@"%02d:%02d:%02d",min,sec,f];
}

@implementation XLDView

- (int)tag
{
	return tag;
}

- (void)setTag:(int)t
{
	tag = t;
}

@end

@implementation XLDTextView

- (void)dealloc
{
	if(actionTarget) [actionTarget release];
	[super dealloc];
}

- (void)setActionTarget:(id)target
{
	if(actionTarget) [actionTarget release];
	actionTarget = [target retain];
}

- (NSMenu *)menuForEvent:(NSEvent *)event
{
	NSMenu *menu = [super menuForEvent:event];
	int tag = [[self delegate] tag];
	if(tag >= 100) {
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:LS(@"Apply This Item for All Tracks") action:@selector(applyForAll:) keyEquivalent:@""];
		[item setTarget:actionTarget];
		[item setTag:tag];
		[menu insertItem:item atIndex:0];
		[item release];
		[menu insertItem:[NSMenuItem separatorItem] atIndex:1];
	}
	else {
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:LS(@"Apply This Item for All Files") action:@selector(applyForAll:) keyEquivalent:@""];
		[item setTarget:actionTarget];
		[item setTag:tag];
		[menu insertItem:item atIndex:0];
		[item release];
		item = [[NSMenuItem alloc] initWithTitle:LS(@"Apply This Item for the Same Album") action:@selector(applyForAlbum:) keyEquivalent:@""];
		[item setTarget:actionTarget];
		[item setTag:tag];
		[menu insertItem:item atIndex:1];
		[menu insertItem:[NSMenuItem separatorItem] atIndex:2];
		[item release];
	}
	
	return menu;
}

@end

@implementation NSImage (String)
+ (NSImage *)imageWithString:(NSString *)string withFont:(NSFont *)font withColor:(NSColor *)color
{
	NSGlyph glyph;
	NSBezierPath *path = [NSBezierPath bezierPath];
	[path moveToPoint:NSMakePoint(0, [font pointSize])];
	int i;
	for(i=0;i<[string length];i++) {
		glyph = [font glyphWithName:[string substringWithRange:NSMakeRange(i,1)]];
		if(glyph == 0xffff || [string characterAtIndex:i] == ' ') [path relativeMoveToPoint:NSMakePoint([font pointSize]/2,0)];
		else [path appendBezierPathWithGlyph:glyph inFont:font];
	}
	NSShadow *shadow = [[NSShadow alloc] init];
	[shadow setShadowOffset:NSMakeSize(3,-3)];
	[shadow setShadowBlurRadius:3];
	[shadow setShadowColor:[NSColor lightGrayColor]];
	NSImage *img = [[NSImage alloc] initWithSize:NSMakeSize([path currentPoint].x,[font pointSize]*2)];
	[img lockFocus];
	[color set];
	//[shadow set];
	[path fill];
	[img unlockFocus];
	[shadow release];
	
	NSRect targetImageFrame = NSMakeRect(0,0,170,170);
	NSImage *targetImage = [[NSImage alloc] initWithSize:targetImageFrame.size];
	[targetImage lockFocus];
	[[NSColor whiteColor] set];
	NSRectFill(targetImageFrame);
	[img compositeToPoint:NSMakePoint((170-[img size].width)/2,(170-[img size].height)/2-5) operation:NSCompositeSourceOver];
	[targetImage unlockFocus];
	[img release];
	return [targetImage autorelease];
}
@end

@implementation XLDButton

- (void)mouseDown:(NSEvent *)theEvent 
{
	modifierFlags = [theEvent modifierFlags];
	[super mouseDown:theEvent];
}

- (BOOL)commandKeyPressed
{
	return ((modifierFlags & NSCommandKeyMask) != 0);
}

- (BOOL)optionKeyPressed
{
	return ((modifierFlags & NSAlternateKeyMask) != 0);
}

- (BOOL)shiftKeyPressed
{
	return ((modifierFlags & NSShiftKeyMask) != 0);
}

@end

@implementation XLDTrackListUtil

+ (NSString *)artistForTracks:(NSArray *)tracks
{
	if(!tracks) return @"";
	if([tracks count] == 0) return @"";
	if([[[tracks objectAtIndex:0] metadata] objectForKey:XLD_METADATA_ALBUMARTIST])
		return [[[tracks objectAtIndex:0] metadata] objectForKey:XLD_METADATA_ALBUMARTIST];
	NSString *artist = nil;
	int i;
	for(i=0;i<[tracks count];i++) {
		BOOL dataTrack = NO;
		if([[[tracks objectAtIndex:i] metadata] objectForKey:XLD_METADATA_DATATRACK]) {
			dataTrack = [[[[tracks objectAtIndex:i] metadata] objectForKey:XLD_METADATA_DATATRACK] boolValue];
		}
		if(dataTrack) continue;
		NSString *str = [[[tracks objectAtIndex:i] metadata] objectForKey:XLD_METADATA_ARTIST];
		if(!str) continue;
		else if([str isEqualToString:@""]) continue;
		else if([str isEqualToString:@" "]) continue;
		else if([str isEqualToString:LS(@"multibyteSpace")]) continue;
		else if(!artist) artist = str;
		else if([artist isEqualToString:str]) continue;
		else return LS(@"Various Artists");
	}
	if(!artist) return @"";
	return artist;
}

+ (NSString *)artistForTracks:(NSArray *)tracks sameArtistForAllTracks:(BOOL*)allSame
{
	*allSame = NO;
	if(!tracks) return @"";
	if([tracks count] == 0) return @"";
	if([[[tracks objectAtIndex:0] metadata] objectForKey:XLD_METADATA_ALBUMARTIST])
		return [[[tracks objectAtIndex:0] metadata] objectForKey:XLD_METADATA_ALBUMARTIST];
	NSString *artist = nil;
	int i;
	for(i=0;i<[tracks count];i++) {
		BOOL dataTrack = NO;
		if([[[tracks objectAtIndex:i] metadata] objectForKey:XLD_METADATA_DATATRACK]) {
			dataTrack = [[[[tracks objectAtIndex:i] metadata] objectForKey:XLD_METADATA_DATATRACK] boolValue];
		}
		if(dataTrack) continue;
		*allSame = NO;
		NSString *str = [[[tracks objectAtIndex:i] metadata] objectForKey:XLD_METADATA_ARTIST];
		if(!str) continue;
		else if([str isEqualToString:@""]) continue;
		else if([str isEqualToString:@" "]) continue;
		else if([str isEqualToString:LS(@"multibyteSpace")]) continue;
		else if(!artist) {
			*allSame = YES;
			artist = str;
		}
		else if([artist isEqualToString:str]) {
			*allSame = YES;
		}
		else return LS(@"Various Artists");
	}
	if(!artist) return @"";
	return artist;
}

+ (NSString *)dateForTracks:(NSArray *)tracks
{
	if(!tracks) return nil;
	if([tracks count] == 0) return nil;
	NSString *date = nil;
	int i;
	for(i=0;i<[tracks count];i++) {
		BOOL dataTrack = NO;
		if([[[tracks objectAtIndex:i] metadata] objectForKey:XLD_METADATA_DATATRACK]) {
			dataTrack = [[[[tracks objectAtIndex:i] metadata] objectForKey:XLD_METADATA_DATATRACK] boolValue];
		}
		if(dataTrack) continue;
		NSString *str = [[[tracks objectAtIndex:i] metadata] objectForKey:XLD_METADATA_DATE];
		if(!str) str = [[[[tracks objectAtIndex:i] metadata] objectForKey:XLD_METADATA_YEAR] stringValue];
		if(!str) return nil;
		else if(!date) {
			date = str;
		}
		else if([date isEqualToString:str]) continue;
		else return nil;
	}
	return date;
}

+ (NSString *)genreForTracks:(NSArray *)tracks
{
	if(!tracks) return nil;
	if([tracks count] == 0) return nil;
	NSString *genre = nil;
	int i;
	for(i=0;i<[tracks count];i++) {
		BOOL dataTrack = NO;
		if([[[tracks objectAtIndex:i] metadata] objectForKey:XLD_METADATA_DATATRACK]) {
			dataTrack = [[[[tracks objectAtIndex:i] metadata] objectForKey:XLD_METADATA_DATATRACK] boolValue];
		}
		if(dataTrack) continue;
		NSString *str = [[[tracks objectAtIndex:i] metadata] objectForKey:XLD_METADATA_GENRE];
		if(!str) return nil;
		else if(!genre) {
			genre = str;
		}
		else if([genre isEqualToString:str]) continue;
		else return nil;
	}
	return genre;
}

+ (NSString *)albumTitleForTracks:(NSArray *)tracks
{
	if(!tracks) return nil;
	if([tracks count] == 0) return nil;
	NSString *title = nil;
	int i;
	for(i=0;i<[tracks count];i++) {
		BOOL dataTrack = NO;
		if([[[tracks objectAtIndex:i] metadata] objectForKey:XLD_METADATA_DATATRACK]) {
			dataTrack = [[[[tracks objectAtIndex:i] metadata] objectForKey:XLD_METADATA_DATATRACK] boolValue];
		}
		if(dataTrack) continue;
		NSString *str = [[[tracks objectAtIndex:i] metadata] objectForKey:XLD_METADATA_ALBUM];
		if(!str) return nil;
		else if(!title) {
			title = str;
		}
		else if([title isEqualToString:str]) continue;
		else return nil;
	}
	return title;
}

+ (NSMutableData *)cueDataForTracks:(NSArray *)tracks withFileName:(NSString *)filename appendBOM:(BOOL)appendBOM samplerate:(int)samplerate
{
	if(!tracks) return nil;
	int i,n=1;
	int offset = 0;
	BOOL removeRedundancy = NO;
	NSMutableData *data = [[NSMutableData alloc] init];
	if(appendBOM) {
		const unsigned char bom[] = {0xEF,0xBB,0xBF};
		[data appendBytes:bom length:3];
	}
	NSString *albumDate = [XLDTrackListUtil dateForTracks:tracks];
	NSString *albumGenre = [XLDTrackListUtil genreForTracks:tracks];
	id obj;
	if(obj=[[[tracks objectAtIndex:0] metadata] objectForKey:XLD_METADATA_ALBUM])
		[data appendData:[[NSString stringWithFormat:@"TITLE \"%@\"\n",obj] dataUsingEncoding:NSUTF8StringEncoding]];
	if(obj=[[[tracks objectAtIndex:0] metadata] objectForKey:XLD_METADATA_ALBUMARTIST])
		[data appendData:[[NSString stringWithFormat:@"PERFORMER \"%@\"\n",obj] dataUsingEncoding:NSUTF8StringEncoding]];
	else {
		NSString *aartist = [XLDTrackListUtil artistForTracks:tracks sameArtistForAllTracks:&removeRedundancy];
		if(removeRedundancy)
			[data appendData:[[NSString stringWithFormat:@"PERFORMER \"%@\"\n",aartist] dataUsingEncoding:NSUTF8StringEncoding]];
	}
	if(obj=[[[tracks objectAtIndex:0] metadata] objectForKey:XLD_METADATA_CATALOG])
		[data appendData:[[NSString stringWithFormat:@"CATALOG %@\n",obj] dataUsingEncoding:NSUTF8StringEncoding]];
	if(albumGenre) {
		[data appendData:[[NSString stringWithFormat:@"REM GENRE \"%@\"\n",albumGenre] dataUsingEncoding:NSUTF8StringEncoding]];
	}
	if(albumDate) {
		[data appendData:[[NSString stringWithFormat:@"REM DATE \"%@\"\n",albumDate] dataUsingEncoding:NSUTF8StringEncoding]];
	}
	if(obj=[[[tracks objectAtIndex:0] metadata] objectForKey:XLD_METADATA_DISC])
		[data appendData:[[NSString stringWithFormat:@"REM DISCNUMBER %d\n",[obj intValue]] dataUsingEncoding:NSUTF8StringEncoding]];
	if(obj=[[[tracks objectAtIndex:0] metadata] objectForKey:XLD_METADATA_TOTALDISCS])
		[data appendData:[[NSString stringWithFormat:@"REM TOTALDISCS %d\n",[obj intValue]] dataUsingEncoding:NSUTF8StringEncoding]];
	if(obj=[[[tracks objectAtIndex:0] metadata] objectForKey:XLD_METADATA_FREEDBDISCID])
		[data appendData:[[NSString stringWithFormat:@"REM DISCID %08X\n",[obj unsignedIntValue]] dataUsingEncoding:NSUTF8StringEncoding]];
	if(obj=[[[tracks objectAtIndex:0] metadata] objectForKey:XLD_METADATA_REPLAYGAIN_ALBUM_GAIN])
		[data appendData:[[NSString stringWithFormat:@"REM REPLAYGAIN_ALBUM_GAIN %.2f dB\n",[obj floatValue]] dataUsingEncoding:NSUTF8StringEncoding]];
	if(obj=[[[tracks objectAtIndex:0] metadata] objectForKey:XLD_METADATA_REPLAYGAIN_ALBUM_PEAK])
		[data appendData:[[NSString stringWithFormat:@"REM REPLAYGAIN_ALBUM_PEAK %f\n",[obj floatValue]] dataUsingEncoding:NSUTF8StringEncoding]];
	if(obj=[[[tracks objectAtIndex:0] metadata] objectForKey:XLD_METADATA_COMPILATION])
		if([obj boolValue]) [data appendData:[@"REM COMPILATION TRUE\n" dataUsingEncoding:NSUTF8StringEncoding]];
	[data appendData:[[NSString stringWithFormat:@"FILE \"%@\" WAVE\n",[filename precomposedStringWithCanonicalMapping]] dataUsingEncoding:NSUTF8StringEncoding]];
	
	for(i=0;i<[tracks count];i++) {
		XLDTrack *track = [tracks objectAtIndex:i];
		if([[track metadata] objectForKey:XLD_METADATA_DATATRACK]) {
			if(i==0) {
				offset = [track frames];
				if(i+1 < [tracks count]) offset += [[tracks objectAtIndex:i+1] gap];
			}
			continue;
		}
		[data appendData:[[NSString stringWithFormat:@"  TRACK %02d AUDIO\n",n] dataUsingEncoding:NSUTF8StringEncoding]];
		if(obj=[[track metadata] objectForKey:XLD_METADATA_TITLE])
			[data appendData:[[NSString stringWithFormat:@"    TITLE \"%@\"\n",obj] dataUsingEncoding:NSUTF8StringEncoding]];
		if((obj=[[track metadata] objectForKey:XLD_METADATA_ARTIST]) && !removeRedundancy)
			[data appendData:[[NSString stringWithFormat:@"    PERFORMER \"%@\"\n",obj] dataUsingEncoding:NSUTF8StringEncoding]];
		if(obj=[[track metadata] objectForKey:XLD_METADATA_COMPOSER])
			[data appendData:[[NSString stringWithFormat:@"    SONGWRITER \"%@\"\n",obj] dataUsingEncoding:NSUTF8StringEncoding]];
		if(obj=[[track metadata] objectForKey:XLD_METADATA_ISRC]) 
			[data appendData:[[NSString stringWithFormat:@"    ISRC %@\n",obj] dataUsingEncoding:NSUTF8StringEncoding]];
		if(obj=[[track metadata] objectForKey:XLD_METADATA_PREEMPHASIS]) {
			if([obj boolValue]) [data appendData:[@"    FLAGS PRE\n" dataUsingEncoding:NSUTF8StringEncoding]];
		}
		if(obj=[[track metadata] objectForKey:XLD_METADATA_DCP]) {
			if([obj boolValue]) [data appendData:[@"    FLAGS DCP\n" dataUsingEncoding:NSUTF8StringEncoding]];
		}
		if(!albumGenre) {
			if(obj=[[track metadata] objectForKey:XLD_METADATA_GENRE])
				[data appendData:[[NSString stringWithFormat:@"    REM GENRE \"%@\"\n",obj] dataUsingEncoding:NSUTF8StringEncoding]];
		}
		if(!albumDate) {
			if(obj=[[track metadata] objectForKey:XLD_METADATA_DATE])
				[data appendData:[[NSString stringWithFormat:@"    REM DATE \"%@\"\n",obj] dataUsingEncoding:NSUTF8StringEncoding]];
			else if(obj=[[track metadata] objectForKey:XLD_METADATA_YEAR])
				[data appendData:[[NSString stringWithFormat:@"    REM DATE %d\n",[obj intValue]] dataUsingEncoding:NSUTF8StringEncoding]];
		}
		if(obj=[[track metadata] objectForKey:XLD_METADATA_COMMENT]) {
			NSMutableString *str = [NSMutableString stringWithString:obj];
			[str replaceOccurrencesOfString:@"\n" withString:@" " options:0 range:NSMakeRange(0,[obj length])];
			[data appendData:[[NSString stringWithFormat:@"    REM COMMENT \"%@\"\n",str] dataUsingEncoding:NSUTF8StringEncoding]];
		}
		if(obj=[[track metadata] objectForKey:XLD_METADATA_REPLAYGAIN_TRACK_GAIN])
			[data appendData:[[NSString stringWithFormat:@"    REM REPLAYGAIN_TRACK_GAIN %.2f dB\n",[obj floatValue]] dataUsingEncoding:NSUTF8StringEncoding]];
		if(obj=[[track metadata] objectForKey:XLD_METADATA_REPLAYGAIN_TRACK_PEAK])
			[data appendData:[[NSString stringWithFormat:@"    REM REPLAYGAIN_TRACK_PEAK %f\n",[obj floatValue]] dataUsingEncoding:NSUTF8StringEncoding]];
		
		if([track gap] != 0)
			[data appendData:[[NSString stringWithFormat:@"    INDEX 00 %@\n",framesToMSFStr([track index]-[track gap]-offset,samplerate)] dataUsingEncoding:NSUTF8StringEncoding]];
		[data appendData:[[NSString stringWithFormat:@"    INDEX 01 %@\n",framesToMSFStr([track index]-offset,samplerate)] dataUsingEncoding:NSUTF8StringEncoding]];
		n++;
	}
	return [data autorelease];
}

+ (NSMutableData *)nonCompliantCueDataForTracks:(NSArray *)trackList withFileNameArray:(NSArray *)filelist appendBOM:(BOOL)appendBOM gapStatus:(unsigned int)status samplerate:(int)samplerate
{
	if(!trackList) return nil;
	int i,n=1;
	BOOL removeRedundancy = NO;
	BOOL nogap = NO;
	BOOL HTOA = NO;
	switch(status & 0xffff) {
		case 0:
			HTOA = YES;
			break;
		case 1:
			nogap = YES;
			break;
		case 2:
			HTOA = YES;
			break;
		case 3:
			HTOA = NO;
			break;
	}
	
	NSMutableData *data = [[NSMutableData alloc] init];
	NSString *albumDate = [XLDTrackListUtil dateForTracks:trackList];
	NSString *albumGenre = [XLDTrackListUtil genreForTracks:trackList];
	id obj;
	if(obj=[[[trackList objectAtIndex:0] metadata] objectForKey:XLD_METADATA_ALBUM])
		[data appendData:[[NSString stringWithFormat:@"TITLE \"%@\"\n",obj] dataUsingEncoding:NSUTF8StringEncoding]];
	if(obj=[[[trackList objectAtIndex:0] metadata] objectForKey:XLD_METADATA_ALBUMARTIST])
		[data appendData:[[NSString stringWithFormat:@"PERFORMER \"%@\"\n",obj] dataUsingEncoding:NSUTF8StringEncoding]];
	else {
		NSString *aartist = [XLDTrackListUtil artistForTracks:trackList sameArtistForAllTracks:&removeRedundancy];
		if(removeRedundancy)
			[data appendData:[[NSString stringWithFormat:@"PERFORMER \"%@\"\n",aartist] dataUsingEncoding:NSUTF8StringEncoding]];
	}
	if(obj=[[[trackList objectAtIndex:0] metadata] objectForKey:XLD_METADATA_CATALOG])
		[data appendData:[[NSString stringWithFormat:@"CATALOG %@\n",obj] dataUsingEncoding:NSUTF8StringEncoding]];
	if(albumGenre) {
		[data appendData:[[NSString stringWithFormat:@"REM GENRE \"%@\"\n",albumGenre] dataUsingEncoding:NSUTF8StringEncoding]];
	}
	if(albumDate) {
		[data appendData:[[NSString stringWithFormat:@"REM DATE \"%@\"\n",albumDate] dataUsingEncoding:NSUTF8StringEncoding]];
	}
	if(obj=[[[trackList objectAtIndex:0] metadata] objectForKey:XLD_METADATA_DISC])
		[data appendData:[[NSString stringWithFormat:@"REM DISCNUMBER %d\n",[obj intValue]] dataUsingEncoding:NSUTF8StringEncoding]];
	if(obj=[[[trackList objectAtIndex:0] metadata] objectForKey:XLD_METADATA_TOTALDISCS])
		[data appendData:[[NSString stringWithFormat:@"REM TOTALDISCS %d\n",[obj intValue]] dataUsingEncoding:NSUTF8StringEncoding]];
	if(obj=[[[trackList objectAtIndex:0] metadata] objectForKey:XLD_METADATA_FREEDBDISCID])
		[data appendData:[[NSString stringWithFormat:@"REM DISCID %08X\n",[obj unsignedIntValue]] dataUsingEncoding:NSUTF8StringEncoding]];
	if(obj=[[[trackList objectAtIndex:0] metadata] objectForKey:XLD_METADATA_REPLAYGAIN_ALBUM_GAIN])
		[data appendData:[[NSString stringWithFormat:@"REM REPLAYGAIN_ALBUM_GAIN %.2f dB\n",[obj floatValue]] dataUsingEncoding:NSUTF8StringEncoding]];
	if(obj=[[[trackList objectAtIndex:0] metadata] objectForKey:XLD_METADATA_REPLAYGAIN_ALBUM_PEAK])
		[data appendData:[[NSString stringWithFormat:@"REM REPLAYGAIN_ALBUM_PEAK %f\n",[obj floatValue]] dataUsingEncoding:NSUTF8StringEncoding]];
	if(obj=[[[trackList objectAtIndex:0] metadata] objectForKey:XLD_METADATA_COMPILATION])
		if([obj boolValue]) [data appendData:[@"REM COMPILATION TRUE\n" dataUsingEncoding:NSUTF8StringEncoding]];
	
	for(i=0;i<[trackList count];i++) {
		XLDTrack *track = [trackList objectAtIndex:i];
		BOOL dataTrack = NO;
		if([[track metadata] objectForKey:XLD_METADATA_DATATRACK]) {
			dataTrack = [[[track metadata] objectForKey:XLD_METADATA_DATATRACK] boolValue];
		}
		if(dataTrack) continue;
		
		[data appendData:[[NSString stringWithFormat:@"FILE \"%@\" WAVE\n",[[[filelist objectAtIndex:n-1] lastPathComponent] precomposedStringWithCanonicalMapping]] dataUsingEncoding:NSUTF8StringEncoding]];
		if(([track gap] != 0) && (i != 0) && !nogap) {
			[data appendData:[@"    INDEX 01 00:00:00\n" dataUsingEncoding:NSUTF8StringEncoding]];
		}
		else {
			[data appendData:[[NSString stringWithFormat:@"  TRACK %02d AUDIO\n",n] dataUsingEncoding:NSUTF8StringEncoding]];
			if(obj=[[track metadata] objectForKey:XLD_METADATA_TITLE])
				[data appendData:[[NSString stringWithFormat:@"    TITLE \"%@\"\n",obj] dataUsingEncoding:NSUTF8StringEncoding]];
			if((obj=[[track metadata] objectForKey:XLD_METADATA_ARTIST]) && !removeRedundancy)
				[data appendData:[[NSString stringWithFormat:@"    PERFORMER \"%@\"\n",obj] dataUsingEncoding:NSUTF8StringEncoding]];
			if(obj=[[track metadata] objectForKey:XLD_METADATA_COMPOSER])
				[data appendData:[[NSString stringWithFormat:@"    SONGWRITER \"%@\"\n",obj] dataUsingEncoding:NSUTF8StringEncoding]];
			if(obj=[[track metadata] objectForKey:XLD_METADATA_ISRC])
				[data appendData:[[NSString stringWithFormat:@"    ISRC %@\n",obj] dataUsingEncoding:NSUTF8StringEncoding]];
			if(obj=[[track metadata] objectForKey:XLD_METADATA_PREEMPHASIS]) {
				if([obj boolValue]) [data appendData:[@"    FLAGS PRE\n" dataUsingEncoding:NSUTF8StringEncoding]];
			}
			if(obj=[[track metadata] objectForKey:XLD_METADATA_DCP]) {
				if([obj boolValue]) [data appendData:[@"    FLAGS DCP\n" dataUsingEncoding:NSUTF8StringEncoding]];
			}
			if(!albumGenre) {
				if(obj=[[track metadata] objectForKey:XLD_METADATA_GENRE])
					[data appendData:[[NSString stringWithFormat:@"    REM GENRE \"%@\"\n",obj] dataUsingEncoding:NSUTF8StringEncoding]];
			}
			if(!albumDate) {
				if(obj=[[track metadata] objectForKey:XLD_METADATA_DATE])
					[data appendData:[[NSString stringWithFormat:@"    REM DATE \"%@\"\n",obj] dataUsingEncoding:NSUTF8StringEncoding]];
				else if(obj=[[track metadata] objectForKey:XLD_METADATA_YEAR])
					[data appendData:[[NSString stringWithFormat:@"    REM DATE %d\n",[obj intValue]] dataUsingEncoding:NSUTF8StringEncoding]];
			}
			if(obj=[[track metadata] objectForKey:XLD_METADATA_COMMENT]) {
				NSMutableString *str = [NSMutableString stringWithString:obj];
				[str replaceOccurrencesOfString:@"\n" withString:@" " options:0 range:NSMakeRange(0,[obj length])];
				[data appendData:[[NSString stringWithFormat:@"    REM COMMENT \"%@\"\n",str] dataUsingEncoding:NSUTF8StringEncoding]];
			}
			if(obj=[[track metadata] objectForKey:XLD_METADATA_REPLAYGAIN_TRACK_GAIN])
				[data appendData:[[NSString stringWithFormat:@"    REM REPLAYGAIN_TRACK_GAIN %.2f dB\n",[obj floatValue]] dataUsingEncoding:NSUTF8StringEncoding]];
			if(obj=[[track metadata] objectForKey:XLD_METADATA_REPLAYGAIN_TRACK_PEAK])
				[data appendData:[[NSString stringWithFormat:@"    REM REPLAYGAIN_TRACK_PEAK %f\n",[obj floatValue]] dataUsingEncoding:NSUTF8StringEncoding]];
			if(([track gap] != 0) && (i == 0)) {
				if(HTOA && !nogap) {
					[data appendData:[@"    INDEX 00 00:00:00\n" dataUsingEncoding:NSUTF8StringEncoding]];
					[data appendData:[[NSString stringWithFormat:@"    INDEX 01 %@\n",framesToMSFStr([track index],samplerate)] dataUsingEncoding:NSUTF8StringEncoding]];
				}
				else {
					[data appendData:[[NSString stringWithFormat:@"    PREGAP %@\n",framesToMSFStr([track index],samplerate)] dataUsingEncoding:NSUTF8StringEncoding]];
					[data appendData:[@"    INDEX 01 00:00:00\n" dataUsingEncoding:NSUTF8StringEncoding]];
				}
			}
			else if(([track gap] != 0) && nogap) {
				[data appendData:[[NSString stringWithFormat:@"    PREGAP %@\n",framesToMSFStr([track gap],samplerate)] dataUsingEncoding:NSUTF8StringEncoding]];
				[data appendData:[@"    INDEX 01 00:00:00\n" dataUsingEncoding:NSUTF8StringEncoding]];
			}
			else {
				[data appendData:[@"    INDEX 01 00:00:00\n" dataUsingEncoding:NSUTF8StringEncoding]];
			}
		}
		n++;
		
		if((i != [trackList count]-1) && [[trackList objectAtIndex:i+1] gap] && !nogap) {
			[data appendData:[[NSString stringWithFormat:@"  TRACK %02d AUDIO\n",n] dataUsingEncoding:NSUTF8StringEncoding]];
			if(obj=[[[trackList objectAtIndex:i+1] metadata] objectForKey:XLD_METADATA_TITLE])
				[data appendData:[[NSString stringWithFormat:@"    TITLE \"%@\"\n",obj] dataUsingEncoding:NSUTF8StringEncoding]];
			if((obj=[[[trackList objectAtIndex:i+1] metadata] objectForKey:XLD_METADATA_ARTIST]) && !removeRedundancy)
				[data appendData:[[NSString stringWithFormat:@"    PERFORMER \"%@\"\n",obj] dataUsingEncoding:NSUTF8StringEncoding]];
			if(obj=[[[trackList objectAtIndex:i+1] metadata] objectForKey:XLD_METADATA_COMPOSER])
				[data appendData:[[NSString stringWithFormat:@"    SONGWRITER \"%@\"\n",obj] dataUsingEncoding:NSUTF8StringEncoding]];
			if(obj=[[[trackList objectAtIndex:i+1] metadata] objectForKey:XLD_METADATA_ISRC])
				[data appendData:[[NSString stringWithFormat:@"    ISRC %@\n",obj] dataUsingEncoding:NSUTF8StringEncoding]];
			if(obj=[[[trackList objectAtIndex:i+1] metadata] objectForKey:XLD_METADATA_PREEMPHASIS]) {
				if([obj boolValue]) [data appendData:[@"    FLAGS PRE\n" dataUsingEncoding:NSUTF8StringEncoding]];
			}
			if(obj=[[[trackList objectAtIndex:i+1] metadata] objectForKey:XLD_METADATA_DCP]) {
				if([obj boolValue]) [data appendData:[@"    FLAGS DCP\n" dataUsingEncoding:NSUTF8StringEncoding]];
			}
			if(!albumGenre) {
				if(obj=[[[trackList objectAtIndex:i+1] metadata] objectForKey:XLD_METADATA_GENRE])
					[data appendData:[[NSString stringWithFormat:@"    REM GENRE \"%@\"\n",obj] dataUsingEncoding:NSUTF8StringEncoding]];
			}
			if(!albumDate) {
				if(obj=[[[trackList objectAtIndex:i+1] metadata] objectForKey:XLD_METADATA_DATE])
					[data appendData:[[NSString stringWithFormat:@"    REM DATE \"%@\"\n",obj] dataUsingEncoding:NSUTF8StringEncoding]];
				else if(obj=[[[trackList objectAtIndex:i+1] metadata] objectForKey:XLD_METADATA_YEAR])
					[data appendData:[[NSString stringWithFormat:@"    REM DATE %d\n",[obj intValue]] dataUsingEncoding:NSUTF8StringEncoding]];
			}
			if(obj=[[[trackList objectAtIndex:i+1] metadata] objectForKey:XLD_METADATA_COMMENT]) {
				NSMutableString *str = [NSMutableString stringWithString:obj];
				[str replaceOccurrencesOfString:@"\n" withString:@" " options:0 range:NSMakeRange(0,[obj length])];
				[data appendData:[[NSString stringWithFormat:@"    REM COMMENT \"%@\"\n",str] dataUsingEncoding:NSUTF8StringEncoding]];
			}
			if(obj=[[[trackList objectAtIndex:i+1] metadata] objectForKey:XLD_METADATA_REPLAYGAIN_TRACK_GAIN])
				[data appendData:[[NSString stringWithFormat:@"    REM REPLAYGAIN_TRACK_GAIN %.2f dB\n",[obj floatValue]] dataUsingEncoding:NSUTF8StringEncoding]];
			if(obj=[[[trackList objectAtIndex:i+1] metadata] objectForKey:XLD_METADATA_REPLAYGAIN_TRACK_PEAK])
				[data appendData:[[NSString stringWithFormat:@"    REM REPLAYGAIN_TRACK_PEAK %f\n",[obj floatValue]] dataUsingEncoding:NSUTF8StringEncoding]];
			if(i==0 && HTOA && !nogap) [data appendData:[[NSString stringWithFormat:@"    INDEX 00 %@\n",framesToMSFStr([track frames]+[track gap],samplerate)] dataUsingEncoding:NSUTF8StringEncoding]];
			else [data appendData:[[NSString stringWithFormat:@"    INDEX 00 %@\n",framesToMSFStr([track frames],samplerate)] dataUsingEncoding:NSUTF8StringEncoding]];
		}
	}
	return [data autorelease];
}

+ (NSString *)gracenoteDiscIDForTracks:(NSArray *)tracks totalFrames:(xldoffset_t)totalFrames freeDBDiscID:(unsigned int)discid
{
	NSMutableString *str = [NSMutableString string];
	[str appendFormat:@"%08X+%lld+%d",discid,(totalFrames)/588+150,[tracks count]];
	int i;
	for(i=0;i<[tracks count];i++) {
		[str appendFormat:@"+%lld",[(XLDTrack *)[tracks objectAtIndex:i] index]/588+150];
	}
	//NSLog(str);
	return str;
}

@end

@implementation NSFileManager (DirectoryAdditions)
- (void)createDirectoryWithIntermediateDirectoryInPath:(NSString *)path
{
	if([self fileExistsAtPath:path]) return;
	if([self respondsToSelector:@selector(createDirectoryAtPath:withIntermediateDirectories:attributes:error:)]) {
		[self createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:NULL];
	}
	else {
		[self _web_createDirectoryAtPathWithIntermediateDirectories:path attributes:nil];
	}
}

- (NSArray *)directoryContentsAt:(NSString *)path
{
	if([self respondsToSelector:@selector(contentsOfDirectoryAtPath:error:)]) {
		return [self contentsOfDirectoryAtPath:path error:NULL];
	}
	else return [self directoryContentsAtPath:path];
}
@end

@implementation NSMutableDictionary (NSUserDefaultsCompatibility)
- (void)setInteger:(int)value forKey:(NSString *)defaultName
{
	[self setObject:[NSNumber numberWithInt:value] forKey:defaultName];
}

- (void)setBool:(BOOL)value forKey:(NSString *)defaultName
{
	[self setObject:[NSNumber numberWithBool:value] forKey:defaultName];
}
@end

@implementation XLDSplitView
- (float)dividerThickness
{
    return 1.0f;
}

- (void)drawDividerInRect:(NSRect)rect
{
    [[NSColor grayColor] set];
    NSRectFill(rect);
}

@end

@implementation XLDAdaptiveTexturedWindow
- (id)initWithContentRect:(NSRect)contentRect styleMask:(unsigned int)windowStyle backing:(NSBackingStoreType)bufferingType defer:(BOOL)deferCreation
{
	if(floor(NSAppKitVersionNumber) > NSAppKitVersionNumber10_4) {
		windowStyle |= NSTexturedBackgroundWindowMask;
	}
	else {
		windowStyle &= ~NSTexturedBackgroundWindowMask;
	}
	return [super initWithContentRect:contentRect styleMask:windowStyle backing:bufferingType defer:deferCreation];
}
@end

@implementation NSWorkspace (IconAdditions)
- (NSImage *)iconForFolder
{
	 return [self iconForFileType:NSFileTypeForHFSTypeCode(kGenericFolderIcon)];
}

- (NSImage *)iconForDisc
{
	 return [self iconForFileType:NSFileTypeForHFSTypeCode(kGenericCDROMIcon)];
}

- (NSImage *)iconForBurn
{
	return [self iconForFileType:NSFileTypeForHFSTypeCode(kBurningIcon)];
}
@end

@implementation NSData (FasterSynchronusDownload)

+ (NSData *)fastDataWithContentsOfURL:(NSURL *)url
{
	NSURLResponse *resp;
	NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:30.0];
	if(floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_4) {
		int sels[2] = { CTL_KERN , KERN_OSRELEASE };
		char darwin[32];
		size_t size = 32;
		sysctl(sels,2,&darwin,&size,NULL,0);
		NSBundle *cfnetwork = [NSBundle bundleWithPath:@"/System/Library/Frameworks/CoreServices.framework/Frameworks/CFNetwork.framework"];
		[req addValue:[NSString stringWithFormat:@"XLD/%@ CFNetwork/%@ Darwin/%s",[[[NSBundle mainBundle] infoDictionary] valueForKey:@"CFBundleVersion"],[[cfnetwork infoDictionary] objectForKey:@"CFBundleVersion"],darwin] forHTTPHeaderField:@"User-Agent"];
	}
	return [NSURLConnection sendSynchronousRequest:req returningResponse:&resp error:nil];
}

+ (NSData *)fastDataWithContentsOfURL:(NSURL *)url error:(NSError **)err
{
	NSURLResponse *resp;
	NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:30.0];
	if(floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_4) {
		int sels[2] = { CTL_KERN , KERN_OSRELEASE };
		char darwin[32];
		size_t size = 32;
		sysctl(sels,2,&darwin,&size,NULL,0);
		NSBundle *cfnetwork = [NSBundle bundleWithPath:@"/System/Library/Frameworks/CoreServices.framework/Frameworks/CFNetwork.framework"];
		[req addValue:[NSString stringWithFormat:@"XLD/%@ CFNetwork/%@ Darwin/%s",[[[NSBundle mainBundle] infoDictionary] valueForKey:@"CFBundleVersion"],[[cfnetwork infoDictionary] objectForKey:@"CFBundleVersion"],darwin] forHTTPHeaderField:@"User-Agent"];
	}
	return [NSURLConnection sendSynchronousRequest:req returningResponse:&resp error:err];
}

@end

@implementation NSFlippedView

- (BOOL)isFlipped
{
	return YES;
}

@end

@implementation NSDate (XLDLocalizedDateDecription)

- (NSString *)localizedDateDescription
{
	if([NSDateFormatter instancesRespondToSelector:@selector(setFormatterBehavior:)]) {
		NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
		[dateFormatter setFormatterBehavior:NSDateFormatterBehavior10_4];
		[dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss ZZZ"];
		NSString *str = [dateFormatter stringFromDate:self];
		[dateFormatter release];
		return str;
	}
	return [self description];
}

@end

@implementation XLDBundle
- (NSDictionary *)infoDictionary
{
	//NSLog(@"infoDictionary");
	id dic = [super infoDictionary];
	//NSDictionary *newDic = [[NSDictionary alloc] initWithDictionary:dic];
	if([dic respondsToSelector:@selector(setBool:forKey:)]) [dic setBool:YES forKey:@"LSUIElement"];
	return dic;
}
@end

@implementation NSFileManager (XLDFileMove)
- (void)moveFileAtPath:(NSString *)src toPath:(NSString *)dst
{
	if([self respondsToSelector:@selector(moveItemAtPath:toPath:error:)]) {
		[self moveItemAtPath:src toPath:dst error:nil];
	}
	else [self movePath:src toPath:dst handler:nil];
}
@end
