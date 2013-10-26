//
//  XLDCCDLoader.m
//  XLD
//
//  Created by tmkk on 13/10/11.
//  Copyright 2013 tmkk. All rights reserved.
//

#import "XLDCCDLoader.h"
#import "XLDTrack.h"

static char *fgets_private(char *buf, int size, FILE *fp)
{
	int i;
	char c;
	
	for(i=0;i<size-1;) {
		if(fread(&c,1,1,fp) != 1) {
			break;
		}
		buf[i++] = c;
		if(c == '\n' || c == '\r') {
			break;
		}
	}
	if(i==0) return NULL;
	buf[i] = 0;
	return buf;
}

@implementation XLDCCDLoader

- (id)init
{
	self = [super init];
	if(!self) return nil;
	trackList = [[NSMutableArray alloc] init];
	return self;
}

- (void)dealloc
{
	[pcmFile release];
	[trackList release];
	[super dealloc];
}

- (BOOL)openFile:(NSString *)ccdFile
{
	FILE *fp = fopen([ccdFile UTF8String], "rb");
	if(!fp) return NO;
	char buf[1024];
	if(fgets_private(buf, 1024, fp) == NULL) {
		goto last;
	}
	if(strncmp(buf,"[CloneCD]",9)) goto last;
	
	NSString *imgFile = [[ccdFile stringByDeletingPathExtension] stringByAppendingPathExtension:@"img"];
	FILE *fpImg = fopen([imgFile UTF8String], "rb");
	if(!fpImg) {
		imgFile = [[ccdFile stringByDeletingPathExtension] stringByAppendingPathExtension:@"bin"];
		fpImg = fopen([imgFile UTF8String], "rb");
		if(!fpImg) {
			goto last;
		}
	}
	pcmFile = [imgFile retain];
	
	fseeko(fpImg,0,SEEK_END);
	fclose(fpImg);
	NSMutableDictionary *tracks = [NSMutableDictionary dictionary];
	int maxTrackNumber = -1;
	while(fgets_private(buf, 1024, fp)) {
		if(!strncasecmp(buf,"[TRACK",6)) {
			int trackNum;
			char *ptr = buf+6;
			while(*ptr == ' ' || *ptr == '\t') ptr++;
			trackNum = atoi(ptr);
			if(trackNum > maxTrackNumber) maxTrackNumber = trackNum;
			int mode = -1;
			int index0 = -1;
			int index1 = -1;
			while(fgets_private(buf, 1024, fp)) {
				if(!strncasecmp(buf,"MODE=",5)) {
					ptr = buf+5;
					mode = atoi(ptr);
				}
				else if(!strncasecmp(buf,"INDEX",5)) {
					ptr = buf+5;
					while(*ptr == ' ' || *ptr == '\t') ptr++;
					int idx = strtol(ptr,&ptr,10);
					while(*ptr != '=' && *ptr != 0) ptr++;
					if(*ptr != 0) {
						ptr++;
						if(idx == 0) index0 = atoi(ptr);
						else if(idx == 1) index1 = atoi(ptr);
					}
				}
				else if(buf[0] == '[') {
					fseeko(fp, ftello(fp)-strlen(buf), SEEK_SET);
					break;
				}
			}
			if(mode < 0 || index1 < 0) continue;
			XLDTrack *track = [[XLDTrack alloc] init];
			[track setIndex:index1*588];
			if(index0 > 0) [track setGap:(index1 - index0)*588];
			if(mode != 0) {
				[track setEnabled:NO];
				[[track metadata] setObject:[NSNumber numberWithBool:YES] forKey:XLD_METADATA_DATATRACK];
			}
			[tracks setObject:track forKey:[NSNumber numberWithInt:trackNum]];
			[track release];
		}
	}
	if(maxTrackNumber != [[tracks allKeys] count]) goto last;
	if(![tracks objectForKey:[NSNumber numberWithInt:1]]) goto last;
	int i;
	for(i=1;i<=maxTrackNumber;i++) {
		XLDTrack *track = [tracks objectForKey:[NSNumber numberWithInt:i]];
		XLDTrack *nextTrack = [tracks objectForKey:[NSNumber numberWithInt:i+1]];
		if(!track) goto last;
		if(nextTrack) {
			if(![nextTrack enabled])
				[track setFrames:[nextTrack index] - [track index] - 588*11400];
			else
				[track setFrames:[nextTrack index] - [track index] - [nextTrack gap]];
		}
		[trackList addObject:track];
	}
	//NSLog(@"%@",[trackList description]);
	fclose(fp);
	return YES;
last:
	fclose(fp);
	return NO;
}

- (NSMutableArray *)trackList
{
	return trackList;
}

- (NSString *)pcmFile
{
	return pcmFile;
}

@end
