/***
 * CopyPolicy: GNU Lesser General Public License 2.1 applies
 * Copyright (C) by Monty (xiphmont@mit.edu)
 *
 ***/

#ifndef _CDROM_PARANOIA_
#define _CDROM_PARANOIA_

#define CD_FRAMEWORDS (CD_FRAMESIZE_RAW/2)

#define PARANOIA_CB_READ           0
#define PARANOIA_CB_VERIFY         1
#define PARANOIA_CB_FIXUP_EDGE     2
#define PARANOIA_CB_FIXUP_ATOM     3
#define PARANOIA_CB_SCRATCH        4
#define PARANOIA_CB_REPAIR         5
#define PARANOIA_CB_SKIP           6
#define PARANOIA_CB_DRIFT          7
#define PARANOIA_CB_BACKOFF        8
#define PARANOIA_CB_OVERLAP        9
#define PARANOIA_CB_FIXUP_DROPPED 10
#define PARANOIA_CB_FIXUP_DUPED   11
#define PARANOIA_CB_READERR       12
#define PARANOIA_CB_CACHEERR      13

#define PARANOIA_MODE_FULL        0xff
#define PARANOIA_MODE_DISABLE     0

#define PARANOIA_MODE_VERIFY      1
#define PARANOIA_MODE_FRAGMENT    2
#define PARANOIA_MODE_OVERLAP     4
#define PARANOIA_MODE_SCRATCH     8
#define PARANOIA_MODE_REPAIR      16
#define PARANOIA_MODE_NEVERSKIP   32

/*#ifndef CDP_COMPILE
typedef void cdrom_paranoia;
#endif*/

typedef struct cdrom_paranoia_s cdrom_paranoia_t;
typedef cdrom_paranoia_t cdrom_paranoia;
typedef int paranoia_cb_mode_t;
typedef int lsn_t;

#include <stdio.h>

char *paranoia_version();
cdrom_paranoia *paranoia_init(cdrom_drive *d);
cdrom_paranoia *paranoia_init_old(cdrom_drive *d);
void paranoia_modeset(cdrom_paranoia *p,int mode);
int paranoia_seek(cdrom_paranoia *p,off_t seek,int mode);
int16_t *paranoia_read(cdrom_paranoia *p,void(*callback)(long,int));
int16_t *paranoia_read_limited(cdrom_paranoia *p,void(*callback)(long,int),int maxretries);
void paranoia_free(cdrom_paranoia *p);
void paranoia_overlapset(cdrom_paranoia *p,long overlap);
int paranoia_cachemodel_size(cdrom_paranoia *p,int sectors);

#endif
