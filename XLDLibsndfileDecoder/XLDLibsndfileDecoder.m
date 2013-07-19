#import <Foundation/Foundation.h>
#import "XLDLibsndfileDecoder.h"
#import <XLDID3/id3lib.h>

#ifdef _BIG_ENDIAN
#define SWAP32(n) (n)
#define SWAP16(n) (n)
#else
#define SWAP32(n) (((n>>24)&0xff) | ((n>>8)&0xff00) | ((n<<8)&0xff0000) | ((n<<24)&0xff000000))
#define SWAP16(n) (((n>>8)&0xff) | ((n<<8)&0xff00))
#endif

typedef struct
{
	xldoffset_t offset;
	char *name;
} marker_t;

int compare_marker(const marker_t *a, const marker_t *b)
{
    return a->offset - b->offset;
}

static NSString* samplesToTimecode(uint64_t samples, int samplerate, double fps)
{
	int timecodeFps = ceil(fps);
	double samplesPerFrame = samplerate / fps;
	int frames = (int)round(samples / samplesPerFrame);
	int ff = frames % timecodeFps;
	int seconds = frames / timecodeFps;
	int ss = seconds % 60;
	int minutes = seconds / 60;
	int mm = minutes % 60;
	int hh = minutes / 60;
	
	return [NSString stringWithFormat:@"%02d:%02d:%02d:%02d",hh,mm,ss,ff];
}

@implementation XLDLibsndfileDecoder
		

+ (BOOL)canHandleFile:(char *)path
{
	SF_INFO sfinfo_tmp;
	memset(&sfinfo_tmp,0,sizeof(SF_INFO));
	SNDFILE *sf_tmp = sf_open(path, SFM_READ, &sfinfo_tmp);
	if(sf_error(sf_tmp)) {
		//NSLog(@"%s",sf_strerror(sf_tmp));
		return NO;
	}
	sf_close(sf_tmp);
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
	sf = NULL;
	//trackArr = nil;
	//cueData = nil;
	error = NO;
	isFloat = 0;
	srcPath = nil;
	//metadataDic = [[NSMutableDictionary alloc] init];
	return self;
}

- (void)findMarkChunkForAIFF:(char *)path
{
	FILE *fp = fopen(path,"rb");
	char chunk[4];
	unsigned int tmp,i,trackNum=1;
	unsigned short tmp2;
	unsigned char tmp3;
	unsigned short markerCount;
	marker_t *markers = NULL;
	XLDTrack *prevTrack = nil;
	xldoffset_t prevIndex = -1;
	
	if(fread(chunk,1,4,fp) != 4) goto last;
	if(memcmp(chunk,"FORM",4)) goto last;
	if(fseeko(fp,4,SEEK_CUR)) goto last;
	if(fread(chunk,1,4,fp) != 4) goto last;
	if(memcmp(chunk,"AIFF",4)) goto last;
	
	while(1) {
		if(fread(chunk,1,4,fp) != 4) goto last;
		if(fread(&tmp,4,1,fp) != 1) goto last;
		tmp = SWAP32(tmp);
		if(!memcmp(chunk,"MARK",4)) break;
		if(tmp&1) tmp++;
		if(fseeko(fp,tmp,SEEK_CUR)) goto last;
	}
	
	if(fread(&tmp2,2,1,fp) != 1) goto last;
	markerCount = SWAP16(tmp2);
	if(!markerCount) goto last;
	
	markers = (marker_t *)malloc(sizeof(marker_t)*markerCount);
	
	for(i=0;i<markerCount;i++) {
		if(fseeko(fp,2,SEEK_CUR)) goto last;
		if(fread(&tmp,4,1,fp) != 1) goto last;
		markers[i].offset = SWAP32(tmp);
		if(fread(&tmp3,1,1,fp) != 1) goto last;
		markers[i].name = (char *)malloc(tmp3+1);
		if(fread(markers[i].name,1,tmp3,fp) != tmp3) goto last;
		markers[i].name[tmp3] = 0;
		if(!(tmp3 & 1)) if(fseeko(fp,1,SEEK_CUR)) goto last;
	}
	
	qsort(markers, markerCount, sizeof(marker_t), (int (*)(const void*, const void*))compare_marker);
	trackArr = [[NSMutableArray alloc] init];
	if(markers[0].offset != 0) {
		XLDTrack *track = [[objc_getClass("XLDTrack") alloc] init];
		[track setIndex:0];
		[[track metadata] setObject:[NSNumber numberWithInt:trackNum++] forKey:XLD_METADATA_TRACK];
		[trackArr addObject:track];
		prevTrack = track;
		prevIndex = 0;
		[track release];
	}
	for(i=0;i<markerCount;i++) {
		if(markers[i].offset >= totalFrames) continue;
		if(markers[i].offset == prevIndex) continue;
		XLDTrack *track = [[objc_getClass("XLDTrack") alloc] init];
		[track setIndex:markers[i].offset];
		if(prevTrack) [prevTrack setFrames:markers[i].offset-prevIndex];
		[[track metadata] setObject:[NSNumber numberWithInt:trackNum++] forKey:XLD_METADATA_TRACK];
		NSString *title = [NSString stringWithUTF8String:markers[i].name];
		if(!title) title = [NSString stringWithCString:markers[i].name];
		if(title) [[track metadata] setObject:title forKey:XLD_METADATA_TITLE];
		[trackArr addObject:track];
		prevTrack = track;
		prevIndex = markers[i].offset;
		[track release];
	}
	[prevTrack setFrames:totalFrames-prevIndex];
	for(i=0;i<trackNum-1;i++) {
		[[[trackArr objectAtIndex:i] metadata] setObject:[NSNumber numberWithInt:trackNum-1] forKey:XLD_METADATA_TOTALTRACKS];
	}
	
last:
	if(markers) {
		for(i=0;i<markerCount;i++) {
			if(markers[i].name) free(markers[i].name);
		}
		free(markers);
	}
	fclose(fp);
}

- (void)readID3TagFromAIFF:(char *)path
{
	FILE *fp = fopen(path,"rb");
	if(!fp) return;
	char chunk[4];
	unsigned int length;
	if(fread(chunk,1,4,fp) != 4) goto end;
	if(memcmp(chunk,"FORM",4)) goto end;
	if(fseeko(fp,4,SEEK_CUR)) goto end;
	if(fread(chunk,1,4,fp) != 4) goto end;
	if(memcmp(chunk,"AIFF",4)) goto end;
	while(1) {
		if(fread(chunk,1,4,fp) != 4) goto end;
		if(fread(&length,4,1,fp) != 1) goto end;
		length = NSSwapBigIntToHost(length);
		if(!memcmp(chunk,"ID3 ",4)) break;
		if(length&1) length++;
		if(fseeko(fp,length,SEEK_CUR)) goto end;
	}
	unsigned char *buf = malloc(length);
	if(fread(buf,1,length,fp) != length) {
		free(buf);
		goto end;
	}
	NSData *dat = [NSData dataWithBytesNoCopy:buf length:length];
	if(metadataDic) [metadataDic release];
	metadataDic = [[NSMutableDictionary alloc] init];
	parseID3(dat,metadataDic);
end:
	fclose(fp);
}

- (void)readID3TagFromWAV:(char *)path
{
	FILE *fp = fopen(path,"rb");
	if(!fp) return;
	char chunk[5];
	unsigned int length;
	if(fread(chunk,1,4,fp) != 4) goto end;
	if(memcmp(chunk,"RIFF",4)) goto end;
	if(fseeko(fp,4,SEEK_CUR)) goto end;
	if(fread(chunk,1,4,fp) != 4) goto end;
	if(memcmp(chunk,"WAVE",4)) goto end;
	while(1) {
		if(fread(chunk,1,4,fp) != 4) goto end;
		if(fread(&length,4,1,fp) != 1) goto end;
		length = NSSwapLittleIntToHost(length);
		chunk[4] = 0;
		if(!strncasecmp(chunk,"ID3 ",4)) break;
		if(length&1) length++;
		if(fseeko(fp,length,SEEK_CUR)) goto end;
	}
	unsigned char *buf = malloc(length);
	if(fread(buf,1,length,fp) != length) {
		free(buf);
		goto end;
	}
	NSData *dat = [NSData dataWithBytesNoCopy:buf length:length];
	if(metadataDic) [metadataDic release];
	metadataDic = [[NSMutableDictionary alloc] init];
	parseID3(dat,metadataDic);
end:
	fclose(fp);
}

- (void)readRegionsFromSd2f:(char *)path
{
	FSRef fsRef;
	OSErr err;
	if(!FSPathMakeRef((UInt8*)path, &fsRef, NULL)) {
		ResFileRefNum resourceRef;
		HFSUniStr255 resourceForkName;
		UniCharCount forkNameLength;
		UniChar *forkName;
		err = FSGetResourceForkName(&resourceForkName);
		if(err) goto last;
		forkNameLength = resourceForkName.length;
		forkName = resourceForkName.unicode;
		err = FSOpenResourceFile(&fsRef, forkNameLength, forkName, (SInt8)fsRdPerm, &resourceRef);
		if(err) goto last;
		
		UseResFile(resourceRef);
		Handle rsrc = Get1Resource('ddRL',1000);
		if(rsrc) {
			trackArr = [[NSMutableArray alloc] init];
			HLock(rsrc);
			unsigned char *ptr = (unsigned char *)*rsrc;
			int resSize = GetHandleSize(rsrc);
			int pos = 6+OSSwapBigToHostInt32(*(int*)(ptr+2));
			int regionSize = OSSwapBigToHostInt32(*(int*)(ptr+6));
			while(pos < resSize) {
				XLDTrack *track = [[objc_getClass("XLDTrack") alloc] init];
				unsigned int idx = OSSwapBigToHostInt32(*(int*)(ptr+pos+4));
				unsigned int length = OSSwapBigToHostInt32(*(int*)(ptr+pos+8)) - idx;
				[track setIndex:idx];
				[track setFrames:length];
				[trackArr addObject:track];
				[track release];
				pos += regionSize;
			}
			if(![trackArr count]) {
				[trackArr release];
				trackArr = nil;
			}
			HUnlock(rsrc);
			ReleaseResource(rsrc);
		}
		if(!trackArr) {
			CloseResFile(resourceRef);
			goto last;
		}
		
		rsrc = Get1Resource('Uni#',1);
		if(rsrc) {
			HLock(rsrc);
			int i=0;
			unsigned char *ptr = (unsigned char *)*rsrc;
			int resSize = GetHandleSize(rsrc);
			short strLength = OSSwapBigToHostInt16(*(short*)(ptr+2));
			int pos = strLength*2+4;
			NSString *album = nil;
			if(strLength) {
				album = [[NSString alloc] initWithBytes:ptr+4 length:strLength*2 encoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingUTF16BE)];
			}
			while(pos < resSize && i < [trackArr count]) {
				strLength = OSSwapBigToHostInt16(*(short*)(ptr+pos));
				if(strLength) {
					NSString *title = [[NSString alloc] initWithBytes:ptr+pos+2 length:strLength*2 encoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingUTF16BE)];
					XLDTrack *track = [trackArr objectAtIndex:i++];
					if(title) {
						[[track metadata] setObject:title forKey:XLD_METADATA_TITLE];
						[title release];
					}
					if(album) [[track metadata] setObject:album forKey:XLD_METADATA_ALBUM];
					pos += 2 + strLength*2;
				}
			}
			if(album) [album release];
			HUnlock(rsrc);
			ReleaseResource(rsrc);
		}
		CloseResFile(resourceRef);
	}
last:
	return;
}

- (void)readBWFMetadataFromWAV:(char *)path
{
	FILE *fp = fopen(path,"rb");
	if(!fp) return;
	char chunk[5];
	unsigned int length;
	if(fread(chunk,1,4,fp) != 4) goto end;
	if(memcmp(chunk,"RIFF",4)) goto end;
	if(fseeko(fp,4,SEEK_CUR)) goto end;
	if(fread(chunk,1,4,fp) != 4) goto end;
	if(memcmp(chunk,"WAVE",4)) goto end;
	while(1) {
		if(fread(chunk,1,4,fp) != 4) goto end;
		if(fread(&length,4,1,fp) != 1) goto end;
		length = NSSwapLittleIntToHost(length);
		chunk[4] = 0;
		if(!strncasecmp(chunk,"bext",4)) break;
		if(length&1) length++;
		if(fseeko(fp,length,SEEK_CUR)) goto end;
	}
	if(fseeko(fp, 338, SEEK_CUR)) goto end;
	if(fread(&length,4,1,fp) != 1) goto end;
	uint64_t sampleCountSinceMidnight = NSSwapLittleIntToHost(length);
	if(fread(&length,4,1,fp) != 1) goto end;
	sampleCountSinceMidnight |= ((uint64_t)NSSwapLittleIntToHost(length) << 32);
	if(fseeko(fp, 12, SEEK_SET)) goto end;
	while(1) {
		if(fread(chunk,1,4,fp) != 4) goto end;
		if(fread(&length,4,1,fp) != 1) goto end;
		length = NSSwapLittleIntToHost(length);
		chunk[4] = 0;
		if(!strncasecmp(chunk,"iXML",4)) break;
		if(length&1) length++;
		if(fseeko(fp,length,SEEK_CUR)) goto end;
	}
	unsigned char *buf = malloc(length);
	if(fread(buf,1,length,fp) != length) {
		free(buf);
		goto end;
	}
	NSData *dat = [NSData dataWithBytesNoCopy:buf length:length];
	NSXMLDocument *xml = [[NSXMLDocument alloc] initWithData:dat options:NSXMLNodePreserveWhitespace error:nil];
	if(!xml) {
		goto end;
	}
	id objs = [xml nodesForXPath:@"./BWFXML/SPEED" error:nil];
	if(![objs count]) {
		[xml release];
		goto end;
	}
	id speedMetadata = [objs objectAtIndex:0];
	objs = [speedMetadata nodesForXPath:@"./TIMECODE_RATE" error:nil];
	if(![objs count]) {
		[xml release];
		goto end;
	}
	const char *fpsStr = [[[objs objectAtIndex:0] stringValue] UTF8String];
	objs = [speedMetadata nodesForXPath:@"./TIMECODE_FLAG" error:nil];
	NSString *fpsFlag = nil;
	if([objs count]) fpsFlag = [NSString stringWithFormat:@"-%@",[[objs objectAtIndex:0] stringValue]];
	double fps;
	if(strchr(fpsStr, '/')) {
		char *ptr = strchr(fpsStr, '/');
		unsigned int denominator = strtoul(fpsStr, NULL, 10);
		unsigned int numerator = strtoul(ptr+1, NULL, 10);
		fps = (float)denominator / (float)numerator;
	}
	else fps = strtod(fpsStr, NULL);
	
	//NSLog(@"%f,%d,%.3f%@,%llx",fps,(int)ceil(fps),fps,fpsFlag,totalFrames);
	//NSLog(@"%@",samplesToTimecode(sampleCountSinceMidnight,sfinfo.samplerate,fps));
	//NSLog(@"%@",samplesToTimecode(totalFrames,sfinfo.samplerate,fps));
	
	if(!metadataDic) metadataDic = [[NSMutableDictionary alloc] init];
	[metadataDic setObject:samplesToTimecode(sampleCountSinceMidnight,sfinfo.samplerate,fps) forKey:XLD_METADATA_SMPTE_TIMECODE_START];
	[metadataDic setObject:samplesToTimecode(totalFrames,sfinfo.samplerate,fps) forKey:XLD_METADATA_SMPTE_TIMECODE_DURATION];
	[metadataDic setObject:[NSString stringWithFormat:@"%.3f%@",fps,fpsFlag?fpsFlag:@""] forKey:XLD_METADATA_MEDIA_FPS];
	
	[xml release];
end:
	fclose(fp);
}

- (BOOL)openFile:(char *)path
{
	memset(&sfinfo,0,sizeof(SF_INFO));
	sf = sf_open(path, SFM_READ, &sfinfo);
	if(sf_error(sf)) {
		error = YES;
		return NO;
	}
	switch((sfinfo.format)&SF_FORMAT_SUBMASK) {
	  case 1:
		bps = 1;
		break;
	  case 2:
		bps = 2;
		break;
	  case 3:
		bps = 3;
		break;
	  case 4:
		bps = 4;
		break;
	  case 5:
		bps = 1;
		break;
	  case 6:
		isFloat = 1;
		bps = 4;
		break;
/*	  case 7:
		isFloat = 1;
		bps = 8;
		break;*/
	  default:
		sf_close(sf);
		sf = NULL;
		error = YES;
		return NO;
	}
	
	totalFrames = sfinfo.frames;
	
	if(!(((sfinfo.format)&SF_FORMAT_ENDMASK)^SF_ENDIAN_LITTLE) && !(((sfinfo.format)&SF_FORMAT_TYPEMASK)^SF_FORMAT_AIFF)) {
		int sample = sfinfo.frames > 16384 ? 16384 : sfinfo.frames;
		int *tmp = malloc(sample*4*sfinfo.channels);
		sf_readf_int(sf,tmp,sample);
		sf_seek(sf,0,SEEK_SET);
		free(tmp);
	}
	
	if(!(((sfinfo.format)&SF_FORMAT_TYPEMASK)^SF_FORMAT_AIFF)) {
		[self findMarkChunkForAIFF:path];
		[self readID3TagFromAIFF:path];
	}
	else if((sfinfo.format&SF_FORMAT_TYPEMASK) == SF_FORMAT_WAV) {
		[self readID3TagFromWAV:path];
		[self readBWFMetadataFromWAV:path];
	}
	else if((sfinfo.format&SF_FORMAT_TYPEMASK) == SF_FORMAT_SD2) {
		[self readRegionsFromSd2f:path];
	}
	
	if(srcPath) [srcPath release];
	srcPath = [[NSString alloc] initWithUTF8String:path];
	return YES;
}

- (void)dealloc
{
	if(sf) sf_close(sf);
	if(srcPath) [srcPath release];
	if(trackArr) [trackArr release];
	//if(cueData) [cueData release];
	if(metadataDic) [metadataDic release];
	[super dealloc];
}

- (int)samplerate
{
	return sfinfo.samplerate;
}

- (int)bytesPerSample
{
	return bps;
}

- (int)channels
{
	return sfinfo.channels;
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
	int ret;
	if(!isFloat) ret = sf_readf_int(sf,buffer,count);
	else ret = sf_readf_float(sf,(float *)buffer,count);
	if(sf_error(sf)) error = YES;
	return ret;
}

- (xldoffset_t)seekToFrame:(xldoffset_t)count
{
	xldoffset_t ret = sf_seek(sf,count,SEEK_SET);
	if(ret == -1 || sf_error(sf)) error = YES;
	return ret;
}

- (void)closeFile
{
	if(sf) sf_close(sf);
	sf = NULL;
	if(trackArr) [trackArr release];
	trackArr = nil;
	//if(cueData) [cueData release];
	//cueData = nil;
	if(metadataDic) [metadataDic release];
	metadataDic = nil;
	error = NO;
}

- (BOOL)error
{
	return error;
}

- (XLDEmbeddedCueSheetType)hasCueSheet
{
	return trackArr ? XLDTrackTypeCueSheet : XLDNoCueSheet;
}

- (id)cueSheet
{
	return trackArr;
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
