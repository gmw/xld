/***
 * CopyPolicy: GNU Lesser General Public License 2.1 applies
 * Copyright (C) by Monty (xiphmont@mit.edu)
 *
 * Statistic code and cache management for overlap settings
 *
 ***/

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "p_block.h"
#include "XLDCDDABackend.h"
//#include <cdio/paranoia.h>
#include "cdda_paranoia.h"
#include "overlap.h"
#include "isort.h"

/**** Internal cache management *****************************************/

void paranoia_resetcache(cdrom_paranoia_t *p){
  c_block *c=c_first(p);
  v_fragment *v;

  while(c){
    free_c_block(c);
    c=c_first(p);
  }

  v=v_first(p);
  while(v){
    free_v_fragment(v);
    v=v_first(p);
  }
}

void paranoia_resetall(cdrom_paranoia_t *p){
  p->root.returnedlimit=0;
  p->dyndrift=0;
  p->root.lastsector=0;

  if(p->root.vector){
    i_cblock_destructor(p->root.vector);
    p->root.vector=NULL;
  }

  paranoia_resetcache(p);
}

void i_paranoia_trim(cdrom_paranoia_t *p,int32_t beginword,int32_t endword){
  root_block *root=&(p->root);
  if(root->vector!=NULL){
    int32_t target=beginword-MAX_SECTOR_OVERLAP*CD_FRAMEWORDS;
    int32_t rbegin=cb(root->vector);
    int32_t rend=ce(root->vector);

    if(rbegin>beginword)
      goto rootfree;
    
    if(rbegin+MAX_SECTOR_OVERLAP*CD_FRAMEWORDS<beginword){
      if(target+MIN_WORDS_OVERLAP>rend)
	goto rootfree;

      {
	int32_t offset=target-rbegin;
	c_removef(root->vector,offset);
      }
    }

    {
      c_block *c=c_first(p);
      while(c){
	c_block *next=c_next(c);
	if(ce(c)<beginword-MAX_SECTOR_OVERLAP*CD_FRAMEWORDS)
	  free_c_block(c);
	c=next;
      }
    }

  }
  return;
  
rootfree:

  i_cblock_destructor(root->vector);
  root->vector=NULL;
  root->returnedlimit=-1;
  root->lastsector=0;
  
}

/**** Statistical and heuristic[al? :-] management ************************/

/* ===========================================================================
 * offset_adjust_settings (internal)
 *
 * This function is called by offset_add_value() every time 10 samples have
 * been accumulated.  This function updates the internal statistics for
 * paranoia (dynoverlap, dyndrift) that compensate for jitter and drift.
 *
 * (dynoverlap) influences how far stage 1 and stage 2 search for matching
 * runs.  In low-jitter conditions, it will be very small (or even 0),
 * narrowing our search.  In high-jitter conditions, it will be much larger,
 * widening our search at the cost of speed.
 */
void offset_adjust_settings(cdrom_paranoia_t *p, void(*callback)(int32_t,paranoia_cb_mode_t)){
  if(p->stage2.offpoints>=10){
    /* drift: look at the average offset value.  If it's over one
       sector, frob it.  We just want a little hysteresis [sp?]*/
    int32_t av=(p->stage2.offpoints?p->stage2.offaccum/p->stage2.offpoints:0);
    
    if(abs(av)>p->dynoverlap/4){
      av=(av/MIN_SECTOR_EPSILON)*MIN_SECTOR_EPSILON;
      
      if(callback)(*callback)(ce(p->root.vector),PARANOIA_CB_DRIFT);
      p->dyndrift+=av;
      
      /* Adjust all the values in the cache otherwise we get a
	 (potentially unstable) feedback loop */
      {
	c_block *c=c_first(p);
	v_fragment *v=v_first(p);

	while(v && v->one){
	  /* safeguard beginning bounds case with a hammer */
	  if(fb(v)<av || cb(v->one)<av){
	    v->one=NULL;
	  }else{
	    fb(v)-=av;
	  }
	  v=v_next(v);
	}
	while(c){
	  int32_t adj=min(av,cb(c));
	  c_set(c,cb(c)-adj);
	  c=c_next(c);
	}
      }

      p->stage2.offaccum=0;
      p->stage2.offmin=0;
      p->stage2.offmax=0;
      p->stage2.offpoints=0;
      p->stage2.newpoints=0;
      p->stage2.offdiff=0;
    }
  }

  if(p->stage1.offpoints>=10){
    /* dynoverlap: we arbitrarily set it to 4x the running difference
       value, unless min/max are more */

    p->dynoverlap=(p->stage1.offpoints?p->stage1.offdiff/
		   p->stage1.offpoints*3:CD_FRAMEWORDS);

    if(p->dynoverlap<-p->stage1.offmin*1.5)
      p->dynoverlap=-p->stage1.offmin*1.5;
						     
    if(p->dynoverlap<p->stage1.offmax*1.5)
      p->dynoverlap=p->stage1.offmax*1.5;

    if(p->dynoverlap<MIN_SECTOR_EPSILON)p->dynoverlap=MIN_SECTOR_EPSILON;
    if(p->dynoverlap>MAX_SECTOR_OVERLAP*CD_FRAMEWORDS)
      p->dynoverlap=MAX_SECTOR_OVERLAP*CD_FRAMEWORDS;
    			     
    if(callback)(*callback)(p->dynoverlap,PARANOIA_CB_OVERLAP);

    if(p->stage1.offpoints>600){ /* bit of a bug; this routine is
				    called too often due to the overlap 
				    mesh alg we use in stage 1 */
      p->stage1.offpoints/=1.2;
      p->stage1.offaccum/=1.2;
      p->stage1.offdiff/=1.2;
    }
    p->stage1.offmin=0;
    p->stage1.offmax=0;
    p->stage1.newpoints=0;
  }
}


/* ===========================================================================
 * offset_add_value (internal)
 *
 * This function adds the given jitter detected (value) to the statistics
 * for the given stage (o).  It is called whenever jitter has been identified
 * by stage 1 or 2.  After every 10 samples, we update the overall jitter-
 * compensation settings (e.g. dynoverlap).  This allows us to narrow our
 * search for matching runs (in both stages) in low-jitter conditions
 * and also widen our search appropriately when there is jitter.
 *
 *
 * "???BUG???:
 * Note that there is a bug in the way that this is called by try_sort_sync().
 * Silence looks like zero jitter, and dynoverlap may be incorrectly reduced
 * when there's lots of silence but also jitter."
 *
 * Strictly speaking, this is only sort-of true.  The silence will
 * incorrectly somewhat reduce dynoverlap.  However, it will increase
 * again once past the silence (even if reduced to zero, it will be
 * increased by the block read loop if we're not getting matches).
 * In reality, silence usually passes rapidly.  Anyway, long streaks
 * of silence benefit performance-wise from having dynoverlap decrease
 * momentarily. There is no correctness bug. --Monty
 *
 */
void offset_add_value(cdrom_paranoia_t *p,offsets *o,int32_t value,
			     void(*callback)(int32_t,paranoia_cb_mode_t)){
  if(o->offpoints!=-1){

    /* Track the average magnitude of jitter (in either direction) */
    o->offdiff+=abs(value);
    o->offpoints++;
    o->newpoints++;

    /* Track the net value of the jitter (to track drift) */
    o->offaccum+=value;

    /* Track the largest jitter we've encountered in each direction */
    if(value<o->offmin)o->offmin=value;
    if(value>o->offmax)o->offmax=value;

    /* After 10 samples, update dynoverlap, etc. */
    if(o->newpoints>=10)offset_adjust_settings(p,callback);
  }
}

