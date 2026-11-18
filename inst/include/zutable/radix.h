/*
 * zutable/radix.h -- the radix and counting sorts of the sort ladder
 * (design-kernel 4.3), written, not ported.
 *
 * They sort records by their key alone and are stable, so the records
 * must come in row order (as the encoder writes them), and then the row
 * order of ties is kept without a pass over the row bytes. A zt_w64's key
 * is its high 32 bits, a zt_r128's its k; `kbits` says how many of the
 * key's low bits are in use (the rest are zero).
 *
 *   zt_lsd_*(a, n, kbits, dbits, tmp)     LSD radix, digits of dbits bits
 *                                         (8 or 11), skipping a digit every
 *                                         record shares. Scratch: tmp, n
 *                                         records.
 *   zt_msd_lsd_*(a, n, kbits, tmp)        one MSD pass on the top 8 bits,
 *                                         then LSD within each bucket: the
 *                                         above-cache variant. Scratch: tmp.
 *   zt_counting_*(a, n, kmin, range, tmp, cnt)
 *                                         counting sort of keys in
 *                                         [kmin, kmin + range]: the dense
 *                                         path. Scratch: tmp, and cnt of
 *                                         range + 2 counts.
 *
 * Counts are 32 bits: there are at most 2^31 - 1 rows (D11).
 */
#ifndef ZUTABLE_RADIX_H
#define ZUTABLE_RADIX_H

#include "sortrec.h"

#define ZT_RADIX_MAX_DBITS 11
#define ZT_RADIX_MAX_PASSES 8 /* 64 key bits in digits of 8 */

ZT_INLINE uint64_t zt_key_w64(zt_w64 a) { return a >> 32; }
ZT_INLINE uint64_t zt_key_r128(zt_r128 a) { return a.k; }

#define ZT_SORT_T zt_w64
#define ZT_SORT_SUF w64
#define ZT_SORT_KEY zt_key_w64
#include "radix.inc"
#undef ZT_SORT_T
#undef ZT_SORT_SUF
#undef ZT_SORT_KEY

#define ZT_SORT_T zt_r128
#define ZT_SORT_SUF r128
#define ZT_SORT_KEY zt_key_r128
#include "radix.inc"
#undef ZT_SORT_T
#undef ZT_SORT_SUF
#undef ZT_SORT_KEY

#endif /* ZUTABLE_RADIX_H */
