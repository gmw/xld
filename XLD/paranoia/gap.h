/***
 * CopyPolicy: GNU Lesser General Public License 2.1 applies
 * Copyright (C) by Monty (xiphmont@mit.edu)
 ***/

#ifndef _GAP_H_
#define _GAP_H_

extern int32_t i_paranoia_overlap_r(int16_t *buffA,int16_t *buffB,
				 int32_t offsetA, int32_t offsetB);
extern int32_t i_paranoia_overlap_f(int16_t *buffA,int16_t *buffB,
				 int32_t offsetA, int32_t offsetB,
				 int32_t sizeA,int32_t sizeB);
extern int i_stutter_or_gap(int16_t *A, int16_t *B,int32_t offA, int32_t offB,
			    int32_t gap);
extern void i_analyze_rift_f(int16_t *A,int16_t *B,
			     int32_t sizeA, int32_t sizeB,
			     int32_t aoffset, int32_t boffset, 
			     int32_t *matchA,int32_t *matchB,int32_t *matchC);
extern void i_analyze_rift_r(int16_t *A,int16_t *B,
			     int32_t sizeA, int32_t sizeB,
			     int32_t aoffset, int32_t boffset, 
			     int32_t *matchA,int32_t *matchB,int32_t *matchC);

extern void analyze_rift_silence_f(int16_t *A,int16_t *B,int32_t sizeA,int32_t sizeB,
				   int32_t aoffset, int32_t boffset,
				   int32_t *matchA, int32_t *matchB);
#endif
