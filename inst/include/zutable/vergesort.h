/*
 * zutable/vergesort.h -- Vergesort over the sort records, the hybrid's
 * adaptive front (design-kernel 4.3): runs of n / log2(n) or more are
 * kept and merged, so sorted data with a few rows out of place sorts in
 * O(n). The port and its MIT notice are in vergesort.inc.
 *
 *   zt_vergesort_w64(b, e, scratch, fallback, ctx)   returns the runs found
 *   zt_vergesort_pdq_w64(b, e, scratch)         the original: pdqsort between runs
 *
 * and the same for r128. Scratch: e - b records.
 */
#ifndef ZUTABLE_VERGESORT_H
#define ZUTABLE_VERGESORT_H

#include "sortrec.h"
#include "pdqsort.h"

#define ZT_SORT_T zt_w64
#define ZT_SORT_SUF w64
#define ZT_SORT_LT zt_lt_w64
#include "vergesort.inc"
#undef ZT_SORT_T
#undef ZT_SORT_SUF
#undef ZT_SORT_LT

#define ZT_SORT_T zt_r128
#define ZT_SORT_SUF r128
#define ZT_SORT_LT zt_lt_r128
#include "vergesort.inc"
#undef ZT_SORT_T
#undef ZT_SORT_SUF
#undef ZT_SORT_LT

#endif /* ZUTABLE_VERGESORT_H */
