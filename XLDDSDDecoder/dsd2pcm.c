/*

Copyright 2009, 2011 Sebastian Gesemann. All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are
permitted provided that the following conditions are met:

   1. Redistributions of source code must retain the above copyright notice, this list of
      conditions and the following disclaimer.

   2. Redistributions in binary form must reproduce the above copyright notice, this list
      of conditions and the following disclaimer in the documentation and/or other materials
      provided with the distribution.

THIS SOFTWARE IS PROVIDED BY SEBASTIAN GESEMANN ''AS IS'' AND ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL SEBASTIAN GESEMANN OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

The views and conclusions contained in the software and documentation are those of the
authors and should not be interpreted as representing official policies, either expressed
or implied, of Sebastian Gesemann.

 */

#include <stdlib.h>
#include <string.h>

#include "dsd2pcm.h"

#define FIFOSIZE 32             /* must be a power of two */
#define FIFOMASK (FIFOSIZE-1)   /* bit mask for FIFO offsets */

#include "filters.h"

struct dsd2pcm_ctx_s
{
	unsigned char fifo[FIFOSIZE];
	unsigned fifopos;
	unsigned int numTables;
	float **ctables;
	unsigned char bitreverse[256];
	int decimation;
};

static void precalc(dsd2pcm_ctx *ctx, const double *htaps, int numCoeffs)
{
	int t, e, m, k;
	double acc;
	for (t=0, e=0; t<256; ++t) {
		ctx->bitreverse[t] = e;
		for (m=128; m && !((e^=m)&m); m>>=1)
			;
	}
	for (t=0; t<ctx->numTables; ++t) {
		k = numCoeffs - t*8;
		if (k>8) k=8;
		for (e=0; e<256; ++e) {
			acc = 0.0;
			for (m=0; m<k; ++m) {
				acc += (((e >> (7-m)) & 1)*2-1) * htaps[t*8+m];
			}
			ctx->ctables[ctx->numTables-1-t][e] = (float)acc;
		}
	}
}

extern dsd2pcm_ctx* dsd2pcm_init(int decimation)
{
	dsd2pcm_ctx* ptr;
	ptr = (dsd2pcm_ctx*) malloc(sizeof(dsd2pcm_ctx));
	if (ptr) {
		int i;
		int numCoeffs;
		const double *htaps;
		if(decimation == 8) {
			numCoeffs = 48;
			htaps = htaps_8to1;
			ptr->decimation = 8;
		}
		else if(decimation == 16) {
			numCoeffs = 120;
			htaps = htaps_16to1;
			ptr->decimation = 16;
		}
		else {
			numCoeffs = 48;
			htaps = htaps_8to1;
			ptr->decimation = 8;
		}
		
		ptr->numTables = (numCoeffs+7)/8;
		ptr->ctables = (float **)malloc(sizeof(float *) * ptr->numTables);
		for(i=0;i<ptr->numTables;i++) {
			ptr->ctables[i] = (float *)malloc(sizeof(float) * 256);
		}
		precalc(ptr, htaps, numCoeffs);
		dsd2pcm_reset(ptr);
	}
	return ptr;
}

extern void dsd2pcm_destroy(dsd2pcm_ctx* ptr)
{
	int i;
	for(i=0;i<ptr->numTables;i++) {
		free(ptr->ctables[i]);
	}
	free(ptr->ctables);
	free(ptr);
}

extern dsd2pcm_ctx* dsd2pcm_clone(dsd2pcm_ctx* ptr)
{
	dsd2pcm_ctx* p2;
	p2 = (dsd2pcm_ctx*) malloc(sizeof(dsd2pcm_ctx));
	if (p2) {
		memcpy(p2,ptr,sizeof(dsd2pcm_ctx));
	}
	return p2;
}

extern void dsd2pcm_reset(dsd2pcm_ctx* ptr)
{
	int i;
	for (i=0; i<FIFOSIZE; ++i)
		ptr->fifo[i] = 0x69; /* my favorite silence pattern */
	ptr->fifopos = 0;
	/* 0x69 = 01101001
	 * This pattern "on repeat" makes a low energy 352.8 kHz tone
	 * and a high energy 1.0584 MHz tone which should be filtered
	 * out completely by any playback system --> silence
	 */
}

extern void dsd2pcm_translate(
	dsd2pcm_ctx* ptr,
	size_t samples,
	const unsigned char *src, ptrdiff_t src_stride,
	int lsbf,
	float *dst, ptrdiff_t dst_stride)
{
	unsigned ffp;
	unsigned i;
	unsigned bite1, bite2;
	unsigned char* p;
	double acc;
	int numTables;
	int bitsRead = 0;
	int decimation = ptr->decimation;
	ffp = ptr->fifopos;
	numTables = ptr->numTables;
	lsbf = lsbf ? 1 : 0;
	while (samples > 0) {
		bite1 = *src & 0xFFu;
		if (lsbf) bite1 = ptr->bitreverse[bite1];
		ptr->fifo[ffp] = bite1; src += src_stride;
		p = ptr->fifo + ((ffp-numTables) & FIFOMASK);
		*p = ptr->bitreverse[*p & 0xFF];
		acc = 0;
		for (i=0; i<numTables; ++i) {
			bite1 = ptr->fifo[(ffp              -i) & FIFOMASK] & 0xFF;
			bite2 = ptr->fifo[(ffp-(numTables*2-1)+i) & FIFOMASK] & 0xFF;
			acc += ptr->ctables[i][bite1] + ptr->ctables[i][bite2];
		}
		bitsRead += 8;
		if(bitsRead == decimation) {
			*dst = (float)acc; dst += dst_stride;
			bitsRead = 0;
			samples--;
		}
		ffp = (ffp + 1) & FIFOMASK;
	}
	ptr->fifopos = ffp;
}

