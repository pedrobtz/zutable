/*
 * zutable/sortrec.h -- the records the sorts work on (design-kernel 4.3).
 *
 * A sort orders key and row-index pairs, never values alone. The
 * normalised key goes in the high bits and the row in the low bits, and
 * records compare as unsigned integers, so an unstable sort still gives a
 * stable permutation (the row breaks every tie) and no two records are
 * equal.
 *
 *   zt_w64   one 64-bit word: a key of at most 32 bits, then the row.
 *   zt_r128  two words: a key of at most 64 bits, then the row.
 *
 * Each sort is written once, in a template file (*.inc) included once per
 * record type with ZT_SORT_T (the type), ZT_SORT_SUF (its suffix) and the
 * functions below in scope. The macros are undefined after each use.
 */
#ifndef ZUTABLE_SORTREC_H
#define ZUTABLE_SORTREC_H

#include "config.h"

typedef uint64_t zt_w64;
typedef struct {
  uint64_t k; /* the normalised key */
  uint64_t i; /* the row, below 2^31 */
} zt_r128;

#define ZT_SORT_CAT2(a, b) a##_##b
#define ZT_SORT_CAT(a, b) ZT_SORT_CAT2(a, b)
/* zt_<name>_<suffix>, the instance of a template function. */
#define ZT_SORT_FN(name) ZT_SORT_CAT(name, ZT_SORT_SUF)

ZT_INLINE int zt_lt_w64(zt_w64 a, zt_w64 b) { return a < b; }
ZT_INLINE int zt_lt_r128(zt_r128 a, zt_r128 b) {
  return a.k < b.k || (a.k == b.k && a.i < b.i);
}

/* Byte d of a record, 0 the most significant: a zt_w64 has 8 (key, then
   row), a zt_r128 12 (8 of key, then the row's 4). */
#define ZT_NBYTES_w64 8
#define ZT_NBYTES_r128 12
ZT_INLINE unsigned zt_byte_w64(zt_w64 a, int d) {
  return (unsigned) (a >> (56 - 8 * d)) & 255u;
}
ZT_INLINE unsigned zt_byte_r128(zt_r128 a, int d) {
  if (d < 8) return (unsigned) (a.k >> (56 - 8 * d)) & 255u;
  return (unsigned) (a.i >> (24 - 8 * (d - 8))) & 255u;
}

/* floor(log2(n)) for n > 0. */
ZT_INLINE int zt_log2(size_t n) {
  int l = 0;
  while (n >>= 1) ++l;
  return l;
}

#endif /* ZUTABLE_SORTREC_H */
