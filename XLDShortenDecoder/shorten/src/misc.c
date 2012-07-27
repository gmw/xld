/*  misc.c - miscellaneous functions
 *  Copyright (C) 2000-2004  Jason Jordan <shnutils@freeshell.org>
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 */

/*
 * $Id: misc.c,v 1.13 2004/04/26 10:26:56 jason Exp $
 */

#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include "shorten.h"

void shn_snprintf(char *dest,int maxlen,char *formatstr, ...)
/* acts like snprintf, but makes 100% sure the string is NULL-terminated */
{
  va_list args;

  va_start(args,formatstr);

  shn_vsnprintf(dest,maxlen,formatstr,args);

  dest[maxlen-1] = 0;

  va_end(args);
}

int shn_filename_contains_a_dot(char *filename)
{
	char *slash,*dot;

	dot = strrchr(filename,'.');
	if (!dot)
		return 0;

	slash = strrchr(filename,'/');
	if (!slash)
		return 1;

	if (slash < dot)
		return 1;
	else
		return 0;
}

char *shn_get_base_filename(char *filename)
{
	char *b,*e,*p,*base;

	b = strrchr(filename,'/');

	if (b)
		b++;
	else
		b = filename;

	e = strrchr(filename,'.');

	if (e < b)
		e = filename + strlen(filename);

	if (NULL == (base = malloc((e - b + 1) * sizeof(char))))
	{
		fprintf(stderr, "Could not allocate memory for base filename");
		return NULL;
	}

	for (p=b;p<e;p++)
		*(base + (p - b)) = *p;

	*(base + (p - b)) = '\0';

	return base;
}

char *shn_get_base_directory(char *filename)
{
	char *e,*p,*base;

	e = strrchr(filename,'/');

	if (!e)
		e = filename;

	if (NULL == (base = malloc((e - filename + 1) * sizeof(char))))
	{
		fprintf(stderr, "Could not allocate memory for base directory");
		return NULL;
	}

	for (p=filename;p<e;p++)
		*(base + (p - filename)) = *p;

	*(base + (p - filename)) = '\0';

	return base;
}

void shn_length_to_str(shn_file *info)
/* converts length of file to a string in m:ss or m:ss.ff format */
{
  ulong newlength,rem1,rem2,frames,ms;
  double tmp;

  if (PROB_NOT_CD(info->wave_header)) {
    newlength = (ulong)info->wave_header.exact_length;

    tmp = info->wave_header.exact_length - (double)((ulong)info->wave_header.exact_length);
    ms = (ulong)((tmp * 1000.0) + 0.5);

    if (1000 == ms) {
      ms = 0;
      newlength++;
    }

    shn_snprintf(info->wave_header.m_ss,16,"%lu:%02lu.%03lu",newlength/60,newlength%60,ms);
  }
  else {
    newlength = info->wave_header.length;

    rem1 = info->wave_header.data_size % CD_RATE;
    rem2 = rem1 % CD_BLOCK_SIZE;

    frames = rem1 / CD_BLOCK_SIZE;
    if (rem2 >= (CD_BLOCK_SIZE / 2))
      frames++;

    if (frames == CD_BLOCKS_PER_SEC) {
      frames = 0;
      newlength++;
    }

    shn_snprintf(info->wave_header.m_ss,16,"%lu:%02lu.%02lu",newlength/60,newlength%60,frames);
  }
}
