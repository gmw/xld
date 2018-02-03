//
//  deltasigma.c
//  XLDDSDOutput
//
//  Created by tmkk on 15/01/24.
//
//	Copyright (c) 2015 tmkk <xld at tmkk.undo.jp> 
//
//	Permission is hereby granted, free of charge, to any person obtaining a copy
//	of this software and associated documentation files (the "Software"), to deal
//	in the Software without restriction, including without limitation the rights
//	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//	copies of the Software, and to permit persons to whom the Software is
//	furnished to do so, subject to the following conditions:
//
//	The above copyright notice and this permission notice shall be included in
//	all copies or substantial portions of the Software.
//
//	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//	THE SOFTWARE.

#include "deltasigma.h"
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#define SCALE 0.5

#if defined(__i386__) || defined(__x86_64__)
#include <emmintrin.h>
#define USE_SSE 1
#endif

static const double consts_pool[] __attribute__((aligned(16))) = {1.0, -1.0, SCALE};
static const float zeros[32];

static const double shaper_coeffs_4th_b[] __attribute__((aligned(16))) = {8.023196099167440e-01, -2.100688172255984e+00, 1.858934365160060e+00, -5.543744282860277e-01};
static const double shaper_coeffs_4th_a[] __attribute__((aligned(16))) = {-3.196966782800000e+00, 3.897884613177504e+00, -2.140352027556684e+00, 4.456255717139723e-01};

static const double shaper_coeffs_6th_b[] __attribute__((aligned(16))) = {8.165482584454580e-01, -3.739348270553497e+00, 6.876758658077048e+00, -6.345865412531847e+00, 2.937512250132895e+00, -5.455108751771455e-01};
static const double shaper_coeffs_6th_a[] __attribute__((aligned(16))) = {-5.181249367400000e+00, 1.125184316831121e+01, -1.311002896796145e+01, 8.645326026332860e+00, -3.060285375712562e+00, 4.544891248228545e-01};

static const double shaper_coeffs_8th_b[] __attribute__((aligned(16))) = {8.036523104430531e-01, -5.294484548544922e+00, 1.497412386332955e+01, -2.356658330575455e+01, 2.228874261804205e+01, -1.266723038877453e+01, 4.005297650249176e+00, -5.435177297167231e-01};
static const double shaper_coeffs_8th_a[] __attribute__((aligned(16))) = {-7.193145776600000e+00, 2.268630685861116e+01, -4.097785898127190e+01, 4.636939574322227e+01, -3.366324022655938e+01, 1.531356101838154e+01, -3.991500436793876e+00, 4.564822702832769e-01};

static int deltasigma_2nd(xld_deltasigma_t *dsm, const float* in, unsigned char *out, int numSamples, int stride);
static int deltasigma_2nd_dsf(xld_deltasigma_t *dsm, const float* in, unsigned char *out, int numSamples, int stride);
static int deltasigma_4th(xld_deltasigma_t *dsm, const float* in, unsigned char *out, int numSamples, int stride);
static int deltasigma_4th_dsf(xld_deltasigma_t *dsm, const float* in, unsigned char *out, int numSamples, int stride);
static int deltasigma_6th(xld_deltasigma_t *dsm, const float* in, unsigned char *out, int numSamples, int stride);
static int deltasigma_6th_dsf(xld_deltasigma_t *dsm, const float* in, unsigned char *out, int numSamples, int stride);
static int deltasigma_8th(xld_deltasigma_t *dsm, const float* in, unsigned char *out, int numSamples, int stride);
static int deltasigma_8th_dsf(xld_deltasigma_t *dsm, const float* in, unsigned char *out, int numSamples, int stride);
static int deltasigma_finalize(xld_deltasigma_t *dsm, unsigned char *out);

xld_deltasigma_t *deltasigma_init(DSDFileFormat format, DSMNoiseShapingType type)
{
	xld_deltasigma_t *dsm = malloc(sizeof(xld_deltasigma_t));
	dsm->buffer = calloc(sizeof(double), 8);
	dsm->idx = 0;
	dsm->bitBuf = 0;
	dsm->bitBufMeter = 0;
	switch(type) {
		case 2:
			if(format == DSDFileFormatDSF) dsm->modulate = deltasigma_2nd_dsf;
			else dsm->modulate = deltasigma_2nd;
			break;
		case 4:
			if(format == DSDFileFormatDSF) dsm->modulate = deltasigma_4th_dsf;
			else dsm->modulate = deltasigma_4th;
			break;
		case 6:
			if(format == DSDFileFormatDSF) dsm->modulate = deltasigma_6th_dsf;
			else dsm->modulate = deltasigma_6th;
			break;
		case 8:
			if(format == DSDFileFormatDSF) dsm->modulate = deltasigma_8th_dsf;
			else dsm->modulate = deltasigma_8th;
			break;
		default:
			if(format == DSDFileFormatDSF) dsm->modulate = deltasigma_6th_dsf;
			else dsm->modulate = deltasigma_6th;
			break;
	}
	dsm->finalize = deltasigma_finalize;
	return dsm;
}

void deltasigma_free(xld_deltasigma_t *dsm)
{
	free(dsm->buffer);
	free(dsm);
}

static int deltasigma_finalize(xld_deltasigma_t *dsm, unsigned char *out)
{
	//fprintf(stderr,"%d\n",dsm->bitBufMeter);
	if(!dsm->bitBufMeter) return 0;
	
	int remaining = 8 - dsm->bitBufMeter;
	return dsm->modulate(dsm, zeros, out, remaining, 1);
}

static int deltasigma_2nd(xld_deltasigma_t *dsm, const float* in, unsigned char *out, int numSamples, int stride)
{
	int i;
	int idx = dsm->idx;
	unsigned int bitBuf = dsm->bitBuf;
	unsigned int bitBufMeter = dsm->bitBufMeter;
	int written = 0;
	for(i=0;i<numSamples;i++) {
		double sample = *in * SCALE + dsm->buffer[idx&1]*2.0 - dsm->buffer[(idx+1)&1];
		double err;
		if(sample < 0) {
			bitBuf = bitBuf << 1;
			err = sample + 1.0;
		}
		else {
			bitBuf = (bitBuf << 1) | 1;
			err = sample - 1.0;
		}
		idx = (idx+1) & 1;
		dsm->buffer[idx&1] = err;
		in += stride;
		
		if(++bitBufMeter == 8) {
			*out = bitBuf;
			bitBuf = 0;
			written++;
			bitBufMeter = 0;
			out += stride;
		}
	}
	dsm->idx = idx;
	dsm->bitBuf = bitBuf;
	dsm->bitBufMeter = bitBufMeter;
	return written;
}

static int deltasigma_2nd_dsf(xld_deltasigma_t *dsm, const float* in, unsigned char *out, int numSamples, int stride)
{
	int i;
	int idx = dsm->idx;
	unsigned int bitBuf = dsm->bitBuf;
	unsigned int bitBufMeter = dsm->bitBufMeter;
	int written = 0;
	for(i=0;i<numSamples;i++) {
		double sample = *in * SCALE + dsm->buffer[idx&1]*2.0 - dsm->buffer[(idx+1)&1];
		double err;
		if(sample < 0) {
			bitBuf = bitBuf >> 1;
			err = sample + 1.0;
		}
		else {
			bitBuf = (bitBuf >> 1) | 0x80;
			err = sample - 1.0;
		}
		idx = (idx+1) & 1;
		dsm->buffer[idx&1] = err;
		in += stride;
		
		if(++bitBufMeter == 8) {
			*out = bitBuf;
			bitBuf = 0;
			written++;
			bitBufMeter = 0;
			out++;
		}
	}
	dsm->idx = idx;
	dsm->bitBuf = bitBuf;
	dsm->bitBufMeter = bitBufMeter;
	return written;
}

static int deltasigma_4th(xld_deltasigma_t *dsm, const float* in, unsigned char *out, int numSamples, int stride)
{
	int i;
	int idx = dsm->idx;
	unsigned int bitBuf = dsm->bitBuf;
	unsigned int bitBufMeter = dsm->bitBufMeter;
	int written = 0;
	
#if USE_SSE
	__m128d v0, v1, v2, v3, v4, v5, v6, v7;
	v6 = (__m128d)_mm_load_ps((float *)dsm->buffer);
	v7 = (__m128d)_mm_load_ps((float *)(dsm->buffer+2));
	for(i=0;i<numSamples;i++) {
		v0 = v6;
		v1 = v7;
		v2 = v6;
		v3 = v7;
		v0 = _mm_mul_pd(v0, *(__m128d*)shaper_coeffs_4th_b);
		v1 = _mm_mul_pd(v1, *(__m128d*)(shaper_coeffs_4th_b+2));
		v2 = _mm_mul_pd(v2, *(__m128d*)shaper_coeffs_4th_a);
		v3 = _mm_mul_pd(v3, *(__m128d*)(shaper_coeffs_4th_a+2));
		v0 = _mm_add_pd(v0, v1);
		v2 = _mm_add_pd(v2, v3);
		v4 = _mm_cvtss_sd(v4, *(__m128*)(in));
		v1 = (__m128d)_mm_movehl_ps((__m128)v1, (__m128)v0);
		v3 = (__m128d)_mm_movehl_ps((__m128)v3, (__m128)v2);
		v0 = _mm_add_sd(v0, v1);
		v2 = _mm_add_sd(v2, v3);
		v4 = _mm_mul_sd(v4, *(__m128d*)(consts_pool+2));
		v1 = (__m128d)_mm_setzero_ps();
		v0 = _mm_add_sd(v0, v4);
		v5 = v6;
		v6 = _mm_shuffle_pd(v6, v7, 0x1);
		v7 = v6;
		v1 = _mm_cmplt_pd(v1, v0); //1111 if plus
		v3 = _mm_load_sd(consts_pool+1);
		v6 = v0;
		v6 = _mm_sub_sd(v6, v2);
		v3 = (__m128d)_mm_and_ps((__m128)v3, (__m128)v1);
		v2 = v1;
		v1 = (__m128d)_mm_andnot_ps((__m128)v1, *(__m128*)(consts_pool));
		v1 = (__m128d)_mm_or_ps((__m128)v1, (__m128)v3);
		v6 = _mm_add_sd(v6, v1);
		unsigned int bit = _mm_cvtsi128_si32((__m128i)v2);
		v6 = _mm_unpacklo_pd(v6, v5);
		bitBuf = (bitBuf << 1) | (bit & 1);
		in += stride;
		
		if(++bitBufMeter == 8) {
			*out = bitBuf;
			bitBuf = 0;
			written++;
			bitBufMeter = 0;
			out += stride;
		}
	}
	_mm_store_ps((float *)dsm->buffer, (__m128)v6);
	_mm_store_ps((float *)(dsm->buffer+2), (__m128)v7);
#else
	for(i=0;i<numSamples;i++) {
		double quantizer_in = *in * SCALE +
					dsm->buffer[idx&3]     * shaper_coeffs_4th_b[0] +
					dsm->buffer[(idx-1)&3] * shaper_coeffs_4th_b[1] +
					dsm->buffer[(idx-2)&3] * shaper_coeffs_4th_b[2] +
					dsm->buffer[(idx-3)&3] * shaper_coeffs_4th_b[3];
		double next = 
					dsm->buffer[idx&3]     * shaper_coeffs_4th_a[0] +
					dsm->buffer[(idx-1)&3] * shaper_coeffs_4th_a[1] +
					dsm->buffer[(idx-2)&3] * shaper_coeffs_4th_a[2] +
					dsm->buffer[(idx-3)&3] * shaper_coeffs_4th_a[3];
		double err;
		if(quantizer_in < 0) {
			bitBuf = bitBuf << 1;
			err = quantizer_in + 1.0;
		}
		else {
			bitBuf = (bitBuf << 1) | 1;
			err = quantizer_in - 1.0;
		}
		
		idx = (idx+1) & 3;
		dsm->buffer[idx] = err - next;
		in += stride;
		
		if(++bitBufMeter == 8) {
			*out = bitBuf;
			bitBuf = 0;
			written++;
			bitBufMeter = 0;
			out += stride;
		}
	}
#endif
	dsm->idx = idx;
	dsm->bitBuf = bitBuf;
	dsm->bitBufMeter = bitBufMeter;
	return written;
}

static int deltasigma_4th_dsf(xld_deltasigma_t *dsm, const float* in, unsigned char *out, int numSamples, int stride)
{
	int i;
	int idx = dsm->idx;
	unsigned int bitBuf = dsm->bitBuf;
	unsigned int bitBufMeter = dsm->bitBufMeter;
	int written = 0;
	
#if USE_SSE
	__m128d v0, v1, v2, v3, v4, v5, v6, v7;
	v6 = (__m128d)_mm_load_ps((float *)dsm->buffer);
	v7 = (__m128d)_mm_load_ps((float *)(dsm->buffer+2));
	for(i=0;i<numSamples;i++) {
		v0 = v6;
		v1 = v7;
		v2 = v6;
		v3 = v7;
		v0 = _mm_mul_pd(v0, *(__m128d*)shaper_coeffs_4th_b);
		v1 = _mm_mul_pd(v1, *(__m128d*)(shaper_coeffs_4th_b+2));
		v2 = _mm_mul_pd(v2, *(__m128d*)shaper_coeffs_4th_a);
		v3 = _mm_mul_pd(v3, *(__m128d*)(shaper_coeffs_4th_a+2));
		v0 = _mm_add_pd(v0, v1);
		v2 = _mm_add_pd(v2, v3);
		v4 = _mm_cvtss_sd(v4, *(__m128*)(in));
		v1 = (__m128d)_mm_movehl_ps((__m128)v1, (__m128)v0);
		v3 = (__m128d)_mm_movehl_ps((__m128)v3, (__m128)v2);
		v0 = _mm_add_sd(v0, v1);
		v2 = _mm_add_sd(v2, v3);
		v4 = _mm_mul_sd(v4, *(__m128d*)(consts_pool+2));
		v1 = (__m128d)_mm_setzero_ps();
		v0 = _mm_add_sd(v0, v4);
		v5 = v6;
		v6 = _mm_shuffle_pd(v6, v7, 0x1);
		v7 = v6;
		v1 = _mm_cmplt_pd(v1, v0); //1111 if plus
		v3 = _mm_load_sd(consts_pool+1);
		v6 = v0;
		v6 = _mm_sub_sd(v6, v2);
		v3 = (__m128d)_mm_and_ps((__m128)v3, (__m128)v1);
		v2 = v1;
		v1 = (__m128d)_mm_andnot_ps((__m128)v1, *(__m128*)(consts_pool));
		v1 = (__m128d)_mm_or_ps((__m128)v1, (__m128)v3);
		v6 = _mm_add_sd(v6, v1);
		unsigned int bit = _mm_cvtsi128_si32((__m128i)v2);
		v6 = _mm_unpacklo_pd(v6, v5);
		bitBuf = (bitBuf >> 1) | (bit & 0x80);
		in += stride;
		
		if(++bitBufMeter == 8) {
			*out = bitBuf;
			bitBuf = 0;
			written++;
			bitBufMeter = 0;
			out++;
		}
	}
	_mm_store_ps((float *)dsm->buffer, (__m128)v6);
	_mm_store_ps((float *)(dsm->buffer+2), (__m128)v7);
#else
	for(i=0;i<numSamples;i++) {
		double quantizer_in = *in * SCALE +
					dsm->buffer[idx&3]     * shaper_coeffs_4th_b[0] +
					dsm->buffer[(idx-1)&3] * shaper_coeffs_4th_b[1] +
					dsm->buffer[(idx-2)&3] * shaper_coeffs_4th_b[2] +
					dsm->buffer[(idx-3)&3] * shaper_coeffs_4th_b[3];
		double next = 
					dsm->buffer[idx&3]     * shaper_coeffs_4th_a[0] +
					dsm->buffer[(idx-1)&3] * shaper_coeffs_4th_a[1] +
					dsm->buffer[(idx-2)&3] * shaper_coeffs_4th_a[2] +
					dsm->buffer[(idx-3)&3] * shaper_coeffs_4th_a[3];
		double err;
		if(quantizer_in < 0) {
			bitBuf = bitBuf >> 1;
			err = quantizer_in + 1.0;
		}
		else {
			bitBuf = (bitBuf >> 1) | 0x80;
			err = quantizer_in - 1.0;
		}
		
		idx = (idx+1) & 3;
		dsm->buffer[idx] = err - next;
		in += stride;
		
		if(++bitBufMeter == 8) {
			*out = bitBuf;
			bitBuf = 0;
			written++;
			bitBufMeter = 0;
			out++;
		}
	}
#endif
	dsm->idx = idx;
	dsm->bitBuf = bitBuf;
	dsm->bitBufMeter = bitBufMeter;
	return written;
}

static int deltasigma_6th(xld_deltasigma_t *dsm, const float* in, unsigned char *out, int numSamples, int stride)
{
	int i;
	int idx = dsm->idx;
	unsigned int bitBuf = dsm->bitBuf;
	unsigned int bitBufMeter = dsm->bitBufMeter;
	int written = 0;
#if USE_SSE
	__m128d v0, v1, v2, v3, v4, v5, v6, v7;
	v5 = (__m128d)_mm_load_ps((float *)dsm->buffer);
	v6 = (__m128d)_mm_load_ps((float *)(dsm->buffer+2));
	v7 = (__m128d)_mm_load_ps((float *)(dsm->buffer+4));
	for(i=0;i<numSamples;i++) {
		v0 = v5;
		v1 = v6;
		v2 = v5;
		v3 = v6;
		v0 = _mm_mul_pd(v0, *(__m128d*)shaper_coeffs_6th_b);
		v1 = _mm_mul_pd(v1, *(__m128d*)(shaper_coeffs_6th_b+2));
		v2 = _mm_mul_pd(v2, *(__m128d*)shaper_coeffs_6th_a);
		v3 = _mm_mul_pd(v3, *(__m128d*)(shaper_coeffs_6th_a+2));
		v0 = _mm_add_pd(v0, v1);
		v2 = _mm_add_pd(v2, v3);
		v1 = v7;
		v3 = v7;
		v1 = _mm_mul_pd(v1, *(__m128d*)(shaper_coeffs_6th_b+4));
		v3 = _mm_mul_pd(v3, *(__m128d*)(shaper_coeffs_6th_a+4));
		v4 = _mm_cvtss_sd(v4, *(__m128*)(in));
		v0 = _mm_add_pd(v0, v1);
		v2 = _mm_add_pd(v2, v3);
		v1 = (__m128d)_mm_movehl_ps((__m128)v1, (__m128)v0);
		v3 = (__m128d)_mm_movehl_ps((__m128)v3, (__m128)v2);
		v0 = _mm_add_sd(v0, v1);
		v2 = _mm_add_sd(v2, v3);
		v4 = _mm_mul_sd(v4, *(__m128d*)(consts_pool+2));
		v1 = (__m128d)_mm_setzero_ps();
		v0 = _mm_add_sd(v0, v4);
		v4 = v5;
		v5 = _mm_shuffle_pd(v5, v6, 0x1);
		v6 = _mm_shuffle_pd(v6, v7, 0x1);
		v7 = v6;
		v6 = v5;
		v1 = _mm_cmplt_pd(v1, v0); //1111 if plus
		v3 = _mm_load_sd(consts_pool+1);
		v5 = v0;
		v5 = _mm_sub_sd(v5, v2);
		v3 = (__m128d)_mm_and_ps((__m128)v3, (__m128)v1);
		v2 = v1;
		v1 = (__m128d)_mm_andnot_ps((__m128)v1, *(__m128*)(consts_pool));
		v1 = (__m128d)_mm_or_ps((__m128)v1, (__m128)v3);
		v5 = _mm_add_sd(v5, v1);
		unsigned int bit = _mm_cvtsi128_si32((__m128i)v2);
		v5 = _mm_unpacklo_pd(v5, v4);
		bitBuf = (bitBuf << 1) | (bit & 1);
		in += stride;
		
		if(++bitBufMeter == 8) {
			*out = bitBuf;
			bitBuf = 0;
			written++;
			bitBufMeter = 0;
			out += stride;
		}
	}
	_mm_store_ps((float *)dsm->buffer, (__m128)v5);
	_mm_store_ps((float *)(dsm->buffer+2), (__m128)v6);
	_mm_store_ps((float *)(dsm->buffer+4), (__m128)v7);
#else
	for(i=0;i<numSamples;i++) {
		double quantizer_in = *in * SCALE +
					dsm->buffer[idx&7]     * shaper_coeffs_6th_b[0] +
					dsm->buffer[(idx-1)&7] * shaper_coeffs_6th_b[1] +
					dsm->buffer[(idx-2)&7] * shaper_coeffs_6th_b[2] +
					dsm->buffer[(idx-3)&7] * shaper_coeffs_6th_b[3] +
					dsm->buffer[(idx-4)&7] * shaper_coeffs_6th_b[4] +
					dsm->buffer[(idx-5)&7] * shaper_coeffs_6th_b[5];
		double next =
					dsm->buffer[idx&7]     * shaper_coeffs_6th_a[0] +
					dsm->buffer[(idx-1)&7] * shaper_coeffs_6th_a[1] +
					dsm->buffer[(idx-2)&7] * shaper_coeffs_6th_a[2] +
					dsm->buffer[(idx-3)&7] * shaper_coeffs_6th_a[3] +
					dsm->buffer[(idx-4)&7] * shaper_coeffs_6th_a[4] +
					dsm->buffer[(idx-5)&7] * shaper_coeffs_6th_a[5];
		double err;
		if(quantizer_in < 0) {
			bitBuf = bitBuf << 1;
			err = quantizer_in + 1.0;
		}
		else {
			bitBuf = (bitBuf << 1) | 1;
			err = quantizer_in - 1.0;
		}
		
		idx = (idx+1) & 7;
		dsm->buffer[idx] = err - next;
		in += stride;

		if(++bitBufMeter == 8) {
			*out = bitBuf;
			bitBuf = 0;
			written++;
			bitBufMeter = 0;
			out += stride;
		}
	}
#endif
	dsm->idx = idx;
	dsm->bitBuf = bitBuf;
	dsm->bitBufMeter = bitBufMeter;
	return written;
}

static int deltasigma_6th_dsf(xld_deltasigma_t *dsm, const float* in, unsigned char *out, int numSamples, int stride)
{
	int i;
	int idx = dsm->idx;
	unsigned int bitBuf = dsm->bitBuf;
	unsigned int bitBufMeter = dsm->bitBufMeter;
	int written = 0;
#if USE_SSE
	__m128d v0, v1, v2, v3, v4, v5, v6, v7;
	v5 = (__m128d)_mm_load_ps((float *)dsm->buffer);
	v6 = (__m128d)_mm_load_ps((float *)(dsm->buffer+2));
	v7 = (__m128d)_mm_load_ps((float *)(dsm->buffer+4));
	for(i=0;i<numSamples;i++) {
		v0 = v5;
		v1 = v6;
		v2 = v5;
		v3 = v6;
		v0 = _mm_mul_pd(v0, *(__m128d*)shaper_coeffs_6th_b);
		v1 = _mm_mul_pd(v1, *(__m128d*)(shaper_coeffs_6th_b+2));
		v2 = _mm_mul_pd(v2, *(__m128d*)shaper_coeffs_6th_a);
		v3 = _mm_mul_pd(v3, *(__m128d*)(shaper_coeffs_6th_a+2));
		v0 = _mm_add_pd(v0, v1);
		v2 = _mm_add_pd(v2, v3);
		v1 = v7;
		v3 = v7;
		v1 = _mm_mul_pd(v1, *(__m128d*)(shaper_coeffs_6th_b+4));
		v3 = _mm_mul_pd(v3, *(__m128d*)(shaper_coeffs_6th_a+4));
		v4 = _mm_cvtss_sd(v4, *(__m128*)(in));
		v0 = _mm_add_pd(v0, v1);
		v2 = _mm_add_pd(v2, v3);
		v1 = (__m128d)_mm_movehl_ps((__m128)v1, (__m128)v0);
		v3 = (__m128d)_mm_movehl_ps((__m128)v3, (__m128)v2);
		v0 = _mm_add_sd(v0, v1);
		v2 = _mm_add_sd(v2, v3);
		v4 = _mm_mul_sd(v4, *(__m128d*)(consts_pool+2));
		v1 = (__m128d)_mm_setzero_ps();
		v0 = _mm_add_sd(v0, v4);
		v4 = v5;
		v5 = _mm_shuffle_pd(v5, v6, 0x1);
		v6 = _mm_shuffle_pd(v6, v7, 0x1);
		v7 = v6;
		v6 = v5;
		v1 = _mm_cmplt_pd(v1, v0); //1111 if plus
		v3 = _mm_load_sd(consts_pool+1);
		v5 = v0;
		v5 = _mm_sub_sd(v5, v2);
		v3 = (__m128d)_mm_and_ps((__m128)v3, (__m128)v1);
		v2 = v1;
		v1 = (__m128d)_mm_andnot_ps((__m128)v1, *(__m128*)(consts_pool));
		v1 = (__m128d)_mm_or_ps((__m128)v1, (__m128)v3);
		v5 = _mm_add_sd(v5, v1);
		unsigned int bit = _mm_cvtsi128_si32((__m128i)v2);
		v5 = _mm_unpacklo_pd(v5, v4);
		bitBuf = (bitBuf >> 1) | (bit & 0x80);
		in += stride;
		
		if(++bitBufMeter == 8) {
			*out = bitBuf;
			bitBuf = 0;
			written++;
			bitBufMeter = 0;
			out++;
		}
	}
	_mm_store_ps((float *)dsm->buffer, (__m128)v5);
	_mm_store_ps((float *)(dsm->buffer+2), (__m128)v6);
	_mm_store_ps((float *)(dsm->buffer+4), (__m128)v7);
#else
	for(i=0;i<numSamples;i++) {
		double quantizer_in = *in * SCALE +
					dsm->buffer[idx&7]     * shaper_coeffs_6th_b[0] +
					dsm->buffer[(idx-1)&7] * shaper_coeffs_6th_b[1] +
					dsm->buffer[(idx-2)&7] * shaper_coeffs_6th_b[2] +
					dsm->buffer[(idx-3)&7] * shaper_coeffs_6th_b[3] +
					dsm->buffer[(idx-4)&7] * shaper_coeffs_6th_b[4] +
					dsm->buffer[(idx-5)&7] * shaper_coeffs_6th_b[5];
		double next =
					dsm->buffer[idx&7]     * shaper_coeffs_6th_a[0] +
					dsm->buffer[(idx-1)&7] * shaper_coeffs_6th_a[1] +
					dsm->buffer[(idx-2)&7] * shaper_coeffs_6th_a[2] +
					dsm->buffer[(idx-3)&7] * shaper_coeffs_6th_a[3] +
					dsm->buffer[(idx-4)&7] * shaper_coeffs_6th_a[4] +
					dsm->buffer[(idx-5)&7] * shaper_coeffs_6th_a[5];
		double err;
		if(quantizer_in < 0) {
			bitBuf = bitBuf >> 1;
			err = quantizer_in + 1.0;
		}
		else {
			bitBuf = (bitBuf >> 1) | 0x80;
			err = quantizer_in - 1.0;
		}
		
		idx = (idx+1) & 7;
		dsm->buffer[idx] = err - next;
		in += stride;
		if(++bitBufMeter == 8) {
			*out = bitBuf;
			bitBuf = 0;
			written++;
			bitBufMeter = 0;
			out++;
		}
	}
#endif
	dsm->idx = idx;
	dsm->bitBuf = bitBuf;
	dsm->bitBufMeter = bitBufMeter;
	return written;
}

static int deltasigma_8th(xld_deltasigma_t *dsm, const float* in, unsigned char *out, int numSamples, int stride)
{
	int i;
	int idx = dsm->idx;
	unsigned int bitBuf = dsm->bitBuf;
	unsigned int bitBufMeter = dsm->bitBufMeter;
	int written = 0;
#if USE_SSE
	__m128d v0, v1, v2, v3, v4, v5, v6, v7;
	v5 = (__m128d)_mm_load_ps((float *)dsm->buffer);
	v6 = (__m128d)_mm_load_ps((float *)(dsm->buffer+2));
	v7 = (__m128d)_mm_load_ps((float *)(dsm->buffer+4));
	for(i=0;i<numSamples;i++) {
		v0 = v5;
		v1 = v6;
		v2 = v5;
		v3 = v6;
		v0 = _mm_mul_pd(v0, *(__m128d*)shaper_coeffs_8th_b);
		v1 = _mm_mul_pd(v1, *(__m128d*)(shaper_coeffs_8th_b+2));
		v2 = _mm_mul_pd(v2, *(__m128d*)shaper_coeffs_8th_a);
		v3 = _mm_mul_pd(v3, *(__m128d*)(shaper_coeffs_8th_a+2));
		v0 = _mm_add_pd(v0, v1);
		v2 = _mm_add_pd(v2, v3);
		v1 = v7;
		v3 = v7;
		v1 = _mm_mul_pd(v1, *(__m128d*)(shaper_coeffs_8th_b+4));
		v3 = _mm_mul_pd(v3, *(__m128d*)(shaper_coeffs_8th_a+4));
		v0 = _mm_add_pd(v0, v1);
		v2 = _mm_add_pd(v2, v3);
		v4 = (__m128d)_mm_load_ps((float *)(dsm->buffer+6));
		v1 = v4;
		v3 = v4;
		v1 = _mm_mul_pd(v1, *(__m128d*)(shaper_coeffs_8th_b+6));
		v3 = _mm_mul_pd(v3, *(__m128d*)(shaper_coeffs_8th_a+6));
		v0 = _mm_add_pd(v0, v1);
		v2 = _mm_add_pd(v2, v3);
		v1 = (__m128d)_mm_movehl_ps((__m128)v1, (__m128)v0);
		v3 = (__m128d)_mm_movehl_ps((__m128)v3, (__m128)v2);
		v0 = _mm_add_sd(v0, v1);
		v2 = _mm_add_sd(v2, v3);
		v3 = v5;
		v5 = _mm_shuffle_pd(v5, v6, 0x1);
		v6 = _mm_shuffle_pd(v6, v7, 0x1);
		v7 = _mm_shuffle_pd(v7, v4, 0x1);
		_mm_store_ps((float *)(dsm->buffer+6), (__m128)v7);
		v7 = v6;
		v6 = v5;
		v4 = _mm_cvtss_sd(v4, *(__m128*)(in));
		v4 = _mm_mul_sd(v4, *(__m128d*)(consts_pool+2));
		v1 = (__m128d)_mm_setzero_ps();
		v0 = _mm_add_sd(v0, v4);
		v1 = _mm_cmplt_pd(v1, v0); //1111 if plus
		v4 = v3;
		v3 = _mm_load_sd(consts_pool+1);
		v5 = v0;
		v5 = _mm_sub_sd(v5, v2);
		v3 = (__m128d)_mm_and_ps((__m128)v3, (__m128)v1);
		v2 = v1;
		v1 = (__m128d)_mm_andnot_ps((__m128)v1, *(__m128*)(consts_pool));
		v1 = (__m128d)_mm_or_ps((__m128)v1, (__m128)v3);
		v5 = _mm_add_sd(v5, v1);
		unsigned int bit = _mm_cvtsi128_si32((__m128i)v2);
		v5 = _mm_unpacklo_pd(v5, v4);
		bitBuf = (bitBuf << 1) | (bit & 1);
		in += stride;
		
		if(++bitBufMeter == 8) {
			*out = bitBuf;
			bitBuf = 0;
			written++;
			bitBufMeter = 0;
			out += stride;
		}
	}
	_mm_store_ps((float *)dsm->buffer, (__m128)v5);
	_mm_store_ps((float *)(dsm->buffer+2), (__m128)v6);
	_mm_store_ps((float *)(dsm->buffer+4), (__m128)v7);
#else
	for(i=0;i<numSamples;i++) {
		double quantizer_in = *in * SCALE +
		dsm->buffer[idx&7]     * shaper_coeffs_8th_b[0] +
		dsm->buffer[(idx-1)&7] * shaper_coeffs_8th_b[1] +
		dsm->buffer[(idx-2)&7] * shaper_coeffs_8th_b[2] +
		dsm->buffer[(idx-3)&7] * shaper_coeffs_8th_b[3] +
		dsm->buffer[(idx-4)&7] * shaper_coeffs_8th_b[4] +
		dsm->buffer[(idx-5)&7] * shaper_coeffs_8th_b[5] +
		dsm->buffer[(idx-6)&7] * shaper_coeffs_8th_b[6] +
		dsm->buffer[(idx-7)&7] * shaper_coeffs_8th_b[7];
		double next =
		dsm->buffer[idx&7]     * shaper_coeffs_8th_a[0] +
		dsm->buffer[(idx-1)&7] * shaper_coeffs_8th_a[1] +
		dsm->buffer[(idx-2)&7] * shaper_coeffs_8th_a[2] +
		dsm->buffer[(idx-3)&7] * shaper_coeffs_8th_a[3] +
		dsm->buffer[(idx-4)&7] * shaper_coeffs_8th_a[4] +
		dsm->buffer[(idx-5)&7] * shaper_coeffs_8th_a[5] +
		dsm->buffer[(idx-6)&7] * shaper_coeffs_8th_a[6] +
		dsm->buffer[(idx-7)&7] * shaper_coeffs_8th_a[7];
		double err;
		if(quantizer_in < 0) {
			bitBuf = bitBuf << 1;
			err = quantizer_in + 1.0;
		}
		else {
			bitBuf = (bitBuf << 1) | 1;
			err = quantizer_in - 1.0;
		}
		
		idx = (idx+1) & 7;
		dsm->buffer[idx] = err - next;
		in += stride;
		
		if(++bitBufMeter == 8) {
			*out = bitBuf;
			bitBuf = 0;
			written++;
			bitBufMeter = 0;
			out += stride;
		}
	}
#endif
	dsm->idx = idx;
	dsm->bitBuf = bitBuf;
	dsm->bitBufMeter = bitBufMeter;
	return written;
}

static int deltasigma_8th_dsf(xld_deltasigma_t *dsm, const float* in, unsigned char *out, int numSamples, int stride)
{
	int i;
	int idx = dsm->idx;
	unsigned int bitBuf = dsm->bitBuf;
	unsigned int bitBufMeter = dsm->bitBufMeter;
	int written = 0;
#if USE_SSE
	__m128d v0, v1, v2, v3, v4, v5, v6, v7;
	v5 = (__m128d)_mm_load_ps((float *)dsm->buffer);
	v6 = (__m128d)_mm_load_ps((float *)(dsm->buffer+2));
	v7 = (__m128d)_mm_load_ps((float *)(dsm->buffer+4));
	for(i=0;i<numSamples;i++) {
		v0 = v5;
		v1 = v6;
		v2 = v5;
		v3 = v6;
		v0 = _mm_mul_pd(v0, *(__m128d*)shaper_coeffs_8th_b);
		v1 = _mm_mul_pd(v1, *(__m128d*)(shaper_coeffs_8th_b+2));
		v2 = _mm_mul_pd(v2, *(__m128d*)shaper_coeffs_8th_a);
		v3 = _mm_mul_pd(v3, *(__m128d*)(shaper_coeffs_8th_a+2));
		v0 = _mm_add_pd(v0, v1);
		v2 = _mm_add_pd(v2, v3);
		v1 = v7;
		v3 = v7;
		v1 = _mm_mul_pd(v1, *(__m128d*)(shaper_coeffs_8th_b+4));
		v3 = _mm_mul_pd(v3, *(__m128d*)(shaper_coeffs_8th_a+4));
		v0 = _mm_add_pd(v0, v1);
		v2 = _mm_add_pd(v2, v3);
		v4 = (__m128d)_mm_load_ps((float *)(dsm->buffer+6));
		v1 = v4;
		v3 = v4;
		v1 = _mm_mul_pd(v1, *(__m128d*)(shaper_coeffs_8th_b+6));
		v3 = _mm_mul_pd(v3, *(__m128d*)(shaper_coeffs_8th_a+6));
		v0 = _mm_add_pd(v0, v1);
		v2 = _mm_add_pd(v2, v3);
		v1 = (__m128d)_mm_movehl_ps((__m128)v1, (__m128)v0);
		v3 = (__m128d)_mm_movehl_ps((__m128)v3, (__m128)v2);
		v0 = _mm_add_sd(v0, v1);
		v2 = _mm_add_sd(v2, v3);
		v3 = v5;
		v5 = _mm_shuffle_pd(v5, v6, 0x1);
		v6 = _mm_shuffle_pd(v6, v7, 0x1);
		v7 = _mm_shuffle_pd(v7, v4, 0x1);
		_mm_store_ps((float *)(dsm->buffer+6), (__m128)v7);
		v7 = v6;
		v6 = v5;
		v4 = _mm_cvtss_sd(v4, *(__m128*)(in));
		v4 = _mm_mul_sd(v4, *(__m128d*)(consts_pool+2));
		v1 = (__m128d)_mm_setzero_ps();
		v0 = _mm_add_sd(v0, v4);
		v1 = _mm_cmplt_pd(v1, v0); //1111 if plus
		v4 = v3;
		v3 = _mm_load_sd(consts_pool+1);
		v5 = v0;
		v5 = _mm_sub_sd(v5, v2);
		v3 = (__m128d)_mm_and_ps((__m128)v3, (__m128)v1);
		v2 = v1;
		v1 = (__m128d)_mm_andnot_ps((__m128)v1, *(__m128*)(consts_pool));
		v1 = (__m128d)_mm_or_ps((__m128)v1, (__m128)v3);
		v5 = _mm_add_sd(v5, v1);
		unsigned int bit = _mm_cvtsi128_si32((__m128i)v2);
		v5 = _mm_unpacklo_pd(v5, v4);
		bitBuf = (bitBuf >> 1) | (bit & 0x80);
		in += stride;
		
		if(++bitBufMeter == 8) {
			*out = bitBuf;
			bitBuf = 0;
			written++;
			bitBufMeter = 0;
			out++;
		}
	}
	_mm_store_ps((float *)dsm->buffer, (__m128)v5);
	_mm_store_ps((float *)(dsm->buffer+2), (__m128)v6);
	_mm_store_ps((float *)(dsm->buffer+4), (__m128)v7);
#else
	for(i=0;i<numSamples;i++) {
		double quantizer_in = *in * SCALE +
		dsm->buffer[idx&7]     * shaper_coeffs_8th_b[0] +
		dsm->buffer[(idx-1)&7] * shaper_coeffs_8th_b[1] +
		dsm->buffer[(idx-2)&7] * shaper_coeffs_8th_b[2] +
		dsm->buffer[(idx-3)&7] * shaper_coeffs_8th_b[3] +
		dsm->buffer[(idx-4)&7] * shaper_coeffs_8th_b[4] +
		dsm->buffer[(idx-5)&7] * shaper_coeffs_8th_b[5] +
		dsm->buffer[(idx-6)&7] * shaper_coeffs_8th_b[6] +
		dsm->buffer[(idx-7)&7] * shaper_coeffs_8th_b[7];
		double next =
		dsm->buffer[idx&7]     * shaper_coeffs_8th_a[0] +
		dsm->buffer[(idx-1)&7] * shaper_coeffs_8th_a[1] +
		dsm->buffer[(idx-2)&7] * shaper_coeffs_8th_a[2] +
		dsm->buffer[(idx-3)&7] * shaper_coeffs_8th_a[3] +
		dsm->buffer[(idx-4)&7] * shaper_coeffs_8th_a[4] +
		dsm->buffer[(idx-5)&7] * shaper_coeffs_8th_a[5] +
		dsm->buffer[(idx-6)&7] * shaper_coeffs_8th_a[6] +
		dsm->buffer[(idx-7)&7] * shaper_coeffs_8th_a[7];
		double err;
		if(quantizer_in < 0) {
			bitBuf = bitBuf >> 1;
			err = quantizer_in + 1.0;
		}
		else {
			bitBuf = (bitBuf >> 1) | 0x80;
			err = quantizer_in - 1.0;
		}
		
		idx = (idx+1) & 7;
		dsm->buffer[idx] = err - next;
		in += stride;
		
		if(++bitBufMeter == 8) {
			*out = bitBuf;
			bitBuf = 0;
			written++;
			bitBufMeter = 0;
			out++;
		}
	}
#endif
	dsm->idx = idx;
	dsm->bitBuf = bitBuf;
	dsm->bitBufMeter = bitBufMeter;
	return written;
}
