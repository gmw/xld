
typedef enum {
	XLDNoCueSheet = 0,
	XLDTrackTypeCueSheet,
	XLDTextTypeCueSheet
} XLDEmbeddedCueSheetType;

#import <wavpack/wavpack.h>
#import "XLDDecoder.h"
/*
typedef unsigned char	uchar;

typedef struct {
    char tag_id [3], title [30], artist [30], album [30];
    char year [4], comment [30], genre;
} ID3_Tag;

typedef struct {
    char ID [8];
    int32_t version, length, item_count, flags;
    char res [8];
} APE_Tag_Hdr;

typedef struct {
    int32_t tag_file_pos;
    ID3_Tag id3_tag;
    APE_Tag_Hdr ape_tag_hdr;
    char *ape_tag_data;
} M_Tag;

typedef struct {
    char ckID [4];
    uint32_t ckSize;
    short version;
    uchar track_no, index_no;
    uint32_t total_samples, block_index, block_samples, flags, crc;
} WavpackHeader;

typedef struct {
    int32_t byte_length;
    void *data;
    uchar id;
} WavpackMetadata;

typedef struct {
    float bitrate, shaping_weight;
    int bits_per_sample, bytes_per_sample;
    int qmode, flags, xmode, num_channels, float_norm_exp;
    int32_t block_samples, extra_flags, sample_rate, channel_mask;
    uchar md5_checksum [16], md5_read;
    int num_tag_strings;
    char **tag_strings;
} WavpackConfig;

typedef struct bs {
#ifdef _BIG_ENDIAN
    unsigned char *buf, *end, *ptr;
#else
	unsigned short *buf, *end, *ptr;
#endif
    void (*wrap)(struct bs *bs);
    int error, bc;
    uint32_t sr;
} Bitstream;

#define MAX_STREAMS 8
#define MAX_NTERMS 16
#define MAX_TERM 8

struct decorr_pass {
    int term, delta, weight_A, weight_B;
    int32_t samples_A [MAX_TERM], samples_B [MAX_TERM];
    int32_t aweight_A, aweight_B;
    int32_t sum_A, sum_B;
};

typedef struct {
    char joint_stereo, delta, terms [MAX_NTERMS+1];
} WavpackDecorrSpec;

struct entropy_data {
    uint32_t median [3], slow_level, error_limit;
};

struct words_data {
    uint32_t bitrate_delta [2], bitrate_acc [2];
    uint32_t pend_data, holding_one, zeros_acc;
    int holding_zero, pend_count;
    struct entropy_data c [2];
};

typedef struct {
    WavpackHeader wphdr;
    struct words_data w;
	
    uchar *blockbuff, *blockend;
    uchar *block2buff, *block2end;
    int32_t *sample_buffer;
	
    int bits, num_terms, mute_error, joint_stereo, false_stereo, shift;
    int num_decorrs, num_passes, best_decorr, mask_decorr;
    uint32_t sample_index, crc, crc_x, crc_wvx;
    Bitstream wvbits, wvcbits, wvxbits;
    int init_done, wvc_skip;
    float delta_decay;
	
    uchar int32_sent_bits, int32_zeros, int32_ones, int32_dups;
    uchar float_flags, float_shift, float_max_exp, float_norm_exp;
	
    struct {
        int32_t shaping_acc [2], shaping_delta [2], error [2];
        double noise_sum, noise_ave, noise_max;
    } dc;
	
    struct decorr_pass decorr_passes [MAX_NTERMS];
    WavpackDecorrSpec *decorr_specs;
} WavpackStream;

typedef struct {
    int32_t (*read_bytes)(void *id, void *data, int32_t bcount);
    uint32_t (*get_pos)(void *id);
    int (*set_pos_abs)(void *id, uint32_t pos);
    int (*set_pos_rel)(void *id, int32_t delta, int mode);
    int (*push_back_byte)(void *id, int c);
    uint32_t (*get_length)(void *id);
    int (*can_seek)(void *id);
	
    // this callback is for writing edited tags only
    int32_t (*write_bytes)(void *id, void *data, int32_t bcount);
} WavpackStreamReader;

typedef int (*WavpackBlockOutput)(void *id, void *data, int32_t bcount);

typedef struct {
    WavpackConfig config;
	
    WavpackMetadata *metadata;
    uint32_t metabytes;
    int metacount;
	
    uchar *wrapper_data;
    uint32_t wrapper_bytes;
	
    WavpackBlockOutput blockout;
    void *wv_out, *wvc_out;
	
    WavpackStreamReader *reader;
    void *wv_in, *wvc_in;
	
    uint32_t filelen, file2len, filepos, file2pos, total_samples, crc_errors, first_flags;
    int wvc_flag, open_flags, norm_offset, reduced_channels, lossy_blocks, close_files;
    uint32_t block_samples, max_samples, acc_samples, initial_index;
    int riff_header_added, riff_header_created;
    M_Tag m_tag;
	
    int current_stream, num_streams, stream_version;
    WavpackStream *streams [MAX_STREAMS];
    void *stream3;
	
    char error_message [80];
} WavpackContext;
*/
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

@interface XLDWavpackDecoder : NSObject <XLDDecoder>
{
	WavpackContext *wc;
	int bps;
	int samplerate;
	int channels;
	xldoffset_t totalFrames;
	int isFloat;
	char errstr[256];
	BOOL error;
	NSString *cueData;
	NSMutableDictionary *metadataDic;
	NSString *srcPath;
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