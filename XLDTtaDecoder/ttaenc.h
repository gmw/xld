/*
 * ttaenc.h
 *
 * Description:	 TTAv1 encoder definitions and prototypes
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
#ifndef TTAENC_H
#define TTAENC_H

#include <stdio.h>
#include <stdlib.h>

#ifdef __GNUC__
#define __USE_ISOC99
#endif

#include <wchar.h>
#include <wctype.h>
#include <limits.h>
#include <string.h>
#include <ctype.h>
#include <time.h>
#include <errno.h>
#include <locale.h>

#ifdef _WIN32
#include <direct.h>
#include <io.h>
#include <conio.h>
#else
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#endif

#ifdef _WIN32
#pragma pack(1)
#define __ATTRIBUTE_PACKED__
#else
#define __ATTRIBUTE_PACKED__	__attribute__((packed))
#endif

#ifdef _WIN32
#define wfopen(x,y) _wfopen(x,L##y)
#define wunlink _wunlink
#define wstrncpy wcsncpy
#else
#define _MAX_FNAME 1024
#define wstrncpy mbstowcs

FILE* wfopen (wchar_t *wcname, char *mode) {
    char name[_MAX_FNAME * MB_LEN_MAX];
    wcstombs(name, wcname, MB_CUR_MAX * wcslen(wcname) + 1);
    return fopen(name, mode);
}

int wunlink (wchar_t *wcname) {
    char name[_MAX_FNAME * MB_LEN_MAX];
    wcstombs(name, wcname, MB_CUR_MAX * wcslen(wcname) + 1);
    return unlink(name);
}

int wcsicmp (const wchar_t *s1, const wchar_t *s2) {
    wint_t c1, c2;
    if (s1 == s2) return 0;
    do {
	c1 = towlower(*s1++);
	c2 = towlower(*s2++);
	if (c1 == L'\0') break;
    } while (c1 == c2);
    return c1 - c2;
}
#endif

#define COPYRIGHT		"Copyright (c) 2005 Alexander Djourik. All rights reserved."

#define MYNAME			"ttaenc"
#define VERSION			"3.3"
#define BUILD			"20050517"
#define PROJECT_URL		"http://tta.sourceforge.net"

#define MAX_BPS			32
#define FRAME_TIME		1.04489795918367346939

#define TTA1_SIGN		0x31415454
#define RIFF_SIGN		0x46464952
#define WAVE_SIGN		0x45564157
#define fmt_SIGN		0x20746D66
#define data_SIGN		0x61746164

#define WAVE_FORMAT_PCM	1
#define WAVE_FORMAT_IEEE_FLOAT 3
#define WAVE_FORMAT_EXTENSIBLE 0xFFFE

#define COMMAND_ERROR	0
#define FORMAT_ERROR	1
#define FILE_ERROR		2
#define FIND_ERROR		3
#define CREATE_ERROR	4
#define OPEN_ERROR		5
#define MEMORY_ERROR	6
#define WRITE_ERROR		7
#define READ_ERROR		8

#ifdef _BIG_ENDIAN
#define	ENDSWAP_INT16(x)	(((((x)>>8)&0xFF)|(((x)&0xFF)<<8)))
#define	ENDSWAP_INT32(x)	(((((x)>>24)&0xFF)|(((x)>>8)&0xFF00)|(((x)&0xFF00)<<8)|(((x)&0xFF)<<24)))
#else
#define	ENDSWAP_INT16(x)	(x)
#define	ENDSWAP_INT32(x)	(x)
#endif

#define SWAP16(x) (\
(((x)&(1<< 0))?(1<<15):0) | \
(((x)&(1<< 1))?(1<<14):0) | \
(((x)&(1<< 2))?(1<<13):0) | \
(((x)&(1<< 3))?(1<<12):0) | \
(((x)&(1<< 4))?(1<<11):0) | \
(((x)&(1<< 5))?(1<<10):0) | \
(((x)&(1<< 6))?(1<< 9):0) | \
(((x)&(1<< 7))?(1<< 8):0) | \
(((x)&(1<< 8))?(1<< 7):0) | \
(((x)&(1<< 9))?(1<< 6):0) | \
(((x)&(1<<10))?(1<< 5):0) | \
(((x)&(1<<11))?(1<< 4):0) | \
(((x)&(1<<12))?(1<< 3):0) | \
(((x)&(1<<13))?(1<< 2):0) | \
(((x)&(1<<14))?(1<< 1):0) | \
(((x)&(1<<15))?(1<< 0):0))

#define LINE "------------------------------------------------------------"

#define PREDICTOR1(x, k)	((long)((((uint64)x << k) - x) >> k))

#define ENC(x)  (((x)>0)?((x)<<1)-1:(-(x)<<1))
#define DEC(x)  (((x)&1)?(++(x)>>1):(-(x)>>1))

#ifdef _WIN32
    #define _SEP L'\\'
    #define ERASE_STDERR fwprintf (stderr, L"%78c\r", 0x20)
	typedef unsigned __int64 uint64;
	#define strcasecmp	stricmp
#else
    #define _SEP L'/'
    #define ERASE_STDERR fwprintf (stderr, L"\033[2K")
	typedef unsigned long long uint64;
#endif

#endif	/* TTAENC_H */
