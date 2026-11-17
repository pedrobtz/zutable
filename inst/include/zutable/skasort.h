/*
 * zutable/skasort.h -- ska sort's in-place MSD radix over the sort
 * records, the hybrid's large-n engine for wide records (design-kernel
 * 4.3): the American flag sort below 1024 elements, ska byte sort above,
 * pdqsort below 128. The port and its Boost notice are in skasort.inc.
 *
 *   zt_ska_sort_from_w64(b, e, d0, nbytes)   sort on bytes d0 .. nbytes - 1
 *
 * and the same for r128. A record's bytes are counted from its most
 * significant (sortrec.h); bytes before d0 must be equal across [b, e).
 * No scratch beyond the stack.
 */
#ifndef ZUTABLE_SKASORT_H
#define ZUTABLE_SKASORT_H

#include "sortrec.h"
#include "pdqsort.h"

#define ZT_SORT_T zt_w64
#define ZT_SORT_SUF w64
#define ZT_SORT_BYTE zt_byte_w64
#include "skasort.inc"
#undef ZT_SORT_T
#undef ZT_SORT_SUF
#undef ZT_SORT_BYTE

#define ZT_SORT_T zt_r128
#define ZT_SORT_SUF r128
#define ZT_SORT_BYTE zt_byte_r128
#include "skasort.inc"
#undef ZT_SORT_T
#undef ZT_SORT_SUF
#undef ZT_SORT_BYTE

#endif /* ZUTABLE_SKASORT_H */
