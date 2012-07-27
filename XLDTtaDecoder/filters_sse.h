/*
 * filters.h
 *
 * Description:	 TTAv1 filters functions
 * Developed by: Alexander Djourik <ald@true-audio.com>
 *               Pavel Zhilin <pzh@true-audio.com>
 *
 * Copyright (c) 1999-2005 Alexander Djourik. All rights reserved.
 *
 */

/*
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * aint with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 * Please see the file COPYING in this directory for full copyright
 * information.
 */

#ifndef FILTERS_H
#define FILTERS_H

#include <emmintrin.h>

///////// Filter Settings //////////
static long flt_set [4][2] = {
	{10,1}, {9,1}, {10,1}, {12,0}
};

__inline void
memshl (register long *pA, register long *pB) {
	*pA++ = *pB++;
	*pA++ = *pB++;
	*pA++ = *pB++;
	*pA++ = *pB++;
	*pA++ = *pB++;
	*pA++ = *pB++;
	*pA++ = *pB++;
	*pA   = *pB;
}

__inline void
hybrid_filter (fltst *fs, long *in, long mode) {
	register long *pA = fs->dl;
	register long *pB = fs->qm;
	register long *pM = fs->dx;
	register long sum = fs->round;
	__m128i vb1, vb2, vm1, vm2;

	if (fs->error < 0) {
		vb1 = _mm_load_si128((__m128i*)pB);
		vb2 = _mm_load_si128((__m128i*)(pB+4));
		vm1 = _mm_load_si128((__m128i*)pM);
		vm2 = _mm_load_si128((__m128i*)(pM+4));
		vb1 = _mm_sub_epi32(vb1,vm1);
		vb2 = _mm_sub_epi32(vb2,vm2);
		_mm_store_si128((__m128i*)pB, vb1);
		_mm_store_si128((__m128i*)(pB+4), vb2);
	} else if (fs->error > 0) {
		vb1 = _mm_load_si128((__m128i*)pB);
		vb2 = _mm_load_si128((__m128i*)(pB+4));
		vm1 = _mm_load_si128((__m128i*)pM);
		vm2 = _mm_load_si128((__m128i*)(pM+4));
		vb1 = _mm_add_epi32(vb1,vm1);
		vb2 = _mm_add_epi32(vb2,vm2);
		_mm_store_si128((__m128i*)pB, vb1);
		_mm_store_si128((__m128i*)(pB+4), vb2);
	}
	sum += *pA++ * *pB, pB++;
	sum += *pA++ * *pB, pB++;
	sum += *pA++ * *pB, pB++;
	sum += *pA++ * *pB, pB++;
	sum += *pA++ * *pB, pB++;
	sum += *pA++ * *pB, pB++;
	sum += *pA++ * *pB, pB++;
	sum += *pA++ * *pB; pM += 8;

	*(pM-0) = ((*(pA-1) >> 30) | 1) << 2;
	*(pM-1) = ((*(pA-2) >> 30) | 1) << 1;
	*(pM-2) = ((*(pA-3) >> 30) | 1) << 1;
	*(pM-3) = ((*(pA-4) >> 30) | 1);

	if (mode) {
		*pA = *in;
		*in -= (sum >> fs->shift);
		fs->error = *in;
	} else {
		fs->error = *in;
		*in += (sum >> fs->shift);
		*pA = *in;
	}

	if (fs->mutex) {
		*(pA-1) = *(pA-0) - *(pA-1);
		*(pA-2) = *(pA-1) - *(pA-2);
		*(pA-3) = *(pA-2) - *(pA-3);
	}

	memshl (fs->dl, fs->dl + 1);
	memshl (fs->dx, fs->dx + 1);
}

void
filter_init (fltst *fs, long shift, long mode) {
	memset (fs, 0, sizeof(fltst));
	fs->shift = shift;
	fs->round = 1 << (shift - 1);
	fs->mutex = mode;
}

#endif	/* FILTERS_H */
