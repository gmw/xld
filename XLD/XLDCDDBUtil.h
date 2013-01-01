//
//  XLDCDDBUtil.h
//  XLD
//
//  Created by tmkk on 06/08/25.
//  Copyright 2006 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <cddb/cddb.h>

enum
{
	XLDCDDBQueryEmptyOnlyMask	= 1,
	XLDCDDBQueryDiscTitleMask	= 2,
	XLDCDDBQueryTrackTitleMask	= 4,
	XLDCDDBQueryArtistMask		= 8,
	XLDCDDBQueryGenreMask		= 16,
	XLDCDDBQueryYearMask		= 32,
	XLDCDDBQueryCoverArtMask	= 64,
	XLDCDDBQueryComposerMask	= 128,
};

typedef enum
{
	XLDCDDBFreeDBPreferred = 0,
	XLDCDDBMusicBrainzPreferred = 1
} XLDCDDBPreferredService;

typedef enum
{
	XLDCDDBSuccess = 0,
	XLDCDDBConnectionFailure,
	XLDCDDBInvalidDisc,
} XLDCDDBResult;

@interface XLDCDDBUtil : NSObject {
	cddb_disc_t *disc;
	cddb_conn_t *conn;
	char discid[100];
	char toc[1024];
	id delegate;
	BOOL useProxy;
	NSArray *trackArr;
	NSMutableArray *queryResult;
	int totalAudioTrack;
	int totalSectors;
	XLDCDDBPreferredService preferredService;
	NSString *asin;
	NSURL *coverURL;
	BOOL ambiguous;
	BOOL freeDBDisabled;
}

- (id)initWithDelegate:(id)del;
- (void)setTracks:(NSArray *)tracks totalFrame:(int)frames;
- (void)setUseProxy:(BOOL)flag;
- (void)setUseCache:(BOOL)flag;
- (void)setServer:(NSString *)server port:(int)port path:(NSString *)path;
- (void)setProxyServer:(NSString *)server port:(int)port user:(NSString *)user passwd:(NSString *)passwd;
- (int)query;
- (NSArray *)queryResult;
- (XLDCDDBResult)readCDDBWithInfo:(NSArray *)info;
- (NSData *)coverData;
- (void)setPreferredService:(XLDCDDBPreferredService)s;
- (NSString *)asin;
- (NSURL *)coverURL;
- (BOOL)associateMBDiscID;
- (void)disableFreeDB;

@end
