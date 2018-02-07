/***
 * CopyPolicy: GNU Lesser General Public License 2.1 applies
 * Copyright (C) by Monty (xiphmont@mit.edu)
 ***/

#ifndef _ISORT_H_
#define _ISORT_H_

typedef struct sort_link{
  struct sort_link *next;
} sort_link;

typedef struct sort_info{
  int16_t *vector;                /* vector (storage doesn't belong to us) */

  int32_t  *abspos;                 /* pointer for side effects */
  int32_t  size;                    /* vector size */

  int32_t  maxsize;                 /* maximum vector size */

  int32_t sortbegin;                /* range of contiguous sorted area */
  int32_t lo,hi;                    /* current post, overlap range */
  int  val;                      /* ...and val */

  /* sort structs */
  sort_link **head;           /* sort buckets (65536) */

  int32_t *bucketusage;          /*  of used buckets (65536) */
  int32_t lastbucket;
  sort_link *revindex;

} sort_info;

/*! ========================================================================
 * sort_alloc()
 *
 * Allocates and initializes a new, empty sort_info object, which can
 * be used to index up to (size) samples from a vector.
 */
extern sort_info *sort_alloc(int32_t size);

/*! ========================================================================
 * sort_unsortall() (internal)
 *
 * This function resets the index for further use with a different
 * vector or range, without the overhead of an unnecessary free/alloc.
 */
extern void sort_unsortall(sort_info *i);

/*! ========================================================================
 * sort_setup()
 *
 * This function initializes a previously allocated sort_info_t.  The
 * sort_info_t is associated with a vector of samples of length
 * (size), whose position begins at (*abspos) within the CD's stream
 * of samples.  Only the range of samples between (sortlo, sorthi)
 * will eventually be indexed for fast searching.  (sortlo, sorthi)
 * are absolute sample positions.
 *
 * Note: size *must* be <= the size given to the preceding sort_alloc(),
 * but no error checking is done here.
 */
extern void sort_setup(sort_info *i,int16_t *vector,int32_t *abspos,int32_t size,
		       int32_t sortlo, int32_t sorthi);

/* =========================================================================
 * sort_free()
 *
 * Releases all memory consumed by a sort_info object.
 */
extern void sort_free(sort_info *i);

/*! ========================================================================
 * sort_getmatch()
 *
 * This function returns a sort_link_t pointer which refers to the
 * first sample equal to (value) in the vector.  It only searches for
 * hits within (overlap) samples of (post), where (post) is an offset
 * within the vector.  The caller can determine the position of the
 * matched sample using ipos(sort_info *, sort_link *).
 *
 * This function returns NULL if no matches were found.
 */
extern sort_link *sort_getmatch(sort_info *i,int32_t post,int32_t overlap,int value);

/*! ========================================================================
 * sort_nextmatch()
 *
 * This function returns a sort_link_t pointer which refers to the
 * next sample matching the criteria previously passed to
 * sort_getmatch().  See sort_getmatch() for details.
 *
 * This function returns NULL if no further matches were found.
 */
extern sort_link *sort_nextmatch(sort_info *i,sort_link *prev);

/* ===========================================================================
 * is()
 *
 * This macro returns the size of the vector indexed by the given sort_info_t.
 */
#define is(i) (i->size)

/* ===========================================================================
 * ib()
 *
 * This macro returns the absolute position of the first sample in the vector
 * indexed by the given sort_info_t.
 */
#define ib(i) (*i->abspos)

/* ===========================================================================
 * ie()
 *
 * This macro returns the absolute position of the sample after the last
 * sample in the vector indexed by the given sort_info_t.
 */
#define ie(i) (i->size+*i->abspos)

/* ===========================================================================
 * iv()
 *
 * This macro returns the vector indexed by the given sort_info_t.
 */
#define iv(i) (i->vector)

/* ===========================================================================
 * ipos()
 *
 * This macro returns the relative position (offset) within the indexed vector
 * at which the given match was found.
 *
 * It uses a little-known and frightening aspect of C pointer arithmetic:
 * subtracting a pointer is not an arithmetic subtraction, but rather the
 * additive inverse.  In other words, since
 *   q     = p + n returns a pointer to the nth object in p,
 *   q - p = p + n - p, and
 *   q - p = n, not the difference of the two addresses.
 */
#define ipos(i,l) (l-i->revindex)

#endif

