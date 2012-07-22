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

static xldoffset_t timeToFrame(int min, int sec, int sector, int samplerate)
{
	xldoffset_t ret;
	ret = min*60*samplerate;
	ret += sec*samplerate;
	ret += sector*samplerate/75;
	return ret;
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
	
	return [trackList autorelease];
}

- (BOOL)openDDPMS:(NSString *)path
{
	char buf[32];
	ddpms_t ddpms;
	BOOL D0read = NO;
	BOOL S0read = NO;
	FILE *fp = fopen([path UTF8String], "rb");
	if(!fp) return NO;
	
	while(fread(&ddpms, 1, 128, fp) == 128) {
		if(memcmp(ddpms.PREFIX, "VVVM", 4)) {
			fclose(fp);
			return NO;
		}
		else if(!memcmp(ddpms.DST, "D0", 2)) {
			if(memcmp(ddpms.CDM, "DA", 2)) continue;
			if(D0read) { // multiple D0 (not supported)
				fclose(fp);
				return NO;
			}
			D0read = YES;
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
			if(memcmp(ddpms.SUB, "PQ DESCR", 8)) continue;
			if(S0read) { // multiple PQ DESCR (not supported)
				fclose(fp);
				return NO;
			}
			S0read = YES;
			
			memcpy(buf, ddpms.DSI, 17);
			buf[17] = 0;
			//NSLog(@"%s",buf);
			int i=0;
			while(*(buf+i) != ' ' && *(buf+i) != 0) i++;
			*(buf+i) = 0;
			pqDescrFile = [[[path stringByDeletingLastPathComponent] stringByAppendingPathComponent:[NSString stringWithUTF8String:buf]] retain];
		}
	}
	fclose(fp);
	if(!S0read || !D0read) {
		if(dataFile) [dataFile release];
		if(pqDescrFile) [pqDescrFile release];
		dataFile = nil;
		pqDescrFile = nil;
		return NO;
	}
	NSFileManager *fm = [NSFileManager defaultManager];
	if(![fm fileExistsAtPath:dataFile] || ![fm fileExistsAtPath:pqDescrFile]) {
		if(dataFile) [dataFile release];
		if(pqDescrFile) [pqDescrFile release];
		dataFile = nil;
		pqDescrFile = nil;
		return NO;
	}
	//NSLog(dataFile);
	//NSLog(pqDescrFile);
	return YES;
}


@end
