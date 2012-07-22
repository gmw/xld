/***
 * CopyPolicy: GNU Lesser General Public License 2.1 applies
 * Copyright (C) by Monty (xiphmont@mit.edu)
 ***/

#ifndef _OVERLAP_H_
#define _OVERLAP_H_

extern void offset_add_value(cdrom_paranoia_t *p,offsets *o,long value,
			     void(*callback)(long,paranoia_cb_mode_t));
extern void offset_clear_settings(offsets *o);
extern void offset_adjust_settings(cdrom_paranoia_t *p, 
				   void(*callback)(long,paranoia_cb_mode_t));
extern void i_paranoia_trim(cdrom_paranoia_t *p,long beginword,long endword);
extern void paranoia_resetall(cdrom_paranoia_t *p);
extern void paranoia_resetcache(cdrom_paranoia_t *p);

#endif
