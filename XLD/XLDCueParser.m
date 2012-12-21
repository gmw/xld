//
//  XLDCueParser.m
//  XLD
//
//  Created by tmkk on 06/06/10.
//  Copyright 2006 tmkk. All rights reserved.
//
// Access to AccurateRip is regulated, see  http://www.accuraterip.com/3rdparty-access.htm for details.

#import "XLDCueParser.h"
#import "XLDController.h"
#import "XLDecoderCenter.h"
#import "XLDTrack.h"
#import "XLDRawDecoder.h"
#import "XLDCustomClasses.h"
#import "XLDMultipleFileWrappedDecoder.h"

static NSString *framesToMSFStr(xldoffset_t frames, int samplerate)
{
	int min = frames/samplerate/60;
	frames -= min*samplerate*60;
	int sec = frames/samplerate;
	frames -= sec*samplerate;
	int f = frames*75/samplerate;
	return [NSString stringWithFormat:@"%02d:%02d:%02d",min,sec,f];
}

static xldoffset_t timeToFrame(int min, int sec, int sector, int samplerate)
{
	xldoffset_t ret;
	ret = min*60*samplerate;
	ret += sec*samplerate;
	ret += sector*samplerate/75;
	return ret;
}

static char *fgets_private(char *buf, int size, FILE *fp)
{
	int i;
	char c;
	
	for(i=0;i<size-1;) {
		if(fread(&c,1,1,fp) != 1) break;
		buf[i++] = c;
		if(c == '\n' || c == '\r') {
			break;
		}
	}
	if(i==0) return NULL;
	buf[i] = 0;
	return buf;
}

static NSStringEncoding detectEncoding(FILE *fp)
{
	char buf[2048];
	char tmp[2048];
	char *ptr = buf;
	int len = 0;
	int minLength = INT_MAX;
	off_t pos = ftello(fp);
	CFStringRef asciiStr;
	CFStringRef sjisStr;
	CFStringRef cp932Str;
	CFStringRef jisStr;
	CFStringRef eucStr;
	CFStringRef utf8Str;
	int asciiLength;
	int sjisLength;
	int cp932Length;
	int jisLength;
	int eucLength;
	int utf8Length;
	
	
	while(fgets_private(tmp,2048,fp) != NULL) {
		int ret = strlen(tmp);
		len += ret;
		if(len > 2048) {
			len -= ret;
			break;
		}
		memcpy(ptr,tmp,ret);
		ptr += ret;
	}
	
	asciiStr = CFStringCreateWithBytes(NULL, (const UInt8 *)buf, len,  kCFStringEncodingASCII,false);
	sjisStr = CFStringCreateWithBytes(NULL, (const UInt8 *)buf, len, kCFStringEncodingShiftJIS,false);
	cp932Str = CFStringCreateWithBytes(NULL, (const UInt8 *)buf, len, kCFStringEncodingDOSJapanese,false);
	jisStr = CFStringCreateWithBytes(NULL, (const UInt8 *)buf, len, kCFStringEncodingISO_2022_JP,false);
	eucStr = CFStringCreateWithBytes(NULL, (const UInt8 *)buf, len, kCFStringEncodingEUC_JP,false);
	utf8Str = CFStringCreateWithBytes(NULL, (const UInt8 *)buf, len, kCFStringEncodingUTF8,false);
	
	asciiLength = (asciiStr) ? CFStringGetLength(asciiStr) : INT_MAX;
	sjisLength = (sjisStr) ? CFStringGetLength(sjisStr) : INT_MAX;
	cp932Length = (cp932Str) ? CFStringGetLength(cp932Str) : INT_MAX;
	jisLength = (jisStr) ? CFStringGetLength(jisStr) : INT_MAX;
	eucLength = (eucStr) ? CFStringGetLength(eucStr) : INT_MAX;
	utf8Length = (utf8Str) ? CFStringGetLength(utf8Str) : INT_MAX;
	
	if(asciiLength < minLength) minLength = asciiLength;
	if(sjisLength < minLength) minLength = sjisLength;
	if(cp932Length < minLength) minLength = cp932Length;
	if(jisLength < minLength) minLength = jisLength;
	if(eucLength < minLength) minLength = eucLength;
	if(utf8Length < minLength) minLength = utf8Length;
	
	//NSLog(@"%d,%d,%d,%d,%d,%d\n",asciiLength,sjisLength,cp932Length,jisLength,eucLength,utf8Length);
	
	if(asciiStr) CFRelease(asciiStr);
	if(sjisStr) CFRelease(sjisStr);
	if(cp932Str) CFRelease(cp932Str);
	if(jisStr) CFRelease(jisStr);
	if(eucStr) CFRelease(eucStr);
	if(utf8Str) CFRelease(utf8Str);
	fseeko(fp,pos,SEEK_SET);
	
	if(minLength == INT_MAX) return [NSString defaultCStringEncoding];
	if(minLength == asciiLength) return [NSString defaultCStringEncoding];
	if(minLength == sjisLength) return CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingShiftJIS);
	if(minLength == cp932Length) return CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingDOSJapanese);
	if(minLength == utf8Length) return CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingUTF8);
	if(minLength == eucLength) return CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingEUC_JP);
	if(minLength == jisLength) return CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISO_2022_JP);
	
	return [NSString defaultCStringEncoding];
}

static NSString *readMetadataFromLineBuf(char *cuebuf, int pos, NSStringEncoding enc, BOOL robustEncoding)
{
	int j, delimiter=0;
	BOOL valid = NO;
	NSString *str;
	while(*(cuebuf+pos)==' ' || *(cuebuf+pos)=='\t' || *(cuebuf+pos)=='"' || *(cuebuf+pos)=='\'') {
		valid = YES;
		pos++;
		if(*(cuebuf+pos-1)=='"' || *(cuebuf+pos-1)=='\'') {
			delimiter = *(cuebuf+pos-1);
			break;
		}
	}
	if(!valid) return nil;
	j=pos;
	if(delimiter) {
		char *found = strrchr(cuebuf+j, delimiter);
		if(found) {
			j = found - cuebuf;
			if(pos == j) return nil;
		}
	}
	if(pos == j) {
		while(*(cuebuf+j)!='\n' && *(cuebuf+j)!='\r' && *(cuebuf+j)!=0) j++;
	}
	if(pos == j) return nil;
	*(cuebuf+j) = 0;
	NSData *dat = [NSData dataWithBytes:cuebuf+pos length:j-pos];
	str = [[NSString alloc] initWithData:dat encoding:enc];
	if(robustEncoding) {
		if(!str) str = [[NSString alloc] initWithData:dat encoding:[NSString defaultCStringEncoding]];
		if(!str) str = [[NSString alloc] initWithData:dat encoding:NSUTF8StringEncoding];
	}
	if(str) return [str autorelease];
	else return nil;
}

static unsigned int getDiscId(NSArray *trackList, xldoffset_t totalFrames)
{
	unsigned int i,cddbDiscId=0;
	int totalTrack = [trackList count];
	
	for(i=0;i<totalTrack;i++) {
		int trackOffset =  [(XLDTrack *)[trackList objectAtIndex:i] index];
		trackOffset /= 588;
		
		int r=0;
		int n=trackOffset/75 + 2;
		while(n>0) {
			r = r + (n%10);
			n = n/10;
		}
		cddbDiscId = cddbDiscId + r;
	}
	
	cddbDiscId = ((cddbDiscId % 255) << 24) | ((totalFrames/588/75 - [(XLDTrack *)[trackList objectAtIndex:0] index]/588/75) << 8) | totalTrack;
	return cddbDiscId;
}

static int numberOfFILELine(NSString *file)
{
	int ret = 0;
	char buf[512];
	int read = 0;
	unsigned char bom[] = {0xEF,0xBB,0xBF};
	unsigned char tmp[3];
	FILE *fp = fopen([file UTF8String],"rb");
	if(!fp) goto last;
	
	fread(tmp,1,3,fp);
	if(memcmp(tmp,bom,3)) rewind(fp);

	while(read < 100*1024 && fgets_private(buf,512,fp) && ret < 2) {
		int i=0;
		read += strlen(buf);
		while(*(buf+i)==' ' || *(buf+i)=='\t') i++;
		if(!strncasecmp(buf,"FILE",4)) ret++;
	}
	
last:
	if(fp) fclose(fp);
	return ret;
}

static NSString *mountNameFromBSDName(const char *bsdName)
{
	NSString *volume = nil;
	DASessionRef session = DASessionCreate(NULL);
	DADiskRef disk = DADiskCreateFromBSDName(NULL,session,bsdName);
	CFDictionaryRef dic = DADiskCopyDescription(disk);
	volume = [NSString stringWithString:(NSString *)CFDictionaryGetValue(dic,kDADiskDescriptionVolumeNameKey)];
	CFRelease(dic);
	CFRelease(disk);
	CFRelease(session);
	
	return volume;
}

@implementation XLDCueParser

- (id)init
{
	trackList = [[NSMutableArray alloc] init];
	checkList = [[NSMutableArray alloc] init];
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
	[trackList release];
	[checkList release];
	if(delegate) [delegate release];
	if(fileToDecode) [fileToDecode release];
	if(title) [title release];
	if(cover) [cover release];
	if(driveStr) [driveStr release];
	if(discLayout) [discLayout release];
	if(accurateRipData) [accurateRipData release];
	if(errorMsg) [errorMsg release];
	if(representedFilename) [representedFilename release];
	if(mediaType) [mediaType release];
	[super dealloc];
}

- (void)clean
{
	int i;
	for(i=0;i<[checkList count];i++) {
		[[checkList objectAtIndex:i] removeFromSuperview];
	}
	if(trackList) [trackList release];
	if(checkList) [checkList release];
	trackList = [[NSMutableArray alloc] init];
	checkList = [[NSMutableArray alloc] init];
	if(fileToDecode) [fileToDecode release];
	if(title) [title release];
	if(cover) [cover release];
	if(driveStr) [driveStr release];
	if(discLayout) [discLayout release];
	if(accurateRipData) [accurateRipData release];
	if(errorMsg) [errorMsg release];
	if(representedFilename) [representedFilename release];
	if(mediaType) [mediaType release];
	fileToDecode = nil;
	title = nil;
	cover = nil;
	driveStr = nil;
	discLayout = nil;
	accurateRipData = nil;
	cueMode = XLDCueModeDefault;
	ARQueried = NO;
	writable = NO;
	errorMsg = nil;
	representedFilename = nil;
	preferredEncoding = 0;
	mediaType = nil;
}

- (BOOL)isCompilationForTracks:(NSArray *)tracks
{
	if(!tracks) return NO;
	if([tracks count] == 0) return NO;
	NSString *albumArtist = [[[tracks objectAtIndex:0] metadata] objectForKey:XLD_METADATA_ALBUMARTIST];
	if(albumArtist && ![albumArtist isEqualToString:@""]) return NO;
	NSString *artist = nil;
	int i;
	for(i=0;i<[tracks count];i++) {
		NSString *str = [[[tracks objectAtIndex:i] metadata] objectForKey:XLD_METADATA_ARTIST];
		if(!str) continue;
		else if([str isEqualToString:@""]) continue;
		else if([str isEqualToString:@" "]) continue;
		else if([str isEqualToString:LS(@"multibyteSpace")]) continue;
		else if(!artist) artist = str;
		else if([artist isEqualToString:str]) continue;
		else return YES;
	}
	return NO;
}

- (BOOL)isCompilation
{
	return [self isCompilationForTracks:trackList];
}

- (NSString *)setTrackData:(NSMutableArray *)tracks forCueFile:(NSString *)file withDecoder:(id)decoder
{
	FILE *fp = fopen([file UTF8String],"rb");
	if(!fp) return nil;
	
	char cuebuf[512];
	int stat = 1,i,len,track=1;
	xldoffset_t gapIdx=0;
	NSString *titleStr = nil;
	NSString *date = nil;
	NSString *genre = nil;
	NSString *albumArtist = nil;
	NSString *catalog = nil;
	NSString *comment = nil;
	NSString *composer = nil;
	int totalDisc = 0;
	int discNumber = 0;
	unsigned int discid = 0;
	BOOL discCompilation = NO;
	NSStringEncoding enc;
	BOOL hasPerformer = NO;
	unsigned char bom[] = {0xEF,0xBB,0xBF};
	unsigned char tmp[3];
	
	if(preferredEncoding) enc = preferredEncoding;
	else if(!delegate || [delegate encoding] == 0xFFFFFFFF || preferredEncoding == 0xFFFFFFFF) {
		enc = detectEncoding(fp);
	}
	else {
		enc = [delegate encoding];
	}
	int read = 0;
	
	fread(tmp,1,3,fp);
	if(memcmp(tmp,bom,3)) rewind(fp);
	
	while(read < 100*1024 && (fgets_private(cuebuf,512,fp) != NULL)) {
		i=0;
		len = strlen(cuebuf);
		read += len;
		while(*(cuebuf+i)==' ' || *(cuebuf+i)=='\t') i++;
		if(i>len-3) continue;
		if(!strncasecmp(cuebuf+i,"TITLE",5)) {
			titleStr = readMetadataFromLineBuf(cuebuf,i+5,enc,YES);
		}
		else if(!strncasecmp(cuebuf+i,"PERFORMER",9)) {
			albumArtist = readMetadataFromLineBuf(cuebuf,i+9,enc,YES);
		}
		else if(!strncasecmp(cuebuf+i,"CATALOG",7)) {
			catalog = readMetadataFromLineBuf(cuebuf,i+7,enc,YES);
		}
		else if(!strncasecmp(cuebuf+i,"SONGWRITER",10)) {
			composer = readMetadataFromLineBuf(cuebuf,i+10,enc,YES);
		}
		else if(!strncasecmp(cuebuf+i,"DISCNUMBER",10)) {
			discNumber = [readMetadataFromLineBuf(cuebuf,i+10,enc,YES) intValue];
		}
		else if(!strncasecmp(cuebuf+i,"TOTALDISCS",10)) {
			totalDisc = [readMetadataFromLineBuf(cuebuf,i+10,enc,YES) intValue];
		}
		else if(!strncasecmp(cuebuf+i,"REM",3)) {
			i = i + 3;
			while(*(cuebuf+i)==' ' || *(cuebuf+i)=='\t') i++;
			if(!strncasecmp(cuebuf+i,"DATE",4)) {
				date = readMetadataFromLineBuf(cuebuf,i+4,enc,YES);
			}
			else if(!strncasecmp(cuebuf+i,"GENRE",5)) {
				genre = readMetadataFromLineBuf(cuebuf,i+5,enc,YES);
			}
			else if(!strncasecmp(cuebuf+i,"COMMENT",7)) {
				comment = readMetadataFromLineBuf(cuebuf,i+7,enc,YES);
			}
			else if(!strncasecmp(cuebuf+i,"DISCNUMBER",10)) {
				discNumber = [readMetadataFromLineBuf(cuebuf,i+10,enc,YES) intValue];
			}
			else if(!strncasecmp(cuebuf+i,"TOTALDISCS",10)) {
				totalDisc = [readMetadataFromLineBuf(cuebuf,i+10,enc,YES) intValue];
			}
			else if(!strncasecmp(cuebuf+i,"DISCID",6)) {
				const char *discidstr = [readMetadataFromLineBuf(cuebuf,i+6,enc,YES) UTF8String];
				if(discidstr) discid = strtoul(discidstr,NULL,16);
			}
			else if(!strncasecmp(cuebuf+i,"COMPILATION",11)) {
				NSString *flag = readMetadataFromLineBuf(cuebuf,i+11,enc,YES);
				if([[flag lowercaseString] isEqualToString:@"true"] || [flag intValue] == 1) discCompilation = YES;
			}
		}
		else if(!strncasecmp(cuebuf+i,"TRACK",5)) break;
	}
	
	rewind(fp);
	fread(tmp,1,3,fp);
	if(memcmp(tmp,bom,3)) rewind(fp);
	
	while(fgets_private(cuebuf,512,fp) != NULL) {
		len = strlen(cuebuf);
		if(stat == 1) {
			i=0;
			while(*(cuebuf+i)==' ' || *(cuebuf+i)=='\t') i++;
			if(i>len-4) continue;
			if(!strncasecmp(cuebuf+i,"TRACK",5)) {
				stat = 2;
				if([tracks count]) gapIdx = -1;
				else gapIdx = 0; // index 00 of track1 is always 0:0:0
				XLDTrack *trk = [[XLDTrack alloc] init];
				[[trk metadata] setObject:[NSNumber numberWithInt: track++] forKey:XLD_METADATA_TRACK];
				if(titleStr) [[trk metadata] setObject:titleStr forKey:XLD_METADATA_ALBUM];
				if(genre) [[trk metadata] setObject:genre forKey:XLD_METADATA_GENRE];
				if(albumArtist) [[trk metadata] setObject:albumArtist forKey:XLD_METADATA_ALBUMARTIST];
				if(catalog) [[trk metadata] setObject:catalog forKey:XLD_METADATA_CATALOG];
				if(comment) [[trk metadata] setObject:comment forKey:XLD_METADATA_COMMENT];
				if(composer) [[trk metadata] setObject:composer forKey:XLD_METADATA_COMPOSER];
				if(date) {
					[[trk metadata] setObject:date forKey:XLD_METADATA_DATE];
					if([date length] > 3) {
						int year = [[date substringWithRange:NSMakeRange(0,4)] intValue];
						if(year >= 1000 && year < 3000) [[trk metadata] setObject:[NSNumber numberWithInt:year] forKey:XLD_METADATA_YEAR];
					}
				}
				if(totalDisc) [[trk metadata] setObject:[NSNumber numberWithInt:totalDisc] forKey:XLD_METADATA_TOTALDISCS];
				if(discNumber) [[trk metadata] setObject:[NSNumber numberWithInt:discNumber] forKey:XLD_METADATA_DISC];
				if(discCompilation) [[trk metadata] setObject:[NSNumber numberWithBool:YES] forKey:XLD_METADATA_COMPILATION];
				[tracks addObject:trk];
				[trk release];
			}
		}
		else if(stat == 2) {
			i=0;
			while(*(cuebuf+i)==' ' || *(cuebuf+i)=='\t') i++;
			//if(i>len-4) continue;
			if(!strncasecmp(cuebuf+i,"INDEX",5)) {
				i = i + 5;
				while(*(cuebuf+i)==' ' || *(cuebuf+i)=='\t') i++;
				if(!strncasecmp(cuebuf+i,"00",2)) {
					i = i + 2;
					while(*(cuebuf+i)==' ' || *(cuebuf+i)=='\t') i++;
					int min = atoi(cuebuf+i);
					while(*(cuebuf+i)!=':') i++;
					i++;
					int sec = atoi(cuebuf+i);
					while(*(cuebuf+i)!=':') i++;
					i++;
					int frame = atoi(cuebuf+i);
					gapIdx = timeToFrame(min,sec,frame,[decoder samplerate]);
				}
				else if(!strncasecmp(cuebuf+i,"01",2)) {
					XLDTrack *trk = [tracks objectAtIndex:[tracks count]-1];
					i = i + 2;
					while(*(cuebuf+i)==' ' || *(cuebuf+i)=='\t') i++;
					int min = atoi(cuebuf+i);
					while(*(cuebuf+i)!=':') i++;
					i++;
					int sec = atoi(cuebuf+i);
					while(*(cuebuf+i)!=':') i++;
					i++;
					int frame = atoi(cuebuf+i);
					xldoffset_t idx = timeToFrame(min,sec,frame,[decoder samplerate]);
					[trk setIndex:idx];
					if(gapIdx != -1) [trk setGap:idx-gapIdx];
					if([tracks count] > 1) {
						XLDTrack *trk2 = [tracks objectAtIndex:[tracks count]-2];
						if(gapIdx != -1) [trk2 setFrames:gapIdx-[trk2 index]];
						else [trk2 setFrames:idx-[trk2 index]];
					}
					stat = 1;
				}
			}
			else if(!strncasecmp(cuebuf+i,"TITLE",5)) {
				NSString *str = readMetadataFromLineBuf(cuebuf,i+5,enc,YES);
				if(str) {
					XLDTrack *trk = [tracks objectAtIndex:[tracks count]-1];
					[[trk metadata] setObject:str forKey:XLD_METADATA_TITLE];
				}
			}
			else if(!strncasecmp(cuebuf+i,"PERFORMER",9)) {
				hasPerformer = YES;
				NSString *str = readMetadataFromLineBuf(cuebuf,i+9,enc,YES);
				if(str) {
					XLDTrack *trk = [tracks objectAtIndex:[tracks count]-1];
					[[trk metadata] setObject:str forKey:XLD_METADATA_ARTIST];
				}
			}
			else if(!strncasecmp(cuebuf+i,"ISRC",4)) {
				NSString *str = readMetadataFromLineBuf(cuebuf,i+4,enc,YES);
				if(str) {
					XLDTrack *trk = [tracks objectAtIndex:[tracks count]-1];
					[[trk metadata] setObject:str forKey:XLD_METADATA_ISRC];
				}
			}
			else if(!strncasecmp(cuebuf+i,"SONGWRITER",10)) {
				NSString *str = readMetadataFromLineBuf(cuebuf,i+10,enc,YES);
				if(str) {
					XLDTrack *trk = [tracks objectAtIndex:[tracks count]-1];
					[[trk metadata] setObject:str forKey:XLD_METADATA_COMPOSER];
				}
			}
			else if(!strncasecmp(cuebuf+i,"REM",3)) {
				i = i + 3;
				while(*(cuebuf+i)==' ' || *(cuebuf+i)=='\t') i++;
				if(!strncasecmp(cuebuf+i,"DATE",4)) {
					NSString *str = readMetadataFromLineBuf(cuebuf,i+4,enc,YES);
					if(str) {
						XLDTrack *trk = [tracks objectAtIndex:[tracks count]-1];
						[[trk metadata] setObject:str forKey:XLD_METADATA_DATE];
						if([str length] > 3) {
							int year = [[str substringWithRange:NSMakeRange(0,4)] intValue];
							if(year >= 1000 && year < 3000) [[trk metadata] setObject:[NSNumber numberWithInt:year] forKey:XLD_METADATA_YEAR];
						}
					}
				}
				else if(!strncasecmp(cuebuf+i,"GENRE",5)) {
					NSString *str = readMetadataFromLineBuf(cuebuf,i+5,enc,YES);
					if(str) {
						XLDTrack *trk = [tracks objectAtIndex:[tracks count]-1];
						[[trk metadata] setObject:str forKey:XLD_METADATA_GENRE];
					}
				}
				else if(!strncasecmp(cuebuf+i,"COMMENT",7)) {
					NSString *str = readMetadataFromLineBuf(cuebuf,i+7,enc,YES);
					if(str) {
						XLDTrack *trk = [tracks objectAtIndex:[tracks count]-1];
						[[trk metadata] setObject:str forKey:XLD_METADATA_COMMENT];
					}
				}
			}
			else if(!strncasecmp(cuebuf+i,"FLAGS",5)) {
				NSString *str = readMetadataFromLineBuf(cuebuf,i+5,enc,YES);
				if(str && [[str lowercaseString] isEqualToString:@"pre"]) {
					XLDTrack *trk = [tracks objectAtIndex:[tracks count]-1];
					[[trk metadata] setObject:[NSNumber numberWithBool:YES] forKey:XLD_METADATA_PREEMPHASIS];
				}
				else if(str && [[str lowercaseString] isEqualToString:@"dcp"]) {
					XLDTrack *trk = [tracks objectAtIndex:[tracks count]-1];
					[[trk metadata] setObject:[NSNumber numberWithBool:YES] forKey:XLD_METADATA_DCP];
				}
			}
		}
	}
	fclose(fp);
	
	if(!discid) discid = getDiscId(tracks, [decoder totalFrames]);
	NSString *gracenoteDiscID = [XLDTrackListUtil gracenoteDiscIDForTracks:tracks totalFrames:[decoder totalFrames] freeDBDiscID:discid];
	
	NSData *coverData = [[decoder metadata] objectForKey:XLD_METADATA_COVER];
	for(i=0;i<[tracks count];i++) {
		[[[tracks objectAtIndex:i] metadata] setObject:[NSNumber numberWithInt:[tracks count]] forKey:XLD_METADATA_TOTALTRACKS];
		[[[tracks objectAtIndex:i] metadata] setObject:[NSNumber numberWithUnsignedInt:discid] forKey:XLD_METADATA_FREEDBDISCID];
		[[[tracks objectAtIndex:i] metadata] setObject:gracenoteDiscID forKey:XLD_METADATA_GRACENOTE2];
		if(coverData) [[[tracks objectAtIndex:i] metadata] setObject:coverData forKey:XLD_METADATA_COVER];
		if(i==[tracks count]-1) [[tracks objectAtIndex:i] setSeconds:([decoder totalFrames]-[(XLDTrack *)[tracks objectAtIndex:i] index])/[decoder samplerate]];
		else [[tracks objectAtIndex:i] setSeconds:[[tracks objectAtIndex:i] frames]/[decoder samplerate]];
		if(!hasPerformer && albumArtist) {
			[[[tracks objectAtIndex:i] metadata] setObject:albumArtist forKey:XLD_METADATA_ARTIST];
			[[[tracks objectAtIndex:i] metadata] removeObjectForKey:XLD_METADATA_ALBUMARTIST];
		}
	}
	
	if((!delegate || [delegate canSetCompilationFlag]) && [self isCompilationForTracks:tracks]) {
		for(i=0;i<[tracks count];i++) [[[tracks objectAtIndex:i] metadata] setObject:[NSNumber numberWithBool:YES] forKey:XLD_METADATA_COMPILATION];
	}
	
	return titleStr;
}

- (NSString *)setTrackData:(NSMutableArray *)tracks andLayout:(XLDDiscLayout *)layout forNonCompliantCueFile:(NSString *)file error:(XLDErr *)error
{
	FILE *fp = fopen([file UTF8String],"rb");
	if(!fp) {
		*error = XLDReadErr;
		if(errorMsg) [errorMsg release];
		errorMsg = [[NSString stringWithFormat:LS(@"Cannot open the file \"%@\"."),[file lastPathComponent]] retain];
		return nil;
	}

	char cuebuf[512];
	int stat = 1,i,len,track=1;
	xldoffset_t gapIdx=0;
	NSString *titleStr = nil;
	NSString *date = nil;
	NSString *genre = nil;
	NSString *albumArtist = nil;
	NSString *catalog = nil;
	NSString *comment = nil;
	NSString *composer = nil;
	int totalDisc = 0;
	int discNumber = 0;
	unsigned int discid = 0;
	BOOL discCompilation = NO;
	NSData *coverData = nil;
	NSStringEncoding enc;
	BOOL hasPerformer = NO;
	unsigned char bom[] = {0xEF,0xBB,0xBF};
	unsigned char tmp[3];
	xldoffset_t absoluteFrameOffset = 0;
	id decoder = nil;
	int currentSamplerate = 0;
	int currentChannels = 0;
	int maxBps = 0;
	int isFloat = -1;
	
	if(preferredEncoding) enc = preferredEncoding;
	else if([delegate encoding] == 0xFFFFFFFF || preferredEncoding == 0xFFFFFFFF) {
		enc = detectEncoding(fp);
	}
	else {
		enc = [delegate encoding];
	}
	int read = 0;
	
	fread(tmp,1,3,fp);
	if(memcmp(tmp,bom,3)) rewind(fp);

	while(read < 100*1024 && (fgets_private(cuebuf,512,fp) != NULL)) {
		i=0;
		len = strlen(cuebuf);
		read += len;
		while(*(cuebuf+i)==' ' || *(cuebuf+i)=='\t') i++;
		if(i>len-3) continue;
		if(!strncasecmp(cuebuf+i,"TITLE",5)) {
			titleStr = readMetadataFromLineBuf(cuebuf,i+5,enc,YES);
		}
		else if(!strncasecmp(cuebuf+i,"PERFORMER",9)) {
			albumArtist = readMetadataFromLineBuf(cuebuf,i+9,enc,YES);
		}
		else if(!strncasecmp(cuebuf+i,"CATALOG",7)) {
			catalog = readMetadataFromLineBuf(cuebuf,i+7,enc,YES);
		}
		else if(!strncasecmp(cuebuf+i,"SONGWRITER",10)) {
			composer = readMetadataFromLineBuf(cuebuf,i+10,enc,YES);
		}
		else if(!strncasecmp(cuebuf+i,"DISCNUMBER",10)) {
			discNumber = [readMetadataFromLineBuf(cuebuf,i+10,enc,YES) intValue];
		}
		else if(!strncasecmp(cuebuf+i,"TOTALDISCS",10)) {
			totalDisc = [readMetadataFromLineBuf(cuebuf,i+10,enc,YES) intValue];
		}
		else if(!strncasecmp(cuebuf+i,"REM",3)) {
			i = i + 3;
			while(*(cuebuf+i)==' ' || *(cuebuf+i)=='\t') i++;
			if(!strncasecmp(cuebuf+i,"DATE",4)) {
				date = readMetadataFromLineBuf(cuebuf,i+4,enc,YES);
			}
			else if(!strncasecmp(cuebuf+i,"GENRE",5)) {
				genre = readMetadataFromLineBuf(cuebuf,i+5,enc,YES);
			}
			else if(!strncasecmp(cuebuf+i,"COMMENT",7)) {
				comment = readMetadataFromLineBuf(cuebuf,i+7,enc,YES);
			}
			else if(!strncasecmp(cuebuf+i,"DISCNUMBER",10)) {
				discNumber = [readMetadataFromLineBuf(cuebuf,i+10,enc,YES) intValue];
			}
			else if(!strncasecmp(cuebuf+i,"TOTALDISCS",10)) {
				totalDisc = [readMetadataFromLineBuf(cuebuf,i+10,enc,YES) intValue];
			}
			else if(!strncasecmp(cuebuf+i,"DISCID",6)) {
				const char *discidstr = [readMetadataFromLineBuf(cuebuf,i+6,enc,YES) UTF8String];
				if(discidstr) discid = strtoul(discidstr,NULL,16);
			}
			else if(!strncasecmp(cuebuf+i,"COMPILATION",11)) {
				NSString *flag = readMetadataFromLineBuf(cuebuf,i+11,enc,YES);
				if([[flag lowercaseString] isEqualToString:@"true"] || [flag intValue] == 1) discCompilation = YES;
			}
		}
		else if(!strncasecmp(cuebuf+i,"TRACK",5)) break;
	}
	
	rewind(fp);
	fread(tmp,1,3,fp);
	if(memcmp(tmp,bom,3)) rewind(fp);
	
	while(fgets_private(cuebuf,512,fp) != NULL) {
		len = strlen(cuebuf);
		i=0;
		while(*(cuebuf+i)==' ' || *(cuebuf+i)=='\t') i++;
		if(!strncasecmp(cuebuf+i,"FILE",4)) {
			NSString *str = readMetadataFromLineBuf(cuebuf,i+4,enc,YES);
			NSString *path;
			if(str) {
				NSMutableString *mstr = [NSMutableString stringWithString:str];
				[mstr replaceOccurrencesOfString:@"\\" withString:@"/" options:0 range:NSMakeRange(0, [mstr length])];
				[mstr replaceOccurrencesOfString:@"¥" withString:@"/" options:0 range:NSMakeRange(0, [mstr length])];
				path = [[file stringByDeletingLastPathComponent] stringByAppendingPathComponent: [mstr lastPathComponent]];
				do {
					NSFileManager *fm = [NSFileManager defaultManager];
					if([fm fileExistsAtPath:path]) break;
					else if(![[[path pathExtension] lowercaseString] isEqualToString:@"wav"]) {
						*error = XLDReadErr;
						if(errorMsg) [errorMsg release];
						errorMsg = [[NSString stringWithFormat:LS(@"Cannot find the associated file \"%@\"."),[path lastPathComponent]] retain];
						goto last;
					}
					path = [[path stringByDeletingPathExtension] stringByAppendingPathExtension:@"flac"];
					if([fm fileExistsAtPath:path]) break;
					path = [[path stringByDeletingPathExtension] stringByAppendingPathExtension:@"aiff"];
					if([fm fileExistsAtPath:path]) break;
					path = [[path stringByDeletingPathExtension] stringByAppendingPathExtension:@"ape"];
					if([fm fileExistsAtPath:path]) break;
					path = [[path stringByDeletingPathExtension] stringByAppendingPathExtension:@"wv"];
					if([fm fileExistsAtPath:path]) break;
					path = [[path stringByDeletingPathExtension] stringByAppendingPathExtension:@"tta"];
					if([fm fileExistsAtPath:path]) break;
					path = [[path stringByDeletingPathExtension] stringByAppendingPathExtension:@"m4a"];
					if([fm fileExistsAtPath:path]) break;
					
					*error = XLDReadErr;
					if(errorMsg) [errorMsg release];
					errorMsg = [[NSString stringWithFormat:LS(@"Cannot find the associated file \"%@\"."),[[path lastPathComponent] stringByDeletingPathExtension]] retain];
					goto last;
				} while(0);
			}
			else {
				*error = XLDUnknownFormatErr;
				goto last;
			}
			if(decoder) { /* 2nd track or later */
				absoluteFrameOffset += [decoder totalFrames];
				[layout addSection:[decoder srcPath] withLength:[decoder totalFrames]];
				[decoder closeFile];
				decoder = [[delegate decoderCenter] preferredDecoderForFile:path];
			}
			else { /* 1st track */
				decoder = [[delegate decoderCenter] preferredDecoderForFile:path];
			}
			if(!decoder) {
				*error = XLDReadErr;
				if(errorMsg) [errorMsg release];
				errorMsg = [[NSString stringWithFormat:LS(@"Cannot find proper decoder for the associated file \"%@\"."),[path lastPathComponent]] retain];
				goto last;
			}
			[(id <XLDDecoder>)decoder openFile:(char *)[path UTF8String]];
			//NSLog(@"%d,%d,%d,%d",[decoder samplerate],[decoder channels],[decoder isFloat],[decoder bytesPerSample]);
			if(!currentSamplerate) currentSamplerate = [decoder samplerate];
			else if(currentSamplerate != [decoder samplerate]) {
				*error = XLDReadErr;
				if(errorMsg) [errorMsg release];
				errorMsg = [[NSString stringWithFormat:LS(@"Samplerate of the associated file \"%@\" is different from others."),[path lastPathComponent]] retain];
				goto last;
			}
			if(!currentChannels) currentChannels = [decoder channels];
			else if(currentChannels != [decoder channels]) {
				*error = XLDReadErr;
				if(errorMsg) [errorMsg release];
				errorMsg = [[NSString stringWithFormat:LS(@"Number of channels of the associated file \"%@\" is different from others."),[path lastPathComponent]] retain];
				goto last;
			}
			if(isFloat == -1) isFloat = [decoder isFloat];
			else if(isFloat != [decoder isFloat]) {
				*error = XLDReadErr;
				if(errorMsg) [errorMsg release];
				errorMsg = [[NSString stringWithFormat:LS(@"PCM format of the associated file \"%@\" is different from others."),[path lastPathComponent]] retain];
				goto last;
			}
			if(maxBps < [decoder bytesPerSample]) maxBps = [decoder bytesPerSample];
			if(!coverData) coverData = [[decoder metadata] objectForKey:XLD_METADATA_COVER];
			continue;
		}
		if(stat == 1) {
			if(i>len-4) continue;
			if(!strncasecmp(cuebuf+i,"TRACK",5)) {
				stat = 2;
				if([tracks count]) gapIdx = -1;
				else gapIdx = 0; // index 00 of track1 is always 0:0:0
				XLDTrack *trk = [[XLDTrack alloc] init];
				[[trk metadata] setObject:[NSNumber numberWithInt: track++] forKey:XLD_METADATA_TRACK];
				if(titleStr) [[trk metadata] setObject:titleStr forKey:XLD_METADATA_ALBUM];
				if(genre) [[trk metadata] setObject:genre forKey:XLD_METADATA_GENRE];
				if(albumArtist) [[trk metadata] setObject:albumArtist forKey:XLD_METADATA_ALBUMARTIST];
				if(catalog) [[trk metadata] setObject:catalog forKey:XLD_METADATA_CATALOG];
				if(comment) [[trk metadata] setObject:comment forKey:XLD_METADATA_COMMENT];
				if(composer) [[trk metadata] setObject:composer forKey:XLD_METADATA_COMPOSER];
				if(date) {
					[[trk metadata] setObject:date forKey:XLD_METADATA_DATE];
					if([date length] > 3) {
						int year = [[date substringWithRange:NSMakeRange(0,4)] intValue];
						if(year >= 1000 && year < 3000) [[trk metadata] setObject:[NSNumber numberWithInt:year] forKey:XLD_METADATA_YEAR];
					}
				}
				if(totalDisc) [[trk metadata] setObject:[NSNumber numberWithInt:totalDisc] forKey:XLD_METADATA_TOTALDISCS];
				if(discNumber) [[trk metadata] setObject:[NSNumber numberWithInt:discNumber] forKey:XLD_METADATA_DISC];
				if(discCompilation) [[trk metadata] setObject:[NSNumber numberWithBool:YES] forKey:XLD_METADATA_COMPILATION];
				[tracks addObject:trk];
				[trk release];
			}
		}
		else if(stat == 2) {
			//if(i>len-4) continue;
			if(!strncasecmp(cuebuf+i,"INDEX",5)) {
				i = i + 5;
				while(*(cuebuf+i)==' ' || *(cuebuf+i)=='\t') i++;
				if(!strncasecmp(cuebuf+i,"00",2)) {
					i = i + 2;
					while(*(cuebuf+i)==' ' || *(cuebuf+i)=='\t') i++;
					int min = atoi(cuebuf+i);
					while(*(cuebuf+i)!=':') i++;
					i++;
					int sec = atoi(cuebuf+i);
					while(*(cuebuf+i)!=':') i++;
					i++;
					int frame = atoi(cuebuf+i);
					gapIdx = absoluteFrameOffset + timeToFrame(min,sec,frame,[decoder samplerate]);
				}
				else if(!strncasecmp(cuebuf+i,"01",2)) {
					XLDTrack *trk = [tracks objectAtIndex:[tracks count]-1];
					i = i + 2;
					while(*(cuebuf+i)==' ' || *(cuebuf+i)=='\t') i++;
					int min = atoi(cuebuf+i);
					while(*(cuebuf+i)!=':') i++;
					i++;
					int sec = atoi(cuebuf+i);
					while(*(cuebuf+i)!=':') i++;
					i++;
					int frame = atoi(cuebuf+i);
					xldoffset_t idx = absoluteFrameOffset + timeToFrame(min,sec,frame,[decoder samplerate]);
					[trk setIndex:idx];
					if(gapIdx != -1) [trk setGap:idx-gapIdx];
					if([tracks count] > 1) {
						XLDTrack *trk2 = [tracks objectAtIndex:[tracks count]-2];
						if(gapIdx != -1) [trk2 setFrames:gapIdx-[trk2 index]];
						else [trk2 setFrames:idx-[trk2 index]];
					}
					NSArray *keyArr = [[decoder metadata] allKeys];
					int j;
					for(j=[keyArr count]-1;j>=0;j--) {
						id key = [keyArr objectAtIndex:j];
						if([[trk metadata] objectForKey:key]) continue;
						[[trk metadata] setObject:[[decoder metadata] objectForKey:key] forKey:key];
					}
					//[[trk metadata] addEntriesFromDictionary:[decoder metadata]];
					stat = 1;
				}
			}
			else if(!strncasecmp(cuebuf+i,"PREGAP",6)) {
				i = i + 6;
				while(*(cuebuf+i)==' ' || *(cuebuf+i)=='\t') i++;
				int min = atoi(cuebuf+i);
				while(*(cuebuf+i)!=':') i++;
				i++;
				int sec = atoi(cuebuf+i);
				while(*(cuebuf+i)!=':') i++;
				i++;
				int frame = atoi(cuebuf+i);

				gapIdx = absoluteFrameOffset;
				xldoffset_t gapLength = timeToFrame(min,sec,frame,[decoder samplerate]);
				absoluteFrameOffset += gapLength;
				[layout addSection:nil withLength:gapLength];
			}
			else if(!strncasecmp(cuebuf+i,"TITLE",5)) {
				NSString *str = readMetadataFromLineBuf(cuebuf,i+5,enc,YES);
				if(str) {
					XLDTrack *trk = [tracks objectAtIndex:[tracks count]-1];
					[[trk metadata] setObject:str forKey:XLD_METADATA_TITLE];
				}
			}
			else if(!strncasecmp(cuebuf+i,"PERFORMER",9)) {
				hasPerformer = YES;
				NSString *str = readMetadataFromLineBuf(cuebuf,i+9,enc,YES);
				if(str) {
					XLDTrack *trk = [tracks objectAtIndex:[tracks count]-1];
					[[trk metadata] setObject:str forKey:XLD_METADATA_ARTIST];
				}
			}
			else if(!strncasecmp(cuebuf+i,"ISRC",4)) {
				NSString *str = readMetadataFromLineBuf(cuebuf,i+4,enc,YES);
				if(str) {
					XLDTrack *trk = [tracks objectAtIndex:[tracks count]-1];
					[[trk metadata] setObject:str forKey:XLD_METADATA_ISRC];
				}
			}
			else if(!strncasecmp(cuebuf+i,"SONGWRITER",10)) {
				NSString *str = readMetadataFromLineBuf(cuebuf,i+10,enc,YES);
				if(str) {
					XLDTrack *trk = [tracks objectAtIndex:[tracks count]-1];
					[[trk metadata] setObject:str forKey:XLD_METADATA_COMPOSER];
				}
			}
			else if(!strncasecmp(cuebuf+i,"REM",3)) {
				i = i + 3;
				while(*(cuebuf+i)==' ' || *(cuebuf+i)=='\t') i++;
				if(!strncasecmp(cuebuf+i,"DATE",4)) {
					NSString *str = readMetadataFromLineBuf(cuebuf,i+4,enc,YES);
					if(str) {
						XLDTrack *trk = [tracks objectAtIndex:[tracks count]-1];
						[[trk metadata] setObject:str forKey:XLD_METADATA_DATE];
						if([str length] > 3) {
							int year = [[str substringWithRange:NSMakeRange(0,4)] intValue];
							if(year >= 1000 && year < 3000) [[trk metadata] setObject:[NSNumber numberWithInt:year] forKey:XLD_METADATA_YEAR];
						}
					}
				}
				else if(!strncasecmp(cuebuf+i,"GENRE",5)) {
					NSString *str = readMetadataFromLineBuf(cuebuf,i+5,enc,YES);
					if(str) {
						XLDTrack *trk = [tracks objectAtIndex:[tracks count]-1];
						[[trk metadata] setObject:str forKey:XLD_METADATA_GENRE];
					}
				}
				else if(!strncasecmp(cuebuf+i,"COMMENT",7)) {
					NSString *str = readMetadataFromLineBuf(cuebuf,i+7,enc,YES);
					if(str) {
						XLDTrack *trk = [tracks objectAtIndex:[tracks count]-1];
						[[trk metadata] setObject:str forKey:XLD_METADATA_COMMENT];
					}
				}
			}
			else if(!strncasecmp(cuebuf+i,"FLAGS",5)) {
				NSString *str = readMetadataFromLineBuf(cuebuf,i+5,enc,YES);
				if(str && [[str lowercaseString] isEqualToString:@"pre"]) {
					XLDTrack *trk = [tracks objectAtIndex:[tracks count]-1];
					[[trk metadata] setObject:[NSNumber numberWithBool:YES] forKey:XLD_METADATA_PREEMPHASIS];
				}
				else if(str && [[str lowercaseString] isEqualToString:@"dcp"]) {
					XLDTrack *trk = [tracks objectAtIndex:[tracks count]-1];
					[[trk metadata] setObject:[NSNumber numberWithBool:YES] forKey:XLD_METADATA_DCP];
				}
			}
		}
	}
	if(!decoder) {
		*error = XLDReadErr;
		if(errorMsg) [errorMsg release];
		errorMsg = [[NSString stringWithString:LS(@"No audio tracks found in the cue sheet.")] retain];
		goto last;
	}

	absoluteFrameOffset += [decoder totalFrames];
	//totlaFrames = absoluteFrameOffset;
	//samplerate = currentSamplerate;
	[layout addSection:[decoder srcPath] withLength:[decoder totalFrames]];
	[layout setSamplerate:currentSamplerate];
	[layout setChannels:currentChannels];
	[layout setBytesPerSample:maxBps];
	[layout setIsFloat:isFloat];
	[decoder closeFile];

	if(!titleStr) titleStr = [XLDTrackListUtil albumTitleForTracks:tracks];
	if(!discid) discid = getDiscId(tracks, absoluteFrameOffset);
	NSString *gracenoteDiscID = [XLDTrackListUtil gracenoteDiscIDForTracks:tracks totalFrames:[decoder totalFrames] freeDBDiscID:discid];
	for(i=0;i<[tracks count];i++) {
		[[[tracks objectAtIndex:i] metadata] setObject:[NSNumber numberWithInt:[tracks count]] forKey:XLD_METADATA_TOTALTRACKS];
		[[[tracks objectAtIndex:i] metadata] setObject:[NSNumber numberWithUnsignedInt:discid] forKey:XLD_METADATA_FREEDBDISCID];
		[[[tracks objectAtIndex:i] metadata] setObject:gracenoteDiscID forKey:XLD_METADATA_GRACENOTE2];
		if(coverData) [[[tracks objectAtIndex:i] metadata] setObject:coverData forKey:XLD_METADATA_COVER];
		if(i==[tracks count]-1) [[tracks objectAtIndex:i] setSeconds:(absoluteFrameOffset-[(XLDTrack *)[tracks objectAtIndex:i] index])/currentSamplerate];
		else [[tracks objectAtIndex:i] setSeconds:[[tracks objectAtIndex:i] frames]/currentSamplerate];
		if(!hasPerformer && albumArtist) {
			[[[tracks objectAtIndex:i] metadata] setObject:albumArtist forKey:XLD_METADATA_ARTIST];
			[[[tracks objectAtIndex:i] metadata] removeObjectForKey:XLD_METADATA_ALBUMARTIST];
		}
	}
	
	if((!delegate || [delegate canSetCompilationFlag]) && [self isCompilationForTracks:tracks]) {
		for(i=0;i<[tracks count];i++) {
			if(![[[tracks objectAtIndex:i] metadata] objectForKey:XLD_METADATA_COMPILATION])
				[[[tracks objectAtIndex:i] metadata] setObject:[NSNumber numberWithBool:YES] forKey:XLD_METADATA_COMPILATION];
		}
	}

	*error = XLDNoErr;

last:
	if(fp) fclose(fp);
	return titleStr;
}

- (id)decoderForCueSheet:(NSString *)file isRaw:(BOOL)raw promptIfNotFound:(BOOL)prompt error:(XLDErr *)error
{
	FILE *fp = fopen([file UTF8String],"rb");
	if(!fp) {
		*error = XLDReadErr;
		if(errorMsg) [errorMsg release];
		errorMsg = [[NSString stringWithFormat:LS(@"Cannot open the file \"%@\"."),[file lastPathComponent]] retain];
		return nil;
	}
	
	int i,len;
	char cuebuf[512];
	NSStringEncoding enc;
	unsigned char bom[] = {0xEF,0xBB,0xBF};
	unsigned char tmp[3];
	NSString *path = nil;
	id decoder;
	
	if(preferredEncoding) enc = preferredEncoding;
	else if(!delegate || [delegate encoding] == 0xFFFFFFFF || preferredEncoding == 0xFFFFFFFF) {
		enc = detectEncoding(fp);
	}
	else {
		enc = [delegate encoding];
	}
	int read = 0;
	
	fread(tmp,1,3,fp);
	if(memcmp(tmp,bom,3)) rewind(fp);
	
	while(read < 100*1024 && (fgets_private(cuebuf,512,fp) != NULL)) {
		i=0;
		len = strlen(cuebuf);
		read += len;
		while(*(cuebuf+i)==' ' || *(cuebuf+i)=='\t') i++;
		if(i>len-3) continue;
		if(!strncasecmp(cuebuf+i,"FILE",4)) {
			NSString *str = readMetadataFromLineBuf(cuebuf,i+4,enc,YES);
			if(str) {
				NSMutableString *mstr = [NSMutableString stringWithString:str];
				[mstr replaceOccurrencesOfString:@"\\" withString:@"/" options:0 range:NSMakeRange(0, [mstr length])];
				path = [[file stringByDeletingLastPathComponent] stringByAppendingPathComponent: [mstr lastPathComponent]];
			}
			break;
		}
	}
	
	if(!path) {
		fclose(fp);
		*error = XLDUnknownFormatErr;
		return nil;
	}
	
	if(![[NSFileManager defaultManager] fileExistsAtPath:path]) {
		if(!prompt) {
			fclose(fp);
			*error = XLDCancelErr;
			return nil;
		}
		NSOpenPanel *op = [NSOpenPanel openPanel];
		[op setCanChooseDirectories:NO];
		[op setCanChooseFiles:YES];
		[op setAllowsMultipleSelection:NO];
		[op setTitle:LS(@"choose file to split")];
		
		int ret = [op runModalForDirectory:[file stringByDeletingLastPathComponent] file:nil types:nil];
		if(ret != NSOKButton) {
			fclose(fp);
			*error = XLDCancelErr;
			return nil;
		}
		path = [op filename];
	}
	if(!raw) {
		decoder = [[delegate decoderCenter] preferredDecoderForFile:path];
		if(![(id <XLDDecoder>)decoder openFile:(char *)[path UTF8String]]) {
			[decoder closeFile];
			fclose(fp);
			*error = XLDReadErr;
			if(errorMsg) [errorMsg release];
			errorMsg = [[NSString stringWithFormat:LS(@"Cannot open the associated file \"%@\"."),[path lastPathComponent]] retain];
			return nil;
		}
	}
	else {
		decoder = [[XLDRawDecoder alloc] initWithFormat:format endian:endian];
		if(![(XLDRawDecoder *)decoder openFile:(char *)[path UTF8String]]) {
			[decoder closeFile];
			[decoder release];
			fclose(fp);
			*error = XLDReadErr;
			if(errorMsg) [errorMsg release];
			errorMsg = [[NSString stringWithFormat:LS(@"Cannot open the associated file \"%@\"."),[path lastPathComponent]] retain];
			return nil;
		}
		[decoder autorelease];
	}
	fclose(fp);
	*error = XLDNoErr;
	return decoder;
}

- (NSString *)setTrackData:(NSMutableArray *)tracks forCueData:(NSString *)cueData withDecoder:(id)decoder
{
	char cuebuf[512];
	int stat = 1,i,len,gapIdx=0,track=1;
	NSString *titleStr = nil;
	NSString *date = nil;
	NSString *genre = nil;
	NSString *albumArtist = nil;
	NSString *catalog = nil;
	NSString *comment = nil;
	NSString *composer = nil;
	int totalDisc = 0;
	int discNumber = 0;
	unsigned int discid = 0;
	BOOL discCompilation = NO;
	NSRange range, subrange;
	BOOL hasPerformer = NO;
	cuebuf[511] = 0;
	
	if([[decoder metadata] objectForKey:XLD_METADATA_TOTALDISCS]) totalDisc = [[[decoder metadata] objectForKey:XLD_METADATA_TOTALDISCS] intValue];
	if([[decoder metadata] objectForKey:XLD_METADATA_DISC]) discNumber = [[[decoder metadata] objectForKey:XLD_METADATA_DISC] intValue];
	
	range = NSMakeRange(0, [cueData length]);
	while(range.length > 0) {
		subrange = [cueData lineRangeForRange:NSMakeRange(range.location, 0)];
		int lengthToCopy = strlen([[cueData substringWithRange:subrange] UTF8String])+1;
		lengthToCopy = (lengthToCopy > 511) ? 511 : lengthToCopy;
        memcpy(cuebuf,[[cueData substringWithRange:subrange] UTF8String],lengthToCopy);
		range.location = NSMaxRange(subrange);
        range.length -= subrange.length;
		
		i=0;
		len = strlen(cuebuf);
		while(*(cuebuf+i)==' ' || *(cuebuf+i)=='\t') i++;
		if(i>len-3) continue;
		if(!strncasecmp(cuebuf+i,"TITLE",5)) {
			titleStr = readMetadataFromLineBuf(cuebuf,i+5,NSUTF8StringEncoding,NO);
		}
		else if(!strncasecmp(cuebuf+i,"PERFORMER",9)) {
			albumArtist = readMetadataFromLineBuf(cuebuf,i+9,NSUTF8StringEncoding,NO);
		}
		else if(!strncasecmp(cuebuf+i,"CATALOG",7)) {
			catalog = readMetadataFromLineBuf(cuebuf,i+7,NSUTF8StringEncoding,NO);
		}
		else if(!strncasecmp(cuebuf+i,"SONGWRITER",10)) {
			composer = readMetadataFromLineBuf(cuebuf,i+10,NSUTF8StringEncoding,NO);
		}
		else if(!strncasecmp(cuebuf+i,"DISCNUMBER",10)) {
			discNumber = [readMetadataFromLineBuf(cuebuf,i+10,NSUTF8StringEncoding,NO) intValue];
		}
		else if(!strncasecmp(cuebuf+i,"TOTALDISCS",10)) {
			totalDisc = [readMetadataFromLineBuf(cuebuf,i+10,NSUTF8StringEncoding,NO) intValue];
		}
		else if(!strncasecmp(cuebuf+i,"REM",3)) {
			i = i + 3;
			while(*(cuebuf+i)==' ' || *(cuebuf+i)=='\t') i++;
			if(!strncasecmp(cuebuf+i,"DATE",4)) {
				date = readMetadataFromLineBuf(cuebuf,i+4,NSUTF8StringEncoding,NO);
			}
			else if(!strncasecmp(cuebuf+i,"GENRE",5)) {
				genre = readMetadataFromLineBuf(cuebuf,i+5,NSUTF8StringEncoding,NO);
			}
			else if(!strncasecmp(cuebuf+i,"COMMENT",7)) {
				comment = readMetadataFromLineBuf(cuebuf,i+7,NSUTF8StringEncoding,NO);
			}
			else if(!strncasecmp(cuebuf+i,"DISCNUMBER",10)) {
				discNumber = [readMetadataFromLineBuf(cuebuf,i+10,NSUTF8StringEncoding,NO) intValue];
			}
			else if(!strncasecmp(cuebuf+i,"TOTALDISCS",10)) {
				totalDisc = [readMetadataFromLineBuf(cuebuf,i+10,NSUTF8StringEncoding,NO) intValue];
			}
			else if(!strncasecmp(cuebuf+i,"DISCID",6)) {
				const char *discidstr = [readMetadataFromLineBuf(cuebuf,i+6,NSUTF8StringEncoding,NO) UTF8String];
				if(discidstr) discid = strtoul(discidstr,NULL,16);
			}
			else if(!strncasecmp(cuebuf+i,"COMPILATION",11)) {
				NSString *flag = readMetadataFromLineBuf(cuebuf,i+11,NSUTF8StringEncoding,NO);
				if([[flag lowercaseString] isEqualToString:@"true"] || [flag intValue] == 1) discCompilation = YES;
			}
		}
		else if(!strncasecmp(cuebuf+i,"TRACK",5)) break;
	}
	
	range = NSMakeRange(0, [cueData length]);
	while(range.length > 0) {
		subrange = [cueData lineRangeForRange:NSMakeRange(range.location, 0)];
		int lengthToCopy = strlen([[cueData substringWithRange:subrange] UTF8String])+1;
		lengthToCopy = (lengthToCopy > 511) ? 511 : lengthToCopy;
        memcpy(cuebuf,[[cueData substringWithRange:subrange] UTF8String],lengthToCopy);
		range.location = NSMaxRange(subrange);
        range.length -= subrange.length;
		
		len = strlen(cuebuf);
		if(stat == 1) {
			i=0;
			while(*(cuebuf+i)==' ' || *(cuebuf+i)=='\t') i++;
			if(i>len-4) continue;
			if(!strncasecmp(cuebuf+i,"TRACK",5)) {
				stat = 2;
				if([tracks count]) gapIdx = -1;
				else gapIdx = 0; // index 00 of track1 is always 0:0:0
				XLDTrack *trk = [[XLDTrack alloc] init];
				[[trk metadata] setObject:[NSNumber numberWithInt: track++] forKey:XLD_METADATA_TRACK];
				if(titleStr) [[trk metadata] setObject:titleStr forKey:XLD_METADATA_ALBUM];
				if(genre) [[trk metadata] setObject:genre forKey:XLD_METADATA_GENRE];
				if(albumArtist) [[trk metadata] setObject:albumArtist forKey:XLD_METADATA_ALBUMARTIST];
				if(catalog) [[trk metadata] setObject:catalog forKey:XLD_METADATA_CATALOG];
				if(comment) [[trk metadata] setObject:comment forKey:XLD_METADATA_COMMENT];
				if(composer) [[trk metadata] setObject:composer forKey:XLD_METADATA_COMPOSER];
				if(date) {
					[[trk metadata] setObject:date forKey:XLD_METADATA_DATE];
					if([date length] > 3) {
						int year = [[date substringWithRange:NSMakeRange(0,4)] intValue];
						if(year >= 1000 && year < 3000) [[trk metadata] setObject:[NSNumber numberWithInt:year] forKey:XLD_METADATA_YEAR];
					}
				}
				if(totalDisc) [[trk metadata] setObject:[NSNumber numberWithInt:totalDisc] forKey:XLD_METADATA_TOTALDISCS];
				if(discNumber) [[trk metadata] setObject:[NSNumber numberWithInt:discNumber] forKey:XLD_METADATA_DISC];
				if(discCompilation) [[trk metadata] setObject:[NSNumber numberWithBool:YES] forKey:XLD_METADATA_COMPILATION];
				[tracks addObject:trk];
				[trk release];
			}
		}
		else if(stat == 2) {
			i=0;
			while(*(cuebuf+i)==' ' || *(cuebuf+i)=='\t') i++;
			//if(i>len-4) continue;
			if(!strncasecmp(cuebuf+i,"INDEX",5)) {
				i = i + 5;
				while(*(cuebuf+i)==' ' || *(cuebuf+i)=='\t') i++;
				if(!strncasecmp(cuebuf+i,"00",2)) {
					i = i + 2;
					while(*(cuebuf+i)==' ' || *(cuebuf+i)=='\t') i++;
					int min = atoi(cuebuf+i);
					while(*(cuebuf+i)!=':') i++;
					i++;
					int sec = atoi(cuebuf+i);
					while(*(cuebuf+i)!=':') i++;
					i++;
					int frame = atoi(cuebuf+i);
					gapIdx = timeToFrame(min,sec,frame,[decoder samplerate]);
				}
				else if(!strncasecmp(cuebuf+i,"01",2)) {
					XLDTrack *trk = [tracks objectAtIndex:[tracks count]-1];
					i = i + 2;
					while(*(cuebuf+i)==' ' || *(cuebuf+i)=='\t') i++;
					int min = atoi(cuebuf+i);
					while(*(cuebuf+i)!=':') i++;
					i++;
					int sec = atoi(cuebuf+i);
					while(*(cuebuf+i)!=':') i++;
					i++;
					int frame = atoi(cuebuf+i);
					xldoffset_t idx = timeToFrame(min,sec,frame,[decoder samplerate]);
					[trk setIndex:idx];
					if(gapIdx != -1) [trk setGap:idx-gapIdx];
					if([tracks count] > 1) {
						XLDTrack *trk2 = [tracks objectAtIndex:[tracks count]-2];
						if(gapIdx != -1) [trk2 setFrames:gapIdx-[trk2 index]];
						else [trk2 setFrames:idx-[trk2 index]];
					}
					stat = 1;
				}
			}
			else if(!strncasecmp(cuebuf+i,"TITLE",5)) {
				NSString *str = readMetadataFromLineBuf(cuebuf,i+5,NSUTF8StringEncoding,NO);
				if(str) {
					XLDTrack *trk = [tracks objectAtIndex:[tracks count]-1];
					[[trk metadata] setObject:str forKey:XLD_METADATA_TITLE];
				}
			}
			else if(!strncasecmp(cuebuf+i,"PERFORMER",9)) {
				hasPerformer = YES;
				NSString *str = readMetadataFromLineBuf(cuebuf,i+9,NSUTF8StringEncoding,NO);
				if(str) {
					XLDTrack *trk = [tracks objectAtIndex:[tracks count]-1];
					[[trk metadata] setObject:str forKey:XLD_METADATA_ARTIST];
				}
			}
			else if(!strncasecmp(cuebuf+i,"SONGWRITER",10)) {
				NSString *str = readMetadataFromLineBuf(cuebuf,i+10,NSUTF8StringEncoding,NO);
				if(str) {
					XLDTrack *trk = [tracks objectAtIndex:[tracks count]-1];
					[[trk metadata] setObject:str forKey:XLD_METADATA_COMPOSER];
				}
			}
			else if(!strncasecmp(cuebuf+i,"ISRC",4)) {
				NSString *str = readMetadataFromLineBuf(cuebuf,i+4,NSUTF8StringEncoding,NO);
				if(str) {
					XLDTrack *trk = [tracks objectAtIndex:[tracks count]-1];
					[[trk metadata] setObject:str forKey:XLD_METADATA_ISRC];
				}
			}
			else if(!strncasecmp(cuebuf+i,"REM",3)) {
				i = i + 3;
				while(*(cuebuf+i)==' ' || *(cuebuf+i)=='\t') i++;
				if(!strncasecmp(cuebuf+i,"DATE",4)) {
					NSString *str = readMetadataFromLineBuf(cuebuf,i+4,NSUTF8StringEncoding,NO);
					if(str) {
						XLDTrack *trk = [tracks objectAtIndex:[tracks count]-1];
						[[trk metadata] setObject:str forKey:XLD_METADATA_DATE];
						if([date length] > 3) {
							int year = [[str substringWithRange:NSMakeRange(0,4)] intValue];
							if(year >= 1000 && year < 3000) [[trk metadata] setObject:[NSNumber numberWithInt:year] forKey:XLD_METADATA_YEAR];
						}
					}
				}
				else if(!strncasecmp(cuebuf+i,"GENRE",5)) {
					NSString *str = readMetadataFromLineBuf(cuebuf,i+5,NSUTF8StringEncoding,NO);
					if(str) {
						XLDTrack *trk = [tracks objectAtIndex:[tracks count]-1];
						[[trk metadata] setObject:str forKey:XLD_METADATA_GENRE];
					}
				}
				else if(!strncasecmp(cuebuf+i,"COMMENT",7)) {
					NSString *str = readMetadataFromLineBuf(cuebuf,i+7,NSUTF8StringEncoding,NO);
					if(str) {
						XLDTrack *trk = [tracks objectAtIndex:[tracks count]-1];
						[[trk metadata] setObject:str forKey:XLD_METADATA_COMMENT];
					}
				}
			}
			else if(!strncasecmp(cuebuf+i,"FLAGS",5)) {
				NSString *str = readMetadataFromLineBuf(cuebuf,i+5,NSUTF8StringEncoding,NO);
				if(str && [[str lowercaseString] isEqualToString:@"pre"]) {
					XLDTrack *trk = [tracks objectAtIndex:[tracks count]-1];
					[[trk metadata] setObject:[NSNumber numberWithBool:YES] forKey:XLD_METADATA_PREEMPHASIS];
				}
				else if(str && [[str lowercaseString] isEqualToString:@"dcp"]) {
					XLDTrack *trk = [tracks objectAtIndex:[tracks count]-1];
					[[trk metadata] setObject:[NSNumber numberWithBool:YES] forKey:XLD_METADATA_DCP];
				}
			}
		}
	}
	
	if(!discid) discid = getDiscId(tracks, [decoder totalFrames]);
	NSString *gracenoteDiscID = [XLDTrackListUtil gracenoteDiscIDForTracks:tracks totalFrames:[decoder totalFrames] freeDBDiscID:discid];
	
	NSData *coverData = [[decoder metadata] objectForKey:XLD_METADATA_COVER];
	for(i=0;i<[tracks count];i++) {
		[[[tracks objectAtIndex:i] metadata] setObject:[NSNumber numberWithInt:[tracks count]] forKey:XLD_METADATA_TOTALTRACKS];
		[[[tracks objectAtIndex:i] metadata] setObject:[NSNumber numberWithUnsignedInt:discid] forKey:XLD_METADATA_FREEDBDISCID];
		[[[tracks objectAtIndex:i] metadata] setObject:gracenoteDiscID forKey:XLD_METADATA_GRACENOTE2];
		if(coverData) [[[tracks objectAtIndex:i] metadata] setObject:coverData forKey:XLD_METADATA_COVER];
		if(i==[tracks count]-1) [[tracks objectAtIndex:i] setSeconds:([decoder totalFrames]-[(XLDTrack *)[tracks objectAtIndex:i] index])/[decoder samplerate]];
		else [[tracks objectAtIndex:i] setSeconds:[[tracks objectAtIndex:i] frames]/[decoder samplerate]];
		if(!hasPerformer && albumArtist) {
			[[[tracks objectAtIndex:i] metadata] setObject:albumArtist forKey:XLD_METADATA_ARTIST];
			[[[tracks objectAtIndex:i] metadata] removeObjectForKey:XLD_METADATA_ALBUMARTIST];
		}
	}
	
	if([delegate canSetCompilationFlag] && [self isCompilationForTracks:tracks]) {
		for(i=0;i<[tracks count];i++) [[[tracks objectAtIndex:i] metadata] setObject:[NSNumber numberWithBool:YES] forKey:XLD_METADATA_COMPILATION];
	}
	
	return titleStr;
}

- (XLDErr)openNonCompliantCueFile:(NSString *)file
{
	int i;
	XLDErr error;
	NSMutableArray *arr = [NSMutableArray array];
	XLDDiscLayout *layout = [[XLDDiscLayout alloc] initWithDecoderCenter:[delegate decoderCenter]];

	NSString *titleStr = [self setTrackData:arr andLayout:layout forNonCompliantCueFile:file error:&error];
	if(error != XLDNoErr) {
		[layout release];
		return error;
	}

	[self clean];
	rawMode = NO;
	cueMode = XLDCueModeMulti;

	[trackList addObjectsFromArray:arr];
	samplerate = [layout samplerate];
	totalFrames = [layout totalFrames];
	discLayout = layout;
	writable = ((samplerate == 44100) && (![discLayout isFloat]));
	representedFilename = [file retain];

	cover = [[[trackList objectAtIndex:0] metadata] objectForKey:XLD_METADATA_COVER];
	if(cover) [cover retain];
	fileToDecode = [file retain];
	if(titleStr) {
		title = [titleStr retain];
	}
	else {
		title = [[[[file lastPathComponent] stringByDeletingPathExtension] precomposedStringWithCanonicalMapping] retain];
	}
	
	for(i=0;i<[trackList count];i++) {
		XLDButton *button = [[XLDButton alloc] init];
		[button setButtonType:NSSwitchButton];
		[button setState:NSOnState];
		[[button cell] setControlSize:NSSmallControlSize];
		[button setTitle:@""];
		[button setTarget:[delegate discView]];
		[button setAction:@selector(checkboxStatusChanged:)];
		[checkList addObject:button];
		[button release];
	}

	return XLDNoErr;
}

- (XLDErr)openFile:(NSString *)file
{
	int i;
	XLDErr error;
	NSString *titleStr = nil;
	i = numberOfFILELine(file);
	if(!i) return XLDUnknownFormatErr;
	else if(i>1) return [self openNonCompliantCueFile:file];

	id decoder = [self decoderForCueSheet:file isRaw:NO promptIfNotFound:YES error:&error];
	if(!decoder) {
		return error;
	}
	
	[self clean];
	rawMode = NO;
	
	titleStr = [self setTrackData:trackList forCueFile:file withDecoder:decoder];
	
	samplerate = [decoder samplerate];
	totalFrames = [decoder totalFrames];
	writable = ((samplerate == 44100) && (![decoder isFloat]));
	representedFilename = [file retain];
	
	cover = [[decoder metadata] objectForKey:XLD_METADATA_COVER];
	if(cover) [cover retain];
	fileToDecode = [[decoder srcPath] retain];
	if(titleStr) {
		title = [titleStr retain];
	}
	else {
		title = [[[[file lastPathComponent] stringByDeletingPathExtension] precomposedStringWithCanonicalMapping] retain];
	}
	
	discLayout = [[XLDDiscLayout alloc] initWithDecoderCenter:[delegate decoderCenter]];
	[discLayout setSamplerate:samplerate];
	[discLayout setChannels:[decoder channels]];
	[discLayout setBytesPerSample:[decoder bytesPerSample]];
	[discLayout setIsFloat:[decoder isFloat]];
	[discLayout addSection:fileToDecode withLength:totalFrames];
	
	[decoder closeFile];
	
	for(i=0;i<[trackList count];i++) {
		XLDButton *button = [[XLDButton alloc] init];
		[button setButtonType:NSSwitchButton];
		[button setState:NSOnState];
		[[button cell] setControlSize:NSSmallControlSize];
		[button setTitle:@""];
		[button setTarget:[delegate discView]];
		[button setAction:@selector(checkboxStatusChanged:)];
		[checkList addObject:button];
		[button release];
	}
	
	return XLDNoErr;
}

- (XLDErr)openFile:(NSString *)file withRawFormat:(XLDFormat)fmt endian:(XLDEndian)e
{
	int i;
	XLDErr error;
	NSString *titleStr = nil;
	XLDFormat origFmt = format;
	XLDEndian origEndian = endian;
	format = fmt;
	endian = e;
	id decoder = [self decoderForCueSheet:file isRaw:YES promptIfNotFound:YES error:&error];
	if(!decoder) {
		format = origFmt;
		endian = origEndian;
		return error;
	}
	
	[self clean];
	rawMode = YES;
	cueMode = XLDCueModeRaw;
	
	titleStr = [self setTrackData:trackList forCueFile:file withDecoder:decoder];
	
	samplerate = [decoder samplerate];
	totalFrames = [decoder totalFrames];
	rawOffset = 0;
	writable = ((samplerate == 44100) && (![decoder isFloat]));
	representedFilename = [file retain];
	
	cover = [[decoder metadata] objectForKey:XLD_METADATA_COVER];
	if(cover) [cover retain];
	fileToDecode = [[decoder srcPath] retain];
	if(titleStr) {
		title = [titleStr retain];
	}
	else {
		title = [[[[file lastPathComponent] stringByDeletingPathExtension] precomposedStringWithCanonicalMapping] retain];
	}
	
	discLayout = [[XLDDiscLayout alloc] initWithDecoderCenter:[delegate decoderCenter]];
	[discLayout setSamplerate:samplerate];
	[discLayout setChannels:[decoder channels]];
	[discLayout setBytesPerSample:[decoder bytesPerSample]];
	[discLayout setIsFloat:[decoder isFloat]];
	[discLayout addRawSection:fileToDecode withLength:totalFrames endian:e offset:0];
	
	[decoder closeFile];
	
	for(i=0;i<[trackList count];i++) {
		XLDButton *button = [[XLDButton alloc] init];
		[button setButtonType:NSSwitchButton];
		[button setState:NSOnState];
		[[button cell] setControlSize:NSSmallControlSize];
		[button setTitle:@""];
		[button setTarget:[delegate discView]];
		[button setAction:@selector(checkboxStatusChanged:)];
		[checkList addObject:button];
		[button release];
	}
	
	return XLDNoErr;
}

- (XLDErr)openFile:(NSString *)file withCueData:(NSString *)cueData decoder:(id)decoder
{
	int i;
	NSString *titleStr = nil;
	rawMode = NO;
	
	[self clean];
	
	titleStr = [self setTrackData:trackList forCueData:cueData withDecoder:decoder];
	
	samplerate = [decoder samplerate];
	totalFrames = [decoder totalFrames];
	writable = ((samplerate == 44100) && (![decoder isFloat]));
	representedFilename = [file retain];
	
	cover = [[decoder metadata] objectForKey:XLD_METADATA_COVER];
	if(cover) [cover retain];
	fileToDecode = [file retain];
	if(titleStr) {
		title = [titleStr retain];
	}
	else {
		title = [[[[file lastPathComponent] stringByDeletingPathExtension] precomposedStringWithCanonicalMapping] retain];
	}
	
	discLayout = [[XLDDiscLayout alloc] initWithDecoderCenter:[delegate decoderCenter]];
	[discLayout setSamplerate:samplerate];
	[discLayout setChannels:[decoder channels]];
	[discLayout setBytesPerSample:[decoder bytesPerSample]];
	[discLayout setIsFloat:[decoder isFloat]];
	if([decoder isMemberOfClass:[XLDRawDecoder class]])
		[discLayout addRawSection:fileToDecode withLength:totalFrames endian:[decoder endian] offset:[decoder offset]];
	else [discLayout addSection:fileToDecode withLength:totalFrames];
	
	for(i=0;i<[trackList count];i++) {
		XLDButton *button = [[XLDButton alloc] init];
		[button setButtonType:NSSwitchButton];
		[button setState:NSOnState];
		[[button cell] setControlSize:NSSmallControlSize];
		[button setTitle:@""];
		[button setTarget:[delegate discView]];
		[button setAction:@selector(checkboxStatusChanged:)];
		[checkList addObject:button];
		[button release];
	}
	
	return XLDNoErr;
}

- (void)openRawFile:(NSString *)file withTrackData:(NSMutableArray *)arr decoder:(id)decoder
{
	[self openFile:file withTrackData:arr decoder:decoder];
	rawMode = YES;
	cueMode = XLDCueModeRaw;
	format.bps = [decoder bytesPerSample];
	format.channels = [decoder channels];
	format.isFloat = [decoder isFloat];
	format.samplerate = [decoder samplerate];
	endian = [(XLDRawDecoder *)decoder endian];;
	rawOffset = [(XLDRawDecoder *)decoder offset];
}

- (void)openFile:(NSString *)file withTrackData:(NSMutableArray *)arr decoder:(id)decoder
{
	int totalDisc = 0;
	int discNumber = 0;
	unsigned int discid = getDiscId(arr, [decoder totalFrames]);
	NSString *gracenoteDiscID = [XLDTrackListUtil gracenoteDiscIDForTracks:arr totalFrames:[decoder totalFrames] freeDBDiscID:discid];
	[self clean];
	rawMode = NO;
	cover = [[decoder metadata] objectForKey:XLD_METADATA_COVER];
	if(cover) [cover retain];
	samplerate = [decoder samplerate];
	totalFrames = [decoder totalFrames];
	writable = ((samplerate == 44100) && (![decoder isFloat]) && ![file hasPrefix:@"/dev/disk"]);
	representedFilename = [file hasPrefix:@"/dev/disk"] ? [[[NSString stringWithString:@"/Volumes"] stringByAppendingPathComponent:mountNameFromBSDName([file UTF8String])] retain] : [file retain];
	
	fileToDecode = [file retain];
	title = [[[[file lastPathComponent] stringByDeletingPathExtension] precomposedStringWithCanonicalMapping] retain];
	[trackList addObjectsFromArray:arr];
	if([decoder isMemberOfClass:[XLDMultipleFileWrappedDecoder class]]) {
		discLayout = [[decoder discLayout] retain];
		cueMode = XLDCueModeMulti;
	}
	else {
		discLayout = [[XLDDiscLayout alloc] initWithDecoderCenter:[delegate decoderCenter]];
		[discLayout setSamplerate:samplerate];
		[discLayout setChannels:[decoder channels]];
		[discLayout setBytesPerSample:[decoder bytesPerSample]];
		[discLayout setIsFloat:[decoder isFloat]];
		if([decoder isMemberOfClass:[XLDRawDecoder class]])
			[discLayout addRawSection:fileToDecode withLength:totalFrames endian:[decoder endian] offset:[decoder offset]];
		else [discLayout addSection:fileToDecode withLength:totalFrames];
	}
	
	if([[decoder metadata] objectForKey:XLD_METADATA_TOTALDISCS]) totalDisc = [[[decoder metadata] objectForKey:XLD_METADATA_TOTALDISCS] intValue];
	if([[decoder metadata] objectForKey:XLD_METADATA_DISC]) discNumber = [[[decoder metadata] objectForKey:XLD_METADATA_DISC] intValue];
	
	int i;
	for(i=0;i<[trackList count];i++) {
		if(![[[trackList objectAtIndex:i] metadata] objectForKey:XLD_METADATA_ALBUM] && [[decoder metadata] objectForKey:XLD_METADATA_ALBUM])
			[[[trackList objectAtIndex:i] metadata] setObject:[[decoder metadata] objectForKey:XLD_METADATA_ALBUM] forKey:XLD_METADATA_ALBUM];
		if(![[[trackList objectAtIndex:i] metadata] objectForKey:XLD_METADATA_ARTIST] && [[decoder metadata] objectForKey:XLD_METADATA_ALBUMARTIST])
			[[[trackList objectAtIndex:i] metadata] setObject:[[decoder metadata] objectForKey:XLD_METADATA_ALBUMARTIST] forKey:XLD_METADATA_ARTIST];
		if(![[[trackList objectAtIndex:i] metadata] objectForKey:XLD_METADATA_ALBUMARTIST] && [[decoder metadata] objectForKey:XLD_METADATA_ALBUMARTIST])
			[[[trackList objectAtIndex:i] metadata] setObject:[[decoder metadata] objectForKey:XLD_METADATA_ALBUMARTIST] forKey:XLD_METADATA_ALBUMARTIST];
		[[[trackList objectAtIndex:i] metadata] setObject:[NSNumber numberWithInt:i+1] forKey:XLD_METADATA_TRACK];
		[[[trackList objectAtIndex:i] metadata] setObject:[NSNumber numberWithInt:[trackList count]] forKey:XLD_METADATA_TOTALTRACKS];
		[[[trackList objectAtIndex:i] metadata] setObject:[NSNumber numberWithUnsignedInt:discid] forKey:XLD_METADATA_FREEDBDISCID];
		[[[trackList objectAtIndex:i] metadata] setObject:gracenoteDiscID forKey:XLD_METADATA_GRACENOTE2];
		if(cover) [[[trackList objectAtIndex:i] metadata] setObject:cover forKey:XLD_METADATA_COVER];
		if(totalDisc) [[[trackList objectAtIndex:i] metadata] setObject:[NSNumber numberWithInt:totalDisc] forKey:XLD_METADATA_TOTALDISCS];
		if(discNumber) [[[trackList objectAtIndex:i] metadata] setObject:[NSNumber numberWithInt:discNumber] forKey:XLD_METADATA_DISC];
		if(i==[trackList count]-1) [[trackList objectAtIndex:i] setSeconds:(totalFrames-[(XLDTrack *)[trackList objectAtIndex:i] index])/samplerate];
		else [[trackList objectAtIndex:i] setSeconds:[[trackList objectAtIndex:i] frames]/samplerate];
	}
	
	if([delegate canSetCompilationFlag] && [self isCompilationForTracks:trackList]) {
		for(i=0;i<[trackList count];i++) [[[trackList objectAtIndex:i] metadata] setObject:[NSNumber numberWithBool:YES] forKey:XLD_METADATA_COMPILATION];
	}
	
	for(i=0;i<[trackList count];i++) {
		XLDButton *button = [[XLDButton alloc] init];
		[button setButtonType:NSSwitchButton];
		BOOL dataTrack = NO;
		if([[[trackList objectAtIndex:i] metadata] objectForKey:XLD_METADATA_DATATRACK]) {
			dataTrack = [[[[trackList objectAtIndex:i] metadata] objectForKey:XLD_METADATA_DATATRACK] boolValue];
		}
		if(!dataTrack) [button setState:NSOnState];
		else {
			[[[trackList objectAtIndex:i] metadata] setObject:LS(@"(Data Track)") forKey:XLD_METADATA_TITLE];
			[button setState:NSOffState];
			[button setEnabled:NO];
		}
		[[button cell] setControlSize:NSSmallControlSize];
		[button setTitle:@""];
		[button setTarget:[delegate discView]];
		[button setAction:@selector(checkboxStatusChanged:)];
		[checkList addObject:button];
		[button release];
	}
}

- (XLDErr)openFiles:(NSArray *)files offset:(xldoffset_t)offset prepended:(BOOL)prepended
{
	int i;
	XLDErr error = XLDNoErr;
	NSMutableArray *arr = [NSMutableArray array];
	XLDDiscLayout *layout = [[XLDDiscLayout alloc] initWithDecoderCenter:[delegate decoderCenter]];
	int track = 1;
	int currentSamplerate = 0;
	int currentChannels = 0;
	int maxBps = 0;
	int isFloat = -1;
	NSData *coverData = nil;
	
	if(offset > 0 && !prepended) [layout addSection:nil withLength:offset];
	
	for(i=0;i<[files count];i++) {
		id <XLDDecoder> decoder = [[delegate decoderCenter] preferredDecoderForFile:[files objectAtIndex:i]];
		if(!decoder) continue;
		[decoder openFile:(char *)[[files objectAtIndex:i] UTF8String]];
		
		//NSLog(@"%d,%d,%d,%d",[decoder samplerate],[decoder channels],[decoder isFloat],[decoder bytesPerSample]);
		if(!currentSamplerate) currentSamplerate = [decoder samplerate];
		else if(currentSamplerate != [decoder samplerate]) {
			error = XLDReadErr;
			if(errorMsg) [errorMsg release];
			errorMsg = [[NSString stringWithFormat:LS(@"Samplerate of the file \"%@\" is different from others."),[[files objectAtIndex:i] lastPathComponent]] retain];
			break;
		}
		if(!currentChannels) currentChannels = [decoder channels];
		else if(currentChannels != [decoder channels]) {
			error = XLDReadErr;
			if(errorMsg) [errorMsg release];
			errorMsg = [[NSString stringWithFormat:LS(@"Number of channels of the file \"%@\" is different from others."),[[files objectAtIndex:i] lastPathComponent]] retain];
			break;
		}
		if(isFloat == -1) isFloat = [decoder isFloat];
		else if(isFloat != [decoder isFloat]) {
			error = XLDReadErr;
			if(errorMsg) [errorMsg release];
			errorMsg = [[NSString stringWithFormat:LS(@"PCM format of the file \"%@\" is different from others."),[[files objectAtIndex:i] lastPathComponent]] retain];
			break;
		}
		if(maxBps < [decoder bytesPerSample]) maxBps = [decoder bytesPerSample];
		if(!coverData) coverData = [[decoder metadata] objectForKey:XLD_METADATA_COVER];
		
		XLDTrack *trk = [[XLDTrack alloc] init];
		if(track == 1 && offset > 0) {
			if(prepended) [trk setFrames:[decoder totalFrames]-offset];
			else [trk setFrames:[decoder totalFrames]];
			[trk setIndex:offset];
			[trk setGap:offset];
		}
		else {
			[trk setFrames:[decoder totalFrames]];
			[trk setIndex:[layout totalFrames]];
		}
		[[trk metadata] addEntriesFromDictionary:[decoder metadata]];
		[[trk metadata] setObject:[NSNumber numberWithInt: track++] forKey:XLD_METADATA_TRACK];
		[arr addObject:trk];
		[trk release];
		
		[layout addSection:[decoder srcPath] withLength:[decoder totalFrames]];
		[decoder closeFile];
	}
	
	if(![arr count]) {
		error = XLDReadErr;
		if(errorMsg) [errorMsg release];
		errorMsg = [[NSString stringWithString:LS(@"No audio files found in the folder.")] retain];
	}
	if(error != XLDNoErr) {
		[layout release];
		return error;
	}
	
	if(!currentSamplerate) currentSamplerate = 44100;
	unsigned int discid = getDiscId(arr, [layout totalFrames]);
	NSString *gracenoteDiscID = [XLDTrackListUtil gracenoteDiscIDForTracks:arr totalFrames:[layout totalFrames] freeDBDiscID:discid];
	for(i=0;i<[arr count];i++) {
		[[[arr objectAtIndex:i] metadata] setObject:[NSNumber numberWithInt:[arr count]] forKey:XLD_METADATA_TOTALTRACKS];
		[[[arr objectAtIndex:i] metadata] setObject:[NSNumber numberWithUnsignedInt:discid] forKey:XLD_METADATA_FREEDBDISCID];
		[[[arr objectAtIndex:i] metadata] setObject:gracenoteDiscID forKey:XLD_METADATA_GRACENOTE2];
		if(coverData) [[[arr objectAtIndex:i] metadata] setObject:coverData forKey:XLD_METADATA_COVER];
		if(i==[arr count]-1) [[arr objectAtIndex:i] setSeconds:([layout totalFrames]-[(XLDTrack *)[arr objectAtIndex:i] index])/currentSamplerate];
		else [[arr objectAtIndex:i] setSeconds:[[arr objectAtIndex:i] frames]/currentSamplerate];
	}
	
	if((!delegate || [delegate canSetCompilationFlag]) && [self isCompilationForTracks:arr]) {
		for(i=0;i<[arr count];i++) {
			if(![[[arr objectAtIndex:i] metadata] objectForKey:XLD_METADATA_COMPILATION])
				[[[arr objectAtIndex:i] metadata] setObject:[NSNumber numberWithBool:YES] forKey:XLD_METADATA_COMPILATION];
		}
	}
	
	[layout setSamplerate:currentSamplerate];
	[layout setChannels:currentChannels];
	[layout setBytesPerSample:maxBps];
	[layout setIsFloat:isFloat];
	
	NSString *titleStr = [XLDTrackListUtil albumTitleForTracks:arr];
	[self clean];
	rawMode = NO;
	cueMode = XLDCueModeMulti;
	
	[trackList addObjectsFromArray:arr];
	samplerate = [layout samplerate];
	totalFrames = [layout totalFrames];
	discLayout = layout;
	writable = ((samplerate == 44100) && (![discLayout isFloat]));
	representedFilename = [[[files objectAtIndex:0] stringByDeletingLastPathComponent] retain];
	
	if(coverData) cover = [coverData retain];
	fileToDecode = [[[[files objectAtIndex:0] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"CDImage.folder"] retain];
	if(titleStr) {
		title = [titleStr retain];
	}
	else {
		title = [[[[[files objectAtIndex:0] stringByDeletingLastPathComponent] lastPathComponent] precomposedStringWithCanonicalMapping] retain];
	}
	
	for(i=0;i<[trackList count];i++) {
		XLDButton *button = [[XLDButton alloc] init];
		[button setButtonType:NSSwitchButton];
		[button setState:NSOnState];
		[[button cell] setControlSize:NSSmallControlSize];
		[button setTitle:@""];
		[button setTarget:[delegate discView]];
		[button setAction:@selector(checkboxStatusChanged:)];
		[checkList addObject:button];
		[button release];
	}
	
	return XLDNoErr;
}

- (NSArray *)trackList
{
	int i;
	for(i=0;i<[checkList count];i++) {
		if([[checkList objectAtIndex:i] state] == NSOnState) [[trackList objectAtIndex:i] setEnabled:YES];
		else [[trackList objectAtIndex:i] setEnabled:NO];
	}
	
	return trackList;
}

- (NSArray *)trackListForMetadata
{
	NSMutableArray *array = [NSMutableArray array];
	int i;
	for(i=0;i<[checkList count];i++) {
		if([[checkList objectAtIndex:i] state] == NSOnState) [array addObject:[trackList objectAtIndex:i]];
	}
	return array;
}

- (NSArray *)checkList
{
	return checkList;
}

- (NSArray *)trackListForExternalNonCompliantCueSheet:(NSString *)file decoder:(id *)decoder
{
	XLDErr error;
	*decoder = nil;
	NSMutableArray *arr = [NSMutableArray array];
	XLDDiscLayout *layout = [[XLDDiscLayout alloc] initWithDecoderCenter:[delegate decoderCenter]];

	[self setTrackData:arr andLayout:layout forNonCompliantCueFile:file error:&error];
	if(error != XLDNoErr) {
		[layout release];
		return nil;
	}

	*decoder = [[[XLDMultipleFileWrappedDecoder alloc] initWithDiscLayout:layout] autorelease];
	[layout release];
	return arr;
}

- (NSArray *)trackListForExternalCueSheet:(NSString *)file decoder:(id *)decoder
{
	int i;
	XLDErr error;
	*decoder = nil;
	i = numberOfFILELine(file);
	if(i<1) return nil;
	else if(i>1) return [self trackListForExternalNonCompliantCueSheet:file decoder:decoder];
	*decoder = [self decoderForCueSheet:file isRaw:NO promptIfNotFound:NO error:&error];
	if(!*decoder) return nil;
	NSMutableArray *arr = [[NSMutableArray alloc] init];
	[self setTrackData:arr forCueFile:file withDecoder:*decoder];
	for(i=0;i<[arr count];i++) {
		[[arr objectAtIndex:i] setEnabled:NO];
	}
	//[self setPreferredFilenameForTracks:arr];
	return [arr autorelease];
}

- (NSArray *)trackListForDecoder:(id)decoder withEmbeddedCueData:(NSString *)cueData
{
	int i;
	NSMutableArray *arr = [[NSMutableArray alloc] init];
	[self setTrackData:arr forCueData:cueData withDecoder:decoder];
	for(i=0;i<[arr count];i++) {
		[[arr objectAtIndex:i] setEnabled:NO];
	}
	//[self setPreferredFilenameForTracks:arr];
	return [arr autorelease];
}

- (NSArray *)trackListForDecoder:(id)decoder withEmbeddedTrackList:(NSArray *)tracks
{
	int i;
	int totalDisc = 0;
	int discNumber = 0;
	unsigned int discid = getDiscId(tracks, [decoder totalFrames]);
	NSString *gracenoteDiscID = [XLDTrackListUtil gracenoteDiscIDForTracks:tracks totalFrames:[decoder totalFrames] freeDBDiscID:discid];
	if([[decoder metadata] objectForKey:XLD_METADATA_TOTALDISCS]) totalDisc = [[[decoder metadata] objectForKey:XLD_METADATA_TOTALDISCS] intValue];
	if([[decoder metadata] objectForKey:XLD_METADATA_DISC]) discNumber = [[[decoder metadata] objectForKey:XLD_METADATA_DISC] intValue];
	NSData *coverData = [[decoder metadata] objectForKey:XLD_METADATA_COVER];
	
	for(i=0;i<[tracks count];i++) {
		if(![[[tracks objectAtIndex:i] metadata] objectForKey:XLD_METADATA_ALBUM] && [[decoder metadata] objectForKey:XLD_METADATA_ALBUM])
			[[[tracks objectAtIndex:i] metadata] setObject:[[decoder metadata] objectForKey:XLD_METADATA_ALBUM] forKey:XLD_METADATA_ALBUM];
		if(![[[tracks objectAtIndex:i] metadata] objectForKey:XLD_METADATA_ARTIST] && [[decoder metadata] objectForKey:XLD_METADATA_ALBUMARTIST])
			[[[tracks objectAtIndex:i] metadata] setObject:[[decoder metadata] objectForKey:XLD_METADATA_ALBUMARTIST] forKey:XLD_METADATA_ARTIST];
		if(![[[tracks objectAtIndex:i] metadata] objectForKey:XLD_METADATA_ALBUMARTIST] && [[decoder metadata] objectForKey:XLD_METADATA_ALBUMARTIST])
			[[[tracks objectAtIndex:i] metadata] setObject:[[decoder metadata] objectForKey:XLD_METADATA_ALBUMARTIST] forKey:XLD_METADATA_ALBUMARTIST];
		[[[tracks objectAtIndex:i] metadata] setObject:[NSNumber numberWithInt:i+1] forKey:XLD_METADATA_TRACK];
		[[[tracks objectAtIndex:i] metadata] setObject:[NSNumber numberWithInt:[tracks count]] forKey:XLD_METADATA_TOTALTRACKS];
		[[[tracks objectAtIndex:i] metadata] setObject:[NSNumber numberWithUnsignedInt:discid] forKey:XLD_METADATA_FREEDBDISCID];
		[[[tracks objectAtIndex:i] metadata] setObject:gracenoteDiscID forKey:XLD_METADATA_GRACENOTE2];
		if(coverData) [[[tracks objectAtIndex:i] metadata] setObject:coverData forKey:XLD_METADATA_COVER];
		if(totalDisc) [[[tracks objectAtIndex:i] metadata] setObject:[NSNumber numberWithInt:totalDisc] forKey:XLD_METADATA_TOTALDISCS];
		if(discNumber) [[[tracks objectAtIndex:i] metadata] setObject:[NSNumber numberWithInt:discNumber] forKey:XLD_METADATA_DISC];
		if(i==[tracks count]-1) [[tracks objectAtIndex:i] setSeconds:([decoder totalFrames]-[(XLDTrack *)[tracks objectAtIndex:i] index])/[decoder samplerate]];
		else [[tracks objectAtIndex:i] setSeconds:[[tracks objectAtIndex:i] frames]/[decoder samplerate]];
		[[tracks objectAtIndex:i] setEnabled:NO];
	}
	
	if([delegate canSetCompilationFlag] && [self isCompilationForTracks:tracks]) {
		for(i=0;i<[tracks count];i++) [[[tracks objectAtIndex:i] metadata] setObject:[NSNumber numberWithBool:YES] forKey:XLD_METADATA_COMPILATION];
	}
	//[self setPreferredFilenameForTracks:tracks];
	
	return tracks;
}

- (NSString *)lengthOfTrack:(int)track
{
	if(track < [trackList count]-1) return framesToMSFStr([[trackList objectAtIndex:track] frames]+[[trackList objectAtIndex:track+1] gap],samplerate);
	return framesToMSFStr(totalFrames - [(XLDTrack *)[trackList objectAtIndex:track] index],samplerate);
}

- (NSString *)gapOfTrack:(int)track
{
	return framesToMSFStr([[trackList objectAtIndex:track] gap],samplerate);
}

- (NSString *)fileToDecode
{
	return fileToDecode;
}

- (NSString *)title
{
	NSString *str = [XLDTrackListUtil albumTitleForTracks:trackList];
	if(str) return str;
	return title;
}

- (NSString *)artist
{
	return [XLDTrackListUtil artistForTracks:trackList];
}

- (xldoffset_t)totalFrames
{
	return totalFrames;
}

- (XLDFormat)rawFormat
{
	return format;
}

- (XLDEndian)rawEndian
{
	return endian;
}

- (int)rawOffset
{
	return rawOffset;
}

- (BOOL)rawMode
{
	return rawMode;
}

- (NSData *)coverData
{
	return cover;
}

- (void)setCoverData:(NSData *)data
{
	int i;
	if(!trackList) return;
	if(cover) [cover release];
	if(data) {
		cover = [data retain];
		for(i=0;i<[trackList count];i++) {
			[[[trackList objectAtIndex:i] metadata] setObject:data forKey:XLD_METADATA_COVER];
		}
	}
	else {
		cover = nil;
		for(i=0;i<[trackList count];i++) {
			[[[trackList objectAtIndex:i] metadata] removeObjectForKey:XLD_METADATA_COVER];
		}
	}
}

- (NSArray *)trackListForSingleFile
{
	int i;
	NSMutableArray *arr = [[NSMutableArray alloc] init];
	XLDTrack *trk = [[XLDTrack alloc] init];
	xldoffset_t index = -1;
	xldoffset_t length = 0;
	for(i=0;i<[trackList count];i++) {
		XLDTrack *track = [trackList objectAtIndex:i];
		if([[checkList objectAtIndex:i] state] == NSOffState) continue;
		if(index == -1) {
			if((i==0) && ([track gap]!=0)) index = 0;
			else index = [track index];
		}
		if([track frames] == -1) length = -1;
		else {
			length = [track index] + [track frames] - index;
			if(i<[trackList count]-1) length += [[trackList objectAtIndex:i+1] gap];
		}
	}
	
	[trk setIndex:index];
	[trk setFrames:length];
	
	id obj;
	if(obj = [[[trackList objectAtIndex:0] metadata] objectForKey:XLD_METADATA_ALBUM])
		[[trk metadata] setObject:obj forKey:XLD_METADATA_ALBUM];
	if(![[self artist] isEqualToString:@""])
		[[trk metadata] setObject:[self artist] forKey:XLD_METADATA_ALBUMARTIST];
	if(obj = [[[trackList objectAtIndex:0] metadata] objectForKey:XLD_METADATA_COMPOSER])
		[[trk metadata] setObject:obj forKey:XLD_METADATA_COMPOSER];
	if(obj = [[[trackList objectAtIndex:0] metadata] objectForKey:XLD_METADATA_YEAR])
		[[trk metadata] setObject:obj forKey:XLD_METADATA_YEAR];
	if(obj = [[[trackList objectAtIndex:0] metadata] objectForKey:XLD_METADATA_DISC])
		[[trk metadata] setObject:obj forKey:XLD_METADATA_DISC];
	if(obj = [[[trackList objectAtIndex:0] metadata] objectForKey:XLD_METADATA_TOTALDISCS])
		[[trk metadata] setObject:obj forKey:XLD_METADATA_TOTALDISCS];
	
	/*NSMutableData *cue = [self cueData];
	[cue replaceBytesInRange:rangeForCuesheet withBytes:"CDImage.wav" length:11];*/
	NSMutableData *cue = [XLDTrackListUtil cueDataForTracks:trackList withFileName:@"CDImage.wav" appendBOM:NO samplerate:samplerate];
	NSString *cueStr = [[NSString alloc] initWithData:cue encoding:NSUTF8StringEncoding];
	
	[[trk metadata] setObject:cueStr forKey:XLD_METADATA_CUESHEET];
	[cueStr release];
	
	[[trk metadata] setObject:[self trackListForMetadata] forKey:XLD_METADATA_TRACKLIST];
	[[trk metadata] setObject:[NSNumber numberWithLongLong:totalFrames] forKey:XLD_METADATA_TOTALSAMPLES];
	
	if(cover) [[trk metadata] setObject:cover forKey:XLD_METADATA_COVER];
	if(length == -1) [trk setSeconds:(totalFrames-[(XLDTrack *)trk index])/samplerate];
	else [trk setSeconds:length/samplerate];
	
	//NSLog(@"index:%lld, length:%lld",index,length);
	
	[arr addObject:trk];
	[trk release];
	return [arr autorelease];
}

- (void)setTitle:(NSString *)str
{
	if(title) [title release];
	title = [str retain];
}

- (void)setDriveStr:(NSString *)str
{
	if(driveStr) [driveStr release];
	driveStr = [str retain];
}

- (NSString *)driveStr
{
	return driveStr;
}

- (NSData *)accurateRipData
{
	if(ARQueried) return accurateRipData;
	
	int i,discId1=0,discId2=0,cddbDiscId=0;
	int totalTrack = [trackList count];
	int totalAudioTrack = [trackList count];
	if(![[checkList objectAtIndex:totalAudioTrack-1] isEnabled] && ![[trackList objectAtIndex:totalAudioTrack-1] enabled]) {
		totalAudioTrack--;
	}
	
	for (i=0;i<totalTrack;i++) {
		int trackOffset =  [(XLDTrack *)[trackList objectAtIndex:i] index];
		trackOffset /= 588;
		
		if(i<totalAudioTrack) {
			discId1 += trackOffset;
			discId2 += (trackOffset ? trackOffset : 1) * (i + 1);
		}
		int r=0;
		int n=trackOffset/75 + 2;
		while(n>0) {
			r = r + (n%10);
			n = n/10;
		}
		cddbDiscId = cddbDiscId + r;
	}
	
	discId1 += totalFrames/588;
	discId2 += totalFrames/588 * (totalAudioTrack+1);
	cddbDiscId = ((cddbDiscId % 255) << 24) | ((totalFrames/588/75 - [(XLDTrack *)[trackList objectAtIndex:0] index]/588/75) << 8) | totalTrack;
	//NSLog([NSString stringWithFormat:@"http://www.accuraterip.com/accuraterip/%01x/%01x/%01x/dBAR-%03d-%08x-%08x-%08x.bin",discId1 & 0xF, discId1>>4 & 0xF, discId1>>8 & 0xF, totalAudioTrack, discId1, discId2, cddbDiscId]);
	accurateRipData = [[NSData alloc] initWithContentsOfURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://www.accuraterip.com/accuraterip/%01x/%01x/%01x/dBAR-%03d-%08x-%08x-%08x.bin",discId1 & 0xF, discId1>>4 & 0xF, discId1>>8 & 0xF, totalAudioTrack, discId1, discId2, cddbDiscId]]];
	ARQueried = YES;
	return accurateRipData;
}

- (xldoffset_t)firstAudioFrame
{
	if(![trackList count]) return 0;
	if(![[checkList objectAtIndex:0] isEnabled] && ([[checkList objectAtIndex:0] state] == NSOffState))
		return [(XLDTrack *)[trackList objectAtIndex:1] index];
	else
		return 0;
}

- (xldoffset_t)lastAudioFrame
{
	if(![trackList count]) return 0;
	if(![[checkList objectAtIndex:[checkList count]-1] isEnabled] && ([[checkList objectAtIndex:[checkList count]-1] state] == NSOffState))
		return [(XLDTrack *)[trackList objectAtIndex:[checkList count]-1] index];
	else
		return [(XLDTrack *)[trackList objectAtIndex:[checkList count]-1] index] + [(XLDTrack *)[trackList objectAtIndex:[checkList count]-1] frames];
}


- (int)cueMode
{
	return cueMode;
}

- (XLDDiscLayout *)discLayout
{
	return discLayout;
}

- (BOOL)writable
{
	return writable;
}

- (int)samplerate
{
	return samplerate;
}

- (NSString *)errorMsg
{
	return errorMsg;
}

- (NSString *)representedFilename
{
	return representedFilename;
}

- (void)setPreferredEncoding:(NSStringEncoding)enc
{
	preferredEncoding = enc;
}

- (void)setMediaType:(NSString *)str
{
	if(mediaType) [mediaType release];
	mediaType = [str retain];
}

- (NSString *)mediaType
{
	return mediaType;
}

@end
