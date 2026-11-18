/*
 * zutable/reduce.h -- one-pass statistics per group (design-kernel 4,
 * layer 5; 6.5).
 *
 * zt_reduce() takes each row's group (0-based, from zutable/groups.h) and
 * any number of value columns, each with its own statistic, and reduces
 * them all in one sweep over the rows: the rows go in blocks, and every
 * column takes its turn on a block while the block's group ids are in
 * cache (fusion, design-kernel 4.2). `mean` of doubles makes a second
 * sweep, the correction pass base R's mean() makes.
 *
 *   zt_reduce(ids, n, ng, cols, ncol)   every column, one sweep
 *   zt_reduce_scratch(...)              the scratch a column needs
 *
 * Missing values: INT32_MIN for int32 and logical columns; for doubles R's
 * NA (a NaN whose low word is 1954), and every other NaN too when
 * nan_missing is set, as base R's na.rm has it. Without nan_missing a NaN
 * is a value, the greatest, as zutable's vocabulary has it (design D47).
 *
 * A group with no values to reduce (all missing under na_rm) gives NA for
 * sum, prod, mean, min and max; count and nobs give 0; first and last give
 * row -1.
 *
 * Accumulation (axis M): ZT_PRECISION 1, the default, sums in long double,
 * as base sum(), prod() and mean() do, so that a group's sum is bit for bit
 * base R's; ZT_PRECISION 0 sums in double. Where long double is double
 * (MSVC, arm64 macOS) the two are the same, as they are for base R.
 *
 * Every buffer is the caller's; nothing here allocates.
 */
#ifndef ZUTABLE_REDUCE_H
#define ZUTABLE_REDUCE_H

#include <float.h>
#include "config.h"
#include "key.h"

#ifndef ZT_PRECISION
#define ZT_PRECISION 1
#endif
#if ZT_PRECISION == 1
typedef long double zt_acc;
#else
typedef double zt_acc;
#endif

/* Rows per block of the sweep: 4096 group ids are 16 KB, in L1 beside the
   block of each column. */
#ifndef ZT_REDUCE_BLOCK
#define ZT_REDUCE_BLOCK 4096
#endif

typedef enum {
  ZT_FN_SUM = 0,
  ZT_FN_PROD = 1,
  ZT_FN_MEAN = 2,
  ZT_FN_MIN = 3,
  ZT_FN_MAX = 4,
  ZT_FN_COUNT = 5,
  ZT_FN_NOBS = 6,
  ZT_FN_FIRST = 7,
  ZT_FN_LAST = 8
} zt_fn;

/* One column to reduce. kind is ZT_KIND_INT32, ZT_KIND_LGL or ZT_KIND_F64;
   x is ignored by ZT_FN_COUNT. out holds ng results:
     sum, prod, mean                double
     min, max                       int32_t (int32, logical) or double
     count, nobs                    int32_t
     first, last                    zt_row, the row, -1 for none
   acc, acc2, cnt and flag are scratch of ng elements each, of the sizes
   zt_reduce_scratch() gives (NULL where it gives 0). */
typedef struct {
  zt_fn fn;
  int kind;
  const void *x;
  int na_rm;
  int nan_missing;
  void *out;
  zt_acc *acc;
  zt_acc *acc2;
  zt_row *cnt;
  uint8_t *flag;
} zt_reduce_col;

/* Which scratch arrays a column needs, as element counts per group. */
ZT_INLINE void zt_reduce_scratch(zt_fn fn, int kind, int *acc, int *acc2, int *cnt,
                                 int *flag) {
  *acc = *acc2 = *cnt = *flag = 0;
  switch (fn) {
  case ZT_FN_SUM:
  case ZT_FN_PROD:
    *acc = *cnt = *flag = 1;
    break;
  case ZT_FN_MEAN:
    *acc = *cnt = *flag = 1;
    *acc2 = kind == ZT_KIND_F64;
    break;
  case ZT_FN_MIN:
  case ZT_FN_MAX:
    *cnt = *flag = 1;
    *acc = kind == ZT_KIND_F64;
    break;
  default:
    break;
  }
}

/* R's NA: a NaN with low word 1954. */
ZT_INLINE int zt_f64_is_na(double v) {
  uint64_t b;
  memcpy(&b, &v, sizeof b);
  return v != v && (uint32_t) b == 1954u;
}

ZT_INLINE double zt_f64_from_bits(uint64_t b) {
  double v;
  memcpy(&v, &b, sizeof v);
  return v;
}

#define ZT_F64_NA zt_f64_from_bits(UINT64_C(0x7ff00000000007a2))
#define ZT_F64_NAN zt_f64_from_bits(UINT64_C(0x7ff8000000000000))

/* flag bits */
#define ZT_RF_MISS 1u /* a missing value was seen (na_rm off) */
#define ZT_RF_NAN 2u  /* a NaN was seen: a value (min, max) */
#define ZT_RF_NA 4u   /* R's NA was seen (min, max, na_rm off) */

/* An accumulated sum or product as a double, the way base R's rsum() and
   rprod() return it: past DBL_MAX is infinite, though rounding the long
   double would give DBL_MAX. */
ZT_INLINE double zt_acc_double(zt_acc s) {
  if (s > DBL_MAX) return zt_f64_from_bits(UINT64_C(0x7ff0000000000000));
  if (s < -DBL_MAX) return zt_f64_from_bits(UINT64_C(0xfff0000000000000));
  return (double) s;
}

ZT_INLINE void zt_reduce_init(zt_reduce_col *c, zt_row ng) {
  for (zt_row g = 0; g < ng; g++) {
    if (c->cnt) c->cnt[g] = 0;
    if (c->flag) c->flag[g] = 0;
    if (c->acc) c->acc[g] = c->fn == ZT_FN_PROD ? 1 : 0;
    if (c->acc2) c->acc2[g] = 0;
  }
  if (c->fn == ZT_FN_COUNT || c->fn == ZT_FN_NOBS) {
    int32_t *o = (int32_t *) c->out;
    for (zt_row g = 0; g < ng; g++) o[g] = 0;
  }
  if (c->fn == ZT_FN_FIRST || c->fn == ZT_FN_LAST) {
    zt_row *o = (zt_row *) c->out;
    for (zt_row g = 0; g < ng; g++) o[g] = -1;
  }
}

/* Is row i of c missing? */
ZT_INLINE int zt_reduce_missing(const zt_reduce_col *c, zt_row i) {
  if (c->kind == ZT_KIND_F64) {
    double v = ((const double *) c->x)[i];
    return c->nan_missing ? v != v : zt_f64_is_na(v);
  }
  return ((const int32_t *) c->x)[i] == INT32_MIN;
}

/* sum, prod and the first sweep of mean, rows lo .. hi. */
ZT_INLINE void zt_reduce_block_sum(zt_reduce_col *c, const zt_row *ids, zt_row lo,
                                   zt_row hi) {
  int prod = c->fn == ZT_FN_PROD;
  if (c->kind == ZT_KIND_F64) {
    const double *x = (const double *) c->x;
    for (zt_row i = lo; i < hi; i++) {
      /* Without na_rm a missing value is added, as base R adds it, so the
         result is the NA or NaN base R gives. */
      if (c->na_rm && zt_reduce_missing(c, i)) continue;
      zt_row g = ids[i];
      if (prod) c->acc[g] *= x[i]; else c->acc[g] += x[i];
      c->cnt[g]++;
    }
    return;
  }
  const int32_t *x = (const int32_t *) c->x;
  for (zt_row i = lo; i < hi; i++) {
    zt_row g = ids[i];
    if (x[i] == INT32_MIN) {
      if (!c->na_rm) c->flag[g] |= ZT_RF_MISS;
      continue;
    }
    if (prod) c->acc[g] *= (zt_acc) x[i]; else c->acc[g] += (zt_acc) x[i];
    c->cnt[g]++;
  }
}

/* mean's correction sweep (base R's real_mean): acc holds each group's
   mean in the accumulator's precision. */
ZT_INLINE void zt_reduce_block_mean2(zt_reduce_col *c, const zt_row *ids, zt_row lo,
                                     zt_row hi) {
  const double *x = (const double *) c->x;
  for (zt_row i = lo; i < hi; i++) {
    if (c->na_rm && zt_reduce_missing(c, i)) continue;
    zt_row g = ids[i];
    if (c->flag[g]) c->acc2[g] += (zt_acc) x[i] - c->acc[g];
  }
}

/* min and max. Ties keep the first value, so -0 and 0 come out in row
   order, as base R's min() and max() give them. */
ZT_INLINE void zt_reduce_block_minmax(zt_reduce_col *c, const zt_row *ids, zt_row lo,
                                      zt_row hi) {
  int want_max = c->fn == ZT_FN_MAX;
  if (c->kind == ZT_KIND_F64) {
    const double *x = (const double *) c->x;
    double *best = (double *) c->out;
    for (zt_row i = lo; i < hi; i++) {
      double v = x[i];
      zt_row g = ids[i];
      if (v != v) {
        int na = zt_f64_is_na(v);
        if (na || c->nan_missing) {
          if (c->na_rm) continue;
          /* NA trumps NaN, as in base R. */
          c->flag[g] |= na ? ZT_RF_NA : ZT_RF_MISS;
          continue;
        }
        c->flag[g] |= ZT_RF_NAN;
        continue;
      }
      if (!c->cnt[g] || (want_max ? v > best[g] : v < best[g])) best[g] = v;
      c->cnt[g]++;
    }
    return;
  }
  const int32_t *x = (const int32_t *) c->x;
  int32_t *best = (int32_t *) c->out;
  for (zt_row i = lo; i < hi; i++) {
    int32_t v = x[i];
    zt_row g = ids[i];
    if (v == INT32_MIN) {
      if (!c->na_rm) c->flag[g] |= ZT_RF_NA;
      continue;
    }
    if (!c->cnt[g] || (want_max ? v > best[g] : v < best[g])) best[g] = v;
    c->cnt[g]++;
  }
}

ZT_INLINE void zt_reduce_block(zt_reduce_col *c, const zt_row *ids, zt_row lo, zt_row hi) {
  switch (c->fn) {
  case ZT_FN_SUM:
  case ZT_FN_PROD:
  case ZT_FN_MEAN:
    zt_reduce_block_sum(c, ids, lo, hi);
    break;
  case ZT_FN_MIN:
  case ZT_FN_MAX:
    zt_reduce_block_minmax(c, ids, lo, hi);
    break;
  case ZT_FN_COUNT: {
    int32_t *o = (int32_t *) c->out;
    for (zt_row i = lo; i < hi; i++) o[ids[i]]++;
    break;
  }
  case ZT_FN_NOBS: {
    int32_t *o = (int32_t *) c->out;
    for (zt_row i = lo; i < hi; i++) if (!zt_reduce_missing(c, i)) o[ids[i]]++;
    break;
  }
  case ZT_FN_FIRST: {
    zt_row *o = (zt_row *) c->out;
    for (zt_row i = lo; i < hi; i++) {
      zt_row g = ids[i];
      if (o[g] >= 0 || (c->na_rm && zt_reduce_missing(c, i))) continue;
      o[g] = i;
    }
    break;
  }
  case ZT_FN_LAST: {
    zt_row *o = (zt_row *) c->out;
    for (zt_row i = lo; i < hi; i++) {
      if (c->na_rm && zt_reduce_missing(c, i)) continue;
      o[ids[i]] = i;
    }
    break;
  }
  }
}

/* Between the sweeps: each double mean's first estimate, and whether its
   correction pass runs (base R corrects only a finite mean). */
ZT_INLINE void zt_reduce_mid(zt_reduce_col *c, zt_row ng) {
  for (zt_row g = 0; g < ng; g++) {
    c->flag[g] = 0;
    if (!c->cnt[g]) continue;
    c->acc[g] /= (zt_acc) c->cnt[g];
    double m = (double) c->acc[g];
    c->flag[g] = m - m == 0; /* finite */
  }
}

ZT_INLINE void zt_reduce_finish(zt_reduce_col *c, zt_row ng) {
  switch (c->fn) {
  case ZT_FN_SUM:
  case ZT_FN_PROD: {
    double *o = (double *) c->out;
    for (zt_row g = 0; g < ng; g++) {
      o[g] = !c->cnt[g] || (c->flag[g] & ZT_RF_MISS) ? ZT_F64_NA : zt_acc_double(c->acc[g]);
    }
    break;
  }
  case ZT_FN_MEAN: {
    double *o = (double *) c->out;
    for (zt_row g = 0; g < ng; g++) {
      if (c->kind == ZT_KIND_F64) {
        if (!c->cnt[g]) { o[g] = ZT_F64_NA; continue; }
        zt_acc s = c->acc[g];
        if (c->flag[g]) s += c->acc2[g] / (zt_acc) c->cnt[g];
        o[g] = (double) s;
      } else {
        o[g] = !c->cnt[g] || (c->flag[g] & ZT_RF_MISS)
                 ? ZT_F64_NA : (double) (c->acc[g] / (zt_acc) c->cnt[g]);
      }
    }
    break;
  }
  case ZT_FN_MIN:
  case ZT_FN_MAX: {
    int want_max = c->fn == ZT_FN_MAX;
    if (c->kind == ZT_KIND_F64) {
      double *o = (double *) c->out;
      for (zt_row g = 0; g < ng; g++) {
        uint8_t f = c->flag[g];
        if (f & ZT_RF_NA) o[g] = ZT_F64_NA;
        else if (f & ZT_RF_MISS) o[g] = ZT_F64_NAN;
        /* A NaN value is the greatest: max is NaN when the group has one,
           min only when it has nothing else. */
        else if ((f & ZT_RF_NAN) && (want_max || !c->cnt[g])) o[g] = ZT_F64_NAN;
        else if (!c->cnt[g]) o[g] = ZT_F64_NA;
      }
    } else {
      int32_t *o = (int32_t *) c->out;
      for (zt_row g = 0; g < ng; g++) {
        if ((c->flag[g] & ZT_RF_NA) || !c->cnt[g]) o[g] = INT32_MIN;
      }
    }
    break;
  }
  default:
    break;
  }
}

/* Reduce the ncol columns over the n rows, ids[i] in 0 .. ng - 1. */
ZT_INLINE void zt_reduce(const zt_row *ids, zt_row n, zt_row ng, zt_reduce_col *cols,
                         int ncol) {
  for (int k = 0; k < ncol; k++) zt_reduce_init(&cols[k], ng);
  for (zt_row lo = 0; lo < n; lo += ZT_REDUCE_BLOCK) {
    zt_row hi = n - lo < ZT_REDUCE_BLOCK ? n : lo + ZT_REDUCE_BLOCK;
    for (int k = 0; k < ncol; k++) zt_reduce_block(&cols[k], ids, lo, hi);
  }
  int second = 0;
  for (int k = 0; k < ncol; k++) {
    if (cols[k].fn == ZT_FN_MEAN && cols[k].kind == ZT_KIND_F64) {
      zt_reduce_mid(&cols[k], ng);
      second = 1;
    }
  }
  if (second) {
    for (zt_row lo = 0; lo < n; lo += ZT_REDUCE_BLOCK) {
      zt_row hi = n - lo < ZT_REDUCE_BLOCK ? n : lo + ZT_REDUCE_BLOCK;
      for (int k = 0; k < ncol; k++) {
        if (cols[k].fn == ZT_FN_MEAN && cols[k].kind == ZT_KIND_F64) {
          zt_reduce_block_mean2(&cols[k], ids, lo, hi);
        }
      }
    }
  }
  for (int k = 0; k < ncol; k++) zt_reduce_finish(&cols[k], ng);
}

#endif /* ZUTABLE_REDUCE_H */
