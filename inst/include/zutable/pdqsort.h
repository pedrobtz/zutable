/*
 * zutable/pdqsort.h -- pattern-defeating quicksort over the sort records,
 * the hybrid's small-n engine and comparison leaf (design-kernel 4.3).
 * The port and its zlib notice are in pdqsort.inc.
 *
 *   zt_pdqsort_w64(b, e), zt_pdqsort_r128(b, e)       sort [b, e)
 *   zt_insertion_w64(b, e), zt_insertion_r128(b, e)   the leaf
 *   zt_heapsort_w64(b, e), zt_heapsort_r128(b, e)     the control
 *
 * No scratch: it sorts in place, with a stack of O(log n) frames.
 */
#ifndef ZUTABLE_PDQSORT_H
#define ZUTABLE_PDQSORT_H

#include "sortrec.h"

/* The original's thresholds. */
#define ZT_PDQ_INSERTION 24
#define ZT_PDQ_NINTHER 128
#define ZT_PDQ_PARTIAL_LIMIT 8
#define ZT_PDQ_BLOCK 64

#define ZT_SORT_T zt_w64
#define ZT_SORT_SUF w64
#define ZT_SORT_LT zt_lt_w64
#include "pdqsort.inc"
#undef ZT_SORT_T
#undef ZT_SORT_SUF
#undef ZT_SORT_LT

#define ZT_SORT_T zt_r128
#define ZT_SORT_SUF r128
#define ZT_SORT_LT zt_lt_r128
#include "pdqsort.inc"
#undef ZT_SORT_T
#undef ZT_SORT_SUF
#undef ZT_SORT_LT

#endif /* ZUTABLE_PDQSORT_H */
