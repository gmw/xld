//
//  XLDDDPParser.m
//  XLD
//
//  Created by tmkk on 09/03/13.
//  Copyright 2009 tmkk. All rights reserved.
//

#import "XLDDDPParser.h"
#import "XLDTrack.h"

struct ddpms_s
{
	char PREFIX[4];
	char DST[2];
	char DSP[8];
	char DSL[8];
	char DSS[8];
	char SUB[8];
	char CDM[2];
	char SSM[1];
	char SCR[1];
	char PRE1[4];
	char PRE2[4];
	char PST[4];
	char MED[1];
	char TRK[2];
	char IDX[2];
	char ISRC[12];
	char DUMMY[3];
	char DSI[17];
	char NEW[1];
	char PRE1NXT[4];
	char PAUSEADD[8];
	char OFS[9];
	char PAD[15];
} __attribute__ ((packed));

typedef struct ddpms_s ddpms_t;

struct ddppq_s
{
	char PREFIX[4];
	char TRK[2];
	char IDX[2];
	char HRS[2];
	char MIN[2];
	char SEC[2];
	char FRM[2];
	char CB1[2];
	char CB2[2];
	char ISRC[12];
	char UPC[13];
	char TXT[19];
} __attribute__ ((packed));

typedef struct ddppq_s ddppq_t;

struct cdtext_s
{
	unsigned char type;
	unsigned char track;
	unsigned char packet_no;
	unsigned char flags;
	unsigned char text[12];
	unsigned short crc16;
} __attribute__ ((packed));

typedef struct cdtext_s cdtext_t;

static const char *cdtext_genres[] =
{
	"Not Used",
	"Not Defined",
	"Adult Contemporary",
	"Alternative Rock",
	"Childrens' Music",
	"Classical",
	"Contemporary Christian",
	"Country",
	"Dance",
	"Easy Listening",
	"Erotic",
	"Folk",
	"Gospel",
	"Hip Hop",
	"Jazz",
	"Latin",
	"Musical",
	"New Age",
	"Opera",
	"Operetta",
	"Pop Music",
	"Rap",
	"Reggae",
	"Rock Music",
	"Rhythm & Blues",
	"Sound Effects",
	"Spoken Word",
	"World Music",
};

static xldoffset_t timeToFrame(int min, int sec, int sector, int samplerate)
{
	xldoffset_t ret;
	ret = (xldoffset_t)min*60*samplerate;
	ret += (xldoffset_t)sec*samplerate;
	ret += (xldoffset_t)sector*samplerate/75;
	return ret;
}

static void appendCDText(int track, int type, const char *data, int length, NSStringEncoding encoding, NSArray *tracks)
{
	if(track < 0 || track > [tracks count]) return;
	if(length <= 0) return;
	NSString *key;
	if(type == 0x80) key = XLD_METADATA_TITLE;
	else if(type == 0x81) key = XLD_METADATA_ARTIST;
	else if(type == 0x83) key = XLD_METADATA_COMPOSER;
	else if(type == 0x8e) {
		if(length != 12 || !memcmp(data, "000000000000", 12)) return;
		key = XLD_METADATA_ISRC;
		encoding = NSISOLatin1StringEncoding;
	}
	else return;
	if(track == 0) {
		if(type == 0x80) key = XLD_METADATA_ALBUM;
		else if(type == 0x81) key = XLD_METADATA_ALBUMARTIST;
		else if(type == 0x83) key = XLD_METADATA_COMPOSER;
		else return;
	}
	NSString *str = nil;
	if((length == 1 && data[0] == '\t') || (length == 2 && data[0] == '\t' && data[1] == '\t')) {
		if(track > 1) str = [[[[tracks objectAtIndex:track-2] metadata] objectForKey:key] copy];
		else if(track == 1) {
			if(type == 0x80) str = [[[[tracks objectAtIndex:0] metadata] objectForKey:XLD_METADATA_ALBUM] copy];
			else if(type == 0x81) str = [[[[tracks objectAtIndex:0] metadata] objectForKey:XLD_METADATA_ALBUMARTIST] copy];
		}
	}
	else str = [[NSString alloc] initWithBytes:data length:length encoding:encoding];
	if(!str) return;
	if(track != 0) {
		[[[tracks objectAtIndex:track-1] metadata] setObject:str forKey:key];
	}
	else {
		int i;
		for(i=0;i<[tracks count];i++) {
			[[[tracks objectAtIndex:i] metadata] setObject:str forKey:key];
		}
	}
	[str release];
}

@implementation XLDDDPParser

- (id)init
{
	[super init];
	return self;
}

- (void)dealloc
{
	if(dataFile) [dataFile release];
	if(pqDescrFile) [pqDescrFile release];
	if(cdtextFile) [cdtextFile release];
	[super dealloc];
}

- (int)getNumberInStr:(char *)str
{
	int i=0;
	while(*(str+i) == ' ') i++;
	if(*(str+i) == 0) return 0; //all spaces
	return atoi(str+i);
}

- (int)offsetBytes
{
	return offsetBytes;
}

- (NSString *)pcmFile
{
	return dataFile;
}

- (NSMutableArray *)trackListArray
{
	if(!pqDescrFile) return nil;
	ddppq_t ddppq;
	xldoffset_t gapIdx=0;
	char buf[32];
	char isrc[13];
	char mcn[14];
	isrc[12] = 0;
	mcn[13] = 0;
	int min,sec,frm;
	BOOL hasISRC = NO;
	BOOL hasMCN = NO;
	
	FILE *fp = fopen([pqDescrFile UTF8String], "rb");
	if(!fp) return nil;
	
	NSMutableArray *trackList = [[NSMutableArray alloc] init];
	
	while(fread(&ddppq, 1, 64, fp) == 64) {
		if(!memcmp(ddppq.TRK, "00", 2)) {
			if(memcmp(ddppq.UPC,"             ",13) && memcmp(ddppq.UPC,"0000000000000",13)) {
				memcpy(mcn,ddppq.UPC,13);
				hasMCN = YES;
			}
			continue;
		}
		else if(!memcmp(ddppq.TRK, "AA", 2)) break;
		else {
			if(!memcmp(ddppq.TRK, "01", 2) && !memcmp(ddppq.IDX, "00", 2)) {
				if(memcmp(ddppq.ISRC,"            ",12)) {
					memcpy(isrc,ddppq.ISRC,12);
					hasISRC = YES;
				}
				continue;
			}
			if(!memcmp(ddppq.IDX, "00", 2)) { // index 00
				memcpy(buf, ddppq.MIN, 2);
				buf[2] = 0;
				min = atoi(buf);
				memcpy(buf, ddppq.SEC, 2);
				buf[2] = 0;
				sec = atoi(buf);
				memcpy(buf, ddppq.FRM, 2);
				buf[2] = 0;
				frm = atoi(buf);
				gapIdx = timeToFrame(min,sec,frm,44100);
				gapIdx -= 88200;
				if(memcmp(ddppq.ISRC,"            ",12)) {
					memcpy(isrc,ddppq.ISRC,12);
					hasISRC = YES;
				}
			}
			else if(!memcmp(ddppq.IDX, "01", 2)) { //index 01
				XLDTrack *trk = [[XLDTrack alloc] init];
				memcpy(buf, ddppq.MIN, 2);
				buf[2] = 0;
				min = atoi(buf);
				memcpy(buf, ddppq.SEC, 2);
				buf[2] = 0;
				sec = atoi(buf);
				memcpy(buf, ddppq.FRM, 2);
				buf[2] = 0;
				frm = atoi(buf);
				xldoffset_t idx = timeToFrame(min,sec,frm,44100);
				idx -= 88200;
				
				[trk setIndex:idx];
				if(gapIdx != -1) [trk setGap:idx-gapIdx];
				if(hasISRC) {
					[[trk metadata] setObject:[NSString stringWithUTF8String:isrc] forKey:XLD_METADATA_ISRC];
				}
				else {
					if(memcmp(ddppq.ISRC,"            ",12)) {
						memcpy(isrc,ddppq.ISRC,12);
						[[trk metadata] setObject:[NSString stringWithUTF8String:isrc] forKey:XLD_METADATA_ISRC];
					}
				}
				if(hasMCN) {
					[[trk metadata] setObject:[NSString stringWithUTF8String:mcn] forKey:XLD_METADATA_CATALOG];
				}
				[trackList addObject:trk];
				[trk release];
				
				if([trackList count] > 1) {
					XLDTrack *trk2 = [trackList objectAtIndex:[trackList count]-2];
					if(gapIdx != -1) [trk2 setFrames:gapIdx-[trk2 index]];
					else [trk2 setFrames:idx-[trk2 index]];
				}
				gapIdx = -1;
				hasISRC = NO;
			}
		}
	}
	fclose(fp);
	
	if(cdtextFile) {
		fp = fopen([cdtextFile UTF8String], "rb");
		if(fp) {
			NSStringEncoding currentEncoding = 0;
			cdtext_t text;
			while(1) {
				int ret = fread(&text,1,18,fp);
				if(ret < 18) break;
				if(text.type == 0x8f && text.track == 0 && (text.flags & 0x70) == 0) {
					if(text.text[0] == 0) currentEncoding = NSISOLatin1StringEncoding;
					else if(text.text[0] == 1) currentEncoding = NSASCIIStringEncoding;
					else if(text.text[0] == 0x80) currentEncoding = NSShiftJISStringEncoding;
					break;
				}
			}
			if(!currentEncoding) goto end;
			
			rewind(fp);
			int currentType = -1;
			int currentTrack = -1;
			char buffer[256];
			int pos = 0;
			while(1) {
				int ret = fread(&text,1,18,fp);
				if(ret < 18) break;
				if((text.flags & 0x70) != 0) continue;
				if((currentType > 0 && currentType != text.type) || (currentTrack > 0 && currentTrack != text.track)) {
					appendCDText(currentTrack, currentType, buffer, pos, currentEncoding, trackList);
					pos = 0;
				}
				currentType = text.type;
				currentTrack = text.track;
				if((currentType >= 0x80 && currentType < 0x86) || currentType == 0x8e) {
					int i;
					if(text.flags & 0x80) {
						for(i=0;i<12;i+=2) {
							buffer[pos++] = text.text[i];
							buffer[pos++] = text.text[i+1];
							if(!text.text[i] && !text.text[i+1]) {
								appendCDText(currentTrack, currentType, buffer, pos-2, currentEncoding, trackList);
								pos = 0;
								currentTrack++;
							}
						}
					}
					else {
						for(i=0;i<12;i++) {
							buffer[pos++] = text.text[i];
							if(!text.text[i]) {
								appendCDText(currentTrack, currentType, buffer, pos-1, currentEncoding, trackList);
								pos = 0;
								currentTrack++;
							}
						}
					}
				}
				else if(currentType == 0x87) {
					unsigned short genre = (text.text[0] << 8) | text.text[1];
					if(genre > 0x01 && genre <= 0x1b) {
						appendCDText(currentTrack, currentType, cdtext_genres[genre], strlen(cdtext_genres[genre]), NSASCIIStringEncoding, trackList);
					}
					/*else if(genre == 0x01) {
						appendCDText(currentTrack, currentType, (char *)text.text+2, strlen((char *)text.text+2), NSISOLatin1StringEncoding, trackList);
					}*/
				}
			}
end:
			fclose(fp);
		}
	}
	
	return [trackList autorelease];
}

- (BOOL)openDDPMS:(NSString *)path
{
	char buf[32];
	ddpms_t ddpms;
	FILE *fp = fopen([path UTF8String], "rb");
	if(!fp) return NO;
	
	while(fread(&ddpms, 1, 128, fp) == 128) {
		if(memcmp(ddpms.PREFIX, "VVVM", 4)) {
			fclose(fp);
			return NO;
		}
		else if(!memcmp(ddpms.DST, "D0", 2)) {
			if(memcmp(ddpms.CDM, "DA", 2)) continue;
			if(dataFile) { // multiple D0 (not supported)
				fclose(fp);
				return NO;
			}
			memcpy(buf, ddpms.DSS, 8);
			buf[8] = 0;
			offsetBytes = [self getNumberInStr:buf];
			//NSLog(@"%d",offsetBytes);
			if(offsetBytes > 150) offsetBytes = 0;
			else offsetBytes = (150 - offsetBytes)*2352;
			//NSLog(@"%d",offsetBytes);
			
			memcpy(buf, ddpms.DSI, 17);
			buf[17] = 0;
			//NSLog(@"%s",buf);
			int i=0;
			while(*(buf+i) != ' ' && *(buf+i) != 0) i++;
			*(buf+i) = 0;
			dataFile = [[[path stringByDeletingLastPathComponent] stringByAppendingPathComponent:[NSString stringWithUTF8String:buf]] retain];
		}
		else if(!memcmp(ddpms.DST, "S0", 2)) {
			if(memcmp(ddpms.SUB, "PQ DESCR", 8) && memcmp(ddpms.SUB, "CDTEXT", 6)) continue;
			if(*ddpms.SUB == 'P' && pqDescrFile) { // multiple PQ DESCR (not supported)
				fclose(fp);
				return NO;
			}
			memcpy(buf, ddpms.DSI, 17);
			buf[17] = 0;
			//NSLog(@"%s",buf);
			int i=0;
			while(*(buf+i) != ' ' && *(buf+i) != 0) i++;
			*(buf+i) = 0;
			if(*ddpms.SUB == 'P')
				pqDescrFile = [[[path stringByDeletingLastPathComponent] stringByAppendingPathComponent:[NSString stringWithUTF8String:buf]] retain];
			else 
				cdtextFile = [[[path stringByDeletingLastPathComponent] stringByAppendingPathComponent:[NSString stringWithUTF8String:buf]] retain];
		}
	}
	fclose(fp);
	if(!pqDescrFile || !dataFile) {
		if(dataFile) [dataFile release];
		if(pqDescrFile) [pqDescrFile release];
		if(cdtextFile) [cdtextFile release];
		dataFile = nil;
		pqDescrFile = nil;
		cdtextFile = nil;
		return NO;
	}
	NSFileManager *fm = [NSFileManager defaultManager];
	if(![fm fileExistsAtPath:dataFile] || ![fm fileExistsAtPath:pqDescrFile]) {
		if(dataFile) [dataFile release];
		if(pqDescrFile) [pqDescrFile release];
		if(cdtextFile) [cdtextFile release];
		dataFile = nil;
		pqDescrFile = nil;
		cdtextFile = nil;
		return NO;
	}
	if(!cdtextFile) {
		cdtextFile = [[[path stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"CDTEXT.BIN"] retain];
		if(![fm fileExistsAtPath:cdtextFile]) {
			[cdtextFile release];
			cdtextFile = nil;
		}
	}
	//NSLog(dataFile);
	//NSLog(pqDescrFile);
	return YES;
}


@end
