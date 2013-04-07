#import <Foundation/Foundation.h>
#import "XLDWavpackDecoder.h"
/*
WavpackContext *WavpackOpenFileInput (const char *infilename, char *error, int flags, int norm_offset);
uint32_t WavpackUnpackSamples (WavpackContext *wpc, int32_t *buffer, uint32_t samples);
uint32_t WavpackGetNumSamples (WavpackContext *wpc);
int WavpackGetBytesPerSample (WavpackContext *wpc);
int WavpackGetNumChannels (WavpackContext *wpc);
WavpackContext *WavpackCloseFile (WavpackContext *wpc);
int WavpackSeekSample (WavpackContext *wpc, uint32_t sample);
uint32_t WavpackGetSampleRate (WavpackContext *wpc);
int WavpackGetNumErrors (WavpackContext *wpc);
int WavpackGetNumTagItems (WavpackContext *wpc);
int WavpackGetTagItem (WavpackContext *wpc, const char *item, char *value, int size);
int WavpackGetTagItemIndexed (WavpackContext *wpc, int index, char *item, int size);
*/
@implementation XLDWavpackDecoder

+ (BOOL)canHandleFile:(char *)path
{
	char err[256];
	WavpackContext *wc_tmp = WavpackOpenFileInput(path,err,3,0);
	if(wc_tmp == NULL) return NO;
	if(WavpackGetNumErrors(wc_tmp)) return NO;
	WavpackCloseFile(wc_tmp);
	return YES;
}

+ (BOOL)canLoadThisBundle
{
	if (floor(NSAppKitVersionNumber) <= 620 ) {
		return NO;
	}
	else return YES;
}

- (id)init
{
	[super init];
	wc = NULL;
	error = NO;
	cueData = nil;
	metadataDic = [[NSMutableDictionary alloc] init];
	srcPath = nil;
	return self;
}

- (BOOL)openFile:(char *)path
{
	wc = WavpackOpenFileInput(path,errstr,0x2|0x1,0);
	if(!wc || WavpackGetNumErrors(wc)) {
		if(wc) WavpackCloseFile(wc);
		wc = NULL;
		error = YES;
		return NO;
	}
	bps = WavpackGetBytesPerSample(wc);
	channels = WavpackGetNumChannels(wc);
	samplerate = WavpackGetSampleRate(wc);
	totalFrames = WavpackGetNumSamples(wc);
	//isFloat = ((wc->config.flags)&0x80)>>7;
	isFloat = (WavpackGetMode(wc) & 0x8) >> 3;
	
	int i,idx;
	char tagIdx[256];
	idx = WavpackGetNumTagItems(wc);
	for(i=0;i<idx;i++) {
		WavpackGetTagItemIndexed(wc, i, tagIdx, 255);
		if(!strcasecmp(tagIdx,"cuesheet")) {
			int size = WavpackGetTagItem(wc, tagIdx, NULL, 0);
			char *buf = (char *)malloc(size+10);
			WavpackGetTagItem(wc, tagIdx, buf, size+10);
			cueData = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:size] encoding:NSUTF8StringEncoding];
			if(cueData) {
				[metadataDic setObject:cueData forKey:XLD_METADATA_CUESHEET];
			}
			free(buf);
		}
		else if(!strcasecmp(tagIdx,"title")) {
			int size = WavpackGetTagItem(wc, tagIdx, NULL, 0);
			char *buf = (char *)malloc(size+10);
			WavpackGetTagItem(wc, tagIdx, buf, size+10);
			NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:size] encoding:NSUTF8StringEncoding];
			if(str) {
				[metadataDic setObject:str forKey:XLD_METADATA_TITLE];
				[str release];
			}
			free(buf);
		}
		else if(!strcasecmp(tagIdx,"artist")) {
			int size = WavpackGetTagItem(wc, tagIdx, NULL, 0);
			char *buf = (char *)malloc(size+10);
			WavpackGetTagItem(wc, tagIdx, buf, size+10);
			NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:size] encoding:NSUTF8StringEncoding];
			if(str) {
				[metadataDic setObject:str forKey:XLD_METADATA_ARTIST];
				[str release];
			}
			free(buf);
		}
		else if(!strcasecmp(tagIdx,"album")) {
			int size = WavpackGetTagItem(wc, tagIdx, NULL, 0);
			char *buf = (char *)malloc(size+10);
			WavpackGetTagItem(wc, tagIdx, buf, size+10);
			NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:size] encoding:NSUTF8StringEncoding];
			if(str) {
				[metadataDic setObject:str forKey:XLD_METADATA_ALBUM];
				[str release];
			}
			free(buf);
		}
		else if(!strcasecmp(tagIdx,"album artist")) {
			int size = WavpackGetTagItem(wc, tagIdx, NULL, 0);
			char *buf = (char *)malloc(size+10);
			WavpackGetTagItem(wc, tagIdx, buf, size+10);
			NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:size] encoding:NSUTF8StringEncoding];
			if(str) {
				[metadataDic setObject:str forKey:XLD_METADATA_ALBUMARTIST];
				[str release];
			}
			free(buf);
		}
		else if(!strcasecmp(tagIdx,"albumartist")) {
			int size = WavpackGetTagItem(wc, tagIdx, NULL, 0);
			char *buf = (char *)malloc(size+10);
			WavpackGetTagItem(wc, tagIdx, buf, size+10);
			NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:size] encoding:NSUTF8StringEncoding];
			if(str) {
				if(![metadataDic objectForKey:XLD_METADATA_ALBUMARTIST])
					[metadataDic setObject:str forKey:XLD_METADATA_ALBUMARTIST];
				[str release];
			}
			free(buf);
		}
		else if(!strcasecmp(tagIdx,"genre")) {
			int size = WavpackGetTagItem(wc, tagIdx, NULL, 0);
			char *buf = (char *)malloc(size+10);
			WavpackGetTagItem(wc, tagIdx, buf, size+10);
			NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:size] encoding:NSUTF8StringEncoding];
			if(str) {
				[metadataDic setObject:str forKey:XLD_METADATA_GENRE];
				[str release];
			}
			free(buf);
		}
		else if(!strcasecmp(tagIdx,"year")) {
			int size = WavpackGetTagItem(wc, tagIdx, NULL, 0);
			char *buf = (char *)malloc(size+10);
			WavpackGetTagItem(wc, tagIdx, buf, size+10);
			NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:size] encoding:NSUTF8StringEncoding];
			if(str) {
				int year = [str intValue];
				if(year >= 1000 && year < 3000) [metadataDic setObject:[NSNumber numberWithInt:year] forKey:XLD_METADATA_YEAR];
				[str release];
			}
			free(buf);
		}
		else if(!strcasecmp(tagIdx,"composer")) {
			int size = WavpackGetTagItem(wc, tagIdx, NULL, 0);
			char *buf = (char *)malloc(size+10);
			WavpackGetTagItem(wc, tagIdx, buf, size+10);
			NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:size] encoding:NSUTF8StringEncoding];
			if(str) {
				[metadataDic setObject:str forKey:XLD_METADATA_COMPOSER];
				[str release];
			}
			free(buf);
		}
		else if(!strcasecmp(tagIdx,"track")) {
			int size = WavpackGetTagItem(wc, tagIdx, NULL, 0);
			char *buf = (char *)malloc(size+10);
			WavpackGetTagItem(wc, tagIdx, buf, size+10);
			NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:size] encoding:NSUTF8StringEncoding];
			if(str) {
				int track = [str intValue];
				if(track > 0) [metadataDic setObject:[NSNumber numberWithInt:track] forKey:XLD_METADATA_TRACK];
				if([str rangeOfString:@"/"].location != NSNotFound) {
					track = [[str substringFromIndex:[str rangeOfString:@"/"].location+1] intValue];
					if(track > 0) [metadataDic setObject:[NSNumber numberWithInt:track] forKey:XLD_METADATA_TOTALTRACKS];
				}
				[str release];
			}
			free(buf);
		}
		else if(!strcasecmp(tagIdx,"disc") || !strcasecmp(tagIdx,"discnumber")) {
			int size = WavpackGetTagItem(wc, tagIdx, NULL, 0);
			char *buf = (char *)malloc(size+10);
			WavpackGetTagItem(wc, tagIdx, buf, size+10);
			NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:size] encoding:NSUTF8StringEncoding];
			if(str) {
				int disc = [str intValue];
				if(disc > 0) [metadataDic setObject:[NSNumber numberWithInt:disc] forKey:XLD_METADATA_DISC];
				if([str rangeOfString:@"/"].location != NSNotFound) {
					disc = [[str substringFromIndex:[str rangeOfString:@"/"].location+1] intValue];
					if(disc > 0) [metadataDic setObject:[NSNumber numberWithInt:disc] forKey:XLD_METADATA_TOTALDISCS];
				}
				[str release];
			}
			free(buf);
		}
		else if(!strcasecmp(tagIdx,"comment")) {
			int size = WavpackGetTagItem(wc, tagIdx, NULL, 0);
			char *buf = (char *)malloc(size+10);
			WavpackGetTagItem(wc, tagIdx, buf, size+10);
			NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:size] encoding:NSUTF8StringEncoding];
			if(str) {
				[metadataDic setObject:str forKey:XLD_METADATA_COMMENT];
				[str release];
			}
			free(buf);
		}
		else if(!strcasecmp(tagIdx,"lyrics")) {
			int size = WavpackGetTagItem(wc, tagIdx, NULL, 0);
			char *buf = (char *)malloc(size+10);
			WavpackGetTagItem(wc, tagIdx, buf, size+10);
			NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:size] encoding:NSUTF8StringEncoding];
			if(str) {
				[metadataDic setObject:str forKey:XLD_METADATA_LYRICS];
				[str release];
			}
			free(buf);
		}
		else if(!strcasecmp(tagIdx,"ISRC")) {
			int size = WavpackGetTagItem(wc, tagIdx, NULL, 0);
			char *buf = (char *)malloc(size+10);
			WavpackGetTagItem(wc, tagIdx, buf, size+10);
			NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:size] encoding:NSUTF8StringEncoding];
			if(str) {
				[metadataDic setObject:str forKey:XLD_METADATA_ISRC];
				[str release];
			}
			free(buf);
		}
		else if(!strcasecmp(tagIdx,"iTunes_CDDB_1")) {
			int size = WavpackGetTagItem(wc, tagIdx, NULL, 0);
			char *buf = (char *)malloc(size+10);
			WavpackGetTagItem(wc, tagIdx, buf, size+10);
			NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:size] encoding:NSUTF8StringEncoding];
			if(str) {
				[metadataDic setObject:str forKey:XLD_METADATA_GRACENOTE2];
				[str release];
			}
			free(buf);
		}
		else if(!strcasecmp(tagIdx,"MUSICBRAINZ_TRACKID")) {
			int size = WavpackGetTagItem(wc, tagIdx, NULL, 0);
			char *buf = (char *)malloc(size+10);
			WavpackGetTagItem(wc, tagIdx, buf, size+10);
			NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:size] encoding:NSUTF8StringEncoding];
			if(str) {
				[metadataDic setObject:str forKey:XLD_METADATA_MB_TRACKID];
				[str release];
			}
			free(buf);
		}
		else if(!strcasecmp(tagIdx,"MUSICBRAINZ_ALBUMID")) {
			int size = WavpackGetTagItem(wc, tagIdx, NULL, 0);
			char *buf = (char *)malloc(size+10);
			WavpackGetTagItem(wc, tagIdx, buf, size+10);
			NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:size] encoding:NSUTF8StringEncoding];
			if(str) {
				[metadataDic setObject:str forKey:XLD_METADATA_MB_ALBUMID];
				[str release];
			}
			free(buf);
		}
		else if(!strcasecmp(tagIdx,"MUSICBRAINZ_ARTISTID")) {
			int size = WavpackGetTagItem(wc, tagIdx, NULL, 0);
			char *buf = (char *)malloc(size+10);
			WavpackGetTagItem(wc, tagIdx, buf, size+10);
			NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:size] encoding:NSUTF8StringEncoding];
			if(str) {
				[metadataDic setObject:str forKey:XLD_METADATA_MB_ARTISTID];
				[str release];
			}
			free(buf);
		}
		else if(!strcasecmp(tagIdx,"MUSICBRAINZ_ALBUMARTISTID")) {
			int size = WavpackGetTagItem(wc, tagIdx, NULL, 0);
			char *buf = (char *)malloc(size+10);
			WavpackGetTagItem(wc, tagIdx, buf, size+10);
			NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:size] encoding:NSUTF8StringEncoding];
			if(str) {
				[metadataDic setObject:str forKey:XLD_METADATA_MB_ALBUMARTISTID];
				[str release];
			}
			free(buf);
		}
		else if(!strcasecmp(tagIdx,"MUSICBRAINZ_DISCID")) {
			int size = WavpackGetTagItem(wc, tagIdx, NULL, 0);
			char *buf = (char *)malloc(size+10);
			WavpackGetTagItem(wc, tagIdx, buf, size+10);
			NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:size] encoding:NSUTF8StringEncoding];
			if(str) {
				[metadataDic setObject:str forKey:XLD_METADATA_MB_DISCID];
				[str release];
			}
			free(buf);
		}
		else if(!strcasecmp(tagIdx,"MUSICIP_PUID")) {
			int size = WavpackGetTagItem(wc, tagIdx, NULL, 0);
			char *buf = (char *)malloc(size+10);
			WavpackGetTagItem(wc, tagIdx, buf, size+10);
			NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:size] encoding:NSUTF8StringEncoding];
			if(str) {
				[metadataDic setObject:str forKey:XLD_METADATA_PUID];
				[str release];
			}
			free(buf);
		}
		else if(!strcasecmp(tagIdx,"MUSICBRAINZ_ALBUMSTATUS")) {
			int size = WavpackGetTagItem(wc, tagIdx, NULL, 0);
			char *buf = (char *)malloc(size+10);
			WavpackGetTagItem(wc, tagIdx, buf, size+10);
			NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:size] encoding:NSUTF8StringEncoding];
			if(str) {
				[metadataDic setObject:str forKey:XLD_METADATA_MB_ALBUMSTATUS];
				[str release];
			}
			free(buf);
		}
		else if(!strcasecmp(tagIdx,"MUSICBRAINZ_ALBUMTYPE")) {
			int size = WavpackGetTagItem(wc, tagIdx, NULL, 0);
			char *buf = (char *)malloc(size+10);
			WavpackGetTagItem(wc, tagIdx, buf, size+10);
			NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:size] encoding:NSUTF8StringEncoding];
			if(str) {
				[metadataDic setObject:str forKey:XLD_METADATA_MB_ALBUMTYPE];
				[str release];
			}
			free(buf);
		}
		else if(!strcasecmp(tagIdx,"RELEASECOUNTRY")) {
			int size = WavpackGetTagItem(wc, tagIdx, NULL, 0);
			char *buf = (char *)malloc(size+10);
			WavpackGetTagItem(wc, tagIdx, buf, size+10);
			NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:size] encoding:NSUTF8StringEncoding];
			if(str) {
				[metadataDic setObject:str forKey:XLD_METADATA_MB_RELEASECOUNTRY];
				[str release];
			}
			free(buf);
		}
		else if(!strcasecmp(tagIdx,"MUSICBRAINZ_RELEASEGROUPID")) {
			int size = WavpackGetTagItem(wc, tagIdx, NULL, 0);
			char *buf = (char *)malloc(size+10);
			WavpackGetTagItem(wc, tagIdx, buf, size+10);
			NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:size] encoding:NSUTF8StringEncoding];
			if(str) {
				[metadataDic setObject:str forKey:XLD_METADATA_MB_RELEASEGROUPID];
				[str release];
			}
			free(buf);
		}
		else if(!strcasecmp(tagIdx,"MUSICBRAINZ_WORKID")) {
			int size = WavpackGetTagItem(wc, tagIdx, NULL, 0);
			char *buf = (char *)malloc(size+10);
			WavpackGetTagItem(wc, tagIdx, buf, size+10);
			NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:size] encoding:NSUTF8StringEncoding];
			if(str) {
				[metadataDic setObject:str forKey:XLD_METADATA_MB_WORKID];
				[str release];
			}
			free(buf);
		}
		else if(!strcasecmp(tagIdx,"REPLAYGAIN_TRACK_GAIN")) {
			int size = WavpackGetTagItem(wc, tagIdx, NULL, 0);
			char *buf = (char *)malloc(size+10);
			WavpackGetTagItem(wc, tagIdx, buf, size+10);
			NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:size] encoding:NSUTF8StringEncoding];
			if(str) {
				[metadataDic setObject:[NSNumber numberWithFloat:[str floatValue]] forKey:XLD_METADATA_REPLAYGAIN_TRACK_GAIN];
				[str release];
			}
			free(buf);
		}
		else if(!strcasecmp(tagIdx,"REPLAYGAIN_TRACK_PEAK")) {
			int size = WavpackGetTagItem(wc, tagIdx, NULL, 0);
			char *buf = (char *)malloc(size+10);
			WavpackGetTagItem(wc, tagIdx, buf, size+10);
			NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:size] encoding:NSUTF8StringEncoding];
			if(str) {
				[metadataDic setObject:[NSNumber numberWithFloat:[str floatValue]] forKey:XLD_METADATA_REPLAYGAIN_TRACK_PEAK];
				[str release];
			}
			free(buf);
		}
		else if(!strcasecmp(tagIdx,"REPLAYGAIN_ALBUM_GAIN")) {
			int size = WavpackGetTagItem(wc, tagIdx, NULL, 0);
			char *buf = (char *)malloc(size+10);
			WavpackGetTagItem(wc, tagIdx, buf, size+10);
			NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:size] encoding:NSUTF8StringEncoding];
			if(str) {
				[metadataDic setObject:[NSNumber numberWithFloat:[str floatValue]] forKey:XLD_METADATA_REPLAYGAIN_ALBUM_GAIN];
				[str release];
			}
			free(buf);
		}
		else if(!strcasecmp(tagIdx,"REPLAYGAIN_ALBUM_PEAK")) {
			int size = WavpackGetTagItem(wc, tagIdx, NULL, 0);
			char *buf = (char *)malloc(size+10);
			WavpackGetTagItem(wc, tagIdx, buf, size+10);
			NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:size] encoding:NSUTF8StringEncoding];
			if(str) {
				[metadataDic setObject:[NSNumber numberWithFloat:[str floatValue]] forKey:XLD_METADATA_REPLAYGAIN_ALBUM_PEAK];
				[str release];
			}
			free(buf);
		}
		else { //unknown text metadata
			int size = WavpackGetTagItem(wc, tagIdx, NULL, 0);
			char *buf = (char *)malloc(size+10);
			WavpackGetTagItem(wc, tagIdx, buf, size+10);
			NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buf length:size] encoding:NSUTF8StringEncoding];
			NSString *idx = [[NSString alloc] initWithData:[NSData dataWithBytes:tagIdx length:strlen(tagIdx)] encoding:NSUTF8StringEncoding];
			if(str && idx) {
				[metadataDic setObject:str forKey:[NSString stringWithFormat:@"XLD_UNKNOWN_TEXT_METADATA_%@",idx]];
			}
			if(str) [str release];
			if(idx) [idx release];
			free(buf);
		}
	}
	
	idx = WavpackGetNumBinaryTagItems(wc);
	for(i=0;i<idx;i++) {
		WavpackGetBinaryTagItemIndexed(wc, i, tagIdx, 255);
		if(!strcasecmp(tagIdx,"Cover Art (front)")) {
			int size = WavpackGetBinaryTagItem(wc, tagIdx, NULL, 0);
			char *buf = (char *)malloc(size+10);
			WavpackGetBinaryTagItem(wc, tagIdx, buf, size+10);
			int i=0;
			while(buf[i] != 0) i++;
			i++;
			if(size-i > 0) {
				NSData *imgData = [NSData dataWithBytes:buf+i length:size-i];
				if(imgData) [metadataDic setObject:imgData forKey:XLD_METADATA_COVER];
			}
			free(buf);
		}
	}
	
	if(srcPath) [srcPath release];
	srcPath = [[NSString alloc] initWithUTF8String:path];
	return YES;
}

- (void)dealloc
{
	if(wc) WavpackCloseFile(wc);
	if(cueData) [cueData release];
	[metadataDic release];
	if(srcPath) [srcPath release];
	[super dealloc];
}

- (int)samplerate
{
	return samplerate;
}

- (int)bytesPerSample
{
	return bps;
}

- (int)channels
{
	return channels;
}

- (xldoffset_t)totalFrames
{
	return totalFrames;
}

- (int)isFloat
{
	return isFloat;
}

- (int)decodeToBuffer:(int *)buffer frames:(int)count
{
	int i,j;
	int ret = WavpackUnpackSamples(wc,buffer,count);
	for(i=0;i<ret*channels;i++) {
		j = *(buffer+i);
		*(buffer+i) = j << (32-bps*8);
	}
	if(WavpackGetNumErrors(wc)) error = YES;
	return ret;
}

- (xldoffset_t)seekToFrame:(xldoffset_t)count
{
	xldoffset_t ret = WavpackSeekSample(wc,(unsigned int)count);
	if(WavpackGetNumErrors(wc)) error = YES;
	return ret;
}

- (void)closeFile;
{
	if(wc) WavpackCloseFile(wc);
	wc = NULL;
	if(cueData) [cueData release];
	cueData = nil;
	[metadataDic removeAllObjects];
	error = NO;
}

- (BOOL)error
{
	return error;
}

- (XLDEmbeddedCueSheetType)hasCueSheet
{
	if(cueData) return XLDTextTypeCueSheet;
	else return XLDNoCueSheet;
}

- (id)cueSheet
{
	return cueData;
}

- (id)metadata
{
	return metadataDic;
}

- (NSString *)srcPath
{
	return srcPath;
}

@end