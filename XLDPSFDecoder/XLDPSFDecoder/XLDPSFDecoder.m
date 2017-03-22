//
//  XLDPSFDecoder.m
//  XLDPSFDecoder
//
//  Created by tmkk on 2017/03/09.
//  Copyright © 2017年 tmkk. All rights reserved.
//

#import "XLDPSFDecoder.h"
#if defined(__i386__)
#import <xmmintrin.h>
#endif
#include <zlib.h>
#import "psx.h"
#import "bios.h"
#import "psf2fs.h"
#import "../Highly Experimental/hebios.h"

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
#define XLD_METADATA_DCP		@"DCP"
#define XLD_METADATA_FREEDBDISCID	@"DISCID"
#define XLD_METADATA_BPM		@"BPM"
#define XLD_METADATA_COPYRIGHT	@"Copyright"
#define XLD_METADATA_GAPLESSALBUM	@"GaplessAlbum"
#define XLD_METADATA_CREATIONDATE	@"CreationDate"
#define XLD_METADATA_MODIFICATIONDATE	@"ModificationDate"
#define XLD_METADATA_ORIGINALFILENAME	@"OriginalFilename"
#define XLD_METADATA_ORIGINALFILEPATH	@"OriginalFilepath"
#define XLD_METADATA_DATATRACK @"DataTrack"
#define XLD_METADATA_TITLESORT	@"TitleSort"
#define XLD_METADATA_ARTISTSORT	@"ArtistSort"
#define XLD_METADATA_ALBUMSORT	@"AlbumSort"
#define XLD_METADATA_ALBUMARTISTSORT	@"AlbumArtistSort"
#define XLD_METADATA_COMPOSERSORT	@"ComposerSort"
#define XLD_METADATA_GRACENOTE2		@"Gracenote2"
#define XLD_METADATA_MB_TRACKID		@"MusicBrainz_TrackID"
#define XLD_METADATA_MB_ALBUMID	@"MusicBrainz_AlbumID"
#define XLD_METADATA_MB_ARTISTID	@"MusicBrainz_ArtistID"
#define XLD_METADATA_MB_ALBUMARTISTID	@"MusicBrainz_AlbumArtistID"
#define XLD_METADATA_MB_DISCID	@"MusicBrainz_DiscID"
#define XLD_METADATA_PUID		@"MusicIP_PUID"
#define XLD_METADATA_MB_ALBUMSTATUS	@"MusicBrainz_AlbumStatus"
#define XLD_METADATA_MB_ALBUMTYPE	@"MusicBrainz_AlbumType"
#define XLD_METADATA_MB_RELEASECOUNTRY	@"MusicBrainz_ReleaseCountry"
#define XLD_METADATA_MB_RELEASEGROUPID	@"MusicBrainz_ReleaseGroupID"
#define XLD_METADATA_MB_WORKID	@"MusicBrainz_WorkID"
#define XLD_METADATA_TOTALSAMPLES	@"TotalSamples"
#define XLD_METADATA_TRACKLIST	@"XLDTrackList"
#define XLD_METADATA_SMPTE_TIMECODE_START	@"SMTPE Timecode Start"
#define XLD_METADATA_SMPTE_TIMECODE_DURATION	@"SMTPE Timecode Duration"
#define XLD_METADATA_MEDIA_FPS	@"Media FPS"
#define XLD_METADATA_FINDERLABEL @"Finder Label"

#define DECOMP_MAX_SIZE		(4 * 1024 * 1024)

static double timestr_to_double(const char *str)
{
    double time = 0;
    const char *ptr = str;
    while(1) {
        time *= 60;
        if(!strchr(ptr,':')) {
            time += strtod(ptr,NULL);
            break;
        }
        time += strtol(ptr,(char **)&ptr,10);
        ptr++;
    }
    return time;
}

static char *find_tag(const char *tags, const char *field)
{
    const char *ptr = tags;
    while(*ptr) {
        if(!strncasecmp(ptr,field,strlen(field))) {
            ptr += strlen(field);
            const char *end = ptr;
            while(*end != '\n' && *end) end++;
            if(end > ptr) {
                char *value = malloc(end-ptr+1);
                memcpy(value, ptr, end-ptr);
                value[end-ptr] = 0;
                return value;
            }
        }
        ptr = strchr(ptr, '\n');
        if(!ptr) break;
        ptr++;
    }
    return NULL;
}

static int load_psf1(void *state, const char *filename)
{
    FILE *fp = fopen(filename, "rb");
    fseeko(fp, 0, SEEK_END);
    off_t size = ftello(fp);
    fseeko(fp, 0, SEEK_SET);
    
    unsigned char *psfFile = malloc((unsigned)size+1);
    fread(psfFile, 1, (unsigned)size, fp);
    if(memcmp(psfFile, "PSF\x01", 4)) {
        free(psfFile);
        fclose(fp);
        return -1;
    }
    
    unsigned int sizeReserved = OSSwapLittleToHostInt(*(unsigned int *)(psfFile+4));
    unsigned long sizeCompressed = OSSwapLittleToHostInt(*(unsigned int *)(psfFile+8));
    
    if(sizeReserved+sizeCompressed+16+5 < size) {
        if(!memcmp(psfFile+sizeReserved+sizeCompressed+16,"[TAG]",5)) {
            psfFile[size] = 0;
            char *lib = find_tag((const char *)psfFile+sizeReserved+sizeCompressed+16+5,"_lib=");
            if(lib) {
                int len = strlen(filename);
                char *dir = malloc(len+strlen(lib)+1);
                strcpy(dir,filename);
                for(len--;len>=0;len--) {
                    if(dir[len] == '/') break;
                }
                strcpy(dir+len+1,lib);
                load_psf1(state, dir);
                free(lib);
                free(dir);
            }
        }
    }
    
    unsigned char *exeCompressed = psfFile+16+sizeReserved;
    unsigned long sizeDecompressed = DECOMP_MAX_SIZE;
    unsigned char *exe = malloc(DECOMP_MAX_SIZE);
    if (uncompress(exe, &sizeDecompressed, exeCompressed, sizeCompressed) != Z_OK)
    {
        fprintf(stderr, "decompress error\n");
        fclose(fp);
        free(psfFile);
        return -1;
    }
    
    int ret = psx_upload_psxexe(state, exe, sizeDecompressed);
    free(exe);
    free(psfFile);
    fclose(fp);
    return ret;
}

static int load_psf2(void *vfs, const char *filename)
{
    FILE *fp = fopen(filename, "rb");
    fseeko(fp, 0, SEEK_END);
    off_t size = ftello(fp);
    fseeko(fp, 0, SEEK_SET);
    
    unsigned char *psfFile = malloc((unsigned)size);
    fread(psfFile, 1, (unsigned)size, fp);
    if(memcmp(psfFile, "PSF\x02", 4)) {
        free(psfFile);
        fclose(fp);
        return -1;
    }
    
    unsigned int sizeReserved = OSSwapLittleToHostInt(*(unsigned int *)(psfFile+4));
    unsigned int sizeCompressed = OSSwapLittleToHostInt(*(unsigned int *)(psfFile+8));
    
    if(sizeReserved+sizeCompressed+16+5 < size) {
        if(!memcmp(psfFile+sizeReserved+sizeCompressed+16,"[TAG]",5)) {
            psfFile[size] = 0;
            char *lib = find_tag((const char *)psfFile+sizeReserved+sizeCompressed+16+5,"_lib=");
            if(lib) {
                int len = strlen(filename);
                char *dir = malloc(len+strlen(lib)+1);
                strcpy(dir,filename);
                for(len--;len>=0;len--) {
                    if(dir[len] == '/') break;
                }
                strcpy(dir+len+1,lib);
                load_psf2(vfs, dir);
                free(lib);
                free(dir);
            }
        }
    }
    
    int ret = psf2fs_load_callback(vfs, NULL, 0, psfFile+16, sizeReserved);
    free(psfFile);
    fclose(fp);
    return ret;
}

@implementation XLDPSFDecoder

+ (void)load
{
    psx_init();
}

+ (BOOL)canHandleFile:(char *)path
{
    FILE *fp = fopen(path,"rb");
    if(!fp) return NO;
    char buf[4];
    if(fread(buf,1,4,fp) < 4) {
        fclose(fp);
        return NO;
    }
    fclose(fp);
    if(memcmp(buf,"PSF",3)) return NO;
    if(buf[3] != 1 && buf[3] != 2) return NO;
    NSString *str = [NSString stringWithUTF8String:path];
    if([[[str pathExtension] lowercaseString] isEqualToString:@"psflib"]) return NO;
    else if([[[str pathExtension] lowercaseString] isEqualToString:@"psf1lib"]) return NO;
    else if([[[str pathExtension] lowercaseString] isEqualToString:@"psf2lib"]) return NO;
    return YES;
}

+ (BOOL)canLoadThisBundle
{
    return YES;
}


- (id)init
{
    self = [super init];
    if(self) {
        metadataDic = [[NSMutableDictionary alloc] init];
        bufferSize = 8192*4*2;
        decodeBuffer = malloc(bufferSize);
    }
    return self;
}

- (BOOL)initialize:(const char *)path
{
    if(psxState) psx_clear_state(psxState, psfVersion);
    psxState = malloc(psx_get_state_size(psfVersion));
    psx_clear_state(psxState, psfVersion);
    
    int ret;
    if(psfVersion == 1) {
        ret = load_psf1(psxState, path);
    }
    else {
        if(psf2fs) psf2fs_delete(psf2fs);
        psf2fs = psf2fs_create();
        ret = load_psf2(psf2fs, path);
        psx_set_readfile(psxState, psf2fs_virtual_readfile, psf2fs);
    }
    return ret ? NO : YES;
}

- (BOOL)openFile:(char *)path
{
    FILE *fp = fopen(path,"rb");
    if(!fp) return NO;
    char buf[256];
    if(fread(buf,1,4,fp) < 4) {
        fclose(fp);
        return NO;
    }
    
    if(memcmp(buf,"PSF",3)) {
        fclose(fp);
        return NO;
    }
    if(buf[3] != 1 && buf[3] != 2) {
        fclose(fp);
        return NO;
    }
    
    psfVersion = buf[3];
    double length = 170;
    double fade = 10;
    
    {
        int sizeReserved,sizeExe;
        fread(&sizeReserved,4,1,fp);
        sizeReserved = OSSwapLittleToHostInt(sizeReserved);
        fread(&sizeExe,4,1,fp);
        sizeExe = OSSwapLittleToHostInt(sizeExe);
        fseeko(fp,sizeReserved+sizeExe+4,SEEK_CUR);
        if(fread(buf,1,5,fp) == 5) {
            if(!strncasecmp(buf, "[TAG]", 5)) {
                NSString *libPath = nil;
                while(fgets(buf,256,fp)) {
                    char *ptr = strchr(buf, '=');
                    if(!ptr) continue;
                    *ptr = 0;
                    char *key = buf;
                    char *value = ptr+1;
                    if(!strcasecmp(key,"title")) {
                        ptr = strchr(value, '\n');
                        if(ptr) *ptr = 0;
                        NSString *str = [NSString stringWithUTF8String:value];
                        [metadataDic setObject:str forKey:XLD_METADATA_TITLE];
                    }
                    else if(!strcasecmp(key,"game")) {
                        ptr = strchr(value, '\n');
                        if(ptr) *ptr = 0;
                        NSString *str = [NSString stringWithUTF8String:value];
                        [metadataDic setObject:str forKey:XLD_METADATA_ALBUM];
                    }
                    else if(!strcasecmp(key,"artist")) {
                        ptr = strchr(value, '\n');
                        if(ptr) *ptr = 0;
                        NSString *str = [NSString stringWithUTF8String:value];
                        [metadataDic setObject:str forKey:XLD_METADATA_ARTIST];
                    }
                    else if(!strcasecmp(key,"genre")) {
                        ptr = strchr(value, '\n');
                        if(ptr) *ptr = 0;
                        NSString *str = [NSString stringWithUTF8String:value];
                        [metadataDic setObject:str forKey:XLD_METADATA_GENRE];
                    }
                    else if(!strcasecmp(key,"year")) {
                        ptr = strchr(value, '\n');
                        if(ptr) *ptr = 0;
                        NSString *str = [NSString stringWithUTF8String:value];
                        [metadataDic setObject:str forKey:XLD_METADATA_DATE];
                    }
                    else if(!strcasecmp(key,"comment")) {
                        ptr = strchr(value, '\n');
                        if(ptr) *ptr = 0;
                        NSString *str = [NSString stringWithUTF8String:value];
                        [metadataDic setObject:str forKey:XLD_METADATA_COMMENT];
                    }
                    else if(!strcasecmp(key,"_lib")) {
                        ptr = strchr(value, '\n');
                        if(ptr) *ptr = 0;
                        NSString *str = [NSString stringWithUTF8String:value];
                        libPath = [[[NSString stringWithUTF8String:path] stringByDeletingLastPathComponent] stringByAppendingPathComponent:str];
                    }
                    else if(!strcasecmp(key,"length")) {
                        ptr = strchr(value, '\n');
                        if(ptr) *ptr = 0;
                        length = timestr_to_double(value);
                    }
                    else if(!strcasecmp(key,"fade")) {
                        ptr = strchr(value, '\n');
                        if(ptr) *ptr = 0;
                        fade = timestr_to_double(value);
                    }
                }
                if(libPath) {
                    NSFileManager *mgr = [NSFileManager defaultManager];
                    if(![mgr fileExistsAtPath:libPath]) {
                        fclose(fp);
                        return NO;
                    }
                }
            }
        }
    }
    
    fclose(fp);
    
    totalFrames = [self samplerate] * (length + fade);
    fadeBeginning = [self samplerate] * length;
    
    if(![self initialize:path]) return NO;
    
    if(srcPath) [srcPath release];
    srcPath = [[NSString alloc] initWithUTF8String:path];
    return YES;
}

- (void)dealloc
{
    [metadataDic release];
    if(srcPath) [srcPath release];
    if(psxState) psx_clear_state(psxState, psfVersion);
    if(psf2fs) psf2fs_delete(psf2fs);
    free(decodeBuffer);
    [super dealloc];
}

- (int)samplerate
{
    return psfVersion == 1 ? 44100 : 48000;
}

- (int)bytesPerSample
{
    return 2;
}

- (int)channels
{
    return 2;
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
    if(count*4*2 > bufferSize) {
        bufferSize = count*4*2;
        decodeBuffer = realloc(decodeBuffer, bufferSize);
    }
    if(currentPos + count > totalFrames) {
        count = (int)(totalFrames - currentPos);
    }
    
    if(count == 0) return 0;
    
    int samplesToDecode = count;
    int ret = psx_execute(psxState, 0x7FFFFFFF, decodeBuffer, (unsigned int*)&samplesToDecode, 0);
    if(ret == -1) {
        bzero(decodeBuffer+samplesToDecode*2, (count-samplesToDecode)*4*2);
        samplesToDecode = count;
    }
    else if(ret < 0) {
        error = YES;
    }
    
    if(currentPos+count > fadeBeginning) {
        int i;
        int fadeLength = (int)(totalFrames - fadeBeginning);
        for(i=0;i<count;i++) {
            float gain = 32768.0f;
            if(currentPos+i > fadeBeginning) {
                gain *= (1.0f/fadeLength)*(fadeLength-(currentPos+i-fadeBeginning+1));
            }
            float valueL = *((float *)decodeBuffer+i*2)*gain;
            float valueR = *((float *)decodeBuffer+i*2+1)*gain;
            int roundedL,roundedR;
#if defined(__i386__)
            __asm__ (
                     "cvtss2si	%2, %0\n\t"
                     "cvtss2si	%3, %1\n\t"
                     : "=r"(roundedL), "=r"(roundedR)
                     : "x"(valueL), "x"(valueR)
            );
#else
            roundedL = (int)valueL;
            roundedR = (int)valueR;
#endif
            if(roundedL > 32767) roundedL = 32767;
            else if(roundedL < -32768) roundedL = -32768;
            if(roundedR > 32767) roundedR = 32767;
            else if(roundedR < -32768) roundedR = -32768;
            *(buffer+i*2) = roundedL << 16;
            *(buffer+i*2+1) = roundedR << 16;
        }
    }
    else {
        int i=0;
#if defined(__i386__)
        __m128 v0, v1;
        v1 = _mm_set1_ps(32768.0f);
        for(;i<count-1;i+=2) {
            v0 = _mm_load_ps(decodeBuffer+i*2);
            v0 = _mm_mul_ps(v0, v1);
            v0 = _mm_cvtps_epi32(v0);
            v0 = _mm_packs_epi32(v0, v0);
            v0 = _mm_unpacklo_epi16(v0, v0);
            v0 = _mm_slli_epi32(v0, 16);
            _mm_storeu_si128((__m128i*)(buffer+i*2), v0);
        }
#endif
        for(;i<count*2;i++) {
            float value = *((float *)decodeBuffer+i)*32768.0f;
            int rounded;
#if defined(__i386__)
            __asm__ (
                     "cvtss2si	%1, %0\n\t"
                     : "=r"(rounded)
                     : "x"(value)
            );
#else
            rounded = (int)value;
#endif
            if(rounded > 32767) rounded = 32767;
            else if(rounded < -32768) rounded = -32768;
            *(buffer+i) = rounded << 16;
        }
    }
    currentPos += count;
    return count;
}

- (xldoffset_t)seekToFrame:(xldoffset_t)count
{
    if(currentPos > count) {
        [self initialize:[srcPath UTF8String]];
        currentPos = 0;
    }
    if(currentPos < count) {
        int request = 4096;
        while(1) {
            if(currentPos + request > count) request = count - currentPos;
            psx_execute(psxState, 0x7FFFFFFF, decodeBuffer, (unsigned int*)&request, 0);
            currentPos += request;
            if(currentPos == count) break;
        }
    }
    return 0;
}

- (void)closeFile;
{
    [metadataDic removeAllObjects];
    if(psxState) psx_clear_state(psxState, psfVersion);
    if(psf2fs) psf2fs_delete(psf2fs);
    psxState = NULL;
    psf2fs = NULL;
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
