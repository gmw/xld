#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import "XLDMP3Decoder.h"
#define LIBID3_TAG_SUPPORT 0
#if LIBID3_TAG_SUPPORT
#import <id3tag.h>
#else
#import <XLDID3/id3lib.h>
#endif

#define XLD_METADATA_TITLE		@"Title"
#define XLD_METADATA_ARTIST		@"Artist"
#define XLD_METADATA_ALBUM		@"Album"
#define XLD_METADATA_GENRE		@"Genre"
#define XLD_METADATA_TRACK		@"Track"
#define XLD_METADATA_DISC		@"Disc"
#define XLD_METADATA_YEAR		@"Year"
#define XLD_METADATA_DATE		@"Date"
#define XLD_METADATA_COMPOSER	@"Composer"
#define XLD_METADATA_CUESHEET	@"Cuesheet"
#define XLD_METADATA_COMMENT	@"Comment"
#define XLD_METADATA_TOTALTRACKS	@"Totaltracks"
#define XLD_METADATA_TOTALDISCS	@"Totaldiscs"
#define XLD_METADATA_LYRICS		@"Lyrics"
#define XLD_METADATA_ISRC		@"ISRC"
#define XLD_METADATA_COVER		@"Cover"
#define XLD_METADATA_ALBUMARTIST	@"AlbumArtist"
#define XLD_METADATA_REPLAYGAIN_TRACK_GAIN	@"RGTrackGain"
#define XLD_METADATA_REPLAYGAIN_ALBUM_GAIN	@"RGAlbumGain"
#define XLD_METADATA_REPLAYGAIN_TRACK_PEAK	@"RGTrackPeak"
#define XLD_METADATA_REPLAYGAIN_ALBUM_PEAK	@"RGAlbumPeak"
#define XLD_METADATA_COMPILATION	@"Compilation"
#define XLD_METADATA_GROUP		@"Group"
#define XLD_METADATA_GRACENOTE		@"Gracenote"
#define XLD_METADATA_CATALOG		@"Catalog"
#define XLD_METADATA_PREEMPHASIS	@"Emphasis"
#define XLD_METADATA_FREEDBDISCID	@"DISCID"

#ifdef _BIG_ENDIAN
#define SWAP32(n) (n)
#define SWAP16(n) (n)
#else
#define SWAP32(n) (((n>>24)&0xff) | ((n>>8)&0xff00) | ((n<<8)&0xff0000) | ((n<<24)&0xff000000))
#define SWAP16(n) (((n>>8)&0xff) | ((n<<8)&0xff00))
#endif

#if LIBID3_TAG_SUPPORT
char *getUTF8StringFromFrame(struct id3_frame *frame)
{
	const id3_ucs4_t *unicode;
	union id3_field *field;
	int i;
	char *str = NULL;
	for(i = 0;; i++)
    {
        field = id3_frame_field(frame, i);
        if (!field) break;
		
        if (id3_field_type(field) == ID3_FIELD_TYPE_STRINGLIST) {
            unicode = id3_field_getstrings(field,0);
            if (unicode) {
                str = (char *)id3_ucs4_utf8duplicate(unicode);
				break;
            }
        }
    }
	return str;
}

char *getUTF8GenreFromFrame(struct id3_frame *frame)
{
	const id3_ucs4_t *unicode;
	union id3_field *field;
	int i;
	char *str = NULL;
	for(i = 0;; i++)
    {
        field = id3_frame_field(frame, i);
        if (!field) break;
		
        if (id3_field_type(field) == ID3_FIELD_TYPE_STRINGLIST) {
            unicode = id3_genre_name(id3_field_getstrings(field,0));
            if (unicode) {
                str = (char *)id3_ucs4_utf8duplicate(unicode);
				break;
            }
        }
    }
	return str;
}

char *getUTF8CommentFromFrame(struct id3_frame *frame)
{
	const id3_ucs4_t *unicode;
	union id3_field *field;
	int i;
	char *str = NULL;
	for(i = 0;; i++)
    {
        field = id3_frame_field(frame, i);
        if (!field) break;
		
        if (id3_field_type(field) == ID3_FIELD_TYPE_STRINGFULL) {
            unicode = id3_field_getfullstring(field);
            if (unicode) {
                str = (char *)id3_ucs4_utf8duplicate(unicode);
				break;
            }
        }
    }
	return str;
}

NSData *getBinaryFromFrame(struct id3_frame *frame)
{
	union id3_field *field;
	int i;
	NSData *data;
	for(i = 0;; i++)
    {
        field = id3_frame_field(frame, i);
        if (!field) break;
		
        if (id3_field_type(field) == ID3_FIELD_TYPE_BINARYDATA) {
			id3_length_t size;
            char *dat = (char *)id3_field_getbinarydata(field,&size);
            if (dat) {
                data = [NSData dataWithBytes:dat length:size];
				break;
            }
        }
    }
	return data;
}
#endif

@implementation XLDMP3Decoder

+ (BOOL)canHandleFile:(char *)path
{
	ExtAudioFileRef infile;
	FSRef inputFSRef;
	FSPathMakeRef((UInt8 *)path,&inputFSRef,NULL);
	if(ExtAudioFileOpen(&inputFSRef, &infile) != noErr) {
		return NO;
	}
	AudioStreamBasicDescription fmt;
	UInt32 size = sizeof(fmt);
	if(ExtAudioFileGetProperty(infile, kExtAudioFileProperty_FileDataFormat, &size, &fmt) != noErr) {
		ExtAudioFileDispose(infile);
		return NO;
	}
	if(fmt.mFormatID != '.mp3') {
		ExtAudioFileDispose(infile);
		return NO;
	}
	ExtAudioFileDispose(infile);
	return YES;
}

+ (BOOL)canLoadThisBundle
{
	if (floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_3 ) {
		return NO;
	}
	else return YES;
}

- (id)init
{
	[super init];
	file = NULL;
	error = NO;
	metadataDic = [[NSMutableDictionary alloc] init];
	srcPath = nil;
	
	return self;
}

- (BOOL)openFile:(char *)path
{
	FSRef inputFSRef;
	FSPathMakeRef((UInt8 *)path,&inputFSRef,NULL);
	if(ExtAudioFileOpen(&inputFSRef, &file) != noErr) return NO;
	AudioStreamBasicDescription inputFormat,outputFormat;
	UInt32 size = sizeof(inputFormat);
	if(ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileDataFormat, &size, &inputFormat) != noErr) {
		ExtAudioFileDispose(file);
		file = NULL;
		error = YES;
		return NO;
	}
	SInt64 frames;
	size = sizeof(frames);
	if(ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileLengthFrames, &size, &frames) != noErr) {
		ExtAudioFileDispose(file);
		file = NULL;
		error = YES;
		return NO;
	}
	if(inputFormat.mFormatID != '.mp3') {
		ExtAudioFileDispose(file);
		file = NULL;
		error = YES;
		return NO;
	}
	
	bps = 2;
	channels = inputFormat.mChannelsPerFrame;
	samplerate = inputFormat.mSampleRate;
	totalFrames = frames;
	
	outputFormat = inputFormat;
	outputFormat.mFormatID = 'lpcm';
#ifdef _BIG_ENDIAN
	outputFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger|kAudioFormatFlagIsBigEndian|kAudioFormatFlagIsPacked;
#else
	outputFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger|kAudioFormatFlagIsPacked;
#endif
	outputFormat.mBytesPerPacket = 4 * inputFormat.mChannelsPerFrame;
	outputFormat.mFramesPerPacket = 1;
	outputFormat.mBytesPerFrame = outputFormat.mBytesPerPacket;
	outputFormat.mChannelsPerFrame = inputFormat.mChannelsPerFrame;
	outputFormat.mBitsPerChannel = 32;
	
	size = sizeof(outputFormat);
	if(ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat, size, &outputFormat) != noErr) {
		ExtAudioFileDispose(file);
		file = NULL;
		error = YES;
		return NO;
	}
	
#if LIBID3_TAG_SUPPORT
	struct id3_file *tf = id3_file_open(path,ID3_FILE_MODE_READONLY);
	if(tf) {
		struct id3_tag *tag = id3_file_tag(tf);
		if(tag) {
			struct id3_frame *frame;
			/*int i;
			for(i=0;i<tag->nframes;i++) {
				NSLog(@"%s",tag->frames[i]->id);
			}*/
			if(frame = id3_tag_findframe(tag,"TIT2", 0)) {
				char *str = getUTF8StringFromFrame(frame);
				if(str) {
					[metadataDic setObject:[NSString stringWithUTF8String:str] forKey:XLD_METADATA_TITLE];
					free(str);
				}
			}
			if(frame = id3_tag_findframe(tag,"TPE1", 0)) {
				char *str = getUTF8StringFromFrame(frame);
				if(str) {
					[metadataDic setObject:[NSString stringWithUTF8String:str] forKey:XLD_METADATA_ARTIST];
					free(str);
				}
			}
			if(frame = id3_tag_findframe(tag,"TALB", 0)) {
				char *str = getUTF8StringFromFrame(frame);
				if(str) {
					[metadataDic setObject:[NSString stringWithUTF8String:str] forKey:XLD_METADATA_ALBUM];
					free(str);
				}
			}
			if(frame = id3_tag_findframe(tag,"TPE2", 0)) {
				char *str = getUTF8StringFromFrame(frame);
				if(str) {
					[metadataDic setObject:[NSString stringWithUTF8String:str] forKey:XLD_METADATA_ALBUMARTIST];
					free(str);
				}
			}
			if(frame = id3_tag_findframe(tag,"TCON", 0)) {
				char *str = getUTF8GenreFromFrame(frame);
				if(str) {
					[metadataDic setObject:[NSString stringWithUTF8String:str] forKey:XLD_METADATA_GENRE];
					free(str);
				}
			}
			if(frame = id3_tag_findframe(tag,"TCOM", 0)) {
				char *str = getUTF8StringFromFrame(frame);
				if(str) {
					[metadataDic setObject:[NSString stringWithUTF8String:str] forKey:XLD_METADATA_COMPOSER];
					free(str);
				}
			}
			if(frame = id3_tag_findframe(tag,"TIT1", 0)) {
				char *str = getUTF8StringFromFrame(frame);
				if(str) {
					[metadataDic setObject:[NSString stringWithUTF8String:str] forKey:XLD_METADATA_GROUP];
					free(str);
				}
			}
			if(frame = id3_tag_findframe(tag,"TSRC", 0)) {
				char *str = getUTF8StringFromFrame(frame);
				if(str) {
					[metadataDic setObject:[NSString stringWithUTF8String:str] forKey:XLD_METADATA_ISRC];
					free(str);
				}
			}
			if(frame = id3_tag_findframe(tag,"TRCK", 0)) {
				char *str = getUTF8StringFromFrame(frame);
				if(str) {
					char *ptr;
					int track = strtol(str,&ptr,10);
					if(track > 0) {
						[metadataDic setObject:[NSNumber numberWithInt:track] forKey:XLD_METADATA_TRACK];
						if(*ptr == '/') {
							track = strtol(ptr+1,NULL,10);
							if(track > 0) [metadataDic setObject:[NSNumber numberWithInt:track] forKey:XLD_METADATA_TOTALTRACKS];
						}
					}
					free(str);
				}
			}
			if(frame = id3_tag_findframe(tag,"TPOS", 0)) {
				char *str = getUTF8StringFromFrame(frame);
				if(str) {
					char *ptr;
					int track = strtol(str,&ptr,10);
					if(track > 0) {
						[metadataDic setObject:[NSNumber numberWithInt:track] forKey:XLD_METADATA_DISC];
						if(*ptr == '/') {
							track = strtol(ptr+1,NULL,10);
							if(track > 0) [metadataDic setObject:[NSNumber numberWithInt:track] forKey:XLD_METADATA_TOTALDISCS];
						}
					}
					free(str);
				}
			}
			if(frame = id3_tag_findframe(tag,"TDRC", 0)) {
				char *str = getUTF8StringFromFrame(frame);
				if(str) {
					int year = atoi(str);
					if(year) [metadataDic setObject:[NSNumber numberWithInt:year] forKey:XLD_METADATA_YEAR];
					free(str);
				}
			}
			if(frame = id3_tag_findframe(tag,"TCMP", 0)) {
				char *str = getUTF8StringFromFrame(frame);
				if(str) {
					int cmpl = atoi(str);
					if(cmpl) [metadataDic setObject:[NSNumber numberWithBool:YES] forKey:XLD_METADATA_COMPILATION];
					free(str);
				}
			}
			if(frame = id3_tag_findframe(tag,"COMM", 0)) {
				char *str = getUTF8CommentFromFrame(frame);
				if(str) {
					[metadataDic setObject:[NSString stringWithUTF8String:str] forKey:XLD_METADATA_COMMENT];
					free(str);
				}
			}
			if(frame = id3_tag_findframe(tag,"APIC", 0)) {
				NSData *dat = getBinaryFromFrame(frame);
				if(dat) {
					[metadataDic setObject:dat forKey:XLD_METADATA_COVER];
				}
			}
		}
		id3_file_close(tf);
	}
#else
	FILE *fp = fopen(path,"rb");
	if(fp) {
		char id3[3];
		int size = 10;
		char byte;
		char *id3buf = NULL;
		if(fread(id3,1,3,fp) != 3) goto last;
		if(memcmp(id3,"ID3",3)) goto last;
		if(fseek(fp,2,SEEK_CUR) != 0) goto last;
		if(fread(&byte,1,1,fp) != 1) goto last;
		if(byte & 0x40) size += 10;
		if(fread(&byte,1,1,fp) != 1) goto last;
		size += (byte & 0x7f) << 21;
		if(fread(&byte,1,1,fp) != 1) goto last;
		size += (byte & 0x7f) << 14;
		if(fread(&byte,1,1,fp) != 1) goto last;
		size += (byte & 0x7f) << 7;
		if(fread(&byte,1,1,fp) != 1) goto last;
		size += (byte & 0x7f);
		if(fseek(fp,0,SEEK_SET) != 0) goto last;
		id3buf = (char *)malloc(size);
		if(fread(id3buf,1,size,fp) != size) goto last;
		NSData *id3dat = [NSData dataWithBytes:id3buf length:size];
		parseID3(id3dat, metadataDic);
	last:
		if(id3buf) free(id3buf);
		fclose(fp);
	}
#endif
	
	if(srcPath) [srcPath release];
	srcPath = [[NSString alloc] initWithUTF8String:path];
	return YES;
}

- (void)dealloc
{
	if(file) ExtAudioFileDispose(file);
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
	return 0;
}

- (int)decodeToBuffer:(int *)buffer frames:(int)count
{
	UInt32 ret;
	UInt32 read = 0;
	fillBufList.mNumberBuffers = 1;
	fillBufList.mBuffers[0].mNumberChannels = channels;
	while(read < count) {
		fillBufList.mBuffers[0].mDataByteSize = (count-read)*4*channels;
		fillBufList.mBuffers[0].mData = buffer+read*channels;
		ret = count-read;
		int err = ExtAudioFileRead (file, &ret, &fillBufList);
		if(err != noErr) {
			//NSLog(@"ExtAudioFileRead error %d, %08x",err,err);
			error = YES;
			return 0;
		}
		if(ret == 0) break;
		read += ret;
	}
	
	return read;
}

- (xldoffset_t)seekToFrame:(xldoffset_t)count
{
	if(ExtAudioFileSeek(file,count) != noErr) {
		error = YES;
		return 0;
	}
	return count;
}

- (void)closeFile
{
	if(file) ExtAudioFileDispose(file);
	file = NULL;
	[metadataDic removeAllObjects];
	error = NO;
}

- (BOOL)error
{
	return error;
}

- (XLDEmbeddedCueSheetType)hasCueSheet
{
	return XLDNoCueSheet;
}

- (id)cueSheet
{
	return nil;
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