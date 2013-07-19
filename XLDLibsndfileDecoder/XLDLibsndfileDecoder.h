typedef enum {
	XLDNoCueSheet = 0,
	XLDTrackTypeCueSheet,
	XLDTextTypeCueSheet
} XLDEmbeddedCueSheetType;

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
#define XLD_METADATA_SMPTE_TIMECODE_START	@"SMTPE Timecode Start"
#define XLD_METADATA_SMPTE_TIMECODE_DURATION	@"SMTPE Timecode Duration"
#define XLD_METADATA_MEDIA_FPS	@"Media FPS"

#import <sndfile.h>
#import "XLDDecoder.h"
#import "XLDTrack.h"

@interface XLDLibsndfileDecoder : NSObject <XLDDecoder>
{
	SNDFILE *sf;
	SF_INFO sfinfo;
	int bps;
	int isFloat;
	char errstr[256];
	xldoffset_t totalFrames;
	BOOL error;
	NSString *srcPath;
	NSMutableArray *trackArr;
	//NSString *cueData;
	NSMutableDictionary *metadataDic;
}

+ (BOOL)canHandleFile:(char *)path;
+ (BOOL)canLoadThisBundle;
- (BOOL)openFile:(char *)path;
- (int)samplerate;
- (int)bytesPerSample;
- (int)channels;
- (int)decodeToBuffer:(int *)buffer frames:(int)count;
- (void)closeFile;
- (xldoffset_t)seekToFrame:(xldoffset_t)count;
- (xldoffset_t)totalFrames;
- (int)isFloat;
- (BOOL)error;
- (XLDEmbeddedCueSheetType)hasCueSheet;
- (id)cueSheet;
- (id)metadata;
- (NSString *)srcPath;

@end
