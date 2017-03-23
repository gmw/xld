//
//  XLDSPCDecoder.m
//  XLDSPCDecoder
//
//  Created by tmkk on 2017/02/28.
//  Copyright © 2017年 tmkk. All rights reserved.
//

#import "XLDSPCDecoder.h"

#define SPC_CMD_TOTALSAMPLES	0x0
#define SPC_CMD_READ_SAMPLES	0x1
#define SPC_CMD_SEEK			0x2
#define SPC_CMD_CLOSE			0x3

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

@implementation XLDSPCDecoder

+ (BOOL)canHandleFile:(char *)path
{
    FILE *fp = fopen(path,"rb");
    if(!fp) return NO;
    char buf[27];
    if(fread(buf,1,27,fp) < 27) {
        fclose(fp);
        return NO;
    }
    fclose(fp);
    if(memcmp(buf,"SNES-SPC700 Sound File Data",27)) return NO;
    return YES;
}

+ (BOOL)canLoadThisBundle
{
#if defined(__ppc__) || defined(__ppc64__)
    return NO;
#else
    return YES;
#endif
}


- (id)init
{
    self = [super init];
    if(self) {
        metadataDic = [[NSMutableDictionary alloc] init];
        recvBufSize = 8192*4*2;
        recvBuf = (unsigned char*)malloc(recvBufSize);
    }
    return self;
}

- (BOOL)openFile:(char *)path
{
    FILE *fp = fopen(path,"rb");
    if(!fp) return NO;
    char buf[256];
    if(fread(buf,1,256,fp) < 256) {
        fclose(fp);
        return NO;
    }
    fclose(fp);
    if(memcmp(buf,"SNES-SPC700 Sound File Data",27)) return NO;
    
    if(buf[0x23] == 0x1a) {
        NSString *str;
        char text[33];
        text[32] = 0;
        if(buf[0x2e] != 0) {
            memcpy(text,buf+0x2e,32);
            str = [NSString stringWithUTF8String:text];
            [metadataDic setObject:str forKey:XLD_METADATA_TITLE];
        }
        if(buf[0x4e] != 0) {
            memcpy(text,buf+0x4e,32);
            str = [NSString stringWithUTF8String:text];
            [metadataDic setObject:str forKey:XLD_METADATA_ALBUM];
        }
        if(buf[0x7e] != 0) {
            memcpy(text,buf+0x7e,32);
            str = [NSString stringWithUTF8String:text];
            [metadataDic setObject:str forKey:XLD_METADATA_COMMENT];
        }
        if(buf[0xd2] < 0x30) {
            if(buf[0xb0] != 0) {
                memcpy(text,buf+0xb0,32);
                str = [NSString stringWithUTF8String:text];
                [metadataDic setObject:str forKey:XLD_METADATA_COMPOSER];
            }
        }
        else {
            if(buf[0xb1] != 0) {
                memcpy(text,buf+0xb1,32);
                str = [NSString stringWithUTF8String:text];
                [metadataDic setObject:str forKey:XLD_METADATA_COMPOSER];
            }
        }
        
    }
    
    task = [[NSTask alloc] init];
    [task setStandardInput:[NSPipe pipe]];
    [task setStandardOutput:[NSPipe pipe]];
    [task setLaunchPath:[[[NSBundle bundleForClass:[self class]] resourcePath] stringByAppendingPathComponent:@"snesapudec"]];
    NSMutableArray *args = [NSMutableArray arrayWithObjects:[NSString stringWithUTF8String:path],nil];
    [task setArguments:args];
    [task launch];
    if(![task isRunning]) {
        [task release];
        task = nil;
        return NO;
    }
    
    NSFileHandle *writeHandle = [[task standardInput] fileHandleForWriting];
    NSFileHandle *readHandle = [[task standardOutput] fileHandleForReading];
    if(!writeHandle || !readHandle) {
        [task release];
        task = nil;
        return NO;
    }
    
    unsigned char cmd = SPC_CMD_TOTALSAMPLES;
    [writeHandle writeData:[NSData dataWithBytes:&cmd length:1]];
    [[readHandle readDataOfLength:8] getBytes:&totalFrames length:8];
    
    if(srcPath) [srcPath release];
    srcPath = [[NSString alloc] initWithUTF8String:path];
    return YES;
}

- (void)dealloc
{
    [metadataDic release];
    if(srcPath) [srcPath release];
    if(task) {
        if([task isRunning]) {
            NSFileHandle *writeHandle = [[task standardInput] fileHandleForWriting];
            unsigned char cmd = SPC_CMD_CLOSE;
            [writeHandle writeData:[NSData dataWithBytes:&cmd length:1]];
        }
        [task release];
    }
    free(recvBuf);
    [super dealloc];
}

- (int)samplerate
{
    return 32000;
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
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSFileHandle *writeHandle = [[task standardInput] fileHandleForWriting];
    NSFileHandle *readHandle = [[task standardOutput] fileHandleForReading];
    unsigned char cmd = SPC_CMD_READ_SAMPLES;
    [writeHandle writeData:[NSData dataWithBytes:&cmd length:1]];
    [writeHandle writeData:[NSData dataWithBytes:&count length:4]];
    int read,i;
    [[readHandle readDataOfLength:4] getBytes:&read length:4];
    if(read>0) {
        if(read*4*2 > recvBufSize) {
            free(recvBuf);
            recvBuf = (unsigned char *)malloc(read*4*2);
            recvBufSize = read*4*2;
        }
        [[readHandle readDataOfLength:read*4*2] getBytes:recvBuf length:read*4*2];
        int *ptr = (int *)recvBuf;
        for(i=0;i<read*2;i++) {
            buffer[i] = *(ptr+i);
        }
    }
    else if(read<0) error = YES;
    [pool release];
    return read;
}

- (xldoffset_t)seekToFrame:(xldoffset_t)count
{
    NSFileHandle *writeHandle = [[task standardInput] fileHandleForWriting];
    NSFileHandle *readHandle = [[task standardOutput] fileHandleForReading];
    unsigned char cmd = SPC_CMD_SEEK;
    [writeHandle writeData:[NSData dataWithBytes:&cmd length:1]];
    [writeHandle writeData:[NSData dataWithBytes:&count length:8]];
    int ret;
    [[readHandle readDataOfLength:4] getBytes:&ret length:4];
    if(ret) error = YES;
    return ret ? 0 : count;
}

- (void)closeFile;
{
    [metadataDic removeAllObjects];
    if(task) {
        if([task isRunning]) {
            NSFileHandle *writeHandle = [[task standardInput] fileHandleForWriting];
            unsigned char cmd = SPC_CMD_CLOSE;
            [writeHandle writeData:[NSData dataWithBytes:&cmd length:1]];
        }
        [task release];
        task = nil;
    }
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
