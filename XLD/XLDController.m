// Access to AccurateRip is regulated, see  http://www.accuraterip.com/3rdparty-access.htm for details.

#import <sys/stat.h>
#import <fcntl.h>
#import <IOKit/scsi/IOSCSIMultimediaCommandsDevice.h>
#import <DiskArbitration/DiskArbitration.h>
#import "XLDController.h"
#import "XLDecoderCenter.h"
#import "XLDDecoder.h"
#import "XLDWavOutput.h"
#import "XLDAiffOutput.h"
#import "XLDWave64Output.h"
#import "XLDPcmBEOutput.h"
#import "XLDPcmLEOutput.h"
#import "XLDDefaultOutputTask.h"
#import "XLDCueParser.h"
#import "XLDTrack.h"
#import "XLDOutput.h"
#import "XLDPlayer.h"
#import "XLDQueue.h"
#import "XLDConverterTask.h"
#import "XLDRawDecoder.h"
#import "XLDMetadataEditor.h"
#import "XLDCDDARipper.h"
#import "XLDAccurateRipDB.h"
#import "XLDAccurateRipChecker.h"
#import "XLDDDPParser.h"
#import "XLDCustomClasses.h"
#import "XLDCustomFormatManager.h"
#import "XLDCDDABackend.h"
#import "XLDMultipleFileWrappedDecoder.h"
#import "XLDProfileManager.h"
#import "XLDDiscView.h"
#import "XLDCoverArtSearcher.h"
#import "XLDShadowedImageView.h"
#import "XLDPluginManager.h"

static NSString*    GeneralIdentifier = @"General";
static NSString*    BatchIdentifier = @"Batch";
static NSString*    CDDBIdentifier = @"CDDB";
static NSString*    MetadataIdentifier = @"Metadata";
static NSString*    CDRipIdentifier = @"CD Rip";
static NSString*    BurnIdentifier = @"Burn";

static void DADoneCallback(DADiskRef DiskRef, DADissenterRef DissenterRef, void *context) 
{
	//NSLog(@"done");
    CFRunLoopStop(CFRunLoopGetCurrent());
}

static void diskAppeared(DADiskRef disk, void *context)
{
	//NSLog(@"appear");
	//NSLog(@"%s",DADiskGetBSDName(disk));
	[(id)context performSelector:@selector(updateCDDAListAndMount:) withObject:[NSString stringWithUTF8String:(const char*)DADiskGetBSDName(disk)] afterDelay:1.0];
}

static void diskDisappeared(DADiskRef disk, void *context)
{
	//NSLog(@"disappear");
	[[(id)context discView] closeFile:[@"/dev" stringByAppendingPathComponent:[NSString stringWithUTF8String:(const char*)DADiskGetBSDName(disk)]]]; 
	[(id)context updateCDDAList:nil];
}

static DADissenterRef diskMounted(DADiskRef disk, void *context)
{
	//NSLog(@"mount");
	[(id)context performSelector:@selector(updateCDDAListAndMount:) withObject:nil afterDelay:1.0];
	return NULL;
}

static int intSort(id num1, id num2, void *context)
{
    int v1 = [num1 intValue];
    int v2 = [num2 intValue];
	
    if (v1 < v2)
        return NSOrderedDescending;
    else if (v1 > v2)
        return NSOrderedAscending;
    else
        return NSOrderedSame;
}

static NSString *mountNameFromBSDName(const char *bsdName)
{
	NSString *volume;
	DASessionRef session = DASessionCreate(NULL);
	DADiskRef disk = DADiskCreateFromBSDName(NULL,session,bsdName);
	CFDictionaryRef dic = DADiskCopyDescription(disk);
	volume = [NSString stringWithString:(NSString *)CFDictionaryGetValue(dic,kDADiskDescriptionVolumeNameKey)];
	CFRelease(dic);
	CFRelease(disk);
	CFRelease(session);
	
	return volume;
}
	

#define kAudioCDFilesystemID			(UInt16)(('J' << 8) | 'H' ) // 'JH'; this avoids compiler warning

#ifdef _BIG_ENDIAN
#define SWAP32(n) (n)
#define SWAP16(n) (n)
#else
#define SWAP32(n) (((n>>24)&0xff) | ((n>>8)&0xff00) | ((n<<8)&0xff0000) | ((n<<24)&0xff000000))
#define SWAP16(n) (((n>>8)&0xff) | ((n<<8)&0xff00))
#endif

#define MAX_SERVICE_NAME 1000

@implementation XLDController

- (NSArray *)coverArtFileListArray;
{
	NSCharacterSet* chSet;
    NSString* scannedName;
    NSScanner* scanner;
	NSMutableArray *arr = [NSMutableArray array];
    
    chSet = [NSCharacterSet characterSetWithCharactersInString:@" "];
    scanner = [NSScanner scannerWithString:[o_autoLoadCoverArtName stringValue]];
    while(![scanner isAtEnd]) {
        if([scanner scanUpToCharactersFromSet:chSet intoString:&scannedName]) {
			[arr addObject:scannedName];
        }
        [scanner scanCharactersFromSet:chSet intoString:nil];
    }
	return arr;
}

- (NSData *)dataForAutoloadCoverArtForFile:(NSString *)file fileListArray:(NSArray *)arr
{
	int i;
	NSData *imgData;
	for(i=0;i<[arr count];i++) {
		imgData = [NSData dataWithContentsOfFile:[[file stringByDeletingLastPathComponent] stringByAppendingPathComponent:[arr objectAtIndex:i]]];
		if(imgData) {
			NSImage *img = [[NSImage alloc] initWithData:imgData];
			if(img) {
				[img release];
				return imgData;
			}
		}
	}
	imgData = [NSData dataWithContentsOfFile:[[file stringByDeletingPathExtension] stringByAppendingPathExtension:@"jpg"]];
	if(imgData) {
		NSImage *img = [[NSImage alloc] initWithData:imgData];
		if(img) {
			[img release];
			return imgData;
		}
	}
	imgData = [NSData dataWithContentsOfFile:[[file stringByDeletingPathExtension] stringByAppendingPathExtension:@"png"]];
	if(imgData) {
		NSImage *img = [[NSImage alloc] initWithData:imgData];
		if(img) {
			[img release];
			return imgData;
		}
	}
	return nil;
}

- (NSString *)currentOutputFormatString
{
	if([[o_formatList selectedItem] tag] == 1) return @"";
	return [[[outputArr objectAtIndex:[o_formatList indexOfSelectedItem]] class] pluginName];
}

- (NSString *)formattedStringForTrack:(id)trk withPattern:(NSString *)pattern singleImageMode:(BOOL)singleImageMode albumArtist:aartist
{
	int j;
	NSMutableString *str;
	
	NSString *name,*artist,*album,*albumartist,*composer,*genre;
	int idx = [[trk metadata] objectForKey:XLD_METADATA_TRACK] ? [[[trk metadata] objectForKey:XLD_METADATA_TRACK] intValue] : 1;
	name = [[trk metadata] objectForKey:XLD_METADATA_TITLE];
	artist = [[trk metadata] objectForKey:XLD_METADATA_ARTIST];
	album = [[trk metadata] objectForKey:XLD_METADATA_ALBUM];
	composer = [[trk metadata] objectForKey:XLD_METADATA_COMPOSER];
	genre = [[trk metadata] objectForKey:XLD_METADATA_GENRE];
	if(aartist == nil) albumartist = artist;
	else {
		if([[trk metadata] objectForKey:XLD_METADATA_ALBUMARTIST]) aartist = [[trk metadata] objectForKey:XLD_METADATA_ALBUMARTIST];
		albumartist = [aartist isEqualToString:@""] ? artist : aartist;
	}
	if([[trk metadata] objectForKey:XLD_METADATA_COMPILATION] && ![[trk metadata] objectForKey:XLD_METADATA_ALBUMARTIST]) {
		if([[[trk metadata] objectForKey:XLD_METADATA_COMPILATION] boolValue])
			albumartist = (NSMutableString *)@"Compilations";
	}
	if(singleImageMode) {
		name = album;
		artist = albumartist;
	}
	
	str = [[[NSMutableString alloc] init] autorelease];
	for(j=0;j<[pattern length]-1;j++) {
		/* track number */
		if([[pattern substringWithRange:NSMakeRange(j,2)] isEqualToString:@"%n"]) {
			[str appendFormat: @"%02d",idx];
			j++;
		}
		/* disc number */
		else if([[pattern substringWithRange:NSMakeRange(j,2)] isEqualToString:@"%D"]) {
			if([[trk metadata] objectForKey:XLD_METADATA_DISC]) {
				[str appendFormat: @"%02d",[[[trk metadata] objectForKey:XLD_METADATA_DISC] intValue]];
			}
			else [str appendString:@"01"];
			j++;
		}
		/* title */
		else if([[pattern substringWithRange:NSMakeRange(j,2)] isEqualToString:@"%t"]) {
			if(name && ![name isEqualToString:@""]) [str appendString: name];
			else [str appendString: @"Unknown Title"];
			j++;
		}
		/* artist */
		else if([[pattern substringWithRange:NSMakeRange(j,2)] isEqualToString:@"%a"]) {
			if(artist && ![artist isEqualToString:@""]) [str appendString: artist];
			else [str appendString: @"Unknown Artist"];
			j++;
		}
		/* album title */
		else if([[pattern substringWithRange:NSMakeRange(j,2)] isEqualToString:@"%T"]) {
			if(album && ![album isEqualToString:@""]) [str appendString: album];
			else [str appendString: @"Unknown Album"];
			j++;
		}
		/* album artist */
		else if([[pattern substringWithRange:NSMakeRange(j,2)] isEqualToString:@"%A"]) {
			if(albumartist && ![albumartist isEqualToString:@""]) [str appendString: albumartist];
			else [str appendString: @"Unknown Artist"];
			j++;
		}
		/* composer */
		else if([[pattern substringWithRange:NSMakeRange(j,2)] isEqualToString:@"%c"]) {
			if(composer && ![composer isEqualToString:@""]) [str appendString: composer];
			else [str appendString: @"Unknown Composer"];
			j++;
		}
		/* year */
		else if([[pattern substringWithRange:NSMakeRange(j,2)] isEqualToString:@"%y"]) {
			NSNumber *year = [[trk metadata] objectForKey:XLD_METADATA_YEAR];
			if(year) [str appendString: [year stringValue]];
			else [str appendString: @"Unknown Year"];
			j++;
		}
		/* genre */
		else if([[pattern substringWithRange:NSMakeRange(j,2)] isEqualToString:@"%g"]) {
			if(genre && ![genre isEqualToString:@""]) [str appendString: genre];
			else [str appendString: @"Unknown Genre"];
			j++;
		}
		/* isrc */
		else if([[pattern substringWithRange:NSMakeRange(j,2)] isEqualToString:@"%i"]) {
			NSString *isrc = [[trk metadata] objectForKey:XLD_METADATA_ISRC];
			if(isrc && ![isrc isEqualToString:@""]) [str appendString: isrc];
			else [str appendString: @"NO_ISRC"];
			j++;
		}
		/* mcn */
		else if([[pattern substringWithRange:NSMakeRange(j,2)] isEqualToString:@"%m"]) {
			NSString *mcn = [[trk metadata] objectForKey:XLD_METADATA_CATALOG];
			if(mcn && ![mcn isEqualToString:@""]) [str appendString: mcn];
			else [str appendString: @"NO_MCN"];
			j++;
		}
		/* discid */
		else if([[pattern substringWithRange:NSMakeRange(j,2)] isEqualToString:@"%I"]) {
			NSNumber *discid = [[trk metadata] objectForKey:XLD_METADATA_FREEDBDISCID];
			if(discid) [str appendString: [NSString stringWithFormat:@"%08X", [discid unsignedIntValue]]];
			else [str appendString: @"NO_DISCID"];
			j++;
		}
		/* format */
		else if([[pattern substringWithRange:NSMakeRange(j,2)] isEqualToString:@"%f"]) {
			if([[o_formatList selectedItem] tag] == 1)
				[str appendString: @"[[[XLD_FORMAT_INDICATOR]]]"];
			else [str appendString: [self currentOutputFormatString]];
			j++;
		}
		else {
			[str appendString: [pattern substringWithRange:NSMakeRange(j,1)]];
		}
	}
	if(j==[pattern length]-1) [str appendString: [pattern substringWithRange:NSMakeRange(j,1)]];
	
	//NSLog(@"%@",str);
	return str;
}

- (NSString *)preferredFilenameForTrack:(id)trk createSubDir:(BOOL)createSubDir singleImageMode:(BOOL)singleImageMode albumArtist:aartist
{
	int j;
	NSMutableString *str;
	
	NSString *name,*artist,*album,*albumartist,*composer,*genre;
	int idx = [[trk metadata] objectForKey:XLD_METADATA_TRACK] ? [[[trk metadata] objectForKey:XLD_METADATA_TRACK] intValue] : 1;
	name = [[trk metadata] objectForKey:XLD_METADATA_TITLE];
	artist = [[trk metadata] objectForKey:XLD_METADATA_ARTIST];
	album = [[trk metadata] objectForKey:XLD_METADATA_ALBUM];
	composer = [[trk metadata] objectForKey:XLD_METADATA_COMPOSER];
	genre = [[trk metadata] objectForKey:XLD_METADATA_GENRE];
	if(aartist == nil) albumartist = artist;
	else {
		if([[trk metadata] objectForKey:XLD_METADATA_ALBUMARTIST]) aartist = [[trk metadata] objectForKey:XLD_METADATA_ALBUMARTIST];
		albumartist = [aartist isEqualToString:@""] ? artist : aartist;
	}
	if([[trk metadata] objectForKey:XLD_METADATA_COMPILATION] && ![[trk metadata] objectForKey:XLD_METADATA_ALBUMARTIST]) {
		if([[[trk metadata] objectForKey:XLD_METADATA_COMPILATION] boolValue])
			albumartist = (NSMutableString *)@"Compilations";
	}
	if(singleImageMode) {
		name = album;
		artist = albumartist;
	}
	
	if([[o_filenameFormatRadio selectedCell] tag] == 0) {
		if(name && artist && ![name isEqualToString:@""] && ![artist isEqualToString:@""])
			str = [NSMutableString stringWithFormat:@"%02d %@ - %@",idx,artist,name];
		else if(name && ![name isEqualToString:@""])
			str = [NSMutableString stringWithFormat:@"%02d %@",idx,name];
		else if(artist && ![artist isEqualToString:@""])
			str = [NSMutableString stringWithFormat:@"%02d %@ - Track %02d",idx,artist,idx];
		else
			str = [NSMutableString stringWithFormat:@"%02d Track %02d",idx,idx];
	}
	else {
		NSString *pattern = [[o_filenameFormat stringValue] stringByStandardizingPath];
		if([pattern characterAtIndex:[pattern length]-1] == '/') pattern = [pattern substringToIndex:[pattern length]-2];
		if([pattern characterAtIndex:0] == '/') pattern = [pattern substringFromIndex:1];
		str = [[[NSMutableString alloc] init] autorelease];
		for(j=0;j<[pattern length]-1;j++) {
			/* track number */
			if([[pattern substringWithRange:NSMakeRange(j,2)] isEqualToString:@"%n"]) {
				[str appendFormat: @"%02d",idx];
				j++;
			}
			/* disc number */
			else if([[pattern substringWithRange:NSMakeRange(j,2)] isEqualToString:@"%D"]) {
				if([[trk metadata] objectForKey:XLD_METADATA_DISC]) {
					[str appendFormat: @"%02d",[[[trk metadata] objectForKey:XLD_METADATA_DISC] intValue]];
				}
				else [str appendString:@"01"];
				j++;
			}
			/* title */
			else if([[pattern substringWithRange:NSMakeRange(j,2)] isEqualToString:@"%t"]) {
				if(name && ![name isEqualToString:@""]) [str appendString: name];
				else [str appendString: @"Unknown Title"];
				j++;
			}
			/* artist */
			else if([[pattern substringWithRange:NSMakeRange(j,2)] isEqualToString:@"%a"]) {
				if(artist && ![artist isEqualToString:@""]) [str appendString: artist];
				else [str appendString: @"Unknown Artist"];
				j++;
			}
			/* album title */
			else if([[pattern substringWithRange:NSMakeRange(j,2)] isEqualToString:@"%T"]) {
				if(album && ![album isEqualToString:@""]) [str appendString: album];
				else [str appendString: @"Unknown Album"];
				j++;
			}
			/* album artist */
			else if([[pattern substringWithRange:NSMakeRange(j,2)] isEqualToString:@"%A"]) {
				if(albumartist && ![albumartist isEqualToString:@""]) [str appendString: albumartist];
				else [str appendString: @"Unknown Artist"];
				j++;
			}
			/* composer */
			else if([[pattern substringWithRange:NSMakeRange(j,2)] isEqualToString:@"%c"]) {
				if(composer && ![composer isEqualToString:@""]) [str appendString: composer];
				else [str appendString: @"Unknown Composer"];
				j++;
			}
			/* year */
			else if([[pattern substringWithRange:NSMakeRange(j,2)] isEqualToString:@"%y"]) {
				NSNumber *year = [[trk metadata] objectForKey:XLD_METADATA_YEAR];
				if(year) [str appendString: [year stringValue]];
				else [str appendString: @"Unknown Year"];
				j++;
			}
			/* genre */
			else if([[pattern substringWithRange:NSMakeRange(j,2)] isEqualToString:@"%g"]) {
				if(genre && ![genre isEqualToString:@""]) [str appendString: genre];
				else [str appendString: @"Unknown Genre"];
				j++;
			}
			/* isrc */
			else if([[pattern substringWithRange:NSMakeRange(j,2)] isEqualToString:@"%i"]) {
				NSString *isrc = [[trk metadata] objectForKey:XLD_METADATA_ISRC];
				if(isrc && ![isrc isEqualToString:@""]) [str appendString: isrc];
				else [str appendString: @"NO_ISRC"];
				j++;
			}
			/* mcn */
			else if([[pattern substringWithRange:NSMakeRange(j,2)] isEqualToString:@"%m"]) {
				NSString *mcn = [[trk metadata] objectForKey:XLD_METADATA_CATALOG];
				if(mcn && ![mcn isEqualToString:@""]) [str appendString: mcn];
				else [str appendString: @"NO_MCN"];
				j++;
			}
			/* discid */
			else if([[pattern substringWithRange:NSMakeRange(j,2)] isEqualToString:@"%I"]) {
				NSNumber *discid = [[trk metadata] objectForKey:XLD_METADATA_FREEDBDISCID];
				if(discid) [str appendString: [NSString stringWithFormat:@"%08X", [discid unsignedIntValue]]];
				else [str appendString: @"NO_DISCID"];
				j++;
			}
			/* format */
			else if([[pattern substringWithRange:NSMakeRange(j,2)] isEqualToString:@"%f"]) {
				if([[o_formatList selectedItem] tag] == 1)
					[str appendString: @"[[[XLD_FORMAT_INDICATOR]]]"];
				else [str appendString: [self currentOutputFormatString]];
				j++;
			}
			else if([[pattern substringWithRange:NSMakeRange(j,1)] isEqualToString:@"/"]) {
				[str appendString: @"[[[XLD_DIRECTORY_SEPARATOR]]]"];
			}
			else {
				[str appendString: [pattern substringWithRange:NSMakeRange(j,1)]];
			}
		}
		if(j==[pattern length]-1) [str appendString: [pattern substringWithRange:NSMakeRange(j,1)]];
		if(!createSubDir || [[o_formatList selectedItem] tag] != 1)
			[str replaceOccurrencesOfString:@"[[[XLD_FORMAT_INDICATOR]]]" withString:[self currentOutputFormatString] options:0 range:NSMakeRange(0, [str length])];
		//NSLog(@"%@",outputSubDir);
	}
	
	[str replaceOccurrencesOfString:@"/" withString:LS(@"slash") options:0 range:NSMakeRange(0, [str length])];
	[str replaceOccurrencesOfString:@":" withString:LS(@"colon") options:0 range:NSMakeRange(0, [str length])];
	[str replaceOccurrencesOfString:@"\0" withString:@"" options:0 range:NSMakeRange(0, [str length])];
	[str replaceOccurrencesOfString:@"[[[XLD_DIRECTORY_SEPARATOR]]]" withString:@"/" options:0 range:NSMakeRange(0, [str length])];
	
	return str;
}

- (BOOL)canHandleOutputForDecoder:(id)decoder
{
	int i;
	XLDFormat fmt;
	fmt.bps = [decoder bytesPerSample];
	fmt.channels = [decoder channels];
	fmt.samplerate = [decoder samplerate];
	fmt.isFloat = [decoder isFloat];
	
	if([[o_formatList selectedItem] tag] == 1) {
		BOOL fail = NO;
		id selectedOutputs = [customFormatManager currentOutputArray];
		NSArray *cfgs = [customFormatManager currentConfigurationsArray];
		for(i=0;i<[selectedOutputs count];i++) {
			id outputTask = [[selectedOutputs objectAtIndex:i] createTaskForOutputWithConfigurations:[cfgs objectAtIndex:i]];
			if(![(id <XLDOutputTask> )outputTask setOutputFormat:fmt]) fail = YES;
			[outputTask release];
		}
		if(fail) return NO;
	}
	else {
		id outputTask = [[outputArr objectAtIndex:[o_formatList indexOfSelectedItem]] createTaskForOutput];
		if(![(id <XLDOutputTask> )outputTask setOutputFormat:fmt]) {
			[outputTask release];
			return NO;
		}
		[outputTask release];
	}
	return YES;
}

- (void)setOutputForTask:(XLDConverterTask *)task
{
	if([[o_formatList selectedItem] tag] == 1) {
		[task setEncoders:[customFormatManager currentOutputArray] withConfigurations:[customFormatManager currentConfigurationsArray]];
	}
	else {
		[task setEncoder:[outputArr objectAtIndex:[o_formatList indexOfSelectedItem]] withConfiguration:[(id <XLDOutput>)[outputArr objectAtIndex:[o_formatList indexOfSelectedItem]] configurations]];
	}
}

- (void)setDefaultCommentValueForTrackList:(NSArray *)list
{
	int i;
	NSString *defaultComment = [o_defaultCommentValue string];
	if([defaultComment isEqualToString:@""]) return;
	for(i=0;i<[list count];i++) {
		XLDTrack *track = [list objectAtIndex:i];
		NSString *comment = [[track metadata] objectForKey:XLD_METADATA_COMMENT];
		if(!comment || [comment isEqualToString:@""]) {
			[[track metadata] setObject:defaultComment forKey:XLD_METADATA_COMMENT];
		}
	}
}

- (void)cddbGetTracksWithAutoStart:(BOOL)start isManualQuery:(BOOL)manualQuery
{
	id cueParser = [discView cueParser];
	if(!cueParser) return;
	[self addServerList:self];
	if(util) [util release];
	util = [[XLDCDDBUtil alloc] initWithDelegate:self];
	[util setTracks:[cueParser trackList] totalFrame:[cueParser totalFrames]];
	BOOL useProxy = ([o_cddbProxyEnabled state] == NSOnState) ? YES : NO;
	BOOL useCache = ([o_cddbUseCache state] == NSOnState) ? YES : NO;
	[util setUseProxy:useProxy];
	[util setUseCache:useCache];
	[util setPreferredService:[[o_preferredService selectedItem] tag]];
	[util setServer:[o_cddbServer stringValue] port:[o_cddbServerPort intValue] path:[o_cddbServerPath stringValue]];
	if(useProxy) [util setProxyServer:[o_cddbProxyServer stringValue] port:[o_cddbProxyServerPort intValue] user:[o_cddbProxyUser stringValue] passwd:[o_cddbProxyPassword stringValue]];
	int ret = [util query];
	//NSLog(@"%d",ret);
	if(ret == 0) {
		[util readCDDBWithInfo:nil];
		if(start) {
			NSData *data = [util coverData];
			if(data) {
				[cueParser setCoverData:data];
				[discView reloadData];
			}
			[self performSelectorOnMainThread:@selector(beginDecode:) withObject:nil waitUntilDone:NO];
		}
		else {
			NSBeginInformationalAlertSheet(LS(@"CDDB connection"), @"OK", nil, nil, [discView window], nil, nil, nil, NULL, LS(@"CDDB not found"));
			if([util asin] && [util coverURL]) {
				[[discView imageView] loadImageFromASIN:[util asin] andAlternateURL:[util coverURL]];
			}
		}
		[util release];
		util = nil;
	}
	else if(ret == -1) {
		[util readCDDBWithInfo:nil];
		if(start) {
			NSData *data = [util coverData];
			if(data) {
				[cueParser setCoverData:data];
				[discView reloadData];
			}
			[self performSelectorOnMainThread:@selector(beginDecode:) withObject:nil waitUntilDone:NO];
		}
		else {
			NSBeginCriticalAlertSheet(LS(@"CDDB connection"), @"OK", nil, nil, [discView window], nil, nil, nil, NULL, LS(@"CDDB connection failure"));
			if([util asin] && [util coverURL]) {
				[[discView imageView] loadImageFromASIN:[util asin] andAlternateURL:[util coverURL]];
			}
		}
		[util release];
		util = nil;
	}
	else if(ret == 1 || (!manualQuery && [o_dontPromptForCDDB state] == NSOnState)) {
		XLDCDDBResult result = [util readCDDBWithInfo:[[util queryResult] objectAtIndex:0]];
		
		if(result == XLDCDDBSuccess) {
			if([self canSetCompilationFlag] && [cueParser isCompilation]) {
				int i;
				for(i=0;i<[[cueParser trackList] count];i++) [[[[cueParser trackList] objectAtIndex:i] metadata] setObject:[NSNumber numberWithBool:YES] forKey:XLD_METADATA_COMPILATION];
			}
			[discView reloadData];
		}
		
		if(start) {
			NSData *data = [util coverData];
			if(data) {
				[cueParser setCoverData:data];
				[discView reloadData];
			}
			[self performSelectorOnMainThread:@selector(beginDecode:) withObject:nil waitUntilDone:NO];
		}
		else {
			if([util asin] && [util coverURL]) {
				[[discView imageView] loadImageFromASIN:[util asin] andAlternateURL:[util coverURL]];
			}
			if(result != XLDCDDBSuccess) {
				NSBeginCriticalAlertSheet(LS(@"CDDB connection"), @"OK", nil, nil, [discView window], nil, nil, nil, NULL, LS(@"CDDB connection failure"));
			}
		}
		[util release];
		util = nil;
	}
	else {
		int i;
		NSArray *result = [util queryResult];
		[o_queryResultList removeAllItems];
		for(i=0;i<ret;i++) {
			if([[result objectAtIndex:i] count] == 5)
				[o_queryResultList addItemWithTitle:[NSString stringWithFormat:@"%d: %@ - %@ (%@)",i+1,[[result objectAtIndex:i] objectAtIndex:3],[[result objectAtIndex:i] objectAtIndex:4],[[result objectAtIndex:i] objectAtIndex:0]]];
			else
				[o_queryResultList addItemWithTitle:[NSString stringWithFormat:@"%d: %@ (%@)",i+1,[[result objectAtIndex:i] objectAtIndex:3],[[result objectAtIndex:i] objectAtIndex:0]]];
		}
		if(start) {
			[NSApp beginSheet:o_queryResultPane
			   modalForWindow:[discView window]
				modalDelegate:self
			   didEndSelector:@selector(sheetDidEnd:returnCode:contextInfo:)
				  contextInfo:@"CDDBQueryWithStart"];
		}
		else {
			[NSApp beginSheet:o_queryResultPane
			   modalForWindow:[discView window]
				modalDelegate:self
			   didEndSelector:@selector(sheetDidEnd:returnCode:contextInfo:)
				  contextInfo:@"CDDBQuery"];
		}
	}
}

- (void)openParsedDisc:(id)cueParser originalFile:(NSString *)filename
{
	NSArray *coverArtFileListArray = [self coverArtFileListArray];
	[self setDefaultCommentValueForTrackList:[cueParser trackList]];
	NSData *imgData = nil;
	if(filename && [o_autoLoadCoverArt state] == NSOnState) {
		imgData = [self dataForAutoloadCoverArtForFile:filename fileListArray:coverArtFileListArray];
	}
	if([cueParser coverData]) {
		if(imgData && ([o_autoLoadCoverArtDontOverwrite state] == NSOffState)) {
			[cueParser setCoverData:imgData];
			//[discView reloadData];
		}
	}
	else {
		if(imgData) {
			[cueParser setCoverData:imgData];
			//[discView reloadData];
		}
	}
	[discView openCueParser:cueParser];
	
	if([[cueParser fileToDecode] hasPrefix:@"/dev/disk"]) {
		if([o_autoQueryCDDB state] == NSOnState) {
			[self cddbGetTracksWithAutoStart:(([o_autoMountDisc state] == NSOnState) && ([o_autoStartRipping state] == NSOnState)) ? YES : NO isManualQuery:NO];
		}
		else if(([o_autoMountDisc state] == NSOnState) && ([o_autoStartRipping state] == NSOnState)) {
			[self performSelectorOnMainThread:@selector(beginDecode:) withObject:nil waitUntilDone:NO];
		}
	}
	else {
		if([o_autoQueryCDDB state] == NSOnState) {
			[self cddbGetTracksWithAutoStart:NO isManualQuery:NO];
		}
	}
	
}

- (void)openFolder:(NSString *)dir offset:(xldoffset_t)offset prepended:(BOOL)prepended
{
	NSFileManager *mgr = [NSFileManager defaultManager];
	NSArray *arr = [mgr directoryContentsAt:dir];
	if(![arr count]) return;
	int i;
	NSMutableArray *files = [NSMutableArray array];
	for(i=0;i<[arr count];i++) {
		BOOL isDir;
		NSString *path = [dir stringByAppendingPathComponent:[arr objectAtIndex:i]];
		[mgr fileExistsAtPath:path isDirectory:&isDir];
		if(isDir || [[arr objectAtIndex:i] characterAtIndex:0] == '.') continue;
		[files addObject:path];
	}
	NSArray *sortedFiles;
	if([NSString instancesRespondToSelector:@selector(localizedStandardCompare:)]) {
		sortedFiles = [files sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
	}
	else {
		sortedFiles = [files sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
	}
	id cueParser = [[XLDCueParser alloc] initWithDelegate:self];
	XLDErr err = [cueParser openFiles:sortedFiles offset:offset prepended:prepended];
	if(err == XLDNoErr)
		[self openParsedDisc:cueParser originalFile:[sortedFiles objectAtIndex:0]];
	else if(err == XLDReadErr) {
		NSString *msg = [cueParser errorMsg];
		if(!msg) msg = @"Unknown error";
		NSRunCriticalAlertPanel(LS(@"Error Opening Folder As a Disc"), msg, @"OK", nil, nil);
	}
	[cueParser release];
}

#pragma mark IBActions

- (IBAction)beginDecode:(id)sender
{
	int i,j;
	NSArray *trackList;
	id resultObj = nil;
	id cueParser = [discView cueParser];
	BOOL singleImageMode = NO;
	if([discView extractionMode] == 2) {
		trackList = [cueParser trackListForSingleFile];
		singleImageMode = YES;
	}
	else {
		trackList = [cueParser trackList];
		for(i=0;i<[trackList count];i++) {
			if([[trackList objectAtIndex:i] enabled]) break;
		}
		if(i==[trackList count]) return;
	}
	
	NSString *outputDir;
	if(tempOutputDir) {
		outputDir = [tempOutputDir autorelease];
		tempOutputDir = nil;
	}
	else if([[o_outputSelectRadio selectedCell] tag] == 0)
		outputDir = [[cueParser fileToDecode] stringByDeletingLastPathComponent];
	else
		outputDir = [o_outputDir stringValue];
	
	if(![[NSFileManager defaultManager] isWritableFileAtPath:outputDir]) {
		NSOpenPanel *op = [NSOpenPanel openPanel];
		[op setTitle:LS(@"Specify the output directory")];
		[op setCanChooseDirectories:YES];
		[op setCanChooseFiles:NO];
		[op setAllowsMultipleSelection:NO];
		if([op respondsToSelector:@selector(setCanCreateDirectories:)] )
			[op setCanCreateDirectories:YES];
		else if([op respondsToSelector:@selector(_setIncludeNewFolderButton:)])
			[op _setIncludeNewFolderButton:YES];
		
		int ret = [op runModal];
		if((ret != NSOKButton) || ![[NSFileManager defaultManager] isWritableFileAtPath:[op filename]]) 
		{
			NSRunCriticalAlertPanel(LS(@"error"), LS(@"no write permission"), @"OK", nil, nil);
			return;
		}
		outputDir = [op filename];
	}
	
	if([[cueParser fileToDecode] hasPrefix:@"/dev/disk"]) {
		if(!ejected) {
			tempOutputDir = [outputDir retain];
			[o_detectPregapPane setTitle:LS(@"Waiting")];
			[o_detectPregapMessage setStringValue:LS(@"Waiting for Drive...")];
			[o_detectPregapProgress setIndeterminate:YES];
			[o_detectPregapProgress startAnimation:self];
			[o_detectPregapPaneButton setHidden:YES];
			[o_detectPregapPane center];
			[o_detectPregapPane makeKeyAndOrderFront:nil];
			[NSThread detachNewThreadSelector:@selector(unmountDisc:) toTarget:self withObject:[cueParser fileToDecode]];
			return;
		}
		else {
			ejected = NO;
			//[o_detectPregapProgress stopAnimation:self];
			//[o_detectPregapPane close];
		}
	}
	
	id decoder;
	if([cueParser cueMode] == XLDCueModeRaw)
		decoder = [[[XLDRawDecoder alloc] initWithFormat:[cueParser rawFormat] endian:[cueParser rawEndian] offset:[cueParser rawOffset]] autorelease];
	else if([cueParser cueMode] == XLDCueModeMulti)
		decoder = [[[XLDMultipleFileWrappedDecoder alloc] initWithDiscLayout:[cueParser discLayout]] autorelease];
	else
		decoder = [decoderCenter preferredDecoderForFile:[cueParser fileToDecode]];
	
	if([NSStringFromClass([decoder class]) isEqualToString:@"XLDCDDARipper"]) {
		int fd = open([[cueParser fileToDecode] UTF8String],O_RDONLY);
		if(fd != -1) close(fd);
		else {
			NSRunCriticalAlertPanel(LS(@"error"), LS(@"Device is busy"), @"OK", nil, nil);
			return;
		}
		XLDRipperMode ripperMode = [[o_ripperMode selectedItem] tag];
		if(ripperMode != kRipperModeBurst && [o_useC2Pointer state] == NSOnState) ripperMode |= kRipperModeC2;
		
		resultObj = [[XLDCDDAResult alloc] initWithTrackNumber:[[cueParser trackList] count]];
		[resultObj setDeviceStr:[cueParser fileToDecode]];
		[resultObj setDriveStr:[cueParser driveStr]];
		[resultObj setRipperMode:ripperMode
				 offsetCorrention:[o_offsetCorrectionValue intValue]
					   retryCount:[o_maxRetryCount intValue]
				 useAccurateRipDB:(([o_queryAccurateRip state] == NSOnState) && ([discView extractionMode] != 1))
			   checkInconsistency:([o_verifySuspiciousSector state] == NSOnState)
					trustARResult:([o_arLogControl state] == NSOnState)
				   scanReplayGain:([o_scanReplayGain state] == NSOnState)
						gapStatus:([o_dontReadSubchannel state] << 16) | ([discView extractionMode]&0xffff)];
		[resultObj setDate:[NSDate date]];
		[resultObj setIncludeHTOA:([discView extractionMode] == 0 || [discView extractionMode] == 2) ? YES : NO];
		[resultObj setTOC:[cueParser trackList]];
		[resultObj setTitle:[cueParser title] andArtist:[cueParser artist]];
		[resultObj setProcessOfExistingFiles:[[o_existingFile selectedCell] tag]];
		{
			NSMutableString *str = [NSMutableString stringWithString:[cueParser title]];
			[str replaceOccurrencesOfString:@"/" withString:LS(@"slash") options:0 range:NSMakeRange(0, [str length])];
			[str replaceOccurrencesOfString:@":" withString:LS(@"colon") options:0 range:NSMakeRange(0, [str length])];
			if([str length] > 240) {
				str = [NSMutableString stringWithString:[str substringToIndex:239]];
			}
			if(([[o_saveLogMode selectedItem] tag] == 0) || ([[o_saveLogMode selectedItem] tag] == 1 && [discView extractionMode] == 2)) {
				[resultObj setLogFileName:[str stringByAppendingPathExtension:@"log"]];
			}
			if([[o_saveCueMode selectedItem] tag] == 0 && [discView extractionMode] != 2) {
				[resultObj setCueFileName:[str stringByAppendingPathExtension:@"cue"]];
			}
		}
		if([discView extractionMode] != 1) {
			[o_detectPregapMessage setStringValue:LS(@"Connecting to AccurateRip")];
			[o_detectPregapMessage display];
			//sleep(1);
			NSData *dbData = [cueParser accurateRipData];
			if(dbData) {
				//NSLog(@"db found");
				id db = [[XLDAccurateRipDB alloc] initWithData:dbData];
				[resultObj setAccurateRipDB:db];
				[db release];
			}
		}
		[o_detectPregapProgress stopAnimation:self];
		[o_detectPregapPane close];
	}
	
	[(id <XLDDecoder>)decoder openFile:(char *)[[cueParser fileToDecode] UTF8String]];
	
	
	if(![self canHandleOutputForDecoder:decoder]) {
		if(resultObj) [resultObj release];
		NSRunCriticalAlertPanel(LS(@"error"), LS(@"output does not support input format"), @"OK", nil, nil);
		return;
	}
	
	NSMutableArray *taskArray = [[NSMutableArray alloc] init];
	
	for(i=0;i<[trackList count];i++) {
		XLDTrack *trk = [trackList objectAtIndex:i];
		if(![trk enabled]) continue; 
		
		XLDConverterTask *task = [[XLDConverterTask alloc] initWithQueue:taskQueue];
		
		NSString *filename;
		if([discView extractionMode] == 2 && [[o_filenameFormatRadio selectedCell] tag] == 0) {
			NSMutableString *str = [NSMutableString stringWithString:[cueParser title]];
			[str replaceOccurrencesOfString:@"/" withString:LS(@"slash") options:0 range:NSMakeRange(0, [str length])];
			[str replaceOccurrencesOfString:@":" withString:LS(@"colon") options:0 range:NSMakeRange(0, [str length])];
			filename = str;
		}
		else filename = [self preferredFilenameForTrack:trk createSubDir:YES singleImageMode:singleImageMode albumArtist:[cueParser artist]];
		[trk setDesiredFileName:[filename lastPathComponent]];
		NSString *outputSubDir = [filename stringByDeletingLastPathComponent];
		
		xldoffset_t actualLength;
		xldoffset_t actualIndex;
		if((i==0) && ([trk gap] != 0) && ([discView extractionMode] == 0 || [discView extractionMode] == 2)) {
			if([trk frames] != -1) actualLength = [trk index] + [trk frames];
			else actualLength = [trk frames];
			actualIndex = 0;
		}
		else {
			actualLength = [trk frames];
			actualIndex = [trk index];
		}
		
		if(i<[trackList count]-1) actualLength += ([discView extractionMode] == 0 || [discView extractionMode] == 3) ? [[trackList objectAtIndex:i+1] gap] : 0;
		if(![NSStringFromClass([decoder class]) isEqualToString:@"XLDCDDARipper"]) {
			if(([o_correctOffset state] == NSOnState) && actualIndex < 30) {
				[task setFixOffset:YES];
				if(i == [trackList count]-1) actualLength = [decoder totalFrames] - actualIndex;
				actualLength -= (30 - actualIndex);
			}
			else if([o_correctOffset state] == NSOnState) {
				if(i == [trackList count]-1) actualLength = [decoder totalFrames] - actualIndex;
				actualIndex -= 30;
			}
		}
		
		[task setScaleType:([o_scaleImage state] == NSOffState) ? XLDNoScale : ([[o_scaleType selectedCell] tag] | (([o_expandImage state] == NSOnState) ? 0x10 : 0))];
		[task setScaleSize:[o_scalePixel intValue]];
		[task setCompressionQuality:[o_compressionQuality intValue]/100.0f];
		[task setIndex:actualIndex];
		[task setTotalFrame:actualLength];
		[task setDecoderClass:[decoder class]];
		if([cueParser cueMode] == XLDCueModeRaw) {
			[task setRawFormat:[cueParser rawFormat]];
			[task setRawEndian:[cueParser rawEndian]];
			[task setRawOffset:[cueParser rawOffset]];
		}
		else if([cueParser cueMode] == XLDCueModeMulti) {
			[task setDiscLayout:[cueParser discLayout]];
		}
		[self setOutputForTask:task];
		[task setInputPath:[cueParser fileToDecode]];
		if([outputSubDir length]) [task setOutputDir:[outputDir stringByAppendingPathComponent:outputSubDir]];
		else [task setOutputDir:outputDir];
		[task setProcessOfExistingFiles:[[o_existingFile selectedCell] tag]];
		[task setTagWritable:([o_autoTagging state] == NSOnState) ? YES : NO];
		[task setEmbedImages:([o_embedCoverArts state] == NSOnState) ? YES : NO];
		[task setMoveAfterFinish:([o_moveAfterFinish state] == NSOnState) ? YES : NO];
		[task setTrack:trk];
		if([o_addiTunes state] == NSOnState) {
			NSString *iTunesLibName;
			if([[o_libraryType selectedCell] tag] == 0) iTunesLibName = @"library playlist 1";
			else iTunesLibName = [self formattedStringForTrack:trk withPattern:[o_libraryName stringValue] singleImageMode:singleImageMode albumArtist:[cueParser artist]];
			[task setiTunesLib:iTunesLibName];
		}
		
		if([NSStringFromClass([decoder class]) isEqualToString:@"XLDCDDARipper"]) {
			driveIsBusy = YES;
			XLDRipperMode ripperMode = [[o_ripperMode selectedItem] tag];
			if(ripperMode != kRipperModeBurst && [o_useC2Pointer state] == NSOnState) ripperMode |= kRipperModeC2;
			[task setRipperMode:ripperMode];
			[task setOffsetCorrectionValue:[o_offsetCorrectionValue intValue]];
			[task setRetryCount:[o_maxRetryCount intValue]];
			[task setResultObj:resultObj];
			[task setFirstAudioFrame:[cueParser firstAudioFrame]];
			[task setLastAudioFrame:[cueParser lastAudioFrame]];
			if(([o_testBeforeCopy state] == NSOnState) && (([[o_testType selectedCell] tag] == 0) || ![resultObj accurateRipDB] || ![[resultObj accurateRipDB] hasValidDataForTrack:i+1])) {
				BOOL testFlag = NO;
				if([[o_testType selectedCell] tag] == 0) testFlag = YES;
				else if(![resultObj accurateRipDB]) testFlag = YES;
				else if(([discView extractionMode] == 0 || [discView extractionMode] == 3) && ![[resultObj accurateRipDB] hasValidDataForTrack:i+1]) testFlag = YES;
				else if([discView extractionMode] == 2) {
					for(j=0;j<[[cueParser trackList] count];j++) {
						if(![[resultObj accurateRipDB] hasValidDataForTrack:j+1]) {
							testFlag = YES;
							break;
						}
					}
				}
				if(testFlag) {
					XLDConverterTask *testTask = [[XLDConverterTask alloc] initWithQueue:taskQueue];
					[testTask setTestMode]; //this should be earliar than setTrack
					[testTask setScaleType:XLDNoScale];
					[testTask setIndex:actualIndex];
					[testTask setTotalFrame:actualLength];
					[testTask setDecoderClass:[decoder class]];
					/*if([cueParser cueMode] == XLDCueModeRaw) {
						[testTask setRawFormat:[cueParser rawFormat]];
						[testTask setRawEndian:[cueParser rawEndian]];
						[testTask setRawOffset:[cueParser rawOffset]];
					}*/
					[testTask setInputPath:[cueParser fileToDecode]];
					if([outputSubDir length]) [testTask setOutputDir:[outputDir stringByAppendingPathComponent:outputSubDir]];
					else [testTask setOutputDir:outputDir];
					[testTask setProcessOfExistingFiles:[[o_existingFile selectedCell] tag]];
					[testTask setTagWritable:([o_autoTagging state] == NSOnState) ? YES : NO];
					[testTask setEmbedImages:([o_embedCoverArts state] == NSOnState) ? YES : NO];
					[testTask setTrack:trk]; //this should be later than setTestMode
					[testTask setEncoder:[[[XLDWavOutput alloc] init] autorelease] withConfiguration:nil];
					[testTask setiTunesLib:nil];
					[testTask setRipperMode:ripperMode];
					[testTask setOffsetCorrectionValue:[o_offsetCorrectionValue intValue]];
					[testTask setRetryCount:[o_maxRetryCount intValue]];
					[testTask setResultObj:resultObj];
					[testTask setFirstAudioFrame:[cueParser firstAudioFrame]];
					[testTask setLastAudioFrame:[cueParser lastAudioFrame]];
					[taskArray addObject:testTask];
					[testTask release];
				}
			}
		}
		
		if([discView extractionMode] == 2) {
			[task setTrackListForCuesheet:[cueParser trackList] appendBOM:([o_appendBOM state] == NSOnState) ? YES : NO];
		}
		
		[taskArray addObject:task];
		[task release];
	}
	[decoder closeFile];
	/*if([NSStringFromClass([decoder class]) isEqualToString:@"XLDCDDARipper"]) {
		[[taskArray objectAtIndex:[taskArray count]-1] setMountOnEnd];
	}*/
	[taskQueue addTasks:taskArray];
	[taskArray release];
	if(resultObj) [resultObj release];
	//decoding = YES;
}

- (IBAction)setOutputDir:(id)sender
{
	NSOpenPanel *op = [NSOpenPanel openPanel];
	[op setCanChooseDirectories:YES];
	[op setCanChooseFiles:NO];
	[op setAllowsMultipleSelection:NO];
	if([op respondsToSelector:@selector(setCanCreateDirectories:)] )
		[op setCanCreateDirectories:YES];
	else if([op respondsToSelector:@selector(_setIncludeNewFolderButton:)])
		[op _setIncludeNewFolderButton:YES];
	
	int ret = [op runModal];
	if(ret != NSOKButton) return;
	
	[o_outputDir setStringValue:[op filename]];
}

- (IBAction)openFile:(id)sender
{
	//if(decoding) return;
	NSOpenPanel *op = [NSOpenPanel openPanel];
	[op setCanChooseDirectories:YES];
	[op setCanChooseFiles:YES];
	[op setAllowsMultipleSelection:YES];
	
	int ret = [op runModal];
	if(ret != NSOKButton) return;
	
	[queue removeAllObjects];
	[queue addObjectsFromArray:[op filenames]];
	[self processQueue];
}

- (void)openRawFileWithDefaultPath:(NSString *)path
{
	NSOpenPanel *op = [NSOpenPanel openPanel];
	[op setCanChooseDirectories:NO];
	[op setCanChooseFiles:YES];
	[op setAllowsMultipleSelection:NO];
	NSRect origFrame = [o_rawFormatView frame];
	[op setAccessoryView:o_rawFormatView];
	
	int ret;
	if(path) ret = [op runModalForDirectory:[path stringByDeletingLastPathComponent] file:[path lastPathComponent] types:nil];
	else ret = [op runModal];
	[op setAccessoryView:nil];
	[o_rawFormatView setFrame:origFrame];
	if(ret != NSOKButton) return;
	
	XLDFormat fmt;
	fmt.samplerate = [o_rawSamplerate intValue];
	switch([o_rawBitDepth indexOfSelectedItem]) {
		case 0:
			fmt.bps = 1;
			break;
		case 1:
			fmt.bps = 2;
			break;
		case 2:
			fmt.bps = 3;
			break;
		case 3:
			fmt.bps = 4;
			break;
		default:
			fmt.bps = 2;
			break;
	}
	
	switch([o_rawChannels indexOfSelectedItem]) {
		case 0:
			fmt.channels = 2;
			break;
		case 1:
			fmt.channels = 1;
			break;
		default:
			fmt.channels = 2;
			break;
	}
	
	fmt.isFloat = 0;
	int endian;
	switch([o_rawEndian indexOfSelectedItem]) {
		case 0:
			endian = XLDBigEndian;
			break;
		case 1:
			endian = XLDLittleEndian;
			break;
		default:
			endian = XLDLittleEndian;
			break;
	}
	
	[self processRawFile:[op filename] withFormat:fmt endian:endian];
}

- (IBAction)openRawFile:(id)sender
{
	//if(decoding) return;
	[self openRawFileWithDefaultPath:nil];
}

- (IBAction)formatChanged:(id)sender
{
	if([[o_formatList selectedItem] tag] == 1) [o_formatOptionButton setEnabled:YES];
	else if([[outputArr objectAtIndex:[o_formatList indexOfSelectedItem]] prefPane])
		[o_formatOptionButton setEnabled:YES];
	else [o_formatOptionButton setEnabled:NO];
}

- (IBAction)showOption:(id)sender
{
	if([[o_formatList selectedItem] tag] == 1) {
		[NSApp beginSheet:[customFormatManager panel]
		   modalForWindow:o_prefPane
			modalDelegate:self
		   didEndSelector:@selector(sheetDidEnd:returnCode:contextInfo:)
			  contextInfo:@"PluginOption"];
	}
	else {
		NSView *view;
		if(![[outputArr objectAtIndex:[o_formatList indexOfSelectedItem]] prefPane]) return;
		else view = [[outputArr objectAtIndex:[o_formatList indexOfSelectedItem]] prefPane];
		NSRect frame = [view frame];
		frame.size.height += 50;
		[o_pluginPrefPane setContentSize:frame.size];
		if([[o_pluginOptionContentView subviews] count])
			[[[o_pluginOptionContentView subviews] objectAtIndex:0] removeFromSuperview];
		[o_pluginOptionContentView addSubview:view];
		[NSApp beginSheet:o_pluginPrefPane
		   modalForWindow:o_prefPane
			modalDelegate:self
		   didEndSelector:@selector(sheetDidEnd:returnCode:contextInfo:)
			  contextInfo:@"PluginOption"];
	}
}

- (IBAction)hideOption:(id)sender
{
	[NSApp endSheet:[sender window] returnCode:0];
	[[sender window] close];
	[self updateFormatDescriptionMenu];
	if([[o_formatList selectedItem] tag] == 1) {
		[customFormatManager savePrefs];
	}
	else {
		[[outputArr objectAtIndex:[o_formatList indexOfSelectedItem]] savePrefs];
	}
	[o_prefPane makeKeyAndOrderFront:self];
}

- (IBAction)cddbGetTracks:(id)sender
{
	[self cddbGetTracksWithAutoStart:NO isManualQuery:YES];
}

- (IBAction)closeQueryResult:(id)sender
{
	[[sender window] close];
	[NSApp endSheet:[sender window] returnCode:[sender tag]];
}

- (IBAction)addServerList:(id)sender
{
	NSString *server = [o_cddbServer stringValue];
	if([server isEqualToString:@""]) return;
	if([serverList containsObject:server]) [serverList removeObject:server];
	[serverList insertObject:server atIndex:0];
	if([serverList count] > 5) [serverList removeObjectAtIndex:5];
	[o_cddbServer setNumberOfVisibleItems:[serverList count]];
	[o_cddbServer reloadData];
}

- (IBAction)rawFormatSelected:(id)sender
{
	[NSApp stopModal];
	[o_rawFormatPane close];
}

- (IBAction)toggleSenderItem:(id)sender
{
	if([sender state] == NSOnState) [sender setState:NSOffState];
	else [sender setState:NSOnState];
}

- (IBAction)showWindow:(id)sender
{
	if([sender tag] == 0) [player showPlayer];
	else if([sender tag] == 1) [taskQueue showProgress];
	else if([sender tag] == 2) [o_logWindow makeKeyAndOrderFront:nil];
}

- (IBAction)statusChanged:(id)sender
{
	if([o_addiTunes state] == NSOnState) {
		[o_libraryType setEnabled:YES];
		if([[o_libraryType selectedCell] tag]) [o_libraryName setEnabled:YES];
		else [o_libraryName setEnabled:NO];
	}
	else {
		[o_libraryType setEnabled:NO];
		[o_libraryName setEnabled:NO];
	}
	
	if([o_testBeforeCopy state] == NSOnState) {
		[o_testType setEnabled:YES];
	}
	else {
		[o_testType setEnabled:NO];
	}
	
	if([o_queryAccurateRip state] == NSOnState) {
		[o_arLogControl setEnabled:YES];
	}
	else {
		[o_arLogControl setEnabled:NO];
	}
	
	if([[o_ripperMode selectedItem] tag]) {
		[o_useC2Pointer setEnabled:YES];
	}
	else {
		[o_useC2Pointer setEnabled:NO];
	}
	
	if([o_autoMountDisc state] == NSOnState) {
		[o_autoStartRipping setEnabled:YES];
	}
	else {
		[o_autoStartRipping setEnabled:NO];
	}
	
	if([o_limitExtension state] == NSOnState) {
		[o_extensionFilter setEnabled:YES];
	}
	else {
		[o_extensionFilter setEnabled:NO];
	}
	
	if([o_autoQueryCDDB state] == NSOnState) {
		[o_dontPromptForCDDB setEnabled:YES];
	}
	else {
		[o_dontPromptForCDDB setEnabled:NO];
	}
	
	if([o_embedCoverArts state] == NSOnState) {
		[o_scaleImage setEnabled:YES];
		[o_autoLoadCoverArt setEnabled:YES];
	}
	else {
		[o_scaleImage setEnabled:NO];
		[o_autoLoadCoverArt setEnabled:NO];
	}
	
	if([o_scaleImage state] == NSOnState && [o_embedCoverArts state] == NSOnState) {
		[o_scaleType setEnabled:YES];
		[o_scalePixel setEnabled:YES];
		[o_compressionQuality setEnabled:YES];
		[o_expandImage setEnabled:YES];
		[o_textGroup_1_1 setTextColor:[NSColor blackColor]];
		[o_textGroup_1_2 setTextColor:[NSColor blackColor]];
		[o_textGroup_1_3 setTextColor:[NSColor blackColor]];
		[o_textGroup_1_4 setTextColor:[NSColor blackColor]];
		[o_textGroup_1_5 setTextColor:[NSColor blackColor]];
	}
	else {
		[o_scaleType setEnabled:NO];
		[o_scalePixel setEnabled:NO];
		[o_compressionQuality setEnabled:NO];
		[o_expandImage setEnabled:NO];
		[o_textGroup_1_1 setTextColor:[NSColor grayColor]];
		[o_textGroup_1_2 setTextColor:[NSColor grayColor]];
		[o_textGroup_1_3 setTextColor:[NSColor grayColor]];
		[o_textGroup_1_4 setTextColor:[NSColor grayColor]];
		[o_textGroup_1_5 setTextColor:[NSColor grayColor]];
	}
	
	if([[o_filenameFormatRadio selectedCell] tag] == 0) {
		[o_filenameFormat setEnabled:NO];
	}
	else [o_filenameFormat setEnabled:YES];
	
	if([o_autoLoadCoverArt state] == NSOnState && [o_embedCoverArts state] == NSOnState) {
		[o_autoLoadCoverArtName setEnabled:YES];
		[o_autoLoadCoverArtDontOverwrite setEnabled:YES];
	}
	else {
		[o_autoLoadCoverArtName setEnabled:NO];
		[o_autoLoadCoverArtDontOverwrite setEnabled:NO];
	}
	
	if([o_removeOriginalFile state] == NSOnState) {
		[o_warnBeforeConversion setEnabled:YES];
	}
	else [o_warnBeforeConversion setEnabled:NO];
	
	if([o_readOffsetUseRipperValue state] == NSOnState)
		[o_readOffsetForVerify setEnabled:NO];
	else [o_readOffsetForVerify setEnabled:YES];
}

- (IBAction)editMetadata:(id)sender
{
	[discView editMetadata:sender];
}

- (IBAction)readCDDA:(id)sender
{
	[o_detectPregapPane setTitle:LS(@"Detect Pregap")];
	[o_detectPregapMessage setStringValue:LS(@"Detecting Pregap...")];
	[o_detectPregapProgress setIndeterminate:NO];
	[o_detectPregapProgress setDoubleValue:0];
	[o_detectPregapPaneButton setHidden:YES];
	[o_detectPregapPane center];
	[o_detectPregapPane makeKeyAndOrderFront:nil];
	[NSThread detachNewThreadSelector:@selector(readPreGapOfDisc:) toTarget:self withObject:[sender title]];
}

- (void)updateCDDAListAndMount:(NSString *)device
{
	//NSLog(@"updateCDDAListAndMount called with %@",device);
	BOOL automount = NO;
	NSMenuItem *discToMount = nil;
	if(device && !driveIsBusy && !openingFiles && ([o_autoMountDisc state] == NSOnState)) automount = YES;
	OSErr	result = noErr;
    ItemCount	volumeIndex;
    long	systemVersion;
	
	int i,n=0;
	for(i=[o_openCDDA numberOfItems]-3;i>=0;i--) {
		[o_openCDDA removeItemAtIndex:i];
	}
	
    if (Gestalt(gestaltSystemVersion, &systemVersion) != noErr)
        systemVersion = 0;
    
    for (volumeIndex = 1; result == noErr || result != nsvErr; volumeIndex++)
	{
        FSVolumeRefNum	actualVolume;
        HFSUniStr255	volumeName;
        FSVolumeInfo	volumeInfo;
        
        bzero((void *) &volumeInfo, sizeof(volumeInfo));
        
        result = FSGetVolumeInfo(kFSInvalidVolumeRefNum,
                                 volumeIndex,
                                 &actualVolume,
                                 kFSVolInfoFSInfo,
                                 &volumeInfo,
                                 &volumeName,
                                 NULL); 
		
        if (result == noErr)
		{
            if ((systemVersion >= 0x00001000 && systemVersion < 0x00001010 &&
				 volumeInfo.signature == kAudioCDFilesystemID) ||
                volumeInfo.filesystemID == kAudioCDFilesystemID) // It's an audio CD
            {
				NSMenuItem *item = [[NSMenuItem alloc]initWithTitle:[NSString stringWithCharacters:volumeName.unicode length:volumeName.length] action:@selector(readCDDA:) keyEquivalent:@""];
				[item setTarget:self];
				if(n==0) [item setKeyEquivalent:@"O"];
				[o_openCDDA insertItem:item atIndex:n++];
				if(automount) {
					const char *devicePath = [[NSString stringWithFormat:@"/dev/%@",device] UTF8String];
					//NSLog(@"%s",devicePath);
					struct statfs fsstat;
					NSMutableString *tmpStr = [NSMutableString stringWithString:[item title]];
					[tmpStr replaceOccurrencesOfString:@"/" withString:@":" options:0 range:NSMakeRange(0, [tmpStr length])];
					statfs([[@"/Volumes" stringByAppendingPathComponent:tmpStr] UTF8String], &fsstat);
					if(!strcmp(devicePath, fsstat.f_mntfromname)) {
						struct stat st;
						stat([[@"/Volumes" stringByAppendingPathComponent:tmpStr] UTF8String], &st);
						//NSLog(@"%f",st.st_mtimespec.tv_sec - launchDate);
						if((st.st_mtimespec.tv_sec - launchDate) > -30) discToMount = item;
					}
					//NSLog(@"%s",fsstat.f_mntfromname);
				}
				[item release];
			}
        }
    }
	if(n==0) {
		NSMenuItem *item = [[NSMenuItem alloc]initWithTitle:LS(@"Audio CD Not Found") action:nil keyEquivalent:@""];
		[item setEnabled:NO];
		[o_openCDDA insertItem:item atIndex:0];
		[item release];
	}
	if(discToMount) [self readCDDA:discToMount];
}

- (IBAction)updateCDDAList:(id)sender
{
	//NSLog(@"update");
	[self updateCDDAListAndMount:nil];
}

- (IBAction)saveCuesheet:(id)sender
{
	NSSavePanel *sv = [NSSavePanel savePanel];
	NSString *defaultLocation = nil;
	id cueParser = [discView cueParser];
	if(cueParser && ![[cueParser fileToDecode] hasPrefix:@"/dev/disk"])
		defaultLocation = [[cueParser fileToDecode] stringByDeletingLastPathComponent];
	
	if(sender && [sender tag] == 0) {
		[sv setAllowedFileTypes:[NSArray arrayWithObject:@"cue"]];
		NSMutableData *data;
		[sv setAccessoryView:o_cuesheetTypeView];
		NSMutableString *str = [NSMutableString stringWithString:[cueParser title]];
		[str replaceOccurrencesOfString:@"/" withString:LS(@"slash") options:0 range:NSMakeRange(0, [str length])];
		[str replaceOccurrencesOfString:@":" withString:LS(@"colon") options:0 range:NSMakeRange(0, [str length])];
		NSString *filename = str;
		if([[[filename pathExtension] lowercaseString] isEqualToString:@"cue"])
			filename = [filename stringByDeletingPathExtension];
		int ret = [sv runModalForDirectory:defaultLocation file:[filename stringByAppendingPathExtension:@"cue"]];
		if(ret != NSOKButton) return;
		
		if([[o_cuesheetType selectedCell] tag] == 0) {
			NSString *name;
			if([[cueParser fileToDecode] hasPrefix:@"/dev/disk"]) name = @"CDImage.wav";
			else name = [[cueParser fileToDecode] lastPathComponent];
			data = [XLDTrackListUtil cueDataForTracks:[cueParser trackList] withFileName:name appendBOM:([o_appendBOM state] == NSOnState) samplerate:[cueParser samplerate]];
		}
		else {
			int i;
			id filenameArray;
			NSArray *trackList = [cueParser trackList];
			if([cueParser cueMode] == XLDCueModeMulti) {
				//NSLog(@"multi");
				filenameArray = [[cueParser discLayout] filePathList];
			}
			else {
				filenameArray = [NSMutableArray array];
				for(i=0;i<[trackList count];i++) {
					XLDTrack *track = [trackList objectAtIndex:i];
					BOOL dataTrack = NO;
					if([[track metadata] objectForKey:XLD_METADATA_DATATRACK]) {
						dataTrack = [[[track metadata] objectForKey:XLD_METADATA_DATATRACK] boolValue];
					}
					if(dataTrack) continue;
					NSString *name = [NSString stringWithFormat:@"%@.wav",[[self preferredFilenameForTrack:track createSubDir:NO singleImageMode:NO albumArtist:[cueParser artist]] lastPathComponent]];
					[filenameArray addObject:name];
				}
			}
			data = [XLDTrackListUtil nonCompliantCueDataForTracks:trackList withFileNameArray:filenameArray appendBOM:([o_appendBOM state] == NSOnState) gapStatus:([o_dontReadSubchannel state] << 16) | ([discView extractionMode]&0xffff) samplerate:[cueParser samplerate]];
		}
		[data writeToFile:[sv filename] atomically:YES];
	}
	else {
		[sv setAllowedFileTypes:[NSArray arrayWithObject:@"log"]];
		NSMutableString *str = [NSMutableString stringWithString:[cueParser title]];
		[str replaceOccurrencesOfString:@"/" withString:LS(@"slash") options:0 range:NSMakeRange(0, [str length])];
		[str replaceOccurrencesOfString:@":" withString:LS(@"colon") options:0 range:NSMakeRange(0, [str length])];
		NSString *filename = str;
		if([[[filename pathExtension] lowercaseString] isEqualToString:@"cue"])
			filename = [filename stringByDeletingPathExtension];
		int ret = [sv runModalForDirectory:defaultLocation file:[filename stringByAppendingPathExtension:@"log"]];
		if(ret != NSOKButton) return;
		NSData *data = [[[o_logView textStorage] mutableString] dataUsingEncoding:NSUTF8StringEncoding];
		[data writeToFile:[sv filename] atomically:YES];
	}
	
}

- (IBAction)checkAccurateRip:(id)sender
{
	id checker;
	id cueParser = [discView cueParser];
	NSData *dbData = [cueParser accurateRipData];
	if([sender tag] != 2) {
		if(!dbData) {
			NSBeginInformationalAlertSheet(@"AccurateRip", @"OK", nil, nil, [discView window], nil, nil, nil, NULL, LS(@"AccurateRip hash not found"));
			return;
		}
	}
	checker = [[XLDAccurateRipChecker alloc] initWithTracks:[cueParser trackList] totalFrames:[cueParser totalFrames]];
	[checker setDelegate:self];
	if([sender tag] != 2) {
		id db = [[XLDAccurateRipDB alloc] initWithData:dbData];
		[checker setAccurateRipDB:db];
		[db release];
	}
	
	id decoder;
	if([cueParser cueMode] == XLDCueModeRaw)
		decoder = [[[XLDRawDecoder alloc] initWithFormat:[cueParser rawFormat] endian:[cueParser rawEndian] offset:[cueParser rawOffset]] autorelease];
	else if([cueParser cueMode] == XLDCueModeMulti)
		decoder = [[[XLDMultipleFileWrappedDecoder alloc] initWithDiscLayout:[cueParser discLayout]] autorelease];
	else
		decoder = [decoderCenter preferredDecoderForFile:[cueParser fileToDecode]];
	
	if([sender tag] == 0) [checker startCheckingForFile:[cueParser fileToDecode] withDecoder:decoder];
	else if([sender tag] == 1) [checker startOffsetCheckingForFile:[cueParser fileToDecode] withDecoder:decoder];
	else if([sender tag] == 2) [checker startReplayGainScanningForFile:[cueParser fileToDecode] withDecoder:decoder];
}

- (IBAction)saveOffsetCorrectedFile:(id)sender
{
	id decoder;
	id cueParser = [discView cueParser];
	if([cueParser cueMode] == XLDCueModeRaw)
		decoder = [[[XLDRawDecoder alloc] initWithFormat:[cueParser rawFormat] endian:[cueParser rawEndian] offset:[cueParser rawOffset]] autorelease];
	else if([cueParser cueMode] == XLDCueModeMulti)
		decoder = [[[XLDMultipleFileWrappedDecoder alloc] initWithDiscLayout:[cueParser discLayout]] autorelease];
	else
		decoder = [decoderCenter preferredDecoderForFile:[cueParser fileToDecode]];
	if(!decoder) return;
	
	[(id <XLDDecoder>)decoder openFile:(char *)[[cueParser fileToDecode] UTF8String]];
	
	if(![self canHandleOutputForDecoder:decoder]) {
		NSRunCriticalAlertPanel(LS(@"error"), LS(@"output does not support input format"), @"OK", nil, nil);
		[decoder closeFile];
		return;
	}
	
	NSString *outputDir;
	NSSavePanel *sv = [NSSavePanel savePanel];
	[sv setAccessoryView:o_offsetView];
	
	int ret = [sv runModalForDirectory:[[cueParser fileToDecode] stringByDeletingLastPathComponent] file:[NSString stringWithFormat:@"%@(offset fix)",[[[cueParser fileToDecode] lastPathComponent] stringByDeletingPathExtension]]];
	[o_offsetValue validateEditing];
	[o_offsetValue abortEditing];
	if(ret != NSOKButton) 
	{
		[decoder closeFile];
		return;
	}
	outputDir = [[sv filename] stringByDeletingLastPathComponent];
	
	XLDConverterTask *task = [[XLDConverterTask alloc] initWithQueue:taskQueue];
	XLDTrack *track = [[XLDTrack alloc] init];
	[track setSeconds:[decoder totalFrames]/[decoder samplerate]];
	[track setDesiredFileName:[[[sv filename] lastPathComponent] stringByDeletingPathExtension]];
	[track setMetadata:[decoder metadata]];
	if([decoder hasCueSheet] == XLDTrackTypeCueSheet) {
		[[track metadata] removeObjectForKey:XLD_METADATA_CUESHEET];
	}
	
	[task setScaleType:([o_scaleImage state] == NSOffState) ? XLDNoScale : ([[o_scaleType selectedCell] tag] | (([o_expandImage state] == NSOnState) ? 0x10 : 0))];
	[task setScaleSize:[o_scalePixel intValue]];
	[task setCompressionQuality:[o_compressionQuality intValue]/100.0f];
	[task setIndex:[track index]];
	[task setTotalFrame:[cueParser totalFrames]];
	[task setDecoderClass:[decoder class]];
	if([cueParser cueMode] == XLDCueModeRaw) {
		[task setRawFormat:[cueParser rawFormat]];
		[task setRawEndian:[cueParser rawEndian]];
		[task setRawOffset:[cueParser rawOffset]];
	}
	else if([cueParser cueMode] == XLDCueModeMulti) {
		[task setDiscLayout:[cueParser discLayout]];
	}
	[self setOutputForTask:task];
	[task setInputPath:[cueParser fileToDecode]];
	[task setOutputDir:outputDir];
	[task setProcessOfExistingFiles:[[o_existingFile selectedCell] tag]];
	[task setTagWritable:([o_autoTagging state] == NSOnState) ? YES : NO];
	[task setTrack:track];
	[task setOffsetFixupValue:[o_offsetValue intValue]];
	
	[decoder closeFile];
	
	[taskQueue addTask:task];
end:
		[track release];
	[task release];
}

- (IBAction)checkForUpdates:(id)sender
{
	if(updater) [updater checkForUpdates:sender];
}

- (IBAction)stopModal:(id)sender
{
	[NSApp stopModalWithCode:[sender tag]];
	[[NSApp modalWindow] close];
}

- (IBAction)analyzeCache:(id)sender
{
	id cueParser = [discView cueParser];
	[o_detectPregapMessage setStringValue:LS(@"Analyzing caching ability... (this may take a few minutes)")];
	[o_detectPregapProgress setIndeterminate:YES];
	[o_detectPregapProgress startAnimation:nil];
	[o_detectPregapPaneButton setHidden:YES];
	[NSApp beginSheet:o_detectPregapPane
	   modalForWindow:[discView window]
		modalDelegate:self
	   didEndSelector:@selector(sheetDidEnd:returnCode:contextInfo:)
		  contextInfo:@"AnalyzeCache"];
	[NSThread detachNewThreadSelector:@selector(analyzeCacheForDrive:) toTarget:self withObject:[cueParser fileToDecode]];
}

- (IBAction)cancelScan:(id)sender
{
	cancelScan = YES;
}

- (IBAction)inputTagsFromText:(id)sender
{
	[metadataEditor inputTagsFromText];
}

- (IBAction)donate:(id)sender
{
	NSWorkspace* ws = [NSWorkspace sharedWorkspace];
	NSString *url;
	NSUserDefaults* defs = [NSUserDefaults standardUserDefaults];
	NSArray* languages = [defs objectForKey:@"AppleLanguages"];
	if([[languages objectAtIndex:0] isEqualToString:@"ja"]) {
		url = @"https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=tmkk%40smoug%2enet&item_name=X%20Lossless%20Decoder&no_shipping=0&no_note=1&tax=0&currency_code=JPY&lc=JP&bn=PP%2dDonationsBF&charset=UTF%2d8";
	}
	else if([[languages objectAtIndex:0] isEqualToString:@"de"]
			|| [[languages objectAtIndex:0] isEqualToString:@"fr"]
			|| [[languages objectAtIndex:0] isEqualToString:@"nl"]
			|| [[languages objectAtIndex:0] isEqualToString:@"it"]
			|| [[languages objectAtIndex:0] isEqualToString:@"el"]) {
		url = @"https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=tmkk%40smoug%2enet&item_name=X%20Lossless%20Decoder&no_shipping=0&no_note=1&tax=0&currency_code=EUR&lc=US&bn=PP%2dDonationsBF&charset=UTF%2d8";
	}
	else {
		url = @"https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=tmkk%40smoug%2enet&item_name=X%20Lossless%20Decoder&no_shipping=0&no_note=1&tax=0&currency_code=USD&lc=US&bn=PP%2dDonationsBF&charset=UTF%2d8";
	}
	[ws openURL:[NSURL URLWithString:url]];
}

- (IBAction)openFolderAsDisc:(id)sender
{
	NSOpenPanel *op = [NSOpenPanel openPanel];
	[op setCanChooseDirectories:YES];
	[op setCanChooseFiles:NO];
	[op setAllowsMultipleSelection:NO];
	[o_htoaLengthM setIntValue:0];
	[o_htoaLengthS setIntValue:0];
	[o_htoaLengthF setIntValue:0];
	[op setAccessoryView:o_htoaView];
	
	int ret = [op runModal];
	[op setAccessoryView:nil];
	if(ret != NSOKButton) return;
	xldoffset_t offset = 588*([o_htoaLengthM intValue]*60*75+[o_htoaLengthS intValue]*75+[o_htoaLengthF intValue]);
	BOOL prepended = [[o_htoaStyle selectedCell] tag] == 0 ? YES : NO;
	[self openFolder:[op filename] offset:offset prepended:prepended];
}

- (IBAction)searchCoverArt:(id)sender
{
	NSDictionary *keys = [self awsKeys];
	if(!keys) {
		NSRunAlertPanel(LS(@"Cannot Search Cover Art"), LS(@"You have to enable Amazon Web Services and set up access keys to use this feature."), @"OK", nil, nil);
		return;
	}
	id cueParser = [discView cueParser];
	if(!cueParser) [coverArtSearcher showWindowWithKeyword:nil];
	else {
		NSString *artist = [cueParser artist];
		NSString *title = [cueParser title];
		if([artist isEqualToString:LS(@"Various Artists")])
			[coverArtSearcher showWindowWithKeyword:title];
		else if([artist rangeOfString:@"Various"].location == 0)
			[coverArtSearcher showWindowWithKeyword:title];
		else if([artist isEqualToString:@""])
			[coverArtSearcher showWindowWithKeyword:title];
		else if([title rangeOfString:artist].location != NSNotFound)
			[coverArtSearcher showWindowWithKeyword:title];
		else [coverArtSearcher showWindowWithKeyword:[NSString stringWithFormat:@"%@ %@",artist,title]];
	}
}

- (IBAction)associateMBDiscID:(id)sender
{
	id cueParser = [discView cueParser];
	if(!cueParser) return;
	XLDCDDBUtil *cddb = [[XLDCDDBUtil alloc] initWithDelegate:self];
	[cddb setTracks:[cueParser trackList] totalFrame:[cueParser totalFrames]];
	if(![cddb associateMBDiscID]) {
		NSBeginAlertSheet(LS(@"DiscID Association Failure"), @"OK", nil, nil, [discView window], nil, nil, nil, NULL, LS(@"This DiscID is already associated with the release."));
	}
	[cddb release];
}

- (IBAction)reportBug:(id)sender
{
	NSWorkspace* ws = [NSWorkspace sharedWorkspace];
	[ws openURL:[NSURL URLWithString:@"http://code.google.com/p/xld/issues/list"]];
}

- (IBAction)getMetadataFromURL:(id)sender
{
	[NSApp beginSheet:o_resourceURLPane
	   modalForWindow:[discView window]
		modalDelegate:self
	   didEndSelector:@selector(sheetDidEnd:returnCode:contextInfo:)
		  contextInfo:@"GetMetadataFromURL"];
}

#pragma mark Normal Methods

- (id)init
{
	[super init];
	NSFileManager *fm = [NSFileManager defaultManager];
	[fm createDirectoryWithIntermediateDirectoryInPath:[@"~/Library/Application Support/XLD/PlugIns" stringByExpandingTildeInPath]];
	
	XLDPluginManager *pluginManager = [[XLDPluginManager alloc] init];
	decoderCenter = [[XLDecoderCenter alloc] initWithPlugins:[pluginManager plugins]];
	//cueParser = [[XLDCueParser alloc] initWithDelegate:self];
	player = [[XLDPlayer alloc] initWithDelegate:self];
	taskQueue = [[XLDQueue alloc] initWithDelegate:self];
	metadataEditor = [[XLDMetadataEditor alloc] initWithDelegate:self];
	//decoding = NO;
	util = nil;
	
	outputArr = [[NSMutableArray alloc] init];
	serverList = [[NSMutableArray alloc] initWithObjects:@"freedb.freedb.org",@"freedbtest.dyndns.org",nil];
	queue = [[NSMutableArray alloc] init];
	NSArray *bundleArr = [pluginManager plugins];
	
	int i;
	NSBundle *bundle = nil;
	id output;
	{
		output = [[XLDWavOutput alloc] init];
		[outputArr addObject:output];
		[output release];
		output = [[XLDAiffOutput alloc] init];
		[outputArr addObject:output];
		[output release];
		output = [[XLDPcmLEOutput alloc] init];
		[outputArr addObject:output];
		[output release];
		output = [[XLDPcmBEOutput alloc] init];
		[outputArr addObject:output];
		[output release];
		output = [[XLDWave64Output alloc] init];
		[outputArr addObject:output];
		[output release];
	}
	for(i=0;i<[bundleArr count];i++) {
		bundle = [NSBundle bundleWithPath:[bundleArr objectAtIndex:i]];
		if(bundle) {
			if([bundle load]) {
				if([[bundle principalClass] conformsToProtocol:@protocol(XLDOutput)] && [[bundle principalClass] canLoadThisBundle]) {
					output = [[[bundle principalClass] alloc] init];
					if([output respondsToSelector:@selector(configurations)]) [outputArr addObject:output];
					[output release];
				}
			}
		}
	}
	ejected = NO;
	launched = NO;
	firstDrag = YES;
	tempOutputDir = nil;
	driveIsBusy = NO;
	openingFiles = NO;
	launchDate = [[NSDate date] timeIntervalSince1970];
	
	updater = nil;
	bundle = [NSBundle bundleWithPath:[[NSBundle mainBundle] pathForResource:@"XLDSparkleUpdater" ofType:@"bundle" inDirectory:@"../PlugIns"]];
	if(bundle && [bundle load]) {
		if([[bundle principalClass] canLoadThisBundle]) {
			updater = [[[bundle principalClass] alloc] init];
		}
	}
	
	customFormatManager = [[XLDCustomFormatManager alloc] initWithOutputArray:outputArr delegate:self];
	profileManager = [[XLDProfileManager alloc] initWithDelegate:self];
	discView = [[XLDDiscView alloc] initWithDelegate:self];
	coverArtSearcher = [[XLDCoverArtSearcher alloc] initWithDelegate:self];
	
	DASessionRef daSession = DASessionCreate(kCFAllocatorDefault);
	DAApprovalSessionRef daASession = DAApprovalSessionCreate(kCFAllocatorDefault);
	NSDictionary *matchedCD = [NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"IOCDMedia", [NSNumber numberWithBool:YES], nil]
														  forKeys:[NSArray arrayWithObjects:(NSString *)kDADiskDescriptionMediaKindKey, kDADiskDescriptionMediaWholeKey, nil]];

	DASessionScheduleWithRunLoop(daSession, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
	DAApprovalSessionScheduleWithRunLoop(daASession, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    DARegisterDiskAppearedCallback(daSession, (CFDictionaryRef)matchedCD, diskAppeared, self);
    DARegisterDiskDisappearedCallback(daSession, (CFDictionaryRef)matchedCD, diskDisappeared, self);
	DARegisterDiskMountApprovalCallback(daASession, (CFDictionaryRef)matchedCD, diskMounted, self);
	
	[pluginManager release];
	
	return self;
}

- (id)decoderCenter
{
	return decoderCenter;
}

- (void)savePrefsToDictionary:(id)pref
{
	[pref setObject:[o_outputDir stringValue] forKey:@"OutputDir"];
	[pref setInteger:[discView extractionMode] forKey:@"Pregap"];
	//[pref setInteger:[o_overwriteButton state] forKey:@"Overwrite"];
	//[pref setInteger:[o_formatList indexOfSelectedItem] forKey:@"OutputFormat"];
	[pref setObject:[o_formatList titleOfSelectedItem] forKey:@"OutputFormatName"];
	[pref setInteger:[[o_outputSelectRadio selectedCell] tag] forKey:@"SelectOutput"];
	[pref setInteger:[o_autoTagging state] forKey:@"Tagging"];
	[pref setInteger:[[o_filenameFormatRadio selectedCell] tag] forKey:@"FilenameFormatRadio"];
	[pref setObject:[o_filenameFormat stringValue] forKey:@"FilenameFormat"];
	[pref setObject:[o_cddbServer stringValue] forKey:@"CDDBServer"];
	[pref setObject:[o_cddbServerPath stringValue] forKey:@"CDDBServerPath"];
	[pref setObject:[o_cddbServerPort stringValue] forKey:@"CDDBServerPort"];
	[pref setObject:[o_cddbProxyServer stringValue] forKey:@"CDDBProxyServer"];
	[pref setObject:[o_cddbProxyUser stringValue] forKey:@"CDDBProxyUser"];
	[pref setObject:[o_cddbProxyPassword stringValue] forKey:@"CDDBProxyPasswd"];
	[pref setObject:[o_cddbProxyServerPort stringValue] forKey:@"CDDBProxyServerPort"];
	[pref setInteger:[o_cddbProxyEnabled state] forKey:@"CDDBUseProxy"];
	[pref setInteger:[o_cddbUseCache state] forKey:@"CDDBUseCache"];
	[pref setObject:serverList forKey:@"CDDBServerList"];
	[pref setInteger:[o_rawBitDepth indexOfSelectedItem] forKey:@"RawBitDepth"];
	[pref setInteger:[o_rawChannels indexOfSelectedItem] forKey:@"RawChannels"];
	[pref setInteger:[o_rawEndian indexOfSelectedItem] forKey:@"RawEndian"];
	[pref setObject:[o_rawSamplerate stringValue] forKey:@"RawSamplerate"];
	[pref setInteger:[o_correctOffset state] forKey:@"CorrectOffset"];
	//[pref setInteger:[o_cuesheetEncodings indexOfSelectedItem] forKey:@"CuesheetEncodings"];
	[pref setInteger:[[o_cuesheetEncodings selectedItem] tag] forKey:@"CuesheetEncodings2"];
	[pref setObject:[NSNumber numberWithUnsignedInt:[self cddbQueryFlag]] forKey:@"CDDBQueryFlag2"];
	[pref setInteger:[o_maxThreads intValue] forKey:@"MaxThreads"];
	[pref setInteger:[o_scaleImage state] forKey:@"ScaleImage"];
	[pref setInteger:[[o_scaleType selectedCell] tag] forKey:@"ScaleType"];
	[pref setInteger:[o_scalePixel intValue] forKey:@"ScalePixel"];
	[pref setInteger:[o_compressionQuality intValue] forKey:@"CompressionQuality"];
	[pref setInteger:[o_editTags state] forKey:@"EditTags"];
	[pref setInteger:[o_addiTunes state] forKey:@"AddiTunes"];
	[pref setInteger:[[o_libraryType selectedCell] tag] forKey:@"LibraryType"];
	[pref setObject:[o_libraryName stringValue] forKey:@"LibraryName"];
	[pref setInteger:[o_maxRetryCount intValue] forKey:@"RetryCount"];
	[pref setInteger:[o_offsetCorrectionValue intValue] forKey:@"OffsetCorrectionValue"];
	[pref setInteger:[o_queryAccurateRip state] forKey:@"QueryAccurateRip"];
	[pref setInteger:[[o_saveLogMode selectedItem] tag] forKey:@"SaveLogMode"];
	[pref setInteger:[[o_saveCueMode selectedItem] tag] forKey:@"SaveCueMode"];
	[pref setInteger:[o_verifySuspiciousSector state] forKey:@"VerifySector"];
	[pref setInteger:[o_testBeforeCopy state] forKey:@"TestAndCopy"];
	[pref setInteger:[[o_testType selectedCell] tag] forKey:@"TestType"];
	[pref setInteger:[[o_cuesheetType selectedCell] tag] forKey:@"CuesheetType"];
	[pref setInteger:[o_arLogControl state] forKey:@"LogControl"];
	[pref setInteger:[o_scanReplayGain state] forKey:@"ScanReplayGain"];
	[pref setInteger:[o_useC2Pointer state] forKey:@"UseC2Pointer"];
	[pref setInteger:[o_autoSetOffsetValue state] forKey:@"AutoSetOffset"];
	[pref setInteger:[o_subdirectoryDepth intValue] forKey:@"SubdirectoryDepth"];
	[pref setInteger:[o_autoMountDisc state] forKey:@"AutoMountDisc"];
	[pref setInteger:[o_autoStartRipping state] forKey:@"AutoStartRipping"];
	[pref setInteger:[o_ejectWhenDone state] forKey:@"EjectWhenDone"];
	[pref setInteger:[o_quitWhenDone state] forKey:@"QuitWhenDone"];
	[pref setInteger:[o_autoQueryCDDB state] forKey:@"AutoQueryCDDB"];
	[pref setInteger:[o_limitExtension state] forKey:@"LimitExtension"];
	[pref setObject:[o_extensionFilter stringValue] forKey:@"ExtensionFilter"];
	[pref setInteger:[o_preserveDirectoryStructure state] forKey:@"PreserveDirectory"];
	[pref setInteger:[o_dontPromptForCDDB state] forKey:@"DontPrompt"];
	[pref setInteger:[o_forceReadCuesheet state] forKey:@"ForceReadCuesheet"];
	[pref setInteger:[o_appendBOM state] forKey:@"AppendBOM"];
	[pref setInteger:[[o_existingFile selectedCell] tag] forKey:@"ExistingFile"];
	[pref setInteger:[o_expandImage state] forKey:@"ExpandImage"];
	[pref setInteger:[o_autoLoadCoverArt state] forKey:@"AutoLoadCover"];
	[pref setObject:[o_autoLoadCoverArtName stringValue] forKey:@"AutoLoadCoverName"];
	[pref setInteger:[o_autoLoadCoverArtDontOverwrite state] forKey:@"AutoLoadCoverDontOverwrite"];
	[pref setInteger:[o_embedCoverArts state] forKey:@"EmbedImages"];
	[pref setInteger:[o_dontReadSubchannel state] forKey:@"DontReadSubchannel"];
	[pref setInteger:[o_moveAfterFinish state] forKey:@"MoveAfterFinish"];
	[pref setInteger:[o_autoSetCompilation state] forKey:@"AutoSetCompilation"];
	[pref setInteger:[o_preserveUnknownMetadata state] forKey:@"PreserveUnknownMetadata"];
	[pref setInteger:[o_keepTimeStamp state] forKey:@"KeepTimeStamp"];
	[pref setInteger:[o_removeOriginalFile state] forKey:@"RemoveOriginal"];
	[pref setInteger:[o_warnBeforeConversion state] forKey:@"WarnRemoval"];
	[pref setBool:[o_prefPane isVisible] forKey:@"PrefPaneVisible"];
	[pref setInteger:[[o_ripperMode selectedItem] tag] forKey:@"RipperMode"];
	[pref setObject:[NSString stringWithString:[o_defaultCommentValue string]] forKey:@"DefaultCommentValue"];
	[pref setInteger:[[o_preferredService selectedItem] tag] forKey:@"PreferredService"];
	[pref setInteger:[o_writeOffset intValue] forKey:@"WriteOffset"];
	[pref setInteger:[o_readOffsetForVerify intValue] forKey:@"ReadOffsetForVerify"];
	[pref setInteger:[o_readOffsetUseRipperValue state] forKey:@"ReadOffsetUseRipperValue"];
	[pref setInteger:[o_useAWS state] forKey:@"UseAWS"];
	[pref setObject:[o_AWSKey stringValue] forKey:@"AWSKey"];
	[pref setObject:[o_AWSSecretKey stringValue] forKey:@"AWSSecretKey"];
	[pref setInteger:[[o_AWSDomain selectedItem] tag] forKey:@"AWSDomain"];
	[pref setInteger:[[o_htoaStyle selectedCell] tag] forKey:@"HTOAStyle"];
}

- (void)savePrefs
{
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	[self savePrefsToDictionary:pref];
	[pref synchronize];
}

- (void)loadPrefsFromDictionary:(id)pref
{
	id obj;
	if(obj=[pref objectForKey:@"Pregap"]) {
		[discView setExtractionMode:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"OutputDir"]) {
		[o_outputDir setStringValue:obj];
	}
	else [o_outputDir setStringValue:[@"~/Music" stringByExpandingTildeInPath]];
	if(obj=[pref objectForKey:@"OutputFormatName"]) {
		if([o_formatList itemWithTitle:obj]) [o_formatList selectItemWithTitle:obj];
		[self formatChanged:self];
	}
	else if(obj=[pref objectForKey:@"OutputFormat"]) {
		if([obj intValue] < [o_formatList numberOfItems]-1) {
			if([obj intValue] < 4) [o_formatList selectItemAtIndex:[obj intValue]];
			else [o_formatList selectItemAtIndex:[obj intValue]+1];
		}
		[pref removeObjectForKey:@"OutputFormat"];
		[pref synchronize];
		[self formatChanged:self];
	}
	/*if(obj=[pref objectForKey:@"OutputFormat"]) {
	 if([obj intValue] < [o_formatList numberOfItems]) {
	 [o_formatList selectItemAtIndex:[obj intValue]];
	 }
	 [self formatChanged:self];
	 }*/
	if(obj=[pref objectForKey:@"SelectOutput"]) {
		[o_outputSelectRadio selectCellWithTag:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"Tagging"]) {
		[o_autoTagging setState:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"FilenameFormatRadio"]) {
		[o_filenameFormatRadio selectCellWithTag:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"FilenameFormat"]) {
		[o_filenameFormat setStringValue:obj];
	}
	if(obj=[pref objectForKey:@"CDDBServer"]) {
		[o_cddbServer setStringValue:obj];
	}
	if(obj=[pref objectForKey:@"CDDBServerPath"]) {
		[o_cddbServerPath setStringValue:obj];
	}
	if(obj=[pref objectForKey:@"CDDBServerPort"]) {
		[o_cddbServerPort setStringValue:obj];
	}
	if(obj=[pref objectForKey:@"CDDBProxyServer"]) {
		[o_cddbProxyServer setStringValue:obj];
	}
	if(obj=[pref objectForKey:@"CDDBProxyServerPort"]) {
		[o_cddbProxyServerPort setStringValue:obj];
	}
	if(obj=[pref objectForKey:@"CDDBProxyUser"]) {
		[o_cddbProxyUser setStringValue:obj];
	}
	if(obj=[pref objectForKey:@"CDDBProxyPasswd"]) {
		[o_cddbProxyPassword setStringValue:obj];
	}
	if(obj=[pref objectForKey:@"CDDBUseProxy"]) {
		[o_cddbProxyEnabled setState:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"CDDBUseCache"]) {
		[o_cddbUseCache setState:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"CDDBServerList"]) {
		[serverList removeAllObjects];
		[serverList addObjectsFromArray:obj];
		[o_cddbServer setNumberOfVisibleItems:[obj count]];
		[o_cddbServer reloadData];
	}
	if(obj=[pref objectForKey:@"RawBitDepth"]) {
		if([obj intValue] < [o_rawBitDepth numberOfItems]) [o_rawBitDepth selectItemAtIndex:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"RawChannels"]) {
		if([obj intValue] < [o_rawChannels numberOfItems]) [o_rawChannels selectItemAtIndex:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"RawEndian"]) {
		if([obj intValue] < [o_rawEndian numberOfItems]) [o_rawEndian selectItemAtIndex:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"RawSamplerate"]) {
		[o_rawSamplerate setStringValue:obj];
	}
	if(obj=[pref objectForKey:@"CorrectOffset"]) {
		[o_correctOffset setState:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"CuesheetEncodings2"]) {
		int i;
		for(i=[o_cuesheetEncodings numberOfItems]-1;i>=0;i--) {
			if([[o_cuesheetEncodings itemAtIndex:i] tag] == [obj intValue]) {
				[o_cuesheetEncodings selectItemAtIndex:i];
				break;
			}
		}
	}
	else if(obj=[pref objectForKey:@"CuesheetEncodings"]) {
		if([obj intValue] == 0) {
			[o_cuesheetEncodings selectItemAtIndex:0];
		}
		else {
			const NSStringEncoding *encodingsArr = [NSString availableStringEncodings];
			int count = 0;
			while(*(encodingsArr+count)) count++;
			if([obj intValue]-2 < count) [o_cuesheetEncodings selectItemWithTitle:[NSString localizedNameOfStringEncoding:*(encodingsArr+[obj intValue]-2)]];
		}
	}
	if(obj=[pref objectForKey:@"CDDBQueryFlag2"]) {
		unsigned int flag = [obj unsignedIntValue];
		NSMenu *submenu = [o_cddbQueryItem submenu];
		if(flag & XLDCDDBQueryEmptyOnlyMask) [[submenu itemAtIndex:0] setState:NSOnState];
		else [[submenu itemAtIndex:0] setState:NSOffState];
		if(flag & XLDCDDBQueryDiscTitleMask) [[submenu itemAtIndex:2] setState:NSOnState];
		else [[submenu itemAtIndex:2] setState:NSOffState];
		if(flag & XLDCDDBQueryTrackTitleMask) [[submenu itemAtIndex:3] setState:NSOnState];
		else [[submenu itemAtIndex:3] setState:NSOffState];
		if(flag & XLDCDDBQueryArtistMask) [[submenu itemAtIndex:4] setState:NSOnState];
		else [[submenu itemAtIndex:4] setState:NSOffState];
		if(flag & XLDCDDBQueryGenreMask) [[submenu itemAtIndex:5] setState:NSOnState];
		else [[submenu itemAtIndex:5] setState:NSOffState];
		if(flag & XLDCDDBQueryYearMask) [[submenu itemAtIndex:6] setState:NSOnState];
		else [[submenu itemAtIndex:6] setState:NSOffState];
		if(flag & XLDCDDBQueryComposerMask) [[submenu itemAtIndex:7] setState:NSOnState];
		else [[submenu itemAtIndex:7] setState:NSOffState];
		if(flag & XLDCDDBQueryCoverArtMask) [[submenu itemAtIndex:8] setState:NSOnState];
		else [[submenu itemAtIndex:8] setState:NSOffState];
	}
	else if(obj=[pref objectForKey:@"CDDBQueryFlag"]) {
		unsigned int flag = [obj unsignedIntValue];
		NSMenu *submenu = [o_cddbQueryItem submenu];
		if(flag & XLDCDDBQueryEmptyOnlyMask) [[submenu itemAtIndex:0] setState:NSOnState];
		else [[submenu itemAtIndex:0] setState:NSOffState];
		if(flag & XLDCDDBQueryDiscTitleMask) [[submenu itemAtIndex:2] setState:NSOnState];
		else [[submenu itemAtIndex:2] setState:NSOffState];
		if(flag & XLDCDDBQueryTrackTitleMask) [[submenu itemAtIndex:3] setState:NSOnState];
		else [[submenu itemAtIndex:3] setState:NSOffState];
		if(flag & XLDCDDBQueryArtistMask) [[submenu itemAtIndex:4] setState:NSOnState];
		else [[submenu itemAtIndex:4] setState:NSOffState];
		if(flag & XLDCDDBQueryGenreMask) [[submenu itemAtIndex:5] setState:NSOnState];
		else [[submenu itemAtIndex:5] setState:NSOffState];
		if(flag & XLDCDDBQueryYearMask) [[submenu itemAtIndex:6] setState:NSOnState];
		else [[submenu itemAtIndex:6] setState:NSOffState];
		if(flag & XLDCDDBQueryCoverArtMask) [[submenu itemAtIndex:8] setState:NSOnState];
		else [[submenu itemAtIndex:8] setState:NSOffState];
	}
	if(obj=[pref objectForKey:@"MaxThreads"]) {
		[o_maxThreads setIntValue:[obj intValue]];
		[o_maxThreads sendAction:[o_maxThreads action] to:[o_maxThreads target]];
	}
	else {
		int numThread;
		size_t size = sizeof(int);
		sysctlbyname("hw.activecpu",&numThread,&size,NULL,0);
		[o_maxThreads setIntValue:numThread];
		[o_maxThreads sendAction:[o_maxThreads action] to:[o_maxThreads target]];
	}
	if(obj=[pref objectForKey:@"ScaleImage"]) {
		[o_scaleImage setState:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"ScaleType"]) {
		[o_scaleType selectCellWithTag:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"ScalePixel"]) {
		[o_scalePixel setIntValue:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"CompressionQuality"]) {
		[o_compressionQuality setIntValue:[obj intValue]];
		[o_compressionQuality performClick:nil];
	}
	if(obj=[pref objectForKey:@"EditTags"]) {
		[o_editTags setState:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"AddiTunes"]) {
		[o_addiTunes setState:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"LibraryType"]) {
		[o_libraryType selectCellWithTag:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"LibraryName"]) {
		[o_libraryName setStringValue:obj];
	}
	if(obj=[pref objectForKey:@"RetryCount"]) {
		[o_maxRetryCount setIntValue:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"OffsetCorrectionValue"]) {
		[o_offsetCorrectionValue setIntValue:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"QueryAccurateRip"]) {
		[o_queryAccurateRip setState:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"SaveLogMode"]) {
		[o_saveLogMode selectItemAtIndex:[o_saveLogMode indexOfItemWithTag:[obj intValue]]];
	}
	else {
		if(obj=[pref objectForKey:@"SaveLog"]) {
			if([obj intValue] == NSOffState) [o_saveLogMode selectItemAtIndex:[o_saveLogMode indexOfItemWithTag:2]];
			else if(obj=[pref objectForKey:@"SaveLogType"]) {
				[o_saveLogMode selectItemAtIndex:[o_saveLogMode indexOfItemWithTag:[obj intValue]]];
			}
		}
	}
	if(obj=[pref objectForKey:@"SaveCueMode"]) {
		[o_saveCueMode selectItemAtIndex:[o_saveCueMode indexOfItemWithTag:[obj intValue]]];
	}
	if(obj=[pref objectForKey:@"VerifySector"]) {
		[o_verifySuspiciousSector setState:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"TestAndCopy"]) {
		[o_testBeforeCopy setState:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"TestType"]) {
		[o_testType selectCellWithTag:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"CuesheetType"]) {
		[o_cuesheetType selectCellWithTag:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"LogControl"]) {
		[o_arLogControl setState:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"ScanReplayGain"]) {
		[o_scanReplayGain setState:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"UseC2Pointer"]) {
		[o_useC2Pointer setState:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"AutoSetOffset"]) {
		[o_autoSetOffsetValue setState:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"SubdirectoryDepth"]) {
		[o_subdirectoryDepth setIntValue:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"AutoMountDisc"]) {
		[o_autoMountDisc setState:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"AutoStartRipping"]) {
		[o_autoStartRipping setState:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"EjectWhenDone"]) {
		[o_ejectWhenDone setState:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"QuitWhenDone"]) {
		[o_quitWhenDone setState:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"AutoQueryCDDB"]) {
		[o_autoQueryCDDB setState:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"LimitExtension"]) {
		[o_limitExtension setState:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"ExtensionFilter"]) {
		[o_extensionFilter setStringValue:obj];
	}
	if(obj=[pref objectForKey:@"PreserveDirectory"]) {
		[o_preserveDirectoryStructure setState:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"DontPrompt"]) {
		[o_dontPromptForCDDB setState:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"ForceReadCuesheet"]) {
		[o_forceReadCuesheet setState:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"AppendBOM"]) {
		[o_appendBOM setState:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"ExistingFile"]) {
		[o_existingFile selectCellWithTag:[obj intValue]];
	}
	else if(obj=[pref objectForKey:@"Overwrite"]) {
		if([obj intValue] == NSOnState) [o_existingFile selectCellWithTag:2];
		else [o_existingFile selectCellWithTag:0];
	}
	if(obj=[pref objectForKey:@"ExpandImage"]) {
		[o_expandImage setState:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"AutoLoadCover"]) {
		[o_autoLoadCoverArt setState:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"AutoLoadCoverName"]) {
		[o_autoLoadCoverArtName setStringValue:obj];
	}
	if(obj=[pref objectForKey:@"AutoLoadCoverDontOverwrite"]) {
		[o_autoLoadCoverArtDontOverwrite setState:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"EmbedImages"]) {
		[o_embedCoverArts setState:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"DontReadSubchannel"]) {
		[o_dontReadSubchannel setState:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"MoveAfterFinish"]) {
		[o_moveAfterFinish setState:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"AutoSetCompilation"]) {
		[o_autoSetCompilation setState:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"PreserveUnknownMetadata"]) {
		[o_preserveUnknownMetadata setState:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"KeepTimeStamp"]) {
		[o_keepTimeStamp setState:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"RemoveOriginal"]) {
		[o_removeOriginalFile setState:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"WarnRemoval"]) {
		[o_warnBeforeConversion setState:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"RipperMode"]) {
		int idx = [o_ripperMode indexOfItemWithTag:[obj intValue]];
		if(idx >= 0) [o_ripperMode selectItemAtIndex:idx];
	}
	else if(obj=[pref objectForKey:@"UseParanoiaMode"]) {
		int tag;
		if([obj intValue] == NSOnState) tag = kRipperModeParanoia;
		else tag = kRipperModeBurst;
		int idx = [o_ripperMode indexOfItemWithTag:tag];
		if(idx >= 0) [o_ripperMode selectItemAtIndex:idx];
	}
	if(obj=[pref objectForKey:@"DefaultCommentValue"]) {
		[[[o_defaultCommentValue textStorage] mutableString] setString:obj];
		[[o_defaultCommentValue textStorage] setFont:[NSFont systemFontOfSize:11]];
	}
	if(obj=[pref objectForKey:@"PreferredService"]) {
		int idx = [o_preferredService indexOfItemWithTag:[obj intValue]];
		if(idx >= 0) [o_preferredService selectItemAtIndex:idx];
	}
	if(obj=[pref objectForKey:@"WriteOffset"]) {
		[o_writeOffset setIntValue:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"ReadOffsetForVerify"]) {
		[o_readOffsetForVerify setIntValue:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"ReadOffsetUseRipperValue"]) {
		[o_readOffsetUseRipperValue setState:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"UseAWS"]) {
		[o_useAWS setState:[obj intValue]];
	}
	if(obj=[pref objectForKey:@"AWSKey"]) {
		[o_AWSKey setStringValue:obj];
	}
	if(obj=[pref objectForKey:@"AWSSecretKey"]) {
		[o_AWSSecretKey setStringValue:obj];
	}
	if(obj=[pref objectForKey:@"AWSDomain"]) {
		int idx = [o_AWSDomain indexOfItemWithTag:[obj intValue]];
		if(idx >= 0) [o_AWSDomain selectItemAtIndex:idx];
	}
	if(obj=[pref objectForKey:@"HTOAStyle"]) {
		[o_htoaStyle selectCellWithTag:[obj intValue]];
	}
}

- (void)loadPrefs
{
	BOOL initialLaunch = NO;
	NSFileManager *fm = [NSFileManager defaultManager];
	if(![fm fileExistsAtPath:[@"~/Library/Preferences/jp.tmkk.XLD.plist" stringByExpandingTildeInPath]]) {
		initialLaunch = YES;
	}
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	[self loadPrefsFromDictionary:pref];
	id obj;
	if(updater) {
		if(![pref objectForKey:@"SUEnableAutomaticChecks"]) {
			[pref setBool:YES forKey:@"SUEnableAutomaticChecks"];
			[pref synchronize];
		}
		else if([pref objectForKey:@"TempUpdateKey"]) {
			[pref setBool:YES forKey:@"SUEnableAutomaticChecks"];
			[pref removeObjectForKey:@"TempUpdateKey"];
			[pref synchronize];
		}
	}
	else {
		[pref setBool:NO forKey:@"SUEnableAutomaticChecks"];
		[pref synchronize];
	}
	
	if(obj=[pref objectForKey:@"PrefPaneVisible"]) {
		if([obj boolValue]) [o_prefPane makeKeyAndOrderFront:nil];
	}
	else {
		if(initialLaunch) {
			[o_prefPane center];
			[o_prefPane makeKeyAndOrderFront:nil];
			[o_formatList performClick:nil];
		}
	}
}

- (NSString *)subdirInDir:(NSString *)dir baseDir:(NSString *)base file:(NSString *)file
{
	if(!base || !file) return nil;
	NSRange range = [file rangeOfString:base options:NSCaseInsensitiveSearch];
	if(range.location != 0) return nil;
	NSString *subdir = [[base lastPathComponent] stringByAppendingPathComponent:[[file substringFromIndex:range.length] stringByDeletingLastPathComponent]];
	//NSLog(subdir);
	return subdir;
}

- (void)processMultipleFilesInThread
{
	NSAutoreleasePool *pool2 = [[NSAutoreleasePool alloc] init];
	NSArray *coverArtFileListArray = [self coverArtFileListArray];
	int i,j;
	NSString *baseDir = nil;
	BOOL isDir;
	BOOL removeFlag = NO;
	if(![queue count]) {
		[pool2 release];
		[o_detectPregapPane close];
		openingFiles = NO;
		return;
	}
	if([[o_outputSelectRadio selectedCell] tag] && ![[NSFileManager defaultManager] isWritableFileAtPath:[o_outputDir stringValue]]) {
		NSRunCriticalAlertPanel(LS(@"error"), LS(@"no write permission"), @"OK", nil, nil);
		[pool2 release];
		[o_detectPregapPane close];
		openingFiles = NO;
		return;
	}
	NSArray *sortedQueue;
	if([NSString instancesRespondToSelector:@selector(localizedStandardCompare:)]) {
		sortedQueue = [queue sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
	}
	else {
		sortedQueue = [queue sortedArrayUsingSelector:@selector(localizedCompare:)];
	}
	
	//NSLog([sortedQueue description]);
	NSMutableArray *taskArray = [[NSMutableArray alloc] init];
	NSMutableArray *trackArray = [[NSMutableArray alloc] init];
	NSMutableArray *rangeArray = [[NSMutableArray alloc] init];
	id cueParser = [[XLDCueParser alloc] initWithDelegate:self];
	int albumRangeIdx = 0;
	for(i=0;i<[sortedQueue count];i++) {
		BOOL removeOriginal = NO;
		if(cancelScan) {
			goto end;
		}
		[o_detectPregapProgress setDoubleValue:i];
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		NSFileManager *fm = [NSFileManager defaultManager];
		NSString *file = [sortedQueue objectAtIndex:i];
		[fm fileExistsAtPath:file isDirectory:&isDir];
		if(isDir) {
			if([o_preserveDirectoryStructure state] == NSOffState) goto next;
			if(!baseDir) baseDir = [file retain];
			else {
				NSRange range = [file rangeOfString:baseDir options:NSCaseInsensitiveSearch];
				if(range.location != 0) {
					[baseDir release];
					baseDir = [file retain];
				}
			}
			goto next;
		}
		
		NSString *outputDir;
		if([[o_outputSelectRadio selectedCell] tag] == 0) {
			outputDir = [file stringByDeletingLastPathComponent];
			if(![fm isWritableFileAtPath:outputDir]) {
				goto next;
			}
		}
		else {
			NSString *subDir = nil;
			if(baseDir) subDir = [self subdirInDir:[o_outputDir stringValue] baseDir:baseDir file:file];
			if(subDir)
				outputDir = [[o_outputDir stringValue] stringByAppendingPathComponent:subDir];
			else {
				outputDir = [o_outputDir stringValue];
				if(baseDir) {
					[baseDir release];
					baseDir = nil;
				}
			}
		}
		
		NSMutableArray *trackList;
		id decoder = [decoderCenter preferredDecoderForFile:file];
		BOOL externalCueMode = NO;
		if(!decoder) {
			externalCueMode = YES;
			trackList = (NSMutableArray *)[cueParser trackListForExternalCueSheet:file decoder:&decoder];
			if(!decoder) goto next;
			else if(![self canHandleOutputForDecoder:decoder]) goto next;

			[rangeArray addObject:[NSValue valueWithRange:NSMakeRange([trackArray count],[trackList count])]];
			for(j=0;j<[trackList count];j++) {
				[[trackList objectAtIndex:j] setDesiredFileName:[NSString stringWithFormat:@"%@ - Track %d",[file lastPathComponent],j+1]];
				[[[trackList objectAtIndex:j] metadata] setObject:[[file lastPathComponent] precomposedStringWithCanonicalMapping] forKey:XLD_METADATA_ORIGINALFILENAME];
				[[[trackList objectAtIndex:j] metadata] setObject:file forKey:XLD_METADATA_ORIGINALFILEPATH];
			}
		}
		else {
			if(![(id <XLDDecoder>)decoder openFile:(char *)[file UTF8String]]) goto next;
			if(![self canHandleOutputForDecoder:decoder]) goto next;

			if([decoder hasCueSheet] && [o_forceReadCuesheet state] == NSOnState) {
				if([decoder hasCueSheet] == XLDTextTypeCueSheet)
					trackList = (NSMutableArray *)[cueParser trackListForDecoder:decoder withEmbeddedCueData:[decoder cueSheet]];
				else
					trackList = (NSMutableArray *)[cueParser trackListForDecoder:decoder withEmbeddedTrackList:[decoder cueSheet]];
				[rangeArray addObject:[NSValue valueWithRange:NSMakeRange([trackArray count],[trackList count])]];
				for(j=0;j<[trackList count];j++) {
					[[trackList objectAtIndex:j] setDesiredFileName:[NSString stringWithFormat:@"%@ - Track %d",[file lastPathComponent],j+1]];
					[[[trackList objectAtIndex:j] metadata] setObject:[[file lastPathComponent] precomposedStringWithCanonicalMapping] forKey:XLD_METADATA_ORIGINALFILENAME];
					[[[trackList objectAtIndex:j] metadata] setObject:file forKey:XLD_METADATA_ORIGINALFILEPATH];
				}
			}
			else {
				trackList = [[[NSMutableArray alloc] init] autorelease];
				XLDTrack *track = [[XLDTrack alloc] init];
				[track setSeconds:[decoder totalFrames]/[decoder samplerate]];
				if(![NSStringFromClass([decoder class]) isEqualToString:@"XLDMP3Decoder"])
					[track setFrames:[decoder totalFrames]];
				[track setDesiredFileName:[[file lastPathComponent] stringByDeletingPathExtension]];
				[track setMetadata:[decoder metadata]];
				if([decoder hasCueSheet] == XLDTrackTypeCueSheet) {
					[[track metadata] removeObjectForKey:XLD_METADATA_CUESHEET];
				}
				if([o_keepTimeStamp state] == NSOnState) {
					NSDictionary *attrDic = [fm fileAttributesAtPath:file traverseLink:YES];
					if(attrDic) {
						[[track metadata] setObject:[attrDic fileCreationDate] forKey:XLD_METADATA_CREATIONDATE];
						[[track metadata] setObject:[attrDic fileModificationDate] forKey:XLD_METADATA_MODIFICATIONDATE];
					}
				}
				[[track metadata] setObject:[[file lastPathComponent] precomposedStringWithCanonicalMapping] forKey:XLD_METADATA_ORIGINALFILENAME];
				[[track metadata] setObject:@"Single" forKey:@"Single"];
				[[track metadata] setObject:file forKey:XLD_METADATA_ORIGINALFILEPATH];
				[trackList addObject:track];
				[track release];
				removeOriginal = ([o_removeOriginalFile state] == NSOnState);
				removeFlag = ([o_removeOriginalFile state] == NSOnState);
			}
		}
		
		NSData *imgData = nil;
		if([o_autoLoadCoverArt state] == NSOnState) {
			imgData = [self dataForAutoloadCoverArtForFile:file fileListArray:coverArtFileListArray];
		}
		
		[self setDefaultCommentValueForTrackList:trackList];
		
		for(j=0;j<[trackList count];j++) {
			XLDTrack *track = [trackList objectAtIndex:j];
			if(imgData && (![[track metadata] objectForKey:XLD_METADATA_COVER] || ([o_autoLoadCoverArtDontOverwrite state] == NSOffState))) {
				[[track metadata] setObject:imgData forKey:XLD_METADATA_COVER];
			}
			if([o_preserveUnknownMetadata state] == NSOffState) {
				int k;
				NSArray *keyArr = [[(XLDTrack *)track metadata] allKeys];
				for(k=[keyArr count]-1;k>=0;k--) {
					NSString *key = [keyArr objectAtIndex:k];
					NSRange range = [key rangeOfString:@"XLD_UNKNOWN_TEXT_METADATA_"];
					if(range.location != 0) continue;
					[[(XLDTrack *)track metadata] removeObjectForKey:key];
				}
			}
			XLDConverterTask *task = [[XLDConverterTask alloc] initWithQueue:taskQueue];
			xldoffset_t actualLength = [track frames];
			xldoffset_t actualIndex = [track index];
			if([trackList count] > 1) {
				if(j<[trackList count]-1) actualLength += [[trackList objectAtIndex:j+1] gap];
			}
			[task setScaleType:([o_scaleImage state] == NSOffState) ? XLDNoScale : ([[o_scaleType selectedCell] tag] | (([o_expandImage state] == NSOnState) ? 0x10 : 0))];
			[task setScaleSize:[o_scalePixel intValue]];
			[task setCompressionQuality:[o_compressionQuality intValue]/100.0f];
			[task setIndex:actualIndex];
			[task setTotalFrame:actualLength];
			[task setDecoderClass:[decoder class]];
			[self setOutputForTask:task];
			if(externalCueMode) [task setInputPath:[decoder srcPath]];
			else [task setInputPath:file];
			if([[decoder className] isEqualToString:@"XLDMultipleFileWrappedDecoder"])
				[task setDiscLayout:[decoder discLayout]];
			[task setOutputDir:outputDir];
			[task setProcessOfExistingFiles:[[o_existingFile selectedCell] tag]];
			[task setTagWritable:([o_autoTagging state] == NSOnState) ? YES : NO];
			[task setEmbedImages:([o_embedCoverArts state] == NSOnState) ? YES : NO];
			[task setMoveAfterFinish:([o_moveAfterFinish state] == NSOnState) ? YES : NO];
			//[task setTrack:track]; // not here, because the filename may be changed by tag editing
			[task setRemoveOriginalFile:removeOriginal];
			[taskArray addObject:task];
			[task release];
		}
		[trackArray addObjectsFromArray:trackList];
		[decoder closeFile];
next:
		[pool release];
	}
	
	[o_detectPregapPane close];
	
	if(![trackArray count]) goto end;
	
	if([o_editTags state] == NSOnState) {
#if 0
		BOOL ret = [metadataEditor editSingleTracks:trackArray atIndex:0];
		if(!ret) goto end;
#else
		SEL selector = @selector(editSingleTracks:withAlbumRanges:andDispatchTasks:);
		NSMethodSignature* signature = [metadataEditor methodSignatureForSelector:selector];
		NSInvocation* invocation = [NSInvocation invocationWithMethodSignature:signature];
		[invocation setTarget:metadataEditor];
		[invocation setSelector:selector];
		[invocation setArgument:(void *)&trackArray atIndex:2];
		[invocation setArgument:(void *)&rangeArray atIndex:3];
		[invocation setArgument:(void *)&taskArray atIndex:4];
		[invocation retainArguments];
		[invocation performSelectorOnMainThread:@selector(invoke) withObject:nil waitUntilDone:YES];
		goto end;
#endif
	}
	
	for(i=0;i<[trackArray count];i++) {
		XLDTrack *track = [trackArray objectAtIndex:i];
		XLDConverterTask *task = [taskArray objectAtIndex:i];
		NSArray *albumArray = nil;
		if([[o_filenameFormatRadio selectedCell] tag] == 0 && [track enabled]) {
			if([o_addiTunes state] == NSOnState) {
				NSString *iTunesLibName;
				if([[o_libraryType selectedCell] tag] == 0) iTunesLibName = @"library playlist 1";
				else iTunesLibName = [self formattedStringForTrack:track withPattern:[o_libraryName stringValue] singleImageMode:NO albumArtist:[[track metadata] objectForKey:XLD_METADATA_ALBUMARTIST]];
				[task setiTunesLib:iTunesLibName];
			}
			[task setTrack:track];
			continue;
		}
		if([rangeArray count] && albumRangeIdx < [rangeArray count]) {
			NSRange range = [[rangeArray objectAtIndex:albumRangeIdx] rangeValue];
			if(i >= range.location && i < range.location+range.length) {
				albumArray = [trackArray subarrayWithRange:range];
				if(i == range.location+range.length-1) albumRangeIdx++;
			}
		}
		NSString *filename = [self preferredFilenameForTrack:track createSubDir:YES singleImageMode:NO albumArtist:(albumArray?[XLDTrackListUtil artistForTracks:albumArray]:[[track metadata] objectForKey:XLD_METADATA_ALBUMARTIST])];
		[track setDesiredFileName:[filename lastPathComponent]];
		NSString *subDir = [filename stringByDeletingLastPathComponent];
		if(![subDir isEqualToString:@""]) {
			[task setOutputDir:[[task outputDir] stringByAppendingPathComponent:subDir]];
		}
		if([o_addiTunes state] == NSOnState) {
			NSString *iTunesLibName;
			if([[o_libraryType selectedCell] tag] == 0) iTunesLibName = @"library playlist 1";
			else iTunesLibName = [self formattedStringForTrack:track withPattern:[o_libraryName stringValue] singleImageMode:NO albumArtist:(albumArray?[XLDTrackListUtil artistForTracks:albumArray]:[[track metadata] objectForKey:XLD_METADATA_ALBUMARTIST])];
			[task setiTunesLib:iTunesLibName];
		}
		[track setEnabled:YES];
		[task setTrack:track];
	}
	if(removeFlag && [o_warnBeforeConversion state] == NSOnState) {
		int ret = NSRunCriticalAlertPanel(LS(@"Deleting Original Files"), LS(@"The original files will be removed after this conversion. Are you sure you want to continue?"), LS(@"OK"), LS(@"Don't delete"), LS(@"Cancel"));
		if(ret == NSAlertAlternateReturn) {
			for(i=0;i<[taskArray count];i++) {
				[[taskArray objectAtIndex:i] setRemoveOriginalFile:NO];
			}
		}
		else if(ret == NSAlertOtherReturn) goto end;
	}
	
	[taskQueue performSelectorOnMainThread:@selector(addTasks:) withObject:taskArray waitUntilDone:YES];
end:
	[cueParser release];
	[taskArray release];
	[trackArray release];
	[rangeArray release];
	if(baseDir) [baseDir release];
	[queue removeAllObjects];
	[o_detectPregapPane close];
	[pool2 release];
	openingFiles = NO;
}

- (void)processMultipleFiles
{
	if([queue count] > 100) {
		openingFiles = YES;
		cancelScan = NO;
		[o_detectPregapPane setTitle:LS(@"Scanning")];
		[o_detectPregapMessage setStringValue:LS(@"Scanning Files...")];
		[o_detectPregapProgress setIndeterminate:NO];
		[o_detectPregapProgress setMaxValue:[queue count]-1];
		[o_detectPregapPaneButton setHidden:NO];
		[o_detectPregapPane center];
		[o_detectPregapPane makeKeyAndOrderFront:nil];
		[NSThread detachNewThreadSelector:@selector(processMultipleFilesInThread) toTarget:self withObject:nil];
	}
	else [self processMultipleFilesInThread];
}

- (void)processSingleFile:(NSString *)filename alwaysOpenAsDisc:(BOOL)discMode
{
	[[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[NSURL fileURLWithPath:filename]];
	NSArray *coverArtFileListArray = [self coverArtFileListArray];
	id decoder = [decoderCenter preferredDecoderForFile:filename];
	if(decoder && [(id <XLDDecoder>)decoder openFile:(char *)[filename UTF8String]]) {
		if(([decoder hasCueSheet] == XLDTrackTypeCueSheet) || ([decoder hasCueSheet] == XLDTextTypeCueSheet)) {
			id cueParser = [[XLDCueParser alloc] initWithDelegate:self];
			int ret;
			if(discMode) ret = NSAlertDefaultReturn;
			else ret = NSRunAlertPanel(LS(@"embedded cue sheet"), LS(@"read embedded cuesheet?"), @"OK", @"Cancel", nil);
			if(ret == NSAlertDefaultReturn) {
				if([decoder hasCueSheet] == XLDTrackTypeCueSheet) [cueParser openFile:filename withTrackData:[decoder cueSheet] decoder:decoder];
				else [cueParser openFile:filename withCueData:[decoder cueSheet] decoder:decoder];
				[decoder closeFile];
				[self openParsedDisc:cueParser originalFile:filename];
				[cueParser release];
				return;
			}
			[cueParser release];
		}
		else if(discMode) {
			[decoder closeFile];
			return;
		}
		if(![self canHandleOutputForDecoder:decoder]) {
			NSRunCriticalAlertPanel(LS(@"error"), LS(@"output does not support input format"), @"OK", nil, nil);
			[decoder closeFile];
			return;
		}
		
		NSString *outputDir;
		if([[o_outputSelectRadio selectedCell] tag] == 0)
			outputDir = [filename stringByDeletingLastPathComponent];
		else
			outputDir = [o_outputDir stringValue];
		if(![[NSFileManager defaultManager] isWritableFileAtPath:outputDir]) {
			NSOpenPanel *op = [NSOpenPanel openPanel];
			[op setTitle:LS(@"Specify the output directory")];
			[op setCanChooseDirectories:YES];
			[op setCanChooseFiles:NO];
			[op setAllowsMultipleSelection:NO];
			if([op respondsToSelector:@selector(setCanCreateDirectories:)] )
				[op setCanCreateDirectories:YES];
			else if([op respondsToSelector:@selector(_setIncludeNewFolderButton:)])
				[op _setIncludeNewFolderButton:YES];
			
			int ret = [op runModal];
			if((ret != NSOKButton) || ![[NSFileManager defaultManager] isWritableFileAtPath:[op filename]]) 
			{
				NSRunCriticalAlertPanel(LS(@"error"), LS(@"no write permission"), @"OK", nil, nil);
				[decoder closeFile];
				return;
			}
			outputDir = [op filename];
		}
		XLDConverterTask *task = [[XLDConverterTask alloc] initWithQueue:taskQueue];
		XLDTrack *track = [[XLDTrack alloc] init];
		[track setSeconds:[decoder totalFrames]/[decoder samplerate]];
		if(![NSStringFromClass([decoder class]) isEqualToString:@"XLDMP3Decoder"])
			[track setFrames:[decoder totalFrames]];
		[track setDesiredFileName:[[filename lastPathComponent] stringByDeletingPathExtension]];
		[track setMetadata:[decoder metadata]];
		if([decoder hasCueSheet] == XLDTrackTypeCueSheet) {
			[[track metadata] removeObjectForKey:XLD_METADATA_CUESHEET];
		}
		if([o_keepTimeStamp state] == NSOnState) {
			NSFileManager *fm = [NSFileManager defaultManager];
			NSDictionary *attrDic = [fm fileAttributesAtPath:filename traverseLink:YES];
			if(attrDic) {
				[[track metadata] setObject:[attrDic fileCreationDate] forKey:XLD_METADATA_CREATIONDATE];
				[[track metadata] setObject:[attrDic fileModificationDate] forKey:XLD_METADATA_MODIFICATIONDATE];
			}
		}
		[[track metadata] setObject:[[filename lastPathComponent] precomposedStringWithCanonicalMapping] forKey:XLD_METADATA_ORIGINALFILENAME];
		[[track metadata] setObject:@"Single" forKey:@"Single"];
		[[track metadata] setObject:filename forKey:XLD_METADATA_ORIGINALFILEPATH];
		
		[self setDefaultCommentValueForTrackList:[NSArray arrayWithObject:track]];
		
		if(([o_autoLoadCoverArt state] == NSOnState) && (![[track metadata] objectForKey:XLD_METADATA_COVER] || ([o_autoLoadCoverArtDontOverwrite state] == NSOffState))) {
			NSData *imgData = [self dataForAutoloadCoverArtForFile:filename fileListArray:coverArtFileListArray];
			if(imgData) {
				[[track metadata] setObject:imgData forKey:XLD_METADATA_COVER];
			}
		}
		
		if([o_preserveUnknownMetadata state] == NSOffState) {
			int i;
			NSArray *keyArr = [[(XLDTrack *)track metadata] allKeys];
			for(i=[keyArr count]-1;i>=0;i--) {
				NSString *key = [keyArr objectAtIndex:i];
				NSRange range = [key rangeOfString:@"XLD_UNKNOWN_TEXT_METADATA_"];
				if(range.location != 0) continue;
				[[(XLDTrack *)track metadata] removeObjectForKey:key];
			}
		}
		
		[task setScaleType:([o_scaleImage state] == NSOffState) ? XLDNoScale : ([[o_scaleType selectedCell] tag] | (([o_expandImage state] == NSOnState) ? 0x10 : 0))];
		[task setScaleSize:[o_scalePixel intValue]];
		[task setCompressionQuality:[o_compressionQuality intValue]/100.0f];
		[task setIndex:[track index]];
		[task setTotalFrame:[track frames]];
		[task setDecoderClass:[decoder class]];
		[self setOutputForTask:task];
		[task setInputPath:filename];
		[task setOutputDir:outputDir];
		[task setProcessOfExistingFiles:[[o_existingFile selectedCell] tag]];
		[task setTagWritable:([o_autoTagging state] == NSOnState) ? YES : NO];
		[task setEmbedImages:([o_embedCoverArts state] == NSOnState) ? YES : NO];
		[task setMoveAfterFinish:([o_moveAfterFinish state] == NSOnState) ? YES : NO];
		[task setRemoveOriginalFile:([o_removeOriginalFile state] == NSOnState)];
		//[task setTrack:track]; //not here...
		
		[decoder closeFile];
		if([o_editTags state] == NSOnState) {
#if 0
			BOOL ret = [metadataEditor editSingleTracks:[NSArray arrayWithObject:track] atIndex:0];
			if(!ret) goto end;
#else
			id tracks = [NSArray arrayWithObject:track];
			id tasks = [NSArray arrayWithObject:task];
			SEL selector = @selector(editSingleTracks:withAlbumRanges:andDispatchTasks:);
			NSMethodSignature* signature = [metadataEditor methodSignatureForSelector:selector];
			NSInvocation* invocation = [NSInvocation invocationWithMethodSignature:signature];
			[invocation setTarget:metadataEditor];
			[invocation setSelector:selector];
			[invocation setArgument:(void *)&tracks atIndex:2];
			[invocation setArgument:(void *)&tasks atIndex:4];
			[invocation retainArguments];
			[invocation performSelectorOnMainThread:@selector(invoke) withObject:nil waitUntilDone:YES];
			goto end;
#endif
		}
		
		if([o_addiTunes state] == NSOnState) {
			NSString *iTunesLibName;
			if([[o_libraryType selectedCell] tag] == 0) iTunesLibName = @"library playlist 1";
			else iTunesLibName = [self formattedStringForTrack:track withPattern:[o_libraryName stringValue] singleImageMode:NO albumArtist:[[track metadata] objectForKey:XLD_METADATA_ALBUMARTIST]];
			[task setiTunesLib:iTunesLibName];
		}
		if([[o_filenameFormatRadio selectedCell] tag] == 0) {
			[task setTrack:track];
		}
		else {
			NSString *filename = [self preferredFilenameForTrack:track createSubDir:YES singleImageMode:NO albumArtist:[[track metadata] objectForKey:XLD_METADATA_ALBUMARTIST]];
			[track setDesiredFileName:[filename lastPathComponent]];
			NSString *subDir = [filename stringByDeletingLastPathComponent];
			if(![subDir isEqualToString:@""]) {
				[task setOutputDir:[outputDir stringByAppendingPathComponent:subDir]];
			}
			[task setTrack:track];
		}
		if([o_removeOriginalFile state] == NSOnState && [o_warnBeforeConversion state] == NSOnState) {
			int ret = NSRunCriticalAlertPanel(LS(@"Deleting Original Files"), LS(@"The original files will be removed after this conversion. Are you sure you want to continue?"), LS(@"OK"), LS(@"Don't delete"), LS(@"Cancel"));
			if(ret == NSAlertAlternateReturn) [task setRemoveOriginalFile:NO];
			else if(ret == NSAlertOtherReturn) goto end;
		}
		
		[taskQueue addTask:task];
end:
		[track release];
		[task release];
		return;
	}
	[decoder closeFile];
	
	/* try opening as a cue sheet... */
	id cueParser = [[XLDCueParser alloc] initWithDelegate:self];
	XLDErr err = [(XLDCueParser *)cueParser openFile:filename];
	if(err == XLDNoErr) {
		[self openParsedDisc:cueParser originalFile:filename];
		[cueParser release];
		return;
	}
	else if(err == XLDReadErr) {
		NSString *msg = [cueParser errorMsg];
		if(!msg) msg = @"Unknown error";
		NSRunCriticalAlertPanel(LS(@"Error Parsing Cue Sheet"), msg, @"OK", nil, nil);
		return;
	}
	else if(err != XLDCancelErr) {
		XLDDDPParser *ddpParser = [[XLDDDPParser alloc] init];
		BOOL result = [ddpParser openDDPMS:filename];
		if(result) {
			NSMutableArray *arr = [ddpParser trackListArray];
			XLDFormat fmt;
			fmt.bps = 2;
			fmt.channels = 2;
			fmt.isFloat = 0;
			fmt.samplerate = 44100;
			XLDRawDecoder *decoder = [[XLDRawDecoder alloc] initWithFormat:fmt endian:XLDLittleEndian offset:[ddpParser offsetBytes]];
			[(id <XLDDecoder>)decoder openFile:(char *)[[ddpParser pcmFile] UTF8String]];
			[(XLDCueParser *)cueParser openRawFile:[ddpParser pcmFile] withTrackData:arr decoder:decoder];
			[decoder closeFile];
			[decoder release];
			[self openParsedDisc:cueParser originalFile:filename];
			[ddpParser release];
			[cueParser release];
			return;
		}
		[ddpParser release];
		int ret = NSRunCriticalAlertPanel(LS(@"error"), LS(@"unsupported input file"), @"OK", LS(@"Open as Raw PCM"), nil);
		if(ret == NSAlertAlternateReturn) {
			//[self openRawFileWithDefaultPath:filename];
			[o_rawFormatPaneContent addSubview:o_rawFormatView];
			[NSApp runModalForWindow: o_rawFormatPane];
			[o_rawFormatView removeFromSuperview];
			XLDFormat fmt;
			fmt.samplerate = [o_rawSamplerate intValue];
			switch([o_rawBitDepth indexOfSelectedItem]) {
				case 0:
					fmt.bps = 1;
					break;
				case 1:
					fmt.bps = 2;
					break;
				case 2:
					fmt.bps = 3;
					break;
				case 3:
					fmt.bps = 4;
					break;
				default:
					fmt.bps = 2;
					break;
			}
			
			switch([o_rawChannels indexOfSelectedItem]) {
				case 0:
					fmt.channels = 2;
					break;
				case 1:
					fmt.channels = 1;
					break;
				default:
					fmt.channels = 2;
					break;
			}
			
			fmt.isFloat = 0;
			int endian;
			switch([o_rawEndian indexOfSelectedItem]) {
				case 0:
					endian = XLDBigEndian;
					break;
				case 1:
					endian = XLDLittleEndian;
					break;
				default:
					endian = XLDLittleEndian;
					break;
			}
			[self processRawFile:filename withFormat:fmt endian:endian];
		}
	}
	[cueParser release];
}

- (void)processRawFile:(NSString *)filename withFormat:(XLDFormat)fmt endian:(XLDEndian)e
{
	NSArray *coverArtFileListArray = [self coverArtFileListArray];
	if([[[filename pathExtension] lowercaseString] isEqualToString:@"cue"]) {
		id cueParser = [[XLDCueParser alloc] initWithDelegate:self];
		XLDErr err = [(XLDCueParser *)cueParser openFile:filename withRawFormat:fmt endian:e];
		if(err == XLDNoErr) {
			[self openParsedDisc:cueParser originalFile:filename];
			[cueParser release];
			return;
		}
		else if(err == XLDReadErr) {
			NSString *msg = [cueParser errorMsg];
			if(!msg) msg = @"Unknown error";
			NSRunCriticalAlertPanel(LS(@"Error Parsing Cue Sheet"), msg, @"OK", nil, nil);
			return;
		}
		else if(err != XLDCancelErr) {
			NSRunCriticalAlertPanel(LS(@"error"), LS(@"unsupported input file"), @"OK", nil, nil);
		}
		[cueParser release];
		return;
	}
	XLDRawDecoder *decoder = [[XLDRawDecoder alloc] initWithFormat:fmt endian:e];
	if([(id <XLDDecoder>)decoder openFile:(char *)[filename UTF8String]]) {
		if(![self canHandleOutputForDecoder:decoder]) {
			NSRunCriticalAlertPanel(LS(@"error"), LS(@"output does not support input format"), @"OK", nil, nil);
			[decoder closeFile];
			[decoder release];
			return;
		}
		
		NSString *outputDir;
		if([[o_outputSelectRadio selectedCell] tag] == 0)
			outputDir = [filename stringByDeletingLastPathComponent];
		else
			outputDir = [o_outputDir stringValue];
		if(![[NSFileManager defaultManager] isWritableFileAtPath:outputDir]) {
			NSOpenPanel *op = [NSOpenPanel openPanel];
			[op setTitle:LS(@"Specify the output directory")];
			[op setCanChooseDirectories:YES];
			[op setCanChooseFiles:NO];
			[op setAllowsMultipleSelection:NO];
			if([op respondsToSelector:@selector(setCanCreateDirectories:)] )
				[op setCanCreateDirectories:YES];
			else if([op respondsToSelector:@selector(_setIncludeNewFolderButton:)])
				[op _setIncludeNewFolderButton:YES];
			
			int ret = [op runModal];
			if((ret != NSOKButton) || ![[NSFileManager defaultManager] isWritableFileAtPath:[op filename]]) 
			{
				NSRunCriticalAlertPanel(LS(@"error"), LS(@"no write permission"), @"OK", nil, nil);
				[decoder closeFile];
				[decoder release];
				return;
			}
			outputDir = [op filename];
		}
		
		XLDConverterTask *task = [[XLDConverterTask alloc] initWithQueue:taskQueue];
		XLDTrack *track = [[XLDTrack alloc] init];
		[track setSeconds:[decoder totalFrames]/[decoder samplerate]];
		[track setFrames:[decoder totalFrames]];
		[track setDesiredFileName:[[filename lastPathComponent] stringByDeletingPathExtension]];
		
		if([o_autoLoadCoverArt state] == NSOnState) {
			NSData *imgData = [self dataForAutoloadCoverArtForFile:filename fileListArray:coverArtFileListArray];
			if(imgData) {
				[[track metadata] setObject:imgData forKey:XLD_METADATA_COVER];
			}
		}
		
		[self setDefaultCommentValueForTrackList:[NSArray arrayWithObject:track]];
		
		[task setScaleType:([o_scaleImage state] == NSOffState) ? XLDNoScale : ([[o_scaleType selectedCell] tag] | (([o_expandImage state] == NSOnState) ? 0x10 : 0))];
		[task setScaleSize:[o_scalePixel intValue]];
		[task setCompressionQuality:[o_compressionQuality intValue]/100.0f];
		[task setIndex:[track index]];
		[task setTotalFrame:[track frames]];
		[task setDecoderClass:[decoder class]];
		[self setOutputForTask:task];
		[task setInputPath:filename];
		[task setOutputDir:outputDir];
		[task setProcessOfExistingFiles:[[o_existingFile selectedCell] tag]];
		[task setTagWritable:([o_autoTagging state] == NSOnState) ? YES : NO];
		[task setEmbedImages:([o_embedCoverArts state] == NSOnState) ? YES : NO];
		[task setMoveAfterFinish:([o_moveAfterFinish state] == NSOnState) ? YES : NO];
		//[task setTrack:track]; //not here...
		[task setRawFormat:fmt];
		[task setRawEndian:e];
		[task setRawOffset:0];
		
		[decoder closeFile];
		
		if([o_editTags state] == NSOnState) {
			id tracks = [NSArray arrayWithObject:track];
			id tasks = [NSArray arrayWithObject:task];
			SEL selector = @selector(editSingleTracks:withAlbumRanges:andDispatchTasks:);
			NSMethodSignature* signature = [metadataEditor methodSignatureForSelector:selector];
			NSInvocation* invocation = [NSInvocation invocationWithMethodSignature:signature];
			[invocation setTarget:metadataEditor];
			[invocation setSelector:selector];
			[invocation setArgument:(void *)&tracks atIndex:2];
			[invocation setArgument:(void *)&tasks atIndex:4];
			[invocation retainArguments];
			[invocation performSelectorOnMainThread:@selector(invoke) withObject:nil waitUntilDone:YES];
			goto end;
		}
		
		if([o_addiTunes state] == NSOnState) {
			NSString *iTunesLibName;
			if([[o_libraryType selectedCell] tag] == 0) iTunesLibName = @"library playlist 1";
			else iTunesLibName = [self formattedStringForTrack:track withPattern:[o_libraryName stringValue] singleImageMode:NO albumArtist:[[track metadata] objectForKey:XLD_METADATA_ALBUMARTIST]];
			[task setiTunesLib:iTunesLibName];
		}
		if([[o_filenameFormatRadio selectedCell] tag] == 0) {
			[task setTrack:track];
		}
		else {
			NSString *filename = [self preferredFilenameForTrack:track createSubDir:YES singleImageMode:NO albumArtist:[[track metadata] objectForKey:XLD_METADATA_ALBUMARTIST]];
			[track setDesiredFileName:[filename lastPathComponent]];
			NSString *subDir = [filename stringByDeletingLastPathComponent];
			if(![subDir isEqualToString:@""]) {
				[task setOutputDir:[outputDir stringByAppendingPathComponent:subDir]];
			}
			[task setTrack:track];
		}
		
		[taskQueue addTask:task];
end:
		[track release];
		[task release];
	}
	[decoder release];
}

- (void)scanDirectory:(NSString *)dirPath depth:(int)depth manager:(NSFileManager *)mgr filter:(NSString *)filter
{
	int i;
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSArray *arr = [mgr directoryContentsAt:dirPath];
	for(i=0;i<[arr count];i++) {
		NSAutoreleasePool *pool2 = [[NSAutoreleasePool alloc] init];
		NSString *file = [arr objectAtIndex:i];
		BOOL isDir;
		[mgr fileExistsAtPath:[dirPath stringByAppendingPathComponent:file] isDirectory:&isDir];
		if(isDir) {
			if(![o_subdirectoryDepth intValue] || (depth < [o_subdirectoryDepth intValue]))
				[self scanDirectory:[dirPath stringByAppendingPathComponent:file] depth:depth+1 manager:mgr filter:filter];
			[pool2 release];
			continue;
		}
		if(filter) {
			NSRange formatIndicatorRange = [filter rangeOfString:[[file pathExtension] lowercaseString]];
			if(formatIndicatorRange.location != NSNotFound) {
				[queue addObject:[dirPath stringByAppendingPathComponent:file]];
			}
		}
		else {
			if([file characterAtIndex:0] != '.')
				[queue addObject:[dirPath stringByAppendingPathComponent:file]];
		}
		[pool2 release];
	}
	[pool release];
}

- (void)processQueue
{
	BOOL isDir;
	NSFileManager *mgr = [NSFileManager defaultManager];
	NSString *filter = ([o_limitExtension state] == NSOnState) ? [[o_extensionFilter stringValue] lowercaseString] : nil;
	[mgr fileExistsAtPath:[queue objectAtIndex:0] isDirectory:&isDir];
	firstDrag = YES;
	if(([queue count] == 1) && !isDir) {
		id obj = [[queue objectAtIndex:0] retain];
		[queue removeAllObjects];
		[self processSingleFile:obj alwaysOpenAsDisc:NO];
		[obj release];
	}
	else {
		int i;
		int n = [queue count];
		for(i=0;i<n;i++) {
			[mgr fileExistsAtPath:[queue objectAtIndex:i] isDirectory:&isDir];
			if(isDir) {
				[queue replaceObjectAtIndex:i withObject:[[queue objectAtIndex:i] stringByAppendingString:@"/"]];
				[self scanDirectory:[queue objectAtIndex:i] depth:1 manager:mgr filter:filter];
			}
		}
		[self processMultipleFiles];
	}
}

- (int)offset
{
	return ([o_correctOffset state] == NSOnState) ? 30 : 0;
}

- (unsigned int)cddbQueryFlag
{
	unsigned int flag = 0xffffffff;
	NSMenu *submenu = [o_cddbQueryItem submenu];
	if([[submenu itemAtIndex:0] state] == NSOffState) flag ^= XLDCDDBQueryEmptyOnlyMask;
	if([[submenu itemAtIndex:2] state] == NSOffState) flag ^= XLDCDDBQueryDiscTitleMask;
	if([[submenu itemAtIndex:3] state] == NSOffState) flag ^= XLDCDDBQueryTrackTitleMask;
	if([[submenu itemAtIndex:4] state] == NSOffState) flag ^= XLDCDDBQueryArtistMask;
	if([[submenu itemAtIndex:5] state] == NSOffState) flag ^= XLDCDDBQueryGenreMask;
	if([[submenu itemAtIndex:6] state] == NSOffState) flag ^= XLDCDDBQueryYearMask;
	if([[submenu itemAtIndex:7] state] == NSOffState) flag ^= XLDCDDBQueryComposerMask;
	if([[submenu itemAtIndex:8] state] == NSOffState) flag ^= XLDCDDBQueryCoverArtMask;
	
	return flag;
}

- (void)delayedRefleshList
{
	[self performSelector:@selector(updateCDDAList:) withObject:nil afterDelay:1.0];
}

- (void)readPreGapOfDisc:(NSString *)volume
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSMutableString *tmpStr = [NSMutableString stringWithString:volume];
	[tmpStr replaceOccurrencesOfString:@"/" withString:@":" options:0 range:NSMakeRange(0, [tmpStr length])];
	//NSLog(@"%s",[[@"/Volumes" stringByAppendingPathComponent:tmpStr] UTF8String]);
	statfs([[@"/Volumes" stringByAppendingPathComponent:tmpStr] UTF8String], &statDisc);
	//NSLog(@"%s",stat.f_mntfromname);
	
	DASessionRef session = DASessionCreate(NULL);
	DASessionScheduleWithRunLoop(session, CFRunLoopGetCurrent(), MY_RUN_LOOP_MODE);
	DADiskRef disk = DADiskCreateFromBSDName(NULL,session,statDisc.f_mntfromname);
	DADiskUnmount(disk,kDADiskUnmountOptionDefault,DADoneCallback,NULL);
	int ret = CFRunLoopRunInMode(MY_RUN_LOOP_MODE, 120.0, false);
	if (ret == kCFRunLoopRunStopped) {
		DASessionUnscheduleFromRunLoop(session, CFRunLoopGetCurrent(), MY_RUN_LOOP_MODE);
	}
	CFRelease(disk);
	CFRelease(session);
	
	int i;
	
	xld_cdread_t cdread;
	
	if(xld_cdda_open(&cdread, statDisc.f_mntfromname) == 0) {
		driveIsBusy = YES;
		if([o_autoSetOffsetValue state] == NSOnState) {
			NSDictionary *dic = [NSDictionary dictionaryWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"offsetlist" ofType:@"plist"]];
			NSString *product = [NSString stringWithUTF8String:cdread.product];
			if([dic objectForKey:product]) {
				[o_offsetCorrectionValue setIntValue:[[dic objectForKey:product] intValue]];
			}
			else if([dic objectForKey:[product substringToIndex:[product length]-1]]) {
				[o_offsetCorrectionValue setIntValue:[[dic objectForKey:[product substringToIndex:[product length]-1]] intValue]];
			}
		}
		NSMutableArray *trackArr = [[NSMutableArray alloc] init];
		[o_detectPregapProgress setMaxValue:cdread.numTracks-1];
		for(i=1;i<=cdread.numTracks;i++) {
			XLDTrack *track = [[XLDTrack alloc] init];
			[track setIndex:xld_cdda_track_firstsector(&cdread,i)*588];
			if((i==1) && ([track index] != 0)) [track setGap:[track index]];
			else [track setGap:0];
			[track setFrames:cdread.tracks[i-1].length];
			[track setSeconds:[track frames]/44100];
			if(cdread.tracks[i-1].type != kTrackTypeAudio) {
				[track setEnabled:NO];
				[[track metadata] setObject:[NSNumber numberWithBool:YES] forKey:XLD_METADATA_DATATRACK];
			}
			else {
				if(cdread.tracks[i-1].preEmphasis) {
					//NSLog(@"pre emphasis");
					[[track metadata] setObject:[NSNumber numberWithBool:YES] forKey:XLD_METADATA_PREEMPHASIS];
				}
				if(cdread.tracks[i-1].dcp) {
					[[track metadata] setObject:[NSNumber numberWithBool:YES] forKey:XLD_METADATA_DCP];
				}
			}
			[trackArr addObject:track];
			[track release];
		}
		
		[self setDefaultCommentValueForTrackList:trackArr];
		
		/* detect pregap, isrc & mcn */
		if([o_dontReadSubchannel state] == NSOffState) {
			//xld_cdda_read_mcn(&cdread);
			for(i=0;i<cdread.numTracks;i++) {
				if(cdread.tracks[i].type == kTrackTypeAudio) {
					xld_cdda_read_isrc(&cdread,i+1);
					if(cdread.mcn[0]) [[[trackArr objectAtIndex:i] metadata] setObject:[NSString stringWithUTF8String:cdread.mcn] forKey:XLD_METADATA_CATALOG];
					if(cdread.tracks[i].isrc[0]) [[[trackArr objectAtIndex:i] metadata] setObject:[NSString stringWithUTF8String:cdread.tracks[i].isrc] forKey:XLD_METADATA_ISRC];
				}
				if(i>0 && cdread.tracks[i].type == kTrackTypeAudio && cdread.tracks[i-1].type == kTrackTypeAudio) {
					xld_cdda_read_pregap(&cdread,i+1);
					[[trackArr objectAtIndex:i] setGap:cdread.tracks[i].pregap*588];
					[[trackArr objectAtIndex:i-1] setFrames:[[trackArr objectAtIndex:i-1] frames] - cdread.tracks[i].pregap*588];
				}
				[o_detectPregapProgress setDoubleValue:i];
			}
		}

		[o_detectPregapProgress setDoubleValue:cdread.numTracks-1];
		xld_cdda_close(&cdread);
		driveIsBusy = NO;
		[self performSelectorOnMainThread:@selector(finishedReadingPregapWithTrackData:) withObject:trackArr waitUntilDone:YES];
		
		session = DASessionCreate(NULL);
		disk = DADiskCreateFromBSDName(NULL,session,statDisc.f_mntfromname);
		DADiskMount(disk,NULL,kDADiskMountOptionDefault,NULL,NULL);
		CFRelease(disk);
		CFRelease(session);
		
		[self performSelectorOnMainThread:@selector(delayedRefleshList) withObject:nil waitUntilDone:NO];
		
		[trackArr release];
		[o_detectPregapPane close];
		
	}
	else {
		[o_detectPregapPane close];
		NSRunCriticalAlertPanel(LS(@"error"), LS(@"Device is busy"), @"OK", nil, nil);
	}
	
	[pool release];
}

- (void)unmountDisc:(NSString *)dev
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	DASessionRef session = DASessionCreate(NULL);
	DASessionScheduleWithRunLoop(session, CFRunLoopGetCurrent(), MY_RUN_LOOP_MODE);
	DADiskRef disk = DADiskCreateFromBSDName(NULL,session,[dev UTF8String]);
	DADiskUnmount(disk,kDADiskUnmountOptionDefault,DADoneCallback,NULL);
	int ret = CFRunLoopRunInMode(MY_RUN_LOOP_MODE, 120.0, false);
	if (ret == kCFRunLoopRunStopped) {
		DASessionUnscheduleFromRunLoop(session, CFRunLoopGetCurrent(), MY_RUN_LOOP_MODE);
	}
	CFRelease(disk);
	CFRelease(session);
	
	ejected = YES;
	[self performSelectorOnMainThread:@selector(beginDecode:) withObject:nil waitUntilDone:NO];
	[pool release];
}

- (void)mountDisc:(NSString *)dev
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[dev retain];
	
	DASessionRef session = DASessionCreate(NULL);
	DADiskRef disk = DADiskCreateFromBSDName(NULL,session,[dev UTF8String]);
	DADiskMount(disk,NULL,kDADiskMountOptionDefault,NULL,NULL);
	CFRelease(disk);
	CFRelease(session);
	
	[dev release];
	[pool release];
}

- (void)ejectDisc:(NSString *)dev
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[dev retain];
	
	DASessionRef session = DASessionCreate(NULL);
	DADiskRef disk = DADiskCreateFromBSDName(NULL,session,[dev UTF8String]);
	DADiskUnmount(disk,kDADiskUnmountOptionWhole,NULL,NULL);
	DADiskEject(disk,kDADiskEjectOptionDefault,NULL,NULL);
	CFRelease(disk);
	CFRelease(session);
	
	[dev release];
	[pool release];
}

- (void)analyzeCacheForDrive:(NSString *)dev
{
	driveIsBusy = YES;
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	id cueParser = [discView cueParser];
	
	DASessionRef session = DASessionCreate(NULL);
	DASessionScheduleWithRunLoop(session, CFRunLoopGetCurrent(), MY_RUN_LOOP_MODE);
	DADiskRef disk = DADiskCreateFromBSDName(NULL,session,[dev UTF8String]);
	DADiskUnmount(disk,kDADiskUnmountOptionDefault,DADoneCallback,NULL);
	int ret = CFRunLoopRunInMode(MY_RUN_LOOP_MODE, 120.0, false);
	if (ret == kCFRunLoopRunStopped) {
		DASessionUnscheduleFromRunLoop(session, CFRunLoopGetCurrent(), MY_RUN_LOOP_MODE);
	}
	CFRelease(disk);
	CFRelease(session);
	
	cache_analysis_t result;
	result.cache_sector_size = -1;
	result.backseek_flush_capable = -1;
	ret = [XLDCDDARipper analyzeCacheForDrive:dev result:&result delegate:self];
	
	[o_detectPregapProgress stopAnimation:nil];
	[NSApp endSheet:o_detectPregapPane returnCode:0];
	[o_detectPregapPane close];
	
	NSMutableString *out =[[NSMutableString alloc] init];
	[out setString:@""];
	[out appendString:[NSString stringWithFormat:@"X Lossless Decoder version %@ (%@)\n\n",[[[NSBundle mainBundle] infoDictionary] valueForKey:@"CFBundleShortVersionString"],[[[NSBundle mainBundle] infoDictionary] valueForKey:@"CFBundleVersion"]]];
	[out appendString:@"XLD drive cache analysis logfile\n\n"];
	
	[out appendString:[NSString stringWithFormat:@"Used drive : %@\n\n",[cueParser driveStr]]];
	
	if((ret < 0) || (result.cache_sector_size < 0)) {
		[out appendString:LS(@"Some errors occured during analysis.\n\n")];
	}
	else {
		[out appendString:[NSString stringWithFormat:LS(@"Your drive seems to have a cache of %d sectors (%d Kbytes).\n"),result.cache_sector_size,result.cache_sector_size*2352/1024]];
		if(result.have_cache && (result.cache_sector_size > 1200))
			[out appendString:LS(@"Your drive has a too large cache to defeat. :(\n\n")];
		else {
			if(result.backseek_flush_capable == 0)
				[out appendString:LS(@"The cache size is small enough for cdparanoia III 10.2 engine, but backseeking doesn't seem to work for flushing cache. Please be careful with this drive.\n\n")];
			else
				[out appendString:LS(@"The cache size is small enough for cdparanoia III 10.2 engine. :)\n\n")];
		}
		/*
		if(result.have_cache && (result.cache_sector_size >= 150)) {
			int defeatPower = 1;
			for(;defeatPower<15;defeatPower++) {
				if(result.cache_sector_size < 550+50*(defeatPower-1)) break;
			}
			if(defeatPower<15) [out appendString:[NSString stringWithFormat:LS(@"Recommended cache defeating strength is: %d (1-14)\n\n"),defeatPower]];
			else [out appendString:LS(@"Your drive has a too large cache to defeat. :(\n\n")];
		}
		else {
			[out appendString:LS(@"The cache size is too small to have an effect.\n")];
			[out appendString:LS(@"You may be able to turn off \"Disable cache\" option, but I recommend you to disable cache with the minimum strength.\n\n")];
		}
		 */
	}
	[out appendString:@"End of status report\n"];
	[[[o_logView textStorage] mutableString] setString:out];
	[[o_logView textStorage] setFont:[NSFont fontWithName:@"Monaco" size:10]];
	[o_logWindow makeKeyAndOrderFront:self];
	
	[out release];
	
	session = DASessionCreate(NULL);
	disk = DADiskCreateFromBSDName(NULL,session,[dev UTF8String]);
	DADiskMount(disk,NULL,kDADiskMountOptionDefault,NULL,NULL);
	CFRelease(disk);
	CFRelease(session);
	
	[pool release];
	driveIsBusy = NO;
}

- (NSString *)setTrackMetadata:(NSMutableArray *)trackArr forDisc:(NSString *)disc alternativeName:(NSString *)altDisc
{
    FILE *fp = fopen([[@"~/Library/Preferences/CD Info.cidb" stringByExpandingTildeInPath] UTF8String],"rb");
    if(!fp) return nil;
    int tmp, actualTotalTrack = [trackArr count];
    char atom[4];
	NSString *albumTitle = nil;
	NSString *albumArtist = nil;
	NSString *albumGenre = nil;
	NSString *albumComposer = nil;
	NSString *albumGroup = nil;
	NSString *albumMEID = nil;
	NSString *albumMUID = nil;
	if(![[trackArr objectAtIndex:actualTotalTrack-1] enabled]) 
		actualTotalTrack--;
	
	while(1) {
		int nextIdx, trakPos, lastTrakPos;
		char *buf;
		int totalTrack = 0;
		int albumYear = 0;
		int discNumber = 0;
		int totalDisc = 0;
		int compilation = 0;
		
		while(1) { //skip until albm;
			if(fread(atom,1,4,fp) < 4) goto end;
			if(fread(&tmp,4,1,fp) < 1) goto end;
			tmp = SWAP32(tmp);
			if(!memcmp(atom,"albm",4)) break;
			else if(!memcmp(atom,"cidb",4)) {
				if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
			}
			else if(!memcmp(atom,"hole",4)) {
				if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
			}
			else { // out of sync??
				if(fseeko(fp,-8,SEEK_CUR) != 0) goto end;
				while(1) {
					if(fread(atom,1,4,fp) < 4) goto end;
					if(!memcmp(atom,"albm",4)) break;
					if(!memcmp(atom,"hole",4)) break;
					if(!memcmp(atom,"cidb",4)) break;
					if(fseeko(fp,-3,SEEK_CUR) != 0) goto end;
				}
				if(fseeko(fp,-4,SEEK_CUR) != 0) goto end;
			}
		}
		nextIdx = ftell(fp) - 8 + tmp;
		trakPos = 0;
		lastTrakPos = 0;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		tmp = SWAP32(tmp);
		int rest = tmp-12;
		while(rest > 0) { //skip until trak;
			if(fread(atom,1,4,fp) < 4) goto end;
			if(fread(&tmp,4,1,fp) < 1) goto end;
			tmp = SWAP32(tmp);
			if(!memcmp(atom,"trak",4)) {
				if(!trakPos) trakPos = ftell(fp);
				lastTrakPos = ftell(fp);
				if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
			}
			else if(!memcmp(atom,"anam",4)) {
				if(fseeko(fp,2,SEEK_CUR) != 0) goto end;
				buf = malloc(tmp-8);
				buf[0] = 0xfe;
				buf[1] = 0xff;
				if(fread(buf+2,1,tmp-10,fp) < tmp-10) goto end;
				if(albumTitle) [albumTitle release];
				albumTitle = [[NSString alloc] initWithBytes:buf length:tmp-8 encoding:NSUnicodeStringEncoding];
				free(buf);
			}
			else if(!memcmp(atom,"auth",4)) {
				if(fseeko(fp,2,SEEK_CUR) != 0) goto end;
				buf = malloc(tmp-8);
				buf[0] = 0xfe;
				buf[1] = 0xff;
				if(fread(buf+2,1,tmp-10,fp) < tmp-10) goto end;
				if(albumArtist) [albumArtist release];
				albumArtist = [[NSString alloc] initWithBytes:buf length:tmp-8 encoding:NSUnicodeStringEncoding];
				free(buf);
			}
			else if(!memcmp(atom,"gnre",4)) {
				if(fseeko(fp,2,SEEK_CUR) != 0) goto end;
				buf = malloc(tmp-8);
				buf[0] = 0xfe;
				buf[1] = 0xff;
				if(fread(buf+2,1,tmp-10,fp) < tmp-10) goto end;
				if(albumGenre) [albumGenre release];
				albumGenre = [[NSString alloc] initWithBytes:buf length:tmp-8 encoding:NSUnicodeStringEncoding];
				free(buf);
			}
			else if(!memcmp(atom,"comp",4)) {
				if(fseeko(fp,2,SEEK_CUR) != 0) goto end;
				buf = malloc(tmp-8);
				buf[0] = 0xfe;
				buf[1] = 0xff;
				if(fread(buf+2,1,tmp-10,fp) < tmp-10) goto end;
				if(albumComposer) [albumComposer release];
				albumComposer = [[NSString alloc] initWithBytes:buf length:tmp-8 encoding:NSUnicodeStringEncoding];
				free(buf);
			}
			else if(!memcmp(atom,"grup",4)) {
				if(fseeko(fp,2,SEEK_CUR) != 0) goto end;
				buf = malloc(tmp-8);
				buf[0] = 0xfe;
				buf[1] = 0xff;
				if(fread(buf+2,1,tmp-10,fp) < tmp-10) goto end;
				if(albumGroup) [albumGroup release];
				albumGroup = [[NSString alloc] initWithBytes:buf length:tmp-8 encoding:NSUnicodeStringEncoding];
				free(buf);
			}
			else if(!memcmp(atom,"meid",4)) {
				if(fseeko(fp,2,SEEK_CUR) != 0) goto end;
				buf = malloc(tmp-8);
				buf[0] = 0xfe;
				buf[1] = 0xff;
				if(fread(buf+2,1,tmp-10,fp) < tmp-10) goto end;
				if(albumMEID) [albumMEID release];
				albumMEID = [[NSString alloc] initWithBytes:buf length:tmp-8 encoding:NSUnicodeStringEncoding];
				free(buf);
			}
			else if(!memcmp(atom,"muid",4)) {
				if(fseeko(fp,2,SEEK_CUR) != 0) goto end;
				buf = malloc(tmp-8);
				buf[0] = 0xfe;
				buf[1] = 0xff;
				if(fread(buf+2,1,tmp-10,fp) < tmp-10) goto end;
				if(albumMUID) [albumMUID release];
				albumMUID = [[NSString alloc] initWithBytes:buf length:tmp-8 encoding:NSUnicodeStringEncoding];
				free(buf);
			}
			else if(!memcmp(atom,"year",4)) {
				if(fread(&albumYear,4,1,fp) < 1) goto end;
				albumYear = SWAP32(albumYear);
			}
			else if(!memcmp(atom,"dnum",4)) {
				if(fread(&discNumber,4,1,fp) < 1) goto end;
				discNumber = SWAP32(discNumber);
			}
			else if(!memcmp(atom,"dcnt",4)) {
				if(fread(&totalDisc,4,1,fp) < 1) goto end;
				totalDisc = SWAP32(totalDisc);
			}
			else if(!memcmp(atom,"cmpl",4)) {
				if(fread(&compilation,4,1,fp) < 1) goto end;
				compilation = SWAP32(compilation);
			}
			else if(!memcmp(atom,"prog",4)) {
				totalTrack = (tmp-8)/2;
				if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
			}
			else {
				if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
			}
			/*else {
				NSLog(@"unknown chunk (rest:%d)",rest);
				int i;
				for(i=0;i<4;i++) putchar(atom[i]);
				break;
			}*/
			rest -= tmp;
		}
		
		if(!trakPos) goto end;
		
		if(fseeko(fp,trakPos-8,SEEK_SET) != 0) goto end;
		
		//if(albumTitle) NSLog(albumTitle);
		if(albumTitle && ([disc isEqualToString:[albumTitle precomposedStringWithCanonicalMapping]] || [altDisc isEqualToString:[albumTitle precomposedStringWithCanonicalMapping]]) && (totalTrack == actualTotalTrack)) {
			int i;
			for(i=0;i<actualTotalTrack;i++) {
				if(albumTitle) [[[trackArr objectAtIndex:i] metadata] setObject:albumTitle forKey:XLD_METADATA_ALBUM];
				if(albumArtist) [[[trackArr objectAtIndex:i] metadata] setObject:albumArtist forKey:XLD_METADATA_ARTIST];
				if(albumGenre) [[[trackArr objectAtIndex:i] metadata] setObject:albumGenre forKey:XLD_METADATA_GENRE];
				if(albumComposer) [[[trackArr objectAtIndex:i] metadata] setObject:albumComposer forKey:XLD_METADATA_COMPOSER];
				if(albumGroup) [[[trackArr objectAtIndex:i] metadata] setObject:albumGroup forKey:XLD_METADATA_GROUP];
				if(albumYear > 0) [[[trackArr objectAtIndex:i] metadata] setObject:[NSNumber numberWithInt:albumYear] forKey:XLD_METADATA_YEAR];
				if(discNumber > 0) [[[trackArr objectAtIndex:i] metadata] setObject:[NSNumber numberWithInt:discNumber] forKey:XLD_METADATA_DISC];
				if(totalDisc > 0) [[[trackArr objectAtIndex:i] metadata] setObject:[NSNumber numberWithInt:totalDisc] forKey:XLD_METADATA_TOTALDISCS];
				if(compilation) [[[trackArr objectAtIndex:i] metadata] setObject:[NSNumber numberWithBool:YES] forKey:XLD_METADATA_COMPILATION];
				if(albumMEID && albumMUID) {
					[[[trackArr objectAtIndex:i] metadata] setObject:[NSString stringWithFormat:@"%d+%@+%@",actualTotalTrack,albumMEID,albumMUID] forKey:XLD_METADATA_GRACENOTE];
				}
			}
			while(1) {
				int trackIdx,trackSize,read=12;
				if(fread(atom,1,4,fp) < 4) goto end;
				if(fread(&tmp,4,1,fp) < 1) goto end;
				trackSize = SWAP32(tmp);
				if(memcmp(atom,"trak",4)) {
					if(ftell(fp) > lastTrakPos) break;
					else {
						if(fseeko(fp,trackSize-8,SEEK_CUR) != 0) goto end;
						continue;
					}
				}
				
				if(fread(&tmp,4,1,fp) < 1) goto end;
				trackIdx = SWAP32(tmp);
				
				while(read<trackSize) {
					if(fread(atom,1,4,fp) < 4) goto end;
					if(fread(&tmp,4,1,fp) < 1) goto end;
					tmp = SWAP32(tmp);
					if(!memcmp(atom,"tnam",4) && (trackIdx <= actualTotalTrack) && (tmp > 0xa)) {
						if(fseeko(fp,2,SEEK_CUR) != 0) goto end;
						buf = malloc(tmp-8);
						buf[0] = 0xfe;
						buf[1] = 0xff;
						if(fread(buf+2,1,tmp-10,fp) < tmp-10) goto end;
						NSString *title = [[NSString alloc] initWithBytes:buf length:tmp-8 encoding:NSUnicodeStringEncoding];
						if(title) {
							[[[trackArr objectAtIndex:trackIdx-1] metadata] setObject:title forKey:XLD_METADATA_TITLE];
							[title release];
						}
						free(buf);
					}
					else if(!memcmp(atom,"auth",4) && (trackIdx <= actualTotalTrack) && (tmp > 0xa)) {
						if(fseeko(fp,2,SEEK_CUR) != 0) goto end;
						buf = malloc(tmp-8);
						buf[0] = 0xfe;
						buf[1] = 0xff;
						if(fread(buf+2,1,tmp-10,fp) < tmp-10) goto end;
						NSString *artist = [[NSString alloc] initWithBytes:buf length:tmp-8 encoding:NSUnicodeStringEncoding];
						if(artist) {
							[[[trackArr objectAtIndex:trackIdx-1] metadata] setObject:artist forKey:XLD_METADATA_ARTIST];
							[artist release];
						}
						free(buf);
					}
					else if(!memcmp(atom,"comp",4) && (trackIdx <= actualTotalTrack) && (tmp > 0xa)) {
						if(fseeko(fp,2,SEEK_CUR) != 0) goto end;
						buf = malloc(tmp-8);
						buf[0] = 0xfe;
						buf[1] = 0xff;
						if(fread(buf+2,1,tmp-10,fp) < tmp-10) goto end;
						NSString *composer = [[NSString alloc] initWithBytes:buf length:tmp-8 encoding:NSUnicodeStringEncoding];
						if(composer) {
							[[[trackArr objectAtIndex:trackIdx-1] metadata] setObject:composer forKey:XLD_METADATA_COMPOSER];
							[composer release];
						}
						free(buf);
					}
					else if(!memcmp(atom,"gnre",4) && (trackIdx <= actualTotalTrack) && (tmp > 0xa)) {
						if(fseeko(fp,2,SEEK_CUR) != 0) goto end;
						buf = malloc(tmp-8);
						buf[0] = 0xfe;
						buf[1] = 0xff;
						if(fread(buf+2,1,tmp-10,fp) < tmp-10) goto end;
						NSString *genre = [[NSString alloc] initWithBytes:buf length:tmp-8 encoding:NSUnicodeStringEncoding];
						if(genre) {
							[[[trackArr objectAtIndex:trackIdx-1] metadata] setObject:genre forKey:XLD_METADATA_GENRE];
							[genre release];
						}
						free(buf);
					}
					else if(!memcmp(atom,"cmnt",4) && (trackIdx <= actualTotalTrack) && (tmp > 0xa)) {
						if(fseeko(fp,2,SEEK_CUR) != 0) goto end;
						buf = malloc(tmp-8);
						buf[0] = 0xfe;
						buf[1] = 0xff;
						if(fread(buf+2,1,tmp-10,fp) < tmp-10) goto end;
						NSString *comment = [[NSString alloc] initWithBytes:buf length:tmp-8 encoding:NSUnicodeStringEncoding];
						if(comment) {
							[[[trackArr objectAtIndex:trackIdx-1] metadata] setObject:comment forKey:XLD_METADATA_COMMENT];
							[comment release];
						}
						free(buf);
					}
					else if(!memcmp(atom,"aaut",4) && (trackIdx <= actualTotalTrack) && (tmp > 0xa)) {
						if(fseeko(fp,2,SEEK_CUR) != 0) goto end;
						buf = malloc(tmp-8);
						buf[0] = 0xfe;
						buf[1] = 0xff;
						if(fread(buf+2,1,tmp-10,fp) < tmp-10) goto end;
						NSString *aArtist = [[NSString alloc] initWithBytes:buf length:tmp-8 encoding:NSUnicodeStringEncoding];
						if(aArtist) {
							[[[trackArr objectAtIndex:trackIdx-1] metadata] setObject:aArtist forKey:XLD_METADATA_ALBUMARTIST];
							[aArtist release];
						}
						free(buf);
					}
					else if(!memcmp(atom,"anam",4) && (trackIdx <= actualTotalTrack) && (tmp > 0xa)) {
						if(fseeko(fp,2,SEEK_CUR) != 0) goto end;
						buf = malloc(tmp-8);
						buf[0] = 0xfe;
						buf[1] = 0xff;
						if(fread(buf+2,1,tmp-10,fp) < tmp-10) goto end;
						NSString *album = [[NSString alloc] initWithBytes:buf length:tmp-8 encoding:NSUnicodeStringEncoding];
						if(album) {
							[[[trackArr objectAtIndex:trackIdx-1] metadata] setObject:album forKey:XLD_METADATA_ALBUM];
							[album release];
						}
						free(buf);
					}
					else if(!memcmp(atom,"grup",4) && (trackIdx <= actualTotalTrack) && (tmp > 0xa)) {
						if(fseeko(fp,2,SEEK_CUR) != 0) goto end;
						buf = malloc(tmp-8);
						buf[0] = 0xfe;
						buf[1] = 0xff;
						if(fread(buf+2,1,tmp-10,fp) < tmp-10) goto end;
						NSString *group = [[NSString alloc] initWithBytes:buf length:tmp-8 encoding:NSUnicodeStringEncoding];
						if(group) {
							[[[trackArr objectAtIndex:trackIdx-1] metadata] setObject:group forKey:XLD_METADATA_GROUP];
							[group release];
						}
						free(buf);
					}
					else if(!memcmp(atom,"year",4) && (trackIdx <= actualTotalTrack)) {
						int year;
						if(fread(&year,4,1,fp) < 1) goto end;
						year = SWAP32(year);
						[[[trackArr objectAtIndex:trackIdx-1] metadata] setObject:[NSNumber numberWithInt:year] forKey:XLD_METADATA_YEAR];
					}
					else {
						if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
					}
					read += tmp;
				}
				
			}
			if(albumArtist) [albumArtist release];
			if(albumGenre) [albumGenre release];
			if(albumComposer) [albumComposer release];
			if(albumGroup) [albumGroup release];
			if(albumMEID) [albumMEID release];
			if(albumMUID) [albumMUID release];
			fclose(fp);
			return [albumTitle autorelease];
		}
		
		if(albumTitle) [albumTitle release];
		if(albumArtist) [albumArtist release];
		if(albumGenre) [albumGenre release];
		if(albumComposer) [albumComposer release];
		if(albumGroup) [albumGroup release];
		if(albumMEID) [albumMEID release];
		if(albumMUID) [albumMUID release];
		albumTitle = nil;
		albumArtist = nil;
		albumGenre = nil;
		albumComposer = nil;
		albumGroup = nil;
		albumMEID = nil;
		albumMUID = nil;
		
		if(fseeko(fp,nextIdx,SEEK_SET) != 0) goto end;
	}
end:
		
	if(albumTitle) [albumTitle release];
	if(albumArtist) [albumArtist release];
	if(albumGenre) [albumGenre release];
	if(albumComposer) [albumComposer release];
	if(albumGroup) [albumGroup release];
	if(albumMEID) [albumMEID release];
	if(albumMUID) [albumMUID release];
	fclose(fp);
    return nil;
}

- (void)finishedReadingPregapWithTrackData:(NSMutableArray *)trackArr
{
	XLDCDDARipper *decoder = [[XLDCDDARipper alloc] init];
	if(![decoder openFile:statDisc.f_mntfromname]) {
		NSLog(@"device open failure");
	}
	
	id cueParser = [[XLDCueParser alloc] initWithDelegate:self];
	
	NSString *volumeName2 = [mountNameFromBSDName(statDisc.f_mntfromname) precomposedStringWithCanonicalMapping];
	NSString *volumeName = [[[NSFileManager defaultManager] displayNameAtPath:[[NSString stringWithString:@"/Volumes"] stringByAppendingPathComponent:volumeName2]] precomposedStringWithCanonicalMapping];
	//NSString *volumeName = [[[NSFileManager defaultManager] displayNameAtPath:mountNameFromBSDName(statDisc.f_mntfromname)] precomposedStringWithCanonicalMapping];
	//NSString *volumeName2 = [[[NSMutableString stringWithUTF8String:statDisc.f_mntonname] lastPathComponent] precomposedStringWithCanonicalMapping];
	//NSLog(@"%@\n%@",volumeName,volumeName2);
	NSString *title = [self setTrackMetadata:trackArr forDisc:volumeName alternativeName:volumeName2];
	
	[cueParser openFile:[NSString stringWithUTF8String:statDisc.f_mntfromname] withTrackData:trackArr decoder:decoder];
	if(title) [cueParser setTitle:title];
	else [cueParser setTitle:volumeName];
	[cueParser setDriveStr:[decoder driveStr]];
	[decoder closeFile];
	[decoder release];
	
	[self openParsedDisc:cueParser originalFile:nil];
	[cueParser release];
}

/* delegate methods */

- (IBAction)offsetSelected:(id)sender
{
	[o_offsetCorrectionValue setIntValue:[[sender selectedItem] tag]];
}

- (void)makeDriveOffsetList
{
	int found = 0;
	NSDictionary *dic = [NSDictionary dictionaryWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"offsetlist" ofType:@"plist"]];
	io_service_t  service;
    io_iterator_t service_iterator;
	
	[o_offsetList removeItemAtIndex:1];
	[o_offsetList setAutoenablesItems:NO];
    
	IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching("IOCDBlockStorageDevice"), &service_iterator);
    
    while((service = IOIteratorNext(service_iterator)) != 0) {
        CFMutableDictionaryRef properties;
        IORegistryEntryCreateCFProperties (service, &properties, kCFAllocatorDefault, 0);
        CFDictionaryRef deviceDict = (CFDictionaryRef)CFDictionaryGetValue(properties, CFSTR(kIOPropertyDeviceCharacteristicsKey));
        CFStringRef      vendor      = NULL;
        CFStringRef      product     = NULL;
        vendor = (CFStringRef)CFDictionaryGetValue(deviceDict, CFSTR(kIOPropertyVendorNameKey));
        product = (CFStringRef)CFDictionaryGetValue(deviceDict, CFSTR(kIOPropertyProductNameKey));
        
        if([dic objectForKey:(NSString *)product]) {
			found++;
			int offsetValue = [[dic objectForKey:(NSString *)product] intValue];
			NSString *title = [NSString stringWithFormat:@"%d (%@ %@)",offsetValue,(NSString *)vendor,(NSString *)product];
			[o_offsetList addItemWithTitle:title];
			[[o_offsetList itemWithTitle:title] setTag:offsetValue];
        }
		else if([dic objectForKey:[(NSString *)product substringToIndex:[(NSString *)product length]-1]]) {
			found++;
			int offsetValue = [[dic objectForKey:[(NSString *)product substringToIndex:[(NSString *)product length]-1]] intValue];
			NSString *title = [NSString stringWithFormat:@"%d (%@ %@)",offsetValue,(NSString *)vendor,(NSString *)product];
			[o_offsetList addItemWithTitle:title];
			[[o_offsetList itemWithTitle:title] setTag:offsetValue];
        }
        
        CFRelease(properties);
        IOObjectRelease( service );
        
    }
    
    IOObjectRelease( service_iterator );
	
	if(!found) {
		[o_offsetList addItemWithTitle:LS(@"No registered drive found")];
		[[o_offsetList itemWithTitle:LS(@"No registered drive found")] setEnabled:NO];
	}
	else {
		if(found == 1) [o_offsetCorrectionValue setIntValue:[[o_offsetList itemAtIndex:1] tag]];
		[o_offsetList setTarget:self];
		[o_offsetList setAction:@selector(offsetSelected:)];
	}
}

- (void)launchOK
{
	launched = YES;
	if([queue count]) [self processQueue];
}

- (NSStringEncoding)encoding
{
	//NSLog([NSString localizedNameOfStringEncoding:[[o_cuesheetEncodings selectedItem] tag]]);
	if([o_cuesheetEncodings indexOfSelectedItem] == 0) return 0xFFFFFFFF;
	else return (NSStringEncoding)[[o_cuesheetEncodings selectedItem] tag];
}

- (int)maxThreads
{
	return [o_maxThreads intValue];
}

- (BOOL)canSetCompilationFlag
{
	return ([o_autoSetCompilation state] == NSOnState);
}

- (void)showLogStr:(NSString *)logStr
{
	[[[o_logView textStorage] mutableString] setString:logStr];
	[[o_logView textStorage] setFont:[NSFont fontWithName:@"Monaco" size:10]];
	[o_logView scrollRangeToVisible: NSMakeRange(0,0)];
	[o_logWindow makeKeyAndOrderFront:self];
}

- (void)discRippedWithResult:(id)result
{
	/*int i;
	 for(i=0;i<[result numberOfTracks]+1;i++) {
	 cddaRipResult *resultp = [result resultForIndex:i];
	 NSLog(@"%@:%d,%d,%d,%d,%d,%d,%d,%d",
	 resultp->filename,
	 resultp->enabled,
	 resultp->finished,
	 resultp->errorCount,
	 resultp->skipCount,
	 resultp->atomJitterCount,
	 resultp->edgeJitterCount,
	 resultp->droppedCount,
	 resultp->duplicatedCount);
	 }*/
	[result analyzeGain];
	NSString *log = [result logStr];
	if(log) [self showLogStr:log];
	[result saveLog];
	[result saveCuesheetIfNeeded];
	if([result isGoodRip] && ([o_ejectWhenDone state] == NSOnState))
		[NSThread detachNewThreadSelector:@selector(ejectDisc:) toTarget:self withObject:[result deviceStr]];
	else
		[NSThread detachNewThreadSelector:@selector(mountDisc:) toTarget:self withObject:[result deviceStr]];
	if([result isGoodRip] && ([o_quitWhenDone state] == NSOnState)) {
		[NSApp terminate:self];
	}
	[NSApp requestUserAttention:NSInformationalRequest];
	NSBeep();
	driveIsBusy = NO;
}

- (void)accurateRipCheckDidFinish:(id)result
{
	if([result logStr]) [self showLogStr:[result logStr]];
	[result release];
}

- (void)offsetCheckDidFinish:(id)result
{
	int offset=0,i,j;
	NSArray *offsetList = nil;
	if([[[result detectedOffset] allKeys] count])
		offsetList = [[result detectedOffset] allKeys];
	int ret = NSAlertDefaultReturn;
	if(![result cancelled]) {
		if(!offsetList)
			ret = NSRunAlertPanel(LS(@"detection failure"),LS(@"Can't detect the offset of this file."),@"OK",nil,nil);
		else if([offsetList count] > 1) {
			[o_offsetCorrectionPopup removeAllItems];
			
			for(i=0;i<[offsetList count];i++) {
				if([[offsetList objectAtIndex:i] intValue] == 0) {
					NSString *title = [NSString stringWithFormat:LS(@"%d (confidence %d)"),0,[[[result detectedOffset] objectForKey:[offsetList objectAtIndex:i]] intValue]];
					[o_offsetCorrectionPopup addItemWithTitle:title];
					id item = [o_offsetCorrectionPopup itemWithTitle:title];
					if(item) [item setTag:0];
				}
			}
			
			NSArray *confidenceList = [[[result detectedOffset] allValues] sortedArrayUsingFunction:intSort context:NULL];
			int previousConfidence = -1;
			for(j=0;j<[confidenceList count];j++) {
				int confidence = [[confidenceList objectAtIndex:j] intValue];
				if(confidence == previousConfidence) continue;
				for(i=0;i<[offsetList count];i++) {
					if([[offsetList objectAtIndex:i] intValue] == 0) continue;
					int value = [[[result detectedOffset] objectForKey:[offsetList objectAtIndex:i]] intValue];
					if(value == confidence) {
						NSString *title = [NSString stringWithFormat:LS(@"%d (confidence %d)"),[[offsetList objectAtIndex:i] intValue],confidence];
						[o_offsetCorrectionPopup addItemWithTitle:title];
						id item = [o_offsetCorrectionPopup itemWithTitle:title];
						if(item) [item setTag:[[offsetList objectAtIndex:i] intValue]];
					}
				}
				previousConfidence = confidence;
			}
			
			ret = [NSApp runModalForWindow:o_offsetCorrectionPanel];
			offset = [[o_offsetCorrectionPopup selectedItem] tag];
		}
		else {
			offset = [[offsetList objectAtIndex:0] intValue];
			int confidence = [[[result detectedOffset] objectForKey:[offsetList objectAtIndex:0]] intValue];
			if(offset)
				ret = NSRunAlertPanel(LS(@"detection success"),[NSString stringWithFormat:LS(@"The offset of this file is wrong in %d samples (confidence %d)."),offset,confidence],@"OK",LS(@"Fix and Save"),nil);
			else
				ret = NSRunAlertPanel(LS(@"detection success"),LS(@"This file has a correct offset."),@"OK",nil,nil);
		}
	}
	[result release];
	
	if(ret == NSAlertDefaultReturn) return;
	
	[o_offsetValue setIntValue:offset];
	[self saveOffsetCorrectedFile:nil];
	
}

- (void)replayGainScanningDidFinish:(id)result
{
	if([result logStrForReplayGainScanner]) [self showLogStr:[result logStrForReplayGainScanner]];
	[result release];
}

- (void)tagEditDidFinishForTracks:(NSArray *)tracks albumRanges:(NSArray *)ranges tasks:(NSArray *)tasks
{
	int i;
	int albumRangeIdx = 0;
	BOOL removeFlag = NO;;
	for(i=0;i<[tracks count];i++) {
		XLDTrack *track = [tracks objectAtIndex:i];
		XLDConverterTask *task = [tasks objectAtIndex:i];
		[task setScaleType:([o_scaleImage state] == NSOffState) ? XLDNoScale : ([[o_scaleType selectedCell] tag] | (([o_expandImage state] == NSOnState) ? 0x10 : 0))];
		[task setScaleSize:[o_scalePixel intValue]];
		[task setCompressionQuality:[o_compressionQuality intValue]/100.0f];
		[self setOutputForTask:task];
		[task setProcessOfExistingFiles:[[o_existingFile selectedCell] tag]];
		[task setTagWritable:([o_autoTagging state] == NSOnState) ? YES : NO];
		[task setEmbedImages:([o_embedCoverArts state] == NSOnState) ? YES : NO];
		[task setMoveAfterFinish:([o_moveAfterFinish state] == NSOnState) ? YES : NO];
		
		if([[track metadata] objectForKey:@"Single"]) {
			removeFlag = ([o_removeOriginalFile state] == NSOnState);
			[task setRemoveOriginalFile:removeFlag];
		}
		
		NSArray *albumArray = nil;
		if([[o_filenameFormatRadio selectedCell] tag] == 0 && [track enabled]) {
			if([o_addiTunes state] == NSOnState) {
				NSString *iTunesLibName;
				if([[o_libraryType selectedCell] tag] == 0) iTunesLibName = @"library playlist 1";
				else iTunesLibName = [self formattedStringForTrack:track withPattern:[o_libraryName stringValue] singleImageMode:NO albumArtist:[[track metadata] objectForKey:XLD_METADATA_ALBUMARTIST]];
				[task setiTunesLib:iTunesLibName];
			}
			[task setTrack:track];
			continue;
		}
		if([ranges count] && albumRangeIdx < [ranges count]) {
			NSRange range = [[ranges objectAtIndex:albumRangeIdx] rangeValue];
			if(i >= range.location && i < range.location+range.length) {
				albumArray = [tracks subarrayWithRange:range];
				if(i == range.location+range.length-1) albumRangeIdx++;
			}
		}
		NSString *filename = [self preferredFilenameForTrack:track createSubDir:YES singleImageMode:NO albumArtist:(albumArray?[XLDTrackListUtil artistForTracks:albumArray]:[[track metadata] objectForKey:XLD_METADATA_ALBUMARTIST])];
		[track setDesiredFileName:[filename lastPathComponent]];
		NSString *subDir = [filename stringByDeletingLastPathComponent];
		if(![subDir isEqualToString:@""]) {
			[task setOutputDir:[[task outputDir] stringByAppendingPathComponent:subDir]];
		}
		if([o_addiTunes state] == NSOnState) {
			NSString *iTunesLibName;
			if([[o_libraryType selectedCell] tag] == 0) iTunesLibName = @"library playlist 1";
			else iTunesLibName = [self formattedStringForTrack:track withPattern:[o_libraryName stringValue] singleImageMode:NO albumArtist:(albumArray?[XLDTrackListUtil artistForTracks:albumArray]:[[track metadata] objectForKey:XLD_METADATA_ALBUMARTIST])];
			[task setiTunesLib:iTunesLibName];
		}
		[track setEnabled:YES];
		[task setTrack:track];
	}
	if(removeFlag && [o_warnBeforeConversion state] == NSOnState) {
		int ret = NSRunCriticalAlertPanel(LS(@"Deleting Original Files"), LS(@"The original files will be removed after this conversion. Are you sure you want to continue?"), LS(@"OK"), LS(@"Don't delete"), LS(@"Cancel"));
		if(ret == NSAlertAlternateReturn) {
			for(i=0;i<[tasks count];i++) {
				XLDConverterTask *task = [tasks objectAtIndex:i];
				[task setRemoveOriginalFile:NO];
			}
		}
		else if(ret == NSAlertOtherReturn) return;
	}
	
	[taskQueue performSelectorOnMainThread:@selector(addTasks:) withObject:tasks waitUntilDone:YES];
}

- (BOOL)checkUpdateStatus
{
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	return [pref boolForKey:@"SUEnableAutomaticChecks"];
}

- (void)setCheckUpdateStatus:(BOOL)flag
{
	if(updater) {
		NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
		[pref setBool:flag forKey:@"SUEnableAutomaticChecks"];
		if(!flag) [pref setBool:YES forKey:@"TempUpdateKey"];
		else [pref removeObjectForKey:@"TempUpdateKey"];
		[pref synchronize];
	}
}

- (void)updateFormatDescriptionMenu
{
	int idx = [o_formatList indexOfItemWithTag:1];
	int i;
	for(i=[o_formatList numberOfItems]-1;i>idx;i--) [o_formatList removeItemAtIndex:i];
	[o_formatList addItemsWithTitles:[customFormatManager descriptionMenuItems]];
	for(i=[o_formatList numberOfItems]-1;i>idx;i--) {
		[[o_formatList itemAtIndex:i] setEnabled:NO];
		[[o_formatList itemAtIndex:i] setTag:2];
	}
}

- (NSMutableDictionary *)currentConfiguration
{
	NSMutableDictionary *dic = [NSMutableDictionary dictionary];
	[self savePrefsToDictionary:dic];
	if([[o_formatList selectedItem] tag] == 1) {
		[dic setObject:[customFormatManager configurations] forKey:@"CustomFormatConfigurations"];
	}
	else {
		[dic addEntriesFromDictionary:(NSDictionary *)[[outputArr objectAtIndex:[o_formatList indexOfSelectedItem]] configurations]];
	}
	return dic;
}

- (void)loadProfileFromDictionary:(NSDictionary *)dic
{
	int i;
	for(i=0;i<[outputArr count];i++) {
		[[outputArr objectAtIndex:i] loadConfigurations:dic];
	}
	[customFormatManager loadConfigurations:dic];
	[self loadPrefsFromDictionary:dic];
	[self statusChanged:nil];
	[self updateFormatDescriptionMenu];
}

- (id)discView
{
	return discView;
}

- (id)metadataEditor
{
	return metadataEditor;
}

- (id)player
{
	return player;
}

- (int)writeOffset
{
	return [o_writeOffset intValue];
}

- (int)readOffsetForVerify
{
	if([o_readOffsetUseRipperValue state] == NSOnState)
		return [o_offsetCorrectionValue intValue];
	return [o_readOffsetForVerify intValue];
}

- (NSDictionary *)awsKeys
{
	if([o_useAWS state] == NSOffState) return nil;
	if([[o_AWSKey stringValue] isEqualToString:@""]) return nil;
	if([[o_AWSSecretKey stringValue] isEqualToString:@""]) return nil;
	NSDictionary *dic = [NSDictionary dictionaryWithObjectsAndKeys:[o_AWSKey stringValue], @"Key", [o_AWSSecretKey stringValue], @"SecretKey", nil];
	return dic;
}

- (const char *)awsDomain
{
	int domain = [[o_AWSDomain selectedItem] tag];
	if(domain == 0) return ".com";
	if(domain == 1) return ".jp";
	if(domain == 2) return ".co.uk";
	if(domain == 3) return ".ca";
	if(domain == 4) return ".fr";
	if(domain == 5) return ".de";
	if(domain == 6) return ".it";
	if(domain == 7) return ".es";
	if(domain == 8) return ".cn";
	return ".com";
}

- (id)imageView
{
	if([metadataEditor imageView]) return [metadataEditor imageView];
	if(![discView cueParser]) return nil;
	return [discView imageView];
}

- (void)imageDataDownloaded:(NSData *)imageData
{
	if([metadataEditor imageView]) {
		[[metadataEditor imageView] setImageData:imageData];
		[metadataEditor imageLoaded];
	}
	else if([discView cueParser]) {
		[[discView imageView] setImageData:imageData];
		[discView imageLoaded];
	}
}

#pragma mark Delegate Methods

- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	id cueParser = [discView cueParser];
	if([(NSString *)contextInfo isEqualTo:@"CDDBQuery"] || [(NSString *)contextInfo isEqualTo:@"CDDBQueryWithStart"]) {
		if(returnCode != 0) {
			[util release];
			util = nil;
			return;
		}
		XLDCDDBResult result = [util readCDDBWithInfo:[[util queryResult] objectAtIndex:[o_queryResultList indexOfSelectedItem]]];
		
		if(result == XLDCDDBSuccess) {
			//NSLog(@"connection OK");
			if([self canSetCompilationFlag] && [cueParser isCompilation]) {
				int i;
				for(i=0;i<[[cueParser trackList] count];i++) [[[[cueParser trackList] objectAtIndex:i] metadata] setObject:[NSNumber numberWithBool:YES] forKey:XLD_METADATA_COMPILATION];
			}
			[discView reloadData];
		}
		
		if([(NSString *)contextInfo isEqualTo:@"CDDBQueryWithStart"]) {
			NSData *data = [util coverData];
			if(data) {
				[cueParser setCoverData:data];
				[discView reloadData];
			}
			[self performSelectorOnMainThread:@selector(beginDecode:) withObject:nil waitUntilDone:NO];
		}
		else {
			if([util asin] && [util coverURL]) {
				[[discView imageView] loadImageFromASIN:[util asin] andAlternateURL:[util coverURL]];
			}
			if(result != XLDCDDBSuccess) {
				NSBeginCriticalAlertSheet(LS(@"CDDB connection"), @"OK", nil, nil, [discView window], nil, nil, nil, NULL, LS(@"CDDB connection failure"));
			}
			
		}
		[util release];
		util = nil;
	}
	else if([(NSString *)contextInfo isEqualTo:@"Start"]) {
		[self performSelectorOnMainThread:@selector(beginDecode:) withObject:nil waitUntilDone:NO];
	}
	else if([(NSString *)contextInfo isEqualTo:@"GetMetadataFromURL"]) {
		if(returnCode != 0) return;
		NSArray *query;
		NSString *urlStr = [o_resourceURL stringValue];
		NSRange range = [urlStr rangeOfString:@"musicbrainz.org/release/" options:NSCaseInsensitiveSearch];
		if(range.location != NSNotFound) {
			if(range.location+range.length+36 > [urlStr length]) goto fail;
			NSString *releaseID = [[urlStr substringWithRange:NSMakeRange(range.location+range.length, 36)] lowercaseString];
			if([releaseID characterAtIndex:8] != '-') goto fail;
			if([releaseID characterAtIndex:13] != '-') goto fail;
			if([releaseID characterAtIndex:18] != '-') goto fail;
			if([releaseID characterAtIndex:23] != '-') goto fail;
			int i;
			for(i=0;i<8;i++) {
				int c = [releaseID characterAtIndex:i];
				if(c >= '0' && c <= '9') continue;
				else if(c >= 'a' && c <= 'f') continue;
				goto fail;
			}
			for(i=9;i<13;i++) {
				int c = [releaseID characterAtIndex:i];
				if(c >= '0' && c <= '9') continue;
				else if(c >= 'a' && c <= 'f') continue;
				goto fail;
			}
			for(i=14;i<18;i++) {
				int c = [releaseID characterAtIndex:i];
				if(c >= '0' && c <= '9') continue;
				else if(c >= 'a' && c <= 'f') continue;
				goto fail;
			}
			for(i=19;i<23;i++) {
				int c = [releaseID characterAtIndex:i];
				if(c >= '0' && c <= '9') continue;
				else if(c >= 'a' && c <= 'f') continue;
				goto fail;
			}
			for(i=24;i<36;i++) {
				int c = [releaseID characterAtIndex:i];
				if(c >= '0' && c <= '9') continue;
				else if(c >= 'a' && c <= 'f') continue;
				goto fail;
			}
			//NSLog(@"%@",releaseID);
			query = [NSArray arrayWithObjects:
					 @"MusicBrainz_fromURL",
					 @"dummy",
					 releaseID,
					 @"Unknown Title",
					 nil];
		}
		else {
			range = [urlStr rangeOfString:@"discogs.com" options:NSCaseInsensitiveSearch];
			if(range.location != NSNotFound) {
				range = [urlStr rangeOfString:@"release/" options:NSCaseInsensitiveSearch];
				if(range.location == NSNotFound) goto fail;
				NSString *releaseID = [[urlStr substringFromIndex:range.location+range.length] lowercaseString];
				if([releaseID intValue] <= 0) goto fail;
				//NSLog(@"%@",releaseID);
				query = [NSArray arrayWithObjects:
						 @"Discogs",
						 @"dummy",
						 releaseID,
						 @"Unknown Title",
						 nil];
			}
			else goto fail;
		}
		
		id cueParser = [discView cueParser];
		if(!cueParser) return;
		if(util) [util release];
		util = [[XLDCDDBUtil alloc] initWithDelegate:self];
		[util setTracks:[cueParser trackList] totalFrame:[cueParser totalFrames]];
		XLDCDDBResult result = [util readCDDBWithInfo:query];
		if(result == XLDCDDBSuccess) {
			//NSLog(@"connection OK");
			if([self canSetCompilationFlag] && [cueParser isCompilation]) {
				int i;
				for(i=0;i<[[cueParser trackList] count];i++) [[[[cueParser trackList] objectAtIndex:i] metadata] setObject:[NSNumber numberWithBool:YES] forKey:XLD_METADATA_COMPILATION];
			}
			[discView reloadData];
		}
		if([util asin] && [util coverURL]) {
			[[discView imageView] loadImageFromASIN:[util asin] andAlternateURL:[util coverURL]];
		}
		else if([util coverURL]) {
			[[discView imageView] loadImageFromURL:[util coverURL]];
		}
		if(result == XLDCDDBConnectionFailure) {
			NSBeginCriticalAlertSheet(LS(@"CDDB connection"), @"OK", nil, nil, [discView window], nil, nil, nil, NULL, LS(@"CDDB connection failure"));
		}
		else if(result == XLDCDDBInvalidDisc) {
			NSBeginCriticalAlertSheet(LS(@"CDDB connection"), @"OK", nil, nil, [discView window], nil, nil, nil, NULL, LS(@"The enterd URL does not contain valid data for the current disc."));
		}
		[util release];
		util = nil;
		return;
fail:
		NSBeginCriticalAlertSheet(LS(@"CDDB connection"), @"OK", nil, nil, [discView window], nil, nil, nil, NULL, LS(@"The entered string is not a valid MusicBrainz or Discogs release URL."));
	}
}

- (void)setNextKeyViews
{
	// General
	[o_filenameFormat setNextKeyView:o_libraryName];
	[o_libraryName setNextKeyView:o_filenameFormat];
	// Batch
	[o_subdirectoryDepth setNextKeyView:o_extensionFilter];
	[o_extensionFilter setNextKeyView:o_subdirectoryDepth];
	// CDDB
	[o_cddbServer setNextKeyView:o_cddbServerPort];
	[o_cddbServerPort setNextKeyView:o_cddbServerPath];
	[o_cddbServerPath setNextKeyView:o_AWSKey];
	[o_AWSKey setNextKeyView:o_AWSSecretKey];
	[o_AWSSecretKey setNextKeyView:o_cddbProxyServer];
	[o_cddbProxyServer setNextKeyView:o_cddbProxyServerPort];
	[o_cddbProxyServerPort setNextKeyView:o_cddbProxyUser];
	[o_cddbProxyUser setNextKeyView:o_cddbProxyPassword];
	[o_cddbProxyPassword setNextKeyView:o_cddbServer];
	// Metadata
	[o_scalePixel setNextKeyView:o_autoLoadCoverArtName];
	[o_autoLoadCoverArtName setNextKeyView:o_defaultCommentValue];
	[o_defaultCommentValue setNextKeyView:o_scalePixel];
	// CD Rip
	[o_maxRetryCount setNextKeyView:o_offsetCorrectionValue];
	[o_offsetCorrectionValue setNextKeyView:o_maxRetryCount];
	// CD Brun
	[o_writeOffset setNextKeyView:o_readOffsetForVerify];
	[o_readOffsetForVerify setNextKeyView:o_writeOffset];
}

- (void)awakeFromNib
{
    
}

- (void)applicationDidFinishLaunching: (NSNotification *)notification
{
	int i;
	
	for(i=0;i<[outputArr count];i++) {
		if(i>=5) {
			[o_formatList addItemWithTitle:[[[outputArr objectAtIndex:i] class] pluginName]];
		}
		[[outputArr objectAtIndex:i] loadPrefs];
	}
	
	[[o_formatList menu] addItem:[NSMenuItem separatorItem]];
	[o_formatList addItemWithTitle:LS(@"Multiple Formats")];
	id item = [o_formatList itemWithTitle:LS(@"Multiple Formats")];
	if(item) [item setTag:1];
	
	[o_cddbServer setNumberOfVisibleItems:2];
	
	[[o_cuesheetEncodings itemAtIndex:0] setTag:0xFFFFFFFF];
	const NSStringEncoding *encodingsArr = [NSString availableStringEncodings];
	NSMutableDictionary *dic = [[NSMutableDictionary alloc] init];
	for(i=0;*(encodingsArr+i);i++) {
		[dic setObject:[NSNumber numberWithUnsignedInt:*(encodingsArr+i)] forKey:[NSString localizedNameOfStringEncoding:*(encodingsArr+i)]];
	}
	NSArray *arr = [[dic allKeys] sortedArrayUsingSelector:@selector(compare:)];
	for(i=0;i<[arr count];i++) {
		[o_cuesheetEncodings addItemWithTitle:[arr objectAtIndex:i]];
		id item = [o_cuesheetEncodings itemWithTitle:[arr objectAtIndex:i]];
		if(item) [item setTag:[[dic objectForKey:[arr objectAtIndex:i]] unsignedIntValue]];
	}
	[dic release];
	/*
	 for(i=0;*(encodingsArr+i);i++) {
	 [o_cuesheetEncodings addItemWithTitle:[NSString localizedNameOfStringEncoding:*(encodingsArr+i)]];
	 id item = [o_cuesheetEncodings itemWithTitle:[NSString localizedNameOfStringEncoding:*(encodingsArr+i)]];
	 if(item) [item setTag:*(encodingsArr+i)];
	 }
	 */
	
	[o_filenameFormat setToolTip:LS(@"formatTooltipStr")];
	[o_libraryName setToolTip:LS(@"formatTooltipStr")];
	
	NSUserDefaults* defs = [NSUserDefaults standardUserDefaults];
	NSArray* languages = [defs objectForKey:@"AppleLanguages"];
	if([[languages objectAtIndex:0] isEqualToString:@"ja"]) {
		[o_cuesheetEncodings selectItemAtIndex:0];
	}
	else {
		[o_cuesheetEncodings selectItemWithTitle:[NSString localizedNameOfStringEncoding:[NSString defaultCStringEncoding]]];
	}
	
	NSToolbar*  toolbar;
    toolbar = [[[NSToolbar alloc] initWithIdentifier:@"PrefToolbar"] autorelease];
    [toolbar setDelegate:self];
    [o_prefPane setToolbar:toolbar];
	[toolbar setSelectedItemIdentifier:GeneralIdentifier];
	
	toolbar = [[[NSToolbar alloc] initWithIdentifier:@"LogToolbar"] autorelease];
    [toolbar setDelegate:self];
    [o_logWindow setToolbar:toolbar];
	
	[o_defaultCommentValue setFont:[NSFont systemFontOfSize:11]]; 
	[o_formatList setAutoenablesItems:NO];
	[self makeDriveOffsetList];
	[self loadPrefs];
	[customFormatManager loadPrefs];
	[profileManager loadPrefs];
	[discView loadPrefs];
	[self updateFormatDescriptionMenu];
	
	[o_addProfileMenu setAction:@selector(addProfile:)];
	[o_addProfileMenu setTarget:profileManager];
	[o_manageProfileMenu setAction:@selector(showProfileManager:)];
	[o_manageProfileMenu setTarget:profileManager];
	//[self setNextKeyViews];
	[self statusChanged:nil];
	[self updateCDDAList:nil];
	
	[self performSelector:@selector(launchOK) withObject:nil afterDelay:0.5];
	/*if(queuedFile) {
	 [self application:NSApp openFile:queuedFile];
	 [queuedFile release];
	 queuedFile = nil;
	 }*/
	//[[NSUserDefaults standardUserDefaults] setObject: @"http://hoge.com/hoge.xml" forKey:@"SUFeedURL"];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
	if([discView burning]) return NO;
	if([taskQueue hasActiveTask]) {
		int ret = NSRunCriticalAlertPanel(LS(@"Quit XLD"), LS(@"You have some active tasks. Are you sure you want to quit?"), @"OK", LS(@"Cancel"), nil);
		if(ret == NSAlertAlternateReturn) return NO;
	}
	[(XLDPlayer *)player releaseDecoder];
	int i;
	for(i=0;i<[outputArr count];i++) {
		[[outputArr objectAtIndex:i] savePrefs];
	}
	[discView savePrefs];
	[profileManager savePrefs];
	[customFormatManager savePrefs];
	[self savePrefs];
	return YES;
}

- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename
{
	if(openingFiles) return NO;
	[queue addObject:filename];
	if(firstDrag && launched) {
		firstDrag = NO;
		[self performSelector:@selector(processQueue) withObject:nil afterDelay:0.2];
	}
	return YES;
}

- (int)numberOfItemsInComboBox:(NSComboBox *)aComboBox
{
	return [serverList count];
}

- (id)comboBox:(NSComboBox *)aComboBox objectValueForItemAtIndex:(int)index
{
	return [serverList objectAtIndex:index];
}

- (NSArray*)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar
{
	if([[toolbar identifier] isEqualToString:@"PrefToolbar"]) {
		return [NSArray arrayWithObjects:GeneralIdentifier, 
				BatchIdentifier, 
				CDDBIdentifier, 
				MetadataIdentifier, 
				CDRipIdentifier,
				BurnIdentifier,
				nil];
	}
	else if([[toolbar identifier] isEqualToString:@"LogToolbar"]) {
		return [NSArray arrayWithObjects:@"SaveAs", 
				nil];
	}
	return nil;
}

- (NSArray*)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar
{
    return [self toolbarDefaultItemIdentifiers:toolbar];
}

- (NSArray*)toolbarSelectableItemIdentifiers:(NSToolbar*)toolbar
{
	if([[toolbar identifier] isEqualToString:@"PrefToolbar"])
		return [self toolbarDefaultItemIdentifiers:toolbar];
	else return nil;
}

- (NSToolbarItem*)toolbar:(NSToolbar*)toolbar 
	itemForItemIdentifier:(NSString*)itemId 
willBeInsertedIntoToolbar:(BOOL)willBeInserted
{
    NSToolbarItem*  toolbarItem;
    toolbarItem = [[[NSToolbarItem alloc] initWithItemIdentifier:itemId] autorelease];
	if([[toolbar identifier] isEqualToString:@"PrefToolbar"]) {
		[toolbarItem setTarget:self];
		[toolbarItem setAction:@selector(showTab:)];
		
		if ([itemId isEqualToString:GeneralIdentifier]) {
			[toolbarItem setLabel:LS(@"General")];
			[toolbarItem setImage:[NSImage imageNamed:@"general"]];
			
			return toolbarItem;
		}
		else if ([itemId isEqualToString:BatchIdentifier]) {
			[toolbarItem setLabel:LS(@"Batch")];
			[toolbarItem setImage:[NSImage imageNamed:@"batch"]];
			
			return toolbarItem;
		}
		else if ([itemId isEqualToString:CDDBIdentifier]) {
			[toolbarItem setLabel:LS(@"CDDB")];
			[toolbarItem setImage:[NSImage imageNamed:@"cddb"]];
			
			return toolbarItem;
		}
		else if ([itemId isEqualToString:MetadataIdentifier]) {
			[toolbarItem setLabel:LS(@"Metadata")];
			[toolbarItem setImage:[NSImage imageNamed:@"metadata"]];
			
			return toolbarItem;
		}
		else if ([itemId isEqualToString:CDRipIdentifier]) {
			[toolbarItem setLabel:LS(@"CD Rip")];
			[toolbarItem setImage:[[NSWorkspace sharedWorkspace] iconForDisc]];
			
			return toolbarItem;
		}
		else if ([itemId isEqualToString:BurnIdentifier]) {
			[toolbarItem setLabel:LS(@"CD Burn")];
			[toolbarItem setImage:[[NSWorkspace sharedWorkspace] iconForBurn]];
			
			return toolbarItem;
		}
	}
	else if([[toolbar identifier] isEqualToString:@"LogToolbar"]) {
		if ([itemId isEqualToString:@"SaveAs"]) {
			[toolbarItem setLabel:LS(@"Save As")];
			[toolbarItem setImage:[NSImage imageNamed:@"SaveAs"]];
			[toolbarItem setTag:1];
			[toolbarItem setTarget:self];
			[toolbarItem setAction:@selector(saveCuesheet:)];
			return toolbarItem;
		}
	}
	
    return nil;
}

-(float)toolbarHeightForWindow:(NSWindow *)window
{
    NSToolbar *toolbar;
    float toolbarHeight = 0.0;
    NSRect windowFrame;
    
    toolbar = [window toolbar];
    
    if(toolbar && [toolbar isVisible])
    {
        windowFrame = [NSWindow contentRectForFrameRect:[window frame]
											  styleMask:[window styleMask]];
        toolbarHeight = NSHeight(windowFrame)
		- NSHeight([[window contentView] frame]);
    }
    
    return toolbarHeight;
}

-(void)resizePrefPane
{
	NSArray *subviews = [[[o_preferencesTab selectedTabViewItem] view] subviews];
	NSEnumerator *enumerator = [subviews objectEnumerator];
	NSRect windowRect = NSZeroRect;
	NSView *subview = nil;
	while((subview = [enumerator nextObject]))
	{
		windowRect = NSUnionRect(windowRect, [subview frame]);
	}
	windowRect.origin.y = [[o_preferencesTab window] frame].origin.y;
	windowRect.size.height += [self toolbarHeightForWindow:[o_preferencesTab window]]; //toolbar height
	windowRect.size.height += 22; //title bar height
	windowRect.size.height += 32; //border
	
	NSRect r = NSMakeRect([[o_preferencesTab window] frame].origin.x, [[o_preferencesTab window] frame].origin.y - 
						  (windowRect.size.height - [[o_preferencesTab window] frame].size.height), [[o_preferencesTab window] frame].size.width, windowRect.size.height);
	[[o_preferencesTab window] setFrame:r display:YES animate:YES];
	//[[o_preferencesTab window] makeFirstResponder:[[o_preferencesTab selectedTabViewItem] view]];
}


- (void)showTab:(id)sender
{
	NSString *newId = [sender itemIdentifier];
	[[[o_preferencesTab tabViewItemAtIndex:[o_preferencesTab indexOfTabViewItemWithIdentifier:newId]] view] setHidden:YES];
	[o_preferencesTab selectTabViewItemWithIdentifier:newId];
	//[[[o_preferencesTab selectedTabViewItem] view] setHidden:YES];
	[self resizePrefPane];
	[[[o_preferencesTab selectedTabViewItem] view] setHidden:NO];
	[o_prefPane makeFirstResponder:[[o_preferencesTab selectedTabViewItem] initialFirstResponder]];
	[self setNextKeyViews];
}


- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	id cueParser = [discView cueParser];
	if([discView burning]) return NO;
    else if([menuItem action] == @selector(editMetadata:))
        return [[discView window] isVisible] && (cueParser != nil);
	else if([menuItem action] == @selector(saveCuesheet:))
        return [[discView window] isVisible] && (cueParser != nil);
	else if([menuItem action] == @selector(checkAccurateRip:))
		return [[discView window] isVisible] && (cueParser != nil) && ![[cueParser fileToDecode] hasPrefix:@"/dev/disk"];
	else if([menuItem action] == @selector(saveOffsetCorrectedFile:))
		return [[discView window] isVisible] && (cueParser != nil) && ![[cueParser fileToDecode] hasPrefix:@"/dev/disk"];
	else if([menuItem action] == @selector(checkForUpdates:))
		return (updater != nil);
	else if([menuItem action] == @selector(analyzeCache:))
		return [[discView window] isVisible] && (cueParser != nil) && [[cueParser fileToDecode] hasPrefix:@"/dev/disk"];
	else if([menuItem action] == @selector(inputTagsFromText:))
        return ([[discView window] isVisible] && (cueParser != nil)) || [metadataEditor editingSingleTags];
	else if([menuItem action] == @selector(cddbGetTracks:))
        return [[discView window] isVisible] && (cueParser != nil);
	else if([menuItem action] == @selector(associateMBDiscID:))
        return [[discView window] isVisible] && (cueParser != nil);
	else if([menuItem action] == @selector(getMetadataFromURL:))
        return [[discView window] isVisible] && (cueParser != nil);
    return YES;
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)theItem
{
	if([[theItem itemIdentifier] isEqualToString:@"Extract"]) return ([discView cueParser] != nil);
	if([[theItem itemIdentifier] isEqualToString:@"GetMetadata"]) return ([discView cueParser] != nil);
	if([[theItem itemIdentifier] isEqualToString:@"SaveAs"]) return (![[[o_logView textStorage] mutableString] isEqualToString:@""]);
	return YES;
}

- (void)updateProfileMenuFromNames:(NSArray *)arr
{
	int i;
	i = [o_profileMenu numberOfItems]-1;
	for(;i>=3;i--) [o_profileMenu removeItemAtIndex:i];

	for(i=0;i<[arr count];i++) {
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[arr objectAtIndex:i] action:@selector(loadProfile:) keyEquivalent:@""];
		[item setTarget:profileManager];
		[o_profileMenu addItem:item];
		[item release];
	}
}

@end
