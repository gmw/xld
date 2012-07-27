
#ifndef TTADEC_H
#define TTADEC_H

#define MAX_ORDER		16
#define BIT_BUFFER_SIZE (1024*1024)

typedef struct {
    unsigned long TTAid;
    unsigned short AudioFormat;
    unsigned short NumChannels;
    unsigned short BitsPerSample;
    unsigned long SampleRate;
    unsigned long DataLength;
    unsigned long CRC32;
} __attribute__ ((packed)) tta_hdr_t;

typedef struct {
    unsigned char id[3];
    unsigned short version;
    unsigned char flags;
    unsigned char size[4];
} __attribute__ ((packed)) id3v2_t;

typedef struct {
	unsigned long k0;
	unsigned long k1;
	unsigned long sum0;
	unsigned long sum1;
} adapt;

typedef struct {
	long shift;
	long round;
	long error;
	long mutex;
	long qm[MAX_ORDER] __attribute__((aligned(16)));
	long dx[MAX_ORDER] __attribute__((aligned(16)));
	long dl[MAX_ORDER] __attribute__((aligned(16)));
} fltst;

typedef struct {
	fltst fst;
	adapt rice;
	long last;
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
	long *data;
	unsigned char *internal_buffer;
	unsigned char *internal_buffer_p;
	int bufferRest;
	unsigned char bit_buffer[BIT_BUFFER_SIZE + 8];
	unsigned char *BIT_BUFFER_END;
	tta_hdr_t tta_hdr;
	unsigned long *seek_table;
	unsigned long *st;
	unsigned long framelen, lastlen, fframes, st_state;
	xldoffset_t lastpos;
	unsigned long frame_crc32;
	unsigned long bit_count;
	unsigned long bit_cache;
	unsigned char *bitpos;
	id3v2_t id3v2;
} ttainfo;

int decode_init(char *filename, ttainfo *info);
int decode_sample(ttainfo *info, unsigned char *outbuf, int bytes);
xldoffset_t seek_tta(ttainfo *info, xldoffset_t pos);
void clean_tta_decoder(ttainfo *info);

#endif	/* TTADEC_H */