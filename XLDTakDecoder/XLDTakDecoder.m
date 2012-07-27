//
//  XLDTakDecoder.m
//  XLDTakDecoder
//
//  Created by tmkk on 10/02/13.
//  Copyright 2010 tmkk. All rights reserved.
//

#import "XLDTakDecoder.h"

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

#define TAK_CMD_BPS				0x0
#define TAK_CMD_CHANNELS		0x1
#define TAK_CMD_SAMPLERATE		0x2
#define TAK_CMD_TOTALSAMPLES	0x3
#define TAK_CMD_READ_METADATA	0x4
#define TAK_CMD_READ_SAMPLES	0x5
#define TAK_CMD_SEEK			0x6
#define TAK_CMD_CLOSE			0x7
#define TAK_CMD_ISVALID			0x8

@implementation XLDTakDecoder

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
	if(memcmp(buf,"tBaK",4)) return NO;
	return YES;
}

+ (BOOL)canLoadThisBundle
{
#if defined(__ppc__) || defined(__ppc64__)
	return NO;
#else
	BOOL fallback = NO;
	NSDictionary *environmentDict = [[NSProcessInfo processInfo] environment];
	NSString *shell = [environmentDict objectForKey:@"SHELL"];
	NSTask *task = [[NSTask alloc] init];
	[task setStandardOutput:[NSPipe pipe]];
	[task setStandardInput:[NSFileHandle fileHandleWithNullDevice]];
	[task setLaunchPath:shell];
	[task setCurrentDirectoryPath:[[NSBundle bundleForClass:[self class]] resourcePath]];
	NSMutableArray *args;
	if([shell isEqualToString:@"/bin/csh"] || [shell isEqualToString:@"/bin/tcsh"])
		args = [NSMutableArray arrayWithObjects:@"-i",@"-c",@"/usr/bin/which wine",nil];
	else
		args = [NSMutableArray arrayWithObjects:@"-l",@"-i",@"-c",@"/usr/bin/which wine",nil];
	[task setArguments:args];
	[task launch];
	NSData *data = [[[task standardOutput] fileHandleForReading] readDataToEndOfFile];
	[task terminate];
	[task release];
	if(!data || ![data length]) fallback = YES;
	else {
		NSString *str = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
		//NSLog(@"PATH:%@",str);
		if([str characterAtIndex:0] != '/') fallback = YES;
	}
	if(fallback) {
		//fallback - search crossover, winebottler or mikuinstaller
		NSFileManager *fm = [NSFileManager defaultManager];
		if([fm fileExistsAtPath:@"/Applications/Wine.app/Contents/Resources/bin/wine"]) return YES;
		if([fm fileExistsAtPath:@"/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wineloader"]) return YES;
		//if([fm fileExistsAtPath:@"/Applications/MikuInstaller.app/Contents/Resources/Wine.bundle/Contents/SharedSupport/bin/wine"]) return YES;
		return NO;
	}
	
	//NSLog(@"wine found!");
	return YES;
#endif
}


- (id)init
{
	[super init];
	error = NO;
	metadataDic = [[NSMutableDictionary alloc] init];
	srcPath = nil;
	task = nil;
	recvBufSize = 8192*4*2;
	recvBuf = (unsigned char*)malloc(recvBufSize);
	return self;
}

- (NSString *)pathForWine
{
	BOOL fallback = NO;
	NSDictionary *environmentDict = [[NSProcessInfo processInfo] environment];
	NSString *shell = [environmentDict objectForKey:@"SHELL"];
	NSTask *tmptask = [[NSTask alloc] init];
	[tmptask setStandardOutput:[NSPipe pipe]];
	[tmptask setStandardInput:[NSFileHandle fileHandleWithNullDevice]];
	[tmptask setLaunchPath:shell];
	[tmptask setCurrentDirectoryPath:[[NSBundle bundleForClass:[self class]] resourcePath]];
	[tmptask setEnvironment:environmentDict];
	NSMutableArray *args;
	if([shell isEqualToString:@"/bin/csh"] || [shell isEqualToString:@"/bin/tcsh"])
		args = [NSMutableArray arrayWithObjects:@"-i",@"-c",@"/usr/bin/which wine",nil];
	else args = [NSMutableArray arrayWithObjects:@"-l",@"-i",@"-c",@"/usr/bin/which wine",nil];
	[tmptask setArguments:args];
	[tmptask launch];
	NSData *data = [[[tmptask standardOutput] fileHandleForReading] readDataToEndOfFile];
	[tmptask terminate];
	[tmptask release];
	if(!data || ![data length]) fallback = YES;
	else {
		//NSLog(@"PATH:%@",[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
		NSString *str = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
		if([str characterAtIndex:0] != '/') fallback = YES;
	}
	if(fallback) {
		//fallback - search winebottler or mikuinstaller
		NSFileManager *fm = [NSFileManager defaultManager];
		if([fm fileExistsAtPath:@"/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wineloader"])
			return [NSString stringWithString:@"/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wineloader"];
		if([fm fileExistsAtPath:@"/Applications/Wine.app/Contents/Resources/bin/wine"])
			return [NSString stringWithString:@"/Applications/Wine.app/Contents/Resources/bin/wine"];
		/*if([fm fileExistsAtPath:@"/Applications/MikuInstaller.app/Contents/Resources/Wine.bundle/Contents/SharedSupport/bin/wine"])
			return [NSString stringWithString:@"/Applications/MikuInstaller.app/Contents/Resources/Wine.bundle/Contents/SharedSupport/bin/wine"];*/
		return nil;
	}
	const char *ptr = [data bytes];
	return [[[NSString alloc] initWithBytes:ptr length:[data length]-1 encoding:NSUTF8StringEncoding] autorelease];
}

- (void)findTagForKey:(char *)key andRegisterWithKey:(NSString *)dicKey
{
	NSFileHandle *writeHandle = [[task standardInput] fileHandleForWriting];
	NSFileHandle *readHandle = [[task standardOutput] fileHandleForReading];
	unsigned char cmd = TAK_CMD_READ_METADATA;
	int length = strlen(key);
	[writeHandle writeData:[NSData dataWithBytes:&cmd length:1]];
	[writeHandle writeData:[NSData dataWithBytes:&length length:4]];
	[writeHandle writeData:[NSData dataWithBytes:key length:length]];
	[[readHandle readDataOfLength:4] getBytes:&length length:4];
	if(length) {
		NSString *str = [[NSString alloc] initWithData:[readHandle readDataOfLength:length] encoding:NSUTF8StringEncoding];
		if(!str) return;
		if(!strcmp(key,"track")) {
			int track = [str intValue];
			if(track>0) [metadataDic setObject:[NSNumber numberWithInt:track] forKey:XLD_METADATA_TRACK];
		}
		else if(!strcmp(key,"year")) {
			int year = [str intValue];
			if(year >= 1000 && year < 3000) [metadataDic setObject:[NSNumber numberWithInt:year] forKey:XLD_METADATA_YEAR];
		}
		else [metadataDic setObject:str forKey:dicKey];
		//NSLog(str);
		[str release];
	}
}

- (void)findBinaryTagForKey:(char *)key andRegisterWithKey:(NSString *)dicKey
{
	NSFileHandle *writeHandle = [[task standardInput] fileHandleForWriting];
	NSFileHandle *readHandle = [[task standardOutput] fileHandleForReading];
	unsigned char cmd = TAK_CMD_READ_METADATA;
	int length = strlen(key);
	[writeHandle writeData:[NSData dataWithBytes:&cmd length:1]];
	[writeHandle writeData:[NSData dataWithBytes:&length length:4]];
	[writeHandle writeData:[NSData dataWithBytes:key length:length]];
	[[readHandle readDataOfLength:4] getBytes:&length length:4];
	if(length) {
		const char *buf = [[readHandle readDataOfLength:length] bytes];
		int i=0;
		while(buf[i] != 0) i++;
		i++;
		NSData *imgData = [NSData dataWithBytes:buf+i length:length-i];
		[metadataDic setObject:imgData forKey:dicKey];
	}
}

- (BOOL)openFile:(char *)path
{
	task = [[NSTask alloc] init];
	NSMutableDictionary *environmentDict = [NSMutableDictionary dictionaryWithDictionary:[[NSProcessInfo processInfo] environment]];
	[task setStandardInput:[NSPipe pipe]];
	[task setStandardOutput:[NSPipe pipe]];
	NSString *winePath = [self pathForWine];
	[task setLaunchPath:winePath];
	[task setCurrentDirectoryPath:[[NSBundle bundleForClass:[self class]] resourcePath]];
	NSString *libPaths;
	libPaths = [NSString stringWithFormat:@"/usr/X11/lib:%@",[[[winePath stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"lib"]];
	if([environmentDict objectForKey:@"DYLD_FALLBACK_LIBRARY_PATH"]) {
		[environmentDict setObject:[NSString stringWithFormat:@"%@:%@",[environmentDict objectForKey:@"DYLD_FALLBACK_LIBRARY_PATH"],libPaths] forKey:@"DYLD_FALLBACK_LIBRARY_PATH"];
	}
	else [environmentDict setObject:[NSString stringWithFormat:@"/usr/local/lib:/lib:/usr/lib:%@",libPaths] forKey:@"DYLD_FALLBACK_LIBRARY_PATH"];
	NSLog(@"%@",[environmentDict objectForKey:@"DYLD_FALLBACK_LIBRARY_PATH"]);
	[environmentDict setObject:@"-all" forKey:@"WINEDEBUG"];
	[task setEnvironment:environmentDict];
	NSMutableArray *args = [NSMutableArray arrayWithObjects:@"tak_decoder.exe.so",[NSString stringWithUTF8String:path],nil];
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
	
	unsigned char cmd;
	cmd = TAK_CMD_ISVALID;
	int valid;
	[writeHandle writeData:[NSData dataWithBytes:&cmd length:1]];
	[[readHandle readDataOfLength:4] getBytes:&valid length:4];
	if(!valid) {
		cmd = TAK_CMD_CLOSE;
		[writeHandle writeData:[NSData dataWithBytes:&cmd length:1]];
		[task release];
		task = nil;
		return NO;
	}
	
	cmd = TAK_CMD_BPS;
	[writeHandle writeData:[NSData dataWithBytes:&cmd length:1]];
	[[readHandle readDataOfLength:4] getBytes:&bps length:4];
	bps >>= 3;
	cmd = TAK_CMD_CHANNELS;
	[writeHandle writeData:[NSData dataWithBytes:&cmd length:1]];
	[[readHandle readDataOfLength:4] getBytes:&channels length:4];
	cmd = TAK_CMD_SAMPLERATE;
	[writeHandle writeData:[NSData dataWithBytes:&cmd length:1]];
	[[readHandle readDataOfLength:4] getBytes:&samplerate length:4];
	cmd = TAK_CMD_TOTALSAMPLES;
	[writeHandle writeData:[NSData dataWithBytes:&cmd length:1]];
	[[readHandle readDataOfLength:8] getBytes:&totalFrames length:8];
	
	[self findTagForKey:"title" andRegisterWithKey:XLD_METADATA_TITLE];
	[self findTagForKey:"artist" andRegisterWithKey:XLD_METADATA_ARTIST];
	[self findTagForKey:"album" andRegisterWithKey:XLD_METADATA_ALBUM];
	[self findTagForKey:"genre" andRegisterWithKey:XLD_METADATA_GENRE];
	[self findTagForKey:"year" andRegisterWithKey:XLD_METADATA_YEAR];
	[self findTagForKey:"composer" andRegisterWithKey:XLD_METADATA_COMPOSER];
	[self findTagForKey:"track" andRegisterWithKey:XLD_METADATA_TRACK];
	[self findTagForKey:"comment" andRegisterWithKey:XLD_METADATA_COMMENT];
	[self findTagForKey:"lyrics" andRegisterWithKey:XLD_METADATA_LYRICS];
	[self findTagForKey:"isrc" andRegisterWithKey:XLD_METADATA_ISRC];
	[self findTagForKey:"cuesheet" andRegisterWithKey:XLD_METADATA_CUESHEET];
	[self findTagForKey:"iTunes_CDDB_1" andRegisterWithKey:XLD_METADATA_GRACENOTE2];
	[self findTagForKey:"MUSICBRAINZ_TRACKID" andRegisterWithKey:XLD_METADATA_MB_TRACKID];
	[self findTagForKey:"MUSICBRAINZ_ALBUMID" andRegisterWithKey:XLD_METADATA_MB_ALBUMID];
	[self findTagForKey:"MUSICBRAINZ_ARTISTID" andRegisterWithKey:XLD_METADATA_MB_ARTISTID];
	[self findTagForKey:"MUSICBRAINZ_ALBUMARTISTID" andRegisterWithKey:XLD_METADATA_MB_ALBUMARTISTID];
	[self findTagForKey:"MUSICBRAINZ_DISCID" andRegisterWithKey:XLD_METADATA_MB_DISCID];
	[self findTagForKey:"MUSICIP_PUID" andRegisterWithKey:XLD_METADATA_PUID];
	[self findTagForKey:"MUSICBRAINZ_ALBUMSTATUS" andRegisterWithKey:XLD_METADATA_MB_ALBUMSTATUS];
	[self findTagForKey:"MUSICBRAINZ_ALBUMTYPE" andRegisterWithKey:XLD_METADATA_MB_ALBUMTYPE];
	[self findTagForKey:"RELEASECOUNTRY" andRegisterWithKey:XLD_METADATA_MB_RELEASECOUNTRY];
	[self findTagForKey:"MUSICBRAINZ_RELEASEGROUPID" andRegisterWithKey:XLD_METADATA_MB_RELEASEGROUPID];
	[self findTagForKey:"MUSICBRAINZ_WORKID" andRegisterWithKey:XLD_METADATA_MB_WORKID];
	[self findBinaryTagForKey:"Cover Art (front)" andRegisterWithKey:XLD_METADATA_COVER];
	
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
			unsigned char cmd = TAK_CMD_CLOSE;
			[writeHandle writeData:[NSData dataWithBytes:&cmd length:1]];
		}
		[task release];
	}
	free(recvBuf);
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
	NSFileHandle *writeHandle = [[task standardInput] fileHandleForWriting];
	NSFileHandle *readHandle = [[task standardOutput] fileHandleForReading];
	unsigned char cmd = TAK_CMD_READ_SAMPLES;
	[writeHandle writeData:[NSData dataWithBytes:&cmd length:1]];
	[writeHandle writeData:[NSData dataWithBytes:&count length:4]];
	int read,i;
	[[readHandle readDataOfLength:4] getBytes:&read length:4];
	if(read>0) {
		if(read*bps*channels > recvBufSize) {
			free(recvBuf);
			recvBuf = (unsigned char *)malloc(read*bps*channels);
			recvBufSize = read*bps*channels;
		}
		switch(bps) {
			case 1:
				[[readHandle readDataOfLength:read*channels] getBytes:recvBuf length:read*channels];
				for(i=0;i<read*channels;i++) {
					int sample = ((recvBuf[i]+0x80)&0xff)<<24;
					buffer[i] = sample;
				}
				break;
			case 2:
				[[readHandle readDataOfLength:read*2*channels] getBytes:recvBuf length:read*2*channels];
				short *ptr = (short *)recvBuf;
				for(i=0;i<read*channels;i++) {
					int sample = *(ptr+i)<<16;
					buffer[i] = sample;
				}
				break;
			case 3:
				[[readHandle readDataOfLength:read*3*channels] getBytes:recvBuf length:read*3*channels];
				for(i=0;i<read*channels;i++) {
					int sample = (recvBuf[i*3]<<8)|(recvBuf[i*3+1]<<16)|(recvBuf[i*3+2]<<24);
					buffer[i] = sample;
				}
				break;
			case 4:
				[[readHandle readDataOfLength:read*4*channels] getBytes:buffer length:read*4*channels];
				break;
		}
	}
	else if(read<0) error = YES;
	return read;
}

- (xldoffset_t)seekToFrame:(xldoffset_t)count
{
	NSFileHandle *writeHandle = [[task standardInput] fileHandleForWriting];
	NSFileHandle *readHandle = [[task standardOutput] fileHandleForReading];
	unsigned char cmd = TAK_CMD_SEEK;
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
			unsigned char cmd = TAK_CMD_CLOSE;
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
	if([metadataDic objectForKey:XLD_METADATA_CUESHEET]) return XLDTextTypeCueSheet;
	else return XLDNoCueSheet;
}

- (id)cueSheet
{
	return [metadataDic objectForKey:XLD_METADATA_CUESHEET];
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
