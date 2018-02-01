
#ifndef TTADEC_H
#define TTADEC_H

#define MAX_ORDER		16
#define BIT_BUFFER_SIZE (1024*1024)

typedef struct {
    uint32_t TTAid;
    unsigned short AudioFormat;
    unsigned short NumChannels;
    unsigned short BitsPerSample;
    uint32_t SampleRate;
    uint32_t DataLength;
    uint32_t CRC32;
} __attribute__ ((packed)) tta_hdr_t;

typedef struct {
    unsigned char id[3];
    unsigned short version;
    unsigned char flags;
    unsigned char size[4];
} __attribute__ ((packed)) id3v2_t;

typedef struct {
	uint32_t k0;
	uint32_t k1;
	uint32_t sum0;
	uint32_t sum1;
} adapt;

typedef struct {
	int32_t shift;
	int32_t round;
	int32_t error;
	int32_t mutex;
	int32_t qm[MAX_ORDER] __attribute__((aligned(16)));
	int32_t dx[MAX_ORDER] __attribute__((aligned(16)));
	int32_t dl[MAX_ORDER] __attribute__((aligned(16)));
} fltst;

typedef struct {
	fltst fst;
	adapt rice;
	int32_t last;
} encoder;

typedef struct
{
	int bps;
	int samplerate;
	int channels;
	int channels_real;
	int finish;
	int totalFrames;
	int isFloat;
	
	FILE *fdin;
	int bytesPerFrame;
	int input_byte_count;
	int data_offset;
	encoder *tta, *enc;
	int32_t *data;
	unsigned char *internal_buffer;
	unsigned char *internal_buffer_p;
	int bufferRest;
	unsigned char bit_buffer[BIT_BUFFER_SIZE + 8];
	unsigned char *BIT_BUFFER_END;
	tta_hdr_t tta_hdr;
	uint32_t *seek_table;
	uint32_t *st;
	uint32_t framelen, lastlen, fframes, st_state;
	xldoffset_t lastpos;
	uint32_t frame_crc32;
	uint32_t bit_count;
	uint32_t bit_cache;
	unsigned char *bitpos;
	id3v2_t id3v2;
} ttainfo;

int decode_init(char *filename, ttainfo *info);
int decode_sample(ttainfo *info, unsigned char *outbuf, int bytes);
xldoffset_t seek_tta(ttainfo *info, xldoffset_t pos);
void clean_tta_decoder(ttainfo *info);

#endif	/* TTADEC_H */
