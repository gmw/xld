/******************************************************************************
*                                                                             *
*  Copyright (C) 1992-1995 Tony Robinson                                      *
*                                                                             *
*  See the file doc/LICENSE.shorten for conditions on distribution and usage  *
*                                                                             *
******************************************************************************/

/*
 * $Id: vario.c,v 1.10 2004/05/04 02:26:36 jason Exp $
 */

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include "shorten.h"

#define MASKTABSIZE 33
ulong masktab[MASKTABSIZE];

void mkmasktab() {
  int i;
  ulong val = 0;

  masktab[0] = val;
  for(i = 1; i < MASKTABSIZE; i++) {
    val <<= 1;
    val |= 1;
    masktab[i] = val;
  }
}

void var_get_init(shn_file *this_shn)
{
  mkmasktab();

  this_shn->decode_state->getbuf   = (uchar*) pmalloc((ulong) BUFSIZ,this_shn);
  this_shn->decode_state->getbufp  = this_shn->decode_state->getbuf;
  this_shn->decode_state->nbyteget = 0;
  this_shn->decode_state->gbuffer  = 0;
  this_shn->decode_state->nbitget  = 0;
}

ulong word_get(shn_file *this_shn)
{
  ulong buffer;
  int bytes;

  if(this_shn->decode_state->nbyteget < 4)
  {
    this_shn->vars.last_file_position = this_shn->vars.bytes_read;

    bytes = fread((uchar*) this_shn->decode_state->getbuf, 1, BUFSIZ, this_shn->vars.fd);
    this_shn->decode_state->nbyteget += bytes;

    if(this_shn->decode_state->nbyteget < 4) {
      shn_error_fatal(this_shn,"Premature EOF on compressed stream -\npossible corrupt or truncated file");
      return (ulong)0;
    }

    this_shn->vars.bytes_read += bytes;

    this_shn->decode_state->getbufp = this_shn->decode_state->getbuf;
  }

  buffer = (((slong) (this_shn->decode_state->getbufp[0])) << 24) | (((slong) (this_shn->decode_state->getbufp[1])) << 16) |
    (((slong) (this_shn->decode_state->getbufp[2])) <<  8) | ((slong) (this_shn->decode_state->getbufp[3]));

  this_shn->decode_state->getbufp += 4;
  this_shn->decode_state->nbyteget -= 4;

  return(buffer);
}

slong uvar_get(int nbin,shn_file *this_shn)
{
  slong result;

  if (this_shn->vars.reading_function_code) {
    this_shn->vars.last_file_position_no_really = this_shn->vars.last_file_position;
  }

  if(this_shn->decode_state->nbitget == 0)
  {
    this_shn->decode_state->gbuffer = word_get(this_shn);
    if (this_shn->vars.fatal_error)
      return (ulong)0;
    this_shn->decode_state->nbitget = 32;
  }

  for(result = 0; !(this_shn->decode_state->gbuffer & (1L << --(this_shn->decode_state->nbitget))); result++)
  {
    if(this_shn->decode_state->nbitget == 0)
    {
      this_shn->decode_state->gbuffer = word_get(this_shn);
      if (this_shn->vars.fatal_error)
        return (ulong)0;
      this_shn->decode_state->nbitget = 32;
    }
  }

  while(nbin != 0)
  {
    if(this_shn->decode_state->nbitget >= nbin)
    {
      result = (result << nbin) | ((this_shn->decode_state->gbuffer >> (this_shn->decode_state->nbitget-nbin)) &masktab[nbin]);
      this_shn->decode_state->nbitget -= nbin;
      nbin = 0;
    }
    else
    {
      result = (result << this_shn->decode_state->nbitget) | (this_shn->decode_state->gbuffer & masktab[this_shn->decode_state->nbitget]);
      this_shn->decode_state->gbuffer = word_get(this_shn);
      if (this_shn->vars.fatal_error)
        return (ulong)0;
      nbin -= this_shn->decode_state->nbitget;
      this_shn->decode_state->nbitget = 32;
    }
  }

  return(result);
}

ulong ulong_get(shn_file *this_shn)
{
  unsigned int nbit = uvar_get(ULONGSIZE,this_shn);
  if (this_shn->vars.fatal_error)
    return (ulong)0;
  return(uvar_get(nbit,this_shn));
}

slong var_get(int nbin,shn_file *this_shn)
{
  ulong uvar = uvar_get(nbin + 1,this_shn);
  if (this_shn->vars.fatal_error)
    return (slong)0;

  if(uvar & 1) return((slong) ~(uvar >> 1));
  else return((slong) (uvar >> 1));
}

void var_get_quit(shn_file *this_shn)
{
  free((void *) this_shn->decode_state->getbuf);
  this_shn->decode_state->getbuf = NULL;
}
