
#include <stdio.h>
#include <sys/types.h>

typedef int64_t xldoffset_t;

#include "ttadec.h"
#include "ttaenc.h"
#include "crc32.h"
#if defined(__i386__)
#include "filters_sse.h"
#else
#include "filters.h"
#endif

const unsigned long bit_mask[] = {
    0x00000000, 0x00000001, 0x00000003, 0x00000007,
    0x0000000f, 0x0000001f, 0x0000003f, 0x0000007f,
    0x000000ff, 0x000001ff, 0x000003ff, 0x000007ff,
    0x00000fff, 0x00001fff, 0x00003fff, 0x00007fff,
    0x0000ffff, 0x0001ffff, 0x0003ffff, 0x0007ffff,
    0x000fffff, 0x001fffff, 0x003fffff, 0x007fffff,
    0x00ffffff, 0x01ffffff, 0x03ffffff, 0x07ffffff,
    0x0fffffff, 0x1fffffff, 0x3fffffff, 0x7fffffff,
    0xffffffff
};

const unsigned long bit_shift[] = {
    0x00000001, 0x00000002, 0x00000004, 0x00000008,
    0x00000010, 0x00000020, 0x00000040, 0x00000080,
    0x00000100, 0x00000200, 0x00000400, 0x00000800,
    0x00001000, 0x00002000, 0x00004000, 0x00008000,
    0x00010000, 0x00020000, 0x00040000, 0x00080000,
    0x00100000, 0x00200000, 0x00400000, 0x00800000,
    0x01000000, 0x02000000, 0x04000000, 0x08000000,
    0x10000000, 0x20000000, 0x40000000, 0x80000000,
    0x80000000, 0x80000000, 0x80000000, 0x80000000,
    0x80000000, 0x80000000, 0x80000000, 0x80000000
	};

const unsigned long *shift_16 = bit_shift + 4;

void tta_error(long error, wchar_t *name)
{
    ERASE_STDERR;
    switch (error) {
    case COMMAND_ERROR:
	fwprintf(stderr, L"Error:   unknown command '%ls'\n%hs\n", name, LINE); break;
    case FORMAT_ERROR:
	fwprintf(stderr, L"Error:   not compatible file format\n%hs\n", LINE); break;
    case FILE_ERROR:
	fwprintf(stderr, L"Error:   file is corrupted\n%hs\n", LINE); break;
    case FIND_ERROR:
	fwprintf(stderr, L"Error:   file(s) not found '%ls'\n%hs\n\n", name, LINE); exit(1);
    case CREATE_ERROR:
	fwprintf(stderr, L"Error:   problem creating directory '%ls'\n%hs\n\n", name, LINE); exit(1);
    case OPEN_ERROR:
	fwprintf(stderr, L"Error:   can't open file '%ls'\n%hs\n\n", name, LINE); exit(1);
    case MEMORY_ERROR:
	fwprintf(stdout, L"Error:   insufficient memory available\n%hs\n\n", LINE); exit(1);
    case WRITE_ERROR:
	fwprintf(stdout, L"Error:   can't write to output file\n%hs\n\n", LINE); exit(1);
    case READ_ERROR:
	fwprintf(stdout, L"Error:   can't read from input file\n%hs\n\n", LINE); exit(1);
    }
}

void *tta_malloc(size_t num, size_t size)
{
    void *array;

    if ((array = calloc(num, size)) == NULL)
		tta_error(MEMORY_ERROR, NULL);

    return (array);
}


__inline void get_binary(unsigned long *value, unsigned long bits, ttainfo *info) {
    while (info->bit_count < bits) {
		if (info->bitpos == info->BIT_BUFFER_END) {
			long res = fread(info->bit_buffer, 1,
					BIT_BUFFER_SIZE, info->fdin);
			if (!res) {
				tta_error(READ_ERROR, NULL);
				return;
			}
			info->input_byte_count += res;
			info->bitpos = info->bit_buffer;
		}

		UPDATE_CRC32(*(info->bitpos), info->frame_crc32);
		info->bit_cache |= *(info->bitpos) << info->bit_count;
		info->bit_count += 8;
		(info->bitpos)++;
    }

    *value = info->bit_cache & bit_mask[bits];
    info->bit_cache >>= bits;
    info->bit_count -= bits;
    info->bit_cache &= bit_mask[info->bit_count];
}

__inline void get_unary(unsigned long *value, ttainfo *info) {
    *value = 0;

    while (!(info->bit_cache ^ bit_mask[info->bit_count])) {
		if (info->bitpos == info->BIT_BUFFER_END) {
			long res = fread(info->bit_buffer, 1,
					BIT_BUFFER_SIZE, info->fdin);
			if (!res) {
				tta_error(READ_ERROR, NULL);
				return;
			}
			info->input_byte_count += res;
			info->bitpos = info->bit_buffer;
		}

		*value += info->bit_count;
		info->bit_cache = *(info->bitpos)++;
		UPDATE_CRC32(info->bit_cache, info->frame_crc32);
		info->bit_count = 8;
    }

    while (info->bit_cache & 1) {
		(*value)++;
		info->bit_cache >>= 1;
		(info->bit_count)--;
    }

    info->bit_cache >>= 1;
    (info->bit_count)--;
}

void init_buffer_read(xldoffset_t pos, ttainfo *info) {
    info->frame_crc32 = 0xFFFFFFFFUL;
    info->bit_count = info->bit_cache = info->lastpos = 0;
    info->bitpos = info->BIT_BUFFER_END;
    info->lastpos = pos;
}

int done_buffer_read(ttainfo *info) {
    unsigned long crc32, rbytes, res;
    info->frame_crc32 ^= 0xFFFFFFFFUL;

    rbytes = info->BIT_BUFFER_END - info->bitpos;
    if (rbytes < sizeof(long)) {
		memcpy(info->bit_buffer, info->bitpos, 4);
		res = fread(info->bit_buffer + rbytes, 1,
			BIT_BUFFER_SIZE - rbytes, info->fdin);
		if (!res) {
			tta_error(READ_ERROR, NULL);
			return 1;
		}
		info->input_byte_count += res;
		info->bitpos = info->bit_buffer;
    }

    memcpy(&crc32, info->bitpos, 4);
    crc32 = ENDSWAP_INT32(crc32);
    info->bitpos += sizeof(long);
    res = (crc32 != info->frame_crc32);

    info->bit_cache = info->bit_count = 0;
    info->frame_crc32 = 0xFFFFFFFFUL;

    return res;
}

void rice_init(adapt *rice, unsigned long k0, unsigned long k1) {
    rice->k0 = k0;
    rice->k1 = k1;
    rice->sum0 = shift_16[k0];
    rice->sum1 = shift_16[k1];
}

void encoder_init(encoder *tta, long nch, long byte_size) {
	long *fset = flt_set[byte_size - 1];
    long i;

    for (i = 0; i < nch; i++) {
		filter_init(&tta[i].fst, fset[0], fset[1]);
		rice_init(&tta[i].rice, 10, 10);
		tta[i].last = 0;
    }
}

int decode_init(char *filename, ttainfo *info)
{
	unsigned long st_size, checksum;
	long len = 0;
	
	info->finish = 0;
	info->BIT_BUFFER_END = info->bit_buffer + BIT_BUFFER_SIZE;
	
	info->fdin = fopen(filename, "rb");
	
	// skip ID3V2 header
	if (fread(&(info->id3v2), sizeof(info->id3v2), 1, info->fdin) == 0) {
		fclose(info->fdin);
		return -1;
	}
	
	if (!memcmp(info->id3v2.id, "ID3", 3)) {

		if (info->id3v2.size[0] & 0x80) {
			fclose(info->fdin);
			return -1;
		}

		len = (info->id3v2.size[0] & 0x7f);
		len = (len << 7) | (info->id3v2.size[1] & 0x7f);
		len = (len << 7) | (info->id3v2.size[2] & 0x7f);
		len = (len << 7) | (info->id3v2.size[3] & 0x7f);
		len += 10;
		if (info->id3v2.flags & (1 << 4)) len += 10;
		
		fseek(info->fdin, len, SEEK_SET);
	} else fseek(info->fdin, 0, SEEK_SET);
	
	info->input_byte_count = 0;
	
	// read TTA header
	if (fread(&info->tta_hdr, sizeof(info->tta_hdr), 1, info->fdin) == 0) {
		fclose(info->fdin);
		return -1;
	}
	else info->input_byte_count += sizeof(info->tta_hdr);

	// check for supported formats
	if (ENDSWAP_INT32(info->tta_hdr.TTAid) != TTA1_SIGN) {
		fclose(info->fdin);
		return -1;
	}
	
	info->tta_hdr.CRC32 = ENDSWAP_INT32(info->tta_hdr.CRC32);
	checksum = crc32((unsigned char *) &info->tta_hdr,
	sizeof(info->tta_hdr) - sizeof(long));
	if (checksum != info->tta_hdr.CRC32) {
		fclose(info->fdin);
		return -1;
	}

	info->tta_hdr.AudioFormat = ENDSWAP_INT16(info->tta_hdr.AudioFormat); 
	info->tta_hdr.NumChannels = ENDSWAP_INT16(info->tta_hdr.NumChannels);
	info->tta_hdr.BitsPerSample = ENDSWAP_INT16(info->tta_hdr.BitsPerSample);
	info->tta_hdr.SampleRate = ENDSWAP_INT32(info->tta_hdr.SampleRate);
	info->tta_hdr.DataLength = ENDSWAP_INT32(info->tta_hdr.DataLength);
	
	int sampleRate = info->tta_hdr.SampleRate;
	int bytesPerSample = (info->tta_hdr.BitsPerSample + 7) / 8;
	info->framelen = (long) (FRAME_TIME * info->tta_hdr.SampleRate);
	int channels = info->tta_hdr.NumChannels;
	info->bytesPerFrame = info->framelen * 4 * channels;
	info->isFloat = (info->tta_hdr.AudioFormat == WAVE_FORMAT_IEEE_FLOAT);
	info->channels_real = channels;
	
	info->lastlen = info->tta_hdr.DataLength % info->framelen;
	info->fframes = info->tta_hdr.DataLength / info->framelen + (info->lastlen ? 1 : 0);
	st_size = (info->fframes + 1);
	info->st_state = 0;
	channels <<= info->isFloat;
	
	info->bps = bytesPerSample;
	info->samplerate = sampleRate;
	info->channels = channels;
	info->totalFrames = info->tta_hdr.DataLength;
	
	// grab some space for a buffer
	info->data = (long *) tta_malloc(channels * info->framelen, sizeof(long));
	info->enc = info->tta = tta_malloc(channels, sizeof(encoder));
	info->seek_table = (unsigned long *) tta_malloc(st_size, sizeof(long));
	
	info->internal_buffer = malloc(info->bytesPerFrame);
	info->internal_buffer_p = info->internal_buffer;
	info->bufferRest = 0;

	// read seek table
	if (fread(info->seek_table, st_size, sizeof(long), info->fdin) == 0) {
		fclose(info->fdin);
		return -1;
	}
	else info->input_byte_count += st_size * sizeof(long);

	checksum = crc32((unsigned char *) info->seek_table, 
		(st_size - 1) * sizeof(long));
	if (checksum != ENDSWAP_INT32(info->seek_table[st_size - 1]))
		fwprintf(stdout, L"Decode:  warning, seek table corrupted\r\n");
	else info->st_state = 1;

	for (info->st = info->seek_table; info->st < (info->seek_table + st_size); (info->st)++)
		*(info->st) = ENDSWAP_INT32(*(info->st));
	
	info->data_offset = info->input_byte_count + len;
	init_buffer_read(info->input_byte_count, info);

	info->st = info->seek_table;
	
	info->bufferRest = 0;
	
	return 0;
}

int decode_sample(ttainfo *info, unsigned char *outbuf, int bytes)
{
	unsigned long depth, k, unary, binary;
	long *p, value;
	unsigned char *outbuf_p = outbuf;
	int bytesCopied = 0, repeat, bytesToCopy;
	
	if(info->finish) return 0;
	
	if(info->bufferRest) {
		if(bytes >= info->bufferRest) memcpy(outbuf, info->internal_buffer_p, info->bufferRest);
		else {
			memcpy(outbuf, info->internal_buffer_p, bytes);
			info->bufferRest -= bytes;
			info->internal_buffer_p += bytes;
			return bytes;
		}
		outbuf_p += info->bufferRest;
	}
	bytesCopied += info->bufferRest;
	bytes -= info->bufferRest;
	repeat = bytes / info->bytesPerFrame + 1;
	info->bufferRest = 0;
	info->internal_buffer_p = info->internal_buffer;
	
	while(repeat--) {
		if(info->fframes == 0) goto done;
		(info->fframes)--;
		
		int framelen;
		if (!(info->fframes) && info->lastlen) framelen = info->lastlen;
		else framelen = info->framelen;
		
		encoder_init(info->tta, info->channels, info->bps);
		for (p = info->data; p < info->data + framelen * info->channels; p++) {
			fltst *fst = &(info->enc->fst);
			adapt *rice = &(info->enc->rice);
			long *last = &(info->enc->last);

			// decode Rice unsigned
			get_unary(&unary, info);
			
			switch (unary) {
			case 0: depth = 0; k = rice->k0; break;
			default:
					depth = 1; k = rice->k1;
					unary--;
			}

			if (k) {
				get_binary(&binary, k, info);
				value = (unary << k) + binary;
			} else value = unary;

			switch (depth) {
			case 1: 
				rice->sum1 += value - (rice->sum1 >> 4);
				if (rice->k1 > 0 && rice->sum1 < shift_16[rice->k1])
					rice->k1--;
				else if (rice->sum1 > shift_16[rice->k1 + 1])
					rice->k1++;
				value += bit_shift[rice->k0];
			default:
				rice->sum0 += value - (rice->sum0 >> 4);
				if (rice->k0 > 0 && rice->sum0 < shift_16[rice->k0])
					rice->k0--;
				else if (rice->sum0 > shift_16[rice->k0 + 1])
				rice->k0++;
			}
			
			*p = DEC(value);

			// decompress stage 1: adaptive hybrid filter
			hybrid_filter(fst, p, 0);

			// decompress stage 2: fixed order 1 prediction
			switch (info->bps) {
			case 1: *p += PREDICTOR1(*last, 4); break;	// bps 8
			case 2: *p += PREDICTOR1(*last, 5); break;	// bps 16
			case 3: *p += PREDICTOR1(*last, 5); break;	// bps 24
			case 4: *p += *last; break;		// bps 32
			} *last = *p;

			// combine data
			if (info->isFloat && ((p - info->data) & 1)) {
				unsigned long negative = *p & 0x80000000;
				unsigned long data_hi = *(p - 1);
				unsigned long data_lo = abs(*p) - 1;

				data_hi += (data_hi || data_lo) ? 0x3F80 : 0;
				*(p - 1) = (data_hi << 16) | SWAP16(data_lo) | negative;
			}

			if (info->enc < info->tta + info->channels - 1) info->enc++;
			else {
				if (!info->isFloat && info->channels > 1) {
					long *r = p - 1;
					for (*p += *r/2; r > p - info->channels; r--)
						*r = *(r + 1) - *r;
				}
				info->enc = info->tta;
			}
		}

		info->lastpos += *(info->st)++;

		if (done_buffer_read(info)) {
			if (info->st_state) {
				fwprintf(stdout, L"Decode:  checksum error, %ld samples wiped\r\n", framelen);
				memset(info->data, 0, info->channels * framelen * sizeof(long));
				fseeko(info->fdin, info->lastpos, SEEK_SET);
				init_buffer_read(info->lastpos, info);
			} else {
				bytesCopied = -1;
				goto error;
			}
			fflush(stderr);
		}
		
		
		bytesToCopy = framelen * 4 * info->channels_real;
		if(repeat == 0 && (bytes - bytesToCopy < 0)) {
			if(info->bps == 4) {
				int i;
				for(i=0;i<(bytesToCopy-bytes)/4;i++) {
					*((int *)info->internal_buffer_p+i) = *((int *)((unsigned char*)info->data+bytes*2)+i*2);
				}
			}
			else memcpy(info->internal_buffer_p,(unsigned char*)info->data+bytes,bytesToCopy-bytes);
			info->bufferRest = bytesToCopy-bytes;
			bytesToCopy = bytes;
		}
		
		if(info->bps == 4) {
			int i;
			for(i=0;i<bytesToCopy/4;i++) {
				*((int *)outbuf_p+i) = *(info->data+i*2);
			}
		}
		else memcpy(outbuf_p, info->data, bytesToCopy);
		bytesCopied += bytesToCopy;
		outbuf_p += bytesToCopy;
		bytes -= bytesToCopy;
		
	}
	
done:	
	return bytesCopied;

error:
	info->finish = 1;
	free(info->seek_table);
	free(info->data);
	free(info->tta);
	free(info->internal_buffer);
	fclose(info->fdin);
	return bytesCopied;
}

xldoffset_t seek_tta(ttainfo *info, xldoffset_t pos)
{
	int i;
	int frame_length = FRAME_TIME*info->samplerate;
	int frame = pos/frame_length;
	int bytesToRead = (pos%frame_length)*4*info->channels_real;
	xldoffset_t seek_pos = info->data_offset;
	for(i=0;i<frame;i++) {
		seek_pos += info->seek_table[i];
	}
	
	//printf("%d,%d,%d\n",data_offset,seek_pos,bytesToRead);
	if(fseeko(info->fdin,seek_pos,SEEK_SET) == -1) return -1;
	info->bufferRest = 0;
	init_buffer_read(seek_pos, info);
	info->fframes = info->tta_hdr.DataLength / frame_length + (info->lastlen ? 1 : 0) - frame;
	if(bytesToRead) {
		unsigned char *buf = (unsigned char*)malloc(bytesToRead);
		if(decode_sample(info,buf,bytesToRead) == -1) pos = -1;
		free(buf);
	}
	return pos;
}

void clean_tta_decoder(ttainfo *info)
{
	if(info->finish) return;
	free(info->seek_table);
	free(info->data);
	free(info->tta);
	free(info->internal_buffer);
	fclose(info->fdin);
	info->finish = 1;
}