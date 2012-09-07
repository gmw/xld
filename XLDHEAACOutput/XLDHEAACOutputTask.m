//
//  XLDHEAACOutputTask.m
//  XLDHEAACOutput
//
//  Created by tmkk on 08/03/04.
//  Copyright 2008 tmkk. All rights reserved.
//

#import "XLDHEAACOutputTask.h"
#import "XLDHEAACOutput.h"

typedef int64_t xldoffset_t;

#import "XLDTrack.h"
#import <sys/stat.h>
#import <unistd.h>
#import <sys/types.h>

#ifdef _BIG_ENDIAN
#define SWAP32(n) (n)
#define SWAP16(n) (n)
#else
#define SWAP32(n) (((n>>24)&0xff) | ((n>>8)&0xff00) | ((n<<8)&0xff0000) | ((n<<24)&0xff000000))
#define SWAP16(n) (((n>>8)&0xff) | ((n<<8)&0xff00))
#endif

static void appendUserDefinedComment(NSMutableData *tagData, NSString *tagIdentifier, NSString *commentStr)
{
	unsigned int tmp;
	unsigned char tmp3;
	NSData *commentData = [commentStr dataUsingEncoding:NSUTF8StringEncoding];
	NSData *tagIdentifierData = [tagIdentifier dataUsingEncoding:NSUTF8StringEncoding];
	tmp = 0x40 + [commentData length] + [tagIdentifierData length];
	tmp = NSSwapHostIntToBig(tmp);
	[tagData appendBytes:&tmp length:4];
	[tagData appendBytes:"----" length:4];
	tmp = 0x1C;
	tmp = NSSwapHostIntToBig(tmp);
	[tagData appendBytes:&tmp length:4];
	[tagData appendBytes:"mean" length:4];
	tmp = 0;
	[tagData appendBytes:&tmp length:4];
	[tagData appendBytes:"com.apple.iTunes" length:16];
	tmp = 0xC + [tagIdentifierData length];
	tmp = NSSwapHostIntToBig(tmp);
	[tagData appendBytes:&tmp length:4];
	[tagData appendBytes:"name" length:4];
	tmp = 0;
	[tagData appendBytes:&tmp length:4];
	[tagData appendData:tagIdentifierData];
	tmp = 0x10 + [commentData length];
	tmp = NSSwapHostIntToBig(tmp);
	[tagData appendBytes:&tmp length:4];
	[tagData appendBytes:"data" length:4];
	tmp = 0;
	[tagData appendBytes:&tmp length:3]; //reserved
	tmp3 = 1;
	[tagData appendBytes:&tmp3 length:1]; //type (1:UTF-8)
	tmp = 0;
	[tagData appendBytes:&tmp length:4]; //locale (reserved to be 0)
	[tagData appendData:commentData];
}

static void appendTextTag(NSMutableData *tagData, const char *atomID, NSString *tagStr)
{
	unsigned int tmp;
	unsigned char tmp3;
	NSData *data = [tagStr dataUsingEncoding:NSUTF8StringEncoding];
	tmp = 24 + [data length];
	tmp = NSSwapHostIntToBig(tmp);
	[tagData appendBytes:&tmp length:4];
	[tagData appendBytes:atomID length:4];
	tmp = 16 + [data length];
	tmp = NSSwapHostIntToBig(tmp);
	[tagData appendBytes:&tmp length:4];
	[tagData appendBytes:"data" length:4];
	tmp = 0;
	[tagData appendBytes:&tmp length:3]; //reserved
	tmp3 = 1;
	[tagData appendBytes:&tmp3 length:1]; //type (1:UTF-8)
	tmp = 0;
	[tagData appendBytes:&tmp length:4]; //locale (reserved to be 0)
	[tagData appendData:data];
}

static void appendNumericTag(NSMutableData *tagData, const char *atomID, NSNumber *tagNum, int length)
{
	if(length != 1 && length != 2 && length != 4) return;
	unsigned int tmp;
	unsigned short tmp2;
	unsigned char tmp3;
	tmp = 24 + length;
	tmp = NSSwapHostIntToBig(tmp);
	[tagData appendBytes:&tmp length:4];
	[tagData appendBytes:atomID length:4];
	tmp = 16 + length;
	tmp = NSSwapHostIntToBig(tmp);
	[tagData appendBytes:&tmp length:4];
	[tagData appendBytes:"data" length:4];
	tmp = 0;
	[tagData appendBytes:&tmp length:3]; //reserved
	tmp3 = 0x15;
	[tagData appendBytes:&tmp3 length:1]; //type (0x15:integer)
	tmp = 0;
	[tagData appendBytes:&tmp length:4]; //locale (reserved to be 0)
	if(length == 1) {
		tmp3 = [tagNum unsignedCharValue];
		[tagData appendBytes:&tmp3 length:1];
	}
	else if(length == 2) {
		tmp2 = NSSwapHostShortToBig([tagNum unsignedShortValue]);
		[tagData appendBytes:&tmp2 length:2];
	}
	else if(length == 4) {
		tmp = NSSwapHostIntToBig([tagNum unsignedIntValue]);
		[tagData appendBytes:&tmp length:4];
	}
}

@implementation XLDHEAACOutputTask

- (id)init
{
	[super init];
	task = nil;
	addTag = NO;
	tagData = [[NSMutableData alloc] init];
	path = nil;
	return self;
}

- (id)initWithConfigurations:(NSDictionary *)cfg
{
	[self init];
	configurations = [cfg retain];
	return self;
}

- (void)dealloc
{
	if(task) [task release];
	if(path) [path release];
	if(configurations) [configurations release];
	[tagData release];
	[super dealloc];
}

- (BOOL)setOutputFormat:(XLDFormat)fmt
{
	if(fmt.isFloat) return NO;
	if(fmt.samplerate != 44100 && fmt.samplerate != 48000) return NO;
	
	if(fmt.channels > 2) return NO;
	if(fmt.channels == 1 && [[configurations objectForKey:@"Bitrate"] intValue] > 44) return NO;
	
	format = fmt;
	return YES;
}

- (BOOL)openFileForOutput:(NSString *)str withTrackData:(id)track
{
	task = [[NSTask alloc] init];
	[task setStandardInput:[NSPipe pipe]];
	[task setLaunchPath:[[NSBundle bundleForClass:[self class]] pathForResource:@"aacplusenc" ofType:nil inDirectory:nil]];
	[task setCurrentDirectoryPath:[str stringByDeletingLastPathComponent]];
	NSMutableArray *args = [NSMutableArray arrayWithObjects:@"-",str,[NSString stringWithFormat:@"%d",[[configurations objectForKey:@"Bitrate"] intValue]],@"--raw",[NSString stringWithFormat:@"%d",format.samplerate],[NSString stringWithFormat:@"%d",format.channels],[NSString stringWithFormat:@"%d",format.bps<<3],nil];
	[task setArguments:args];
	
	path = [str retain];
	
	if(addTag) {
		BOOL added = NO;
		int tmp;
		short tmp2;
		char atomID[4];
		
		/* udta atom */
		tmp = 0;
		memcpy(atomID,"udta",4);
		[tagData appendBytes:&tmp length:4];
		[tagData appendBytes:atomID length:4];
		
		/* meta atom */
		tmp = 0;
		memcpy(atomID,"meta",4);
		[tagData appendBytes:&tmp length:4];
		[tagData appendBytes:atomID length:4];
		[tagData appendBytes:&tmp length:4];
		
		/* hdlr atom */
		tmp = 0x22;
		tmp = SWAP32(tmp);
		memcpy(atomID,"hdlr",4);
		[tagData appendBytes:&tmp length:4];
		[tagData appendBytes:atomID length:4];
		tmp = 0;
		[tagData appendBytes:&tmp length:4];
		[tagData appendBytes:&tmp length:4];
		memcpy(atomID,"mdir",4);
		[tagData appendBytes:atomID length:4];
		memcpy(atomID,"appl",4);
		[tagData appendBytes:atomID length:4];
		[tagData appendBytes:&tmp length:4];
		[tagData appendBytes:&tmp length:4];
		tmp2 = 0;
		tmp2 = SWAP16(tmp2);
		[tagData appendBytes:&tmp2 length:2];
		
		/* ilst atom */
		tmp = 0;
		memcpy(atomID,"ilst",4);
		[tagData appendBytes:&tmp length:4];
		[tagData appendBytes:atomID length:4];
		
		/* nam atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLE]) {
			added = YES;
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLE];
			atomID[0] = 0xa9;
			memcpy(atomID+1,"nam",3);
			appendTextTag(tagData, atomID, str);
		}
		
		/* ART atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTIST]) {
			added = YES;
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTIST];
			atomID[0] = 0xa9;
			memcpy(atomID+1,"ART",3);
			appendTextTag(tagData, atomID, str);
		}
		
		/* aART atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMARTIST]) {
			added = YES;
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMARTIST];
			appendTextTag(tagData, "aART", str);
		}
		
		/* alb atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUM]) {
			added = YES;
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUM];
			atomID[0] = 0xa9;
			memcpy(atomID+1,"alb",3);
			appendTextTag(tagData, atomID, str);
		}
		
		/* gen atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GENRE]) {
			added = YES;
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GENRE];
			atomID[0] = 0xa9;
			memcpy(atomID+1,"gen",3);
			appendTextTag(tagData, atomID, str);
		}
		
		/* wrt atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPOSER]) {
			added = YES;
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPOSER];
			atomID[0] = 0xa9;
			memcpy(atomID+1,"wrt",3);
			appendTextTag(tagData, atomID, str);
		}
		
		/* trkn atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TRACK] || [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALTRACKS]) {
			added = YES;
			tmp = 0x20;
			tmp = SWAP32(tmp);
			memcpy(atomID,"trkn",4);
			[tagData appendBytes:&tmp length:4];
			[tagData appendBytes:atomID length:4];
			tmp = 0x18;
			tmp = SWAP32(tmp);
			memcpy(atomID,"data",4);
			[tagData appendBytes:&tmp length:4];
			[tagData appendBytes:atomID length:4];
			tmp = 0;
			[tagData appendBytes:&tmp length:4];
			[tagData appendBytes:&tmp length:4];
			tmp2 = 0;
			[tagData appendBytes:&tmp2 length:2];
			if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TRACK]) {
				tmp2 = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TRACK] shortValue];
				tmp2 = SWAP16(tmp2);
			}
			[tagData appendBytes:&tmp2 length:2];
			tmp2 = 0;
			if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALTRACKS]) {
				tmp2 = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALTRACKS] shortValue];
				tmp2 = SWAP16(tmp2);
			}
			[tagData appendBytes:&tmp2 length:2];
			tmp2 = 0;
			[tagData appendBytes:&tmp2 length:2];
		}
		
		/* disk atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DISC] || [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALDISCS]) {
			added = YES;
			tmp = 0x1E;
			tmp = SWAP32(tmp);
			memcpy(atomID,"disk",4);
			[tagData appendBytes:&tmp length:4];
			[tagData appendBytes:atomID length:4];
			tmp = 0x16;
			tmp = SWAP32(tmp);
			memcpy(atomID,"data",4);
			[tagData appendBytes:&tmp length:4];
			[tagData appendBytes:atomID length:4];
			tmp = 0;
			[tagData appendBytes:&tmp length:4];
			[tagData appendBytes:&tmp length:4];
			tmp2 = 0;
			[tagData appendBytes:&tmp2 length:2];
			if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DISC]) {
				tmp2 = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DISC] shortValue];
				tmp2 = SWAP16(tmp2);
			}
			[tagData appendBytes:&tmp2 length:2];
			tmp2 = 0;
			if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALDISCS]) {
				tmp2 = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALDISCS] shortValue];
				tmp2 = SWAP16(tmp2);
			}
			[tagData appendBytes:&tmp2 length:2];
		}
		
		/* day atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DATE]) {
			added = YES;
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DATE];
			atomID[0] = 0xa9;
			memcpy(atomID+1,"day",3);
			appendTextTag(tagData, atomID, str);
		}
		else if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_YEAR]) {
			added = YES;
			NSString *str = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_YEAR] stringValue];
			atomID[0] = 0xa9;
			memcpy(atomID+1,"day",3);
			appendTextTag(tagData, atomID, str);
		}
		
		/* cmt atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMMENT]) {
			added = YES;
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMMENT];
			atomID[0] = 0xa9;
			memcpy(atomID+1,"cmt",3);
			appendTextTag(tagData, atomID, str);
		}
		
		/* lyr atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_LYRICS]) {
			added = YES;
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_LYRICS];
			atomID[0] = 0xa9;
			memcpy(atomID+1,"lyr",3);
			appendTextTag(tagData, atomID, str);
		}
		
		/* grp atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GROUP]) {
			added = YES;
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GROUP];
			atomID[0] = 0xa9;
			memcpy(atomID+1,"grp",3);
			appendTextTag(tagData, atomID, str);
		}
		
		/* sonm atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLESORT]) {
			added = YES;
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLESORT];
			appendTextTag(tagData, "sonm", str);
		}
		
		/* soar atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTISTSORT]) {
			added = YES;
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTISTSORT];
			appendTextTag(tagData, "soar", str);
		}
		
		/* soal atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMSORT]) {
			added = YES;
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMSORT];
			appendTextTag(tagData, "soal", str);
		}
		
		/* soaa atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMARTISTSORT]) {
			added = YES;
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMARTISTSORT];
			appendTextTag(tagData, "soaa", str);
		}
		
		/* soco atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPOSERSORT]) {
			added = YES;
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPOSERSORT];
			appendTextTag(tagData, "soco", str);
		}
		
		/* cpil atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPILATION]) {
			if([[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPILATION] boolValue]) {
				added = YES;
				appendNumericTag(tagData, "cpil", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPILATION], 1);
			}
		}
		
		/* Gracenote CDDB information */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GRACENOTE]) {
			added = YES;
			appendUserDefinedComment(tagData, @"iTunes_CDDB_IDs", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GRACENOTE]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GRACENOTE2]) {
			added = YES;
			appendUserDefinedComment(tagData, @"iTunes_CDDB_1", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GRACENOTE2]);
			if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TRACK]) {
				appendUserDefinedComment(tagData, @"iTunes_CDDB_TrackNumber", [NSString stringWithFormat:@"%d",[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TRACK] intValue]]);
			}
		}
		
		/* tmpo atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_BPM]) {
			added = YES;
			appendNumericTag(tagData, "tmpo", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_BPM], 2);
		}
		
		/* cprt atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COPYRIGHT]) {
			added = YES;
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COPYRIGHT];
			appendTextTag(tagData, "cprt", str);
		}
		
		/* pgap atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GAPLESSALBUM]) {
			if([[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GAPLESSALBUM] boolValue]) {
				added = YES;
				appendNumericTag(tagData, "pgap", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GAPLESSALBUM], 1);
			}
		}
		
		/* MusicBrainz related tags */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_TRACKID]) {
			added = YES;
			appendUserDefinedComment(tagData, @"MusicBrainz Track Id", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_TRACKID]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMID]) {
			added = YES;
			appendUserDefinedComment(tagData, @"MusicBrainz Album Id", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMID]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ARTISTID]) {
			added = YES;
			appendUserDefinedComment(tagData, @"MusicBrainz Artist Id", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ARTISTID]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMARTISTID]) {
			added = YES;
			appendUserDefinedComment(tagData, @"MusicBrainz Album Artist Id", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMARTISTID]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_DISCID]) {
			added = YES;
			appendUserDefinedComment(tagData, @"MusicBrainz Disc Id", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_DISCID]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_PUID]) {
			added = YES;
			appendUserDefinedComment(tagData, @"MusicIP PUID", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_PUID]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMSTATUS]) {
			added = YES;
			appendUserDefinedComment(tagData, @"MusicBrainz Album Status", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMSTATUS]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMTYPE]) {
			added = YES;
			appendUserDefinedComment(tagData, @"MusicBrainz Album Type", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMTYPE]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASECOUNTRY]) {
			added = YES;
			appendUserDefinedComment(tagData, @"MusicBrainz Album Release Country", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASECOUNTRY]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASEGROUPID]) {
			added = YES;
			appendUserDefinedComment(tagData, @"MusicBrainz Release Group Id", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASEGROUPID]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_WORKID]) {
			added = YES;
			appendUserDefinedComment(tagData, @"MusicBrainz Work Id", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_WORKID]);
		}
		
		/* covr atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COVER]) {
			added = YES;
			NSData *imgData = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COVER];
			tmp = [imgData length]+24;
			tmp = SWAP32(tmp);
			memcpy(atomID,"covr",4);
			[tagData appendBytes:&tmp length:4];
			[tagData appendBytes:atomID length:4];
			tmp = [imgData length]+16;
			tmp = SWAP32(tmp);
			memcpy(atomID,"data",4);
			[tagData appendBytes:&tmp length:4];
			[tagData appendBytes:atomID length:4];
			if([imgData length] >= 8 && 0 == memcmp([imgData bytes], "\x89PNG\x0d\x0a\x1a\x0a", 8))
				tmp = 0xe;
			else if([imgData length] >= 2 && 0 == memcmp([imgData bytes], "BM", 2))
				tmp = 0x1b;
			else if([imgData length] >= 3 && 0 == memcmp([imgData bytes], "GIF", 3))
				tmp = 0xc;
			else tmp = 0xd;
			tmp = SWAP32(tmp);
			[tagData appendBytes:&tmp length:4];
			tmp = 0;
			[tagData appendBytes:&tmp length:4];
			[tagData appendData:imgData];
		}
		
		/* version strings */
		long version;
		OSErr result;
		result = Gestalt(gestaltQuickTime,&version);
		if (result == noErr)
		{
			added = YES;
			NSString *str = [NSString stringWithFormat:@"X Lossless Decoder %@, aacplusenc 0.16.3",[[NSBundle mainBundle] objectForInfoDictionaryKey: @"CFBundleShortVersionString"]];
			atomID[0] = 0xa9;
			memcpy(atomID+1,"too",3);
			appendTextTag(tagData, atomID, str);
		}
		
		if(added) {
			int freeSize = 0x800;
			/* update length of udta atom */
			tmp = [tagData length] + freeSize;
			tmp = SWAP32(tmp);
			[tagData replaceBytesInRange:NSMakeRange(0,4) withBytes:&tmp];
			
			/* update length of meta atom */
			tmp = [tagData length] - 8 + freeSize;
			tmp = SWAP32(tmp);
			[tagData replaceBytesInRange:NSMakeRange(8,4) withBytes:&tmp];
			
			/* update length of ilst atom */
			tmp = [tagData length] - 54;
			tmp = SWAP32(tmp);
			[tagData replaceBytesInRange:NSMakeRange(54,4) withBytes:&tmp];
			
			/* add free atom */
			if(freeSize) {
				tmp = freeSize;
				tmp = SWAP32(tmp);
				memcpy(atomID,"free",4);
				[tagData appendBytes:&tmp length:4];
				[tagData appendBytes:atomID length:4];
				[tagData increaseLengthBy:freeSize-8];
			}
		}
		else [tagData setLength:0];
	}
	
	[task launch];
	
	return YES;
}

- (NSString *)extensionStr
{
	if([[configurations objectForKey:@"UseMP4"] boolValue]) return @"m4a";
	else return @"aac";
}

- (BOOL)writeBuffer:(int *)buffer frames:(int)counts
{
	if(![task isRunning]) return NO;
	[[[task standardInput] fileHandleForWriting] writeData:[NSData dataWithBytes:buffer length:counts*4*format.channels]];
	
	return YES;
}

- (void)finalize
{
	[[[task standardInput] fileHandleForWriting] closeFile];
	/*while([task isRunning]) {
		usleep(10000);
	}*/
	[task waitUntilExit];
	
	if(addTag && [tagData length]) {
		int tmp;
		int udatSize = [tagData length];
		int origSize;
		char atom[4];
		struct stat stbuf;
		
		stat([path UTF8String], &stbuf);
		origSize = stbuf.st_size;
		
		FILE *fp = fopen([path UTF8String], "r+b");
		if(!fp) return;
		int bufferSize = 1024*1024;
		char *tmpbuf = (char *)malloc(bufferSize);
		char *tmpbuf2 = (char *)malloc(bufferSize);
		char *read = tmpbuf;
		char *write = tmpbuf2;
		char *swap;
		BOOL moov_after_mdat = NO;
		
		while(1) { //skip until moov;
			if(fread(&tmp,4,1,fp) < 1) goto end;
			if(fread(atom,1,4,fp) < 4) goto end;
			tmp = SWAP32(tmp);
			if(!memcmp(atom,"moov",4)) break;
			if(!memcmp(atom,"mdat",4)) moov_after_mdat = YES;
			if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
		}
		
		if(fseeko(fp,-8,SEEK_CUR) != 0) goto end;
		
		/* update moov atom size */
		if(fread(&tmp,4,1,fp) < 1) goto end;
		int moovSize = SWAP32(tmp);
		if(fseeko(fp,-4,SEEK_CUR) != 0) goto end;
		tmp = moovSize + udatSize;
		tmp = SWAP32(tmp);
		if(fwrite(&tmp,4,1,fp) < 1) goto end;
		
		off_t pos_moov = ftello(fp);
		
		if(fseeko(fp,4,SEEK_CUR) != 0) goto end;
		
		while(1) { //skip until trak;
			if(fread(&tmp,4,1,fp) < 1) goto end;
			if(fread(atom,1,4,fp) < 4) goto end;
			tmp = SWAP32(tmp);
			if(!memcmp(atom,"trak",4)) break;
			if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
		}
		
		if(moov_after_mdat) {
			if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
			goto beginWrite;
		}
		
		while(1) { //skip until mdia;
			if(fread(&tmp,4,1,fp) < 1) goto end;
			if(fread(atom,1,4,fp) < 4) goto end;
			tmp = SWAP32(tmp);
			if(!memcmp(atom,"mdia",4)) break;
			if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
		}
		
		while(1) { //skip until minf;
			if(fread(&tmp,4,1,fp) < 1) goto end;
			if(fread(atom,1,4,fp) < 4) goto end;
			tmp = SWAP32(tmp);
			if(!memcmp(atom,"minf",4)) break;
			if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
		}
		
		while(1) { //skip until stbl;
			if(fread(&tmp,4,1,fp) < 1) goto end;
			if(fread(atom,1,4,fp) < 4) goto end;
			tmp = SWAP32(tmp);
			if(!memcmp(atom,"stbl",4)) break;
			if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
		}
		
		while(1) { //skip until stco;
			if(fread(&tmp,4,1,fp) < 1) goto end;
			if(fread(atom,1,4,fp) < 4) goto end;
			tmp = SWAP32(tmp);
			if(!memcmp(atom,"stco",4)) break;
			if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
		}
		
		int *stco = (int *)malloc(tmp-8);
		if(fread(stco,1,tmp-8,fp) < tmp-8) goto end;
		int nElement = SWAP32(stco[1]);
		
		/* update stco atom */
		
		int i;
		for(i=0;i<nElement;i++) {
			stco[2+i] = SWAP32(SWAP32(stco[2+i])+udatSize);
		}
		if(fseeko(fp,8-tmp,SEEK_CUR) != 0) goto end;
		if(fwrite(stco,1,tmp-8,fp) < tmp-8) goto end;
		
		free(stco);
		
		/* write tags */
beginWrite:
		if(fseeko(fp,pos_moov,SEEK_SET) != 0) goto end;
		if(fseeko(fp,moovSize-4,SEEK_CUR) != 0) goto end;
		off_t pos_tag = ftello(fp);
		
		
		//if(fseek(fp,0-udatSize,SEEK_END) != 0) goto end;
		
		int bytesToMove = origSize-pos_tag;
		if(bytesToMove == 0) goto write;
		
		if(bytesToMove < udatSize) {
			if(fread(read,1,bytesToMove,fp) < bytesToMove) goto end;
			if(fwrite(read,1,udatSize-bytesToMove,fp) < udatSize-bytesToMove) goto end;
			if(fwrite(read,1,bytesToMove,fp) < bytesToMove) goto end;
		}
		else if(bytesToMove > bufferSize) {
			if(bufferSize < udatSize) {
				tmpbuf = (char *)realloc(tmpbuf,udatSize);
				tmpbuf2 = (char *)realloc(tmpbuf2,udatSize);
				read = tmpbuf;
				write = tmpbuf2;
				bufferSize = udatSize;
				if(bytesToMove <= bufferSize) goto moveBlock_is_smaller_than_buffer;
			}
			if(fread(write,1,bufferSize,fp) < bufferSize) goto end;
			bytesToMove -= bufferSize;
			while(bytesToMove > bufferSize) {
				if(fread(read,1,bufferSize,fp) < bufferSize) goto end;
				if(fseeko(fp,udatSize-2*bufferSize,SEEK_CUR) != 0) goto end;
				if(fwrite(write,1,bufferSize,fp) < bufferSize) goto end;
				if(fseeko(fp,bufferSize-udatSize,SEEK_CUR) != 0) goto end;
				swap = read;
				read = write;
				write = swap;
				bytesToMove -= bufferSize;
			}
			if(fread(read,1,bytesToMove,fp) < bytesToMove) goto end;
			if(fseeko(fp,udatSize-bufferSize-bytesToMove,SEEK_CUR) != 0) goto end;
			if(fwrite(write,1,bufferSize,fp) < bufferSize) goto end;
			if(fwrite(read,1,bytesToMove,fp) < bytesToMove) goto end;
		}
		else {
moveBlock_is_smaller_than_buffer:
			if(fread(read,1,bytesToMove,fp) < bytesToMove) goto end;
			if(udatSize < bytesToMove) {
				if(fseeko(fp,udatSize-bytesToMove,SEEK_CUR) != 0) goto end;
			}
			else {
				if(fseeko(fp,0-bytesToMove,SEEK_CUR) != 0) goto end;
				if(fwrite([tagData bytes],1,udatSize,fp) < udatSize) goto end;
			}
			if(fwrite(read,1,bytesToMove,fp) < bytesToMove) goto end;
		}
		
		if(fseeko(fp,pos_tag,SEEK_SET) != 0) goto end;
write:
		if(fwrite([tagData bytes],1,udatSize,fp) < udatSize) goto end;
		
end:
		free(tmpbuf);
		free(tmpbuf2);
		fclose(fp);
	}
}

- (void)closeFile
{
	if(task) [task release];
	task = nil;
	if(path) [path release];
	path = nil;
	[tagData setLength:0];
}

- (void)setEnableAddTag:(BOOL)flag
{
	if(![[configurations objectForKey:@"UseMP4"] boolValue]) addTag = NO;
	else addTag = flag;
}

@end
