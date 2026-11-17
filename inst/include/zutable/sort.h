/*
 * zutable/sort.h -- sort order over keys (design-kernel 4.3, 6.3).
 *
 * The normalised key. Each key column becomes an unsigned code whose
 * integer order is the sort order: a valid value's ordinal shifted to
 * start at 0 (range compression, so narrow keys take few bits) and
 * reversed for `decreasing`, with one slot for missing values at either
 * end. -0 equals 0; NA and NaN are equal and missing, as base R's order
 * has them. The codes of several keys are packed into one record when
 * they fit in 64 bits, the last key lowest; otherwise the keys are sorted
 * in chunks of at most 64 bits, last chunk first, each pass stable.
 *
 * The hybrid (hybrid.inc). A record holds its code and its row, so the
 * sort is stable whatever algorithm runs: Vergesort's run detection in
 * front, and between runs insertion sort at the leaf, counting sort when
 * the codes span fewer values than there are rows and fewer than 4096,
 * pdqsort for small n,
 * LSD radix for keys of up to 32 bits, ska sort for wider ones, and one
 * MSD pass then LSD from a million rows. The thresholds are read off the
 * regime map in .agents/benchmarks.md.
 *
 *   zt_order_prepare(cols, ncol, n, na_last, cb, plan)
 *       fills the ncol code books and returns the scratch bytes the order
 *       needs: 20 per row with keys of up to 32 bits a chunk, 36 above,
 *       and 0 when one key's values never fall, or never rise.
 *   zt_order_run(cols, ncol, n, na_last, cb, plan, out, mem)
 *       the stable permutation, 0-based, in out; returns its length (rows
 *       with a missing key are dropped when na_last < 0).
 *   zt_order(cols, ncol, n, na_last, cb, out, mem)
 *       both, with mem of zt_sort_scratch_bytes(n), enough for any order.
 *   zt_rank(cols, ncol, n, na_last, ties, cb, out, mem, ord)
 *       ranks, 1-based, in out; ord is n rows of scratch.
 */
#ifndef ZUTABLE_SORT_H
#define ZUTABLE_SORT_H

#include "config.h"
#include "key.h"
#include "sortrec.h"
#include "pdqsort.h"
#include "vergesort.h"
#include "radix.h"
#include "skasort.h"

/* The hybrid's thresholds (from the regime map). */
#ifndef ZT_SORT_LEAF
#define ZT_SORT_LEAF 24          /* insertion sort below this */
#endif
#ifndef ZT_SORT_RADIX_MIN
#define ZT_SORT_RADIX_MIN 1000   /* pdqsort below this */
#endif
#ifndef ZT_SORT_DENSE_MAX
#define ZT_SORT_DENSE_MAX 4096   /* counting sort only below this many code values */
#endif
#ifndef ZT_SORT_MSD_MIN
#define ZT_SORT_MSD_MIN 1000000  /* MSD then LSD from this many records */
#endif

/* A key column to sort by: INT32, LGL, I64 or F64. */
typedef struct {
  zt_kind kind;
  const void *data;
  int decreasing;
} zt_sort_col;

/* Scratch for one order: records and their copy (8 bytes each, or 16
   when a chunk of keys is wider than 32 bits), the permutation between
   chunks, and counts for the dense path. */
typedef struct {
  void *rec;      /* n records */
  void *tmp;      /* n records */
  zt_row *perm;   /* n */
  uint32_t *cnt;  /* ZT_SORT_DENSE_MAX + 2 */
} zt_sort_scratch;

ZT_INLINE size_t zt_sort_scratch_bytes_for(zt_row n, int wide) {
  size_t m = n > 0 ? (size_t) n : 1;
  size_t rec = wide ? sizeof(zt_r128) : sizeof(zt_w64);
  return 2 * m * rec + m * sizeof(zt_row) + (ZT_SORT_DENSE_MAX + 2) * sizeof(uint32_t);
}

/* Enough for any order of n rows. */
ZT_INLINE size_t zt_sort_scratch_bytes(zt_row n) { return zt_sort_scratch_bytes_for(n, 1); }

ZT_INLINE void zt_sort_scratch_init(zt_sort_scratch *s, void *mem, zt_row n, int wide) {
  size_t m = n > 0 ? (size_t) n : 1;
  size_t rec = wide ? sizeof(zt_r128) : sizeof(zt_w64);
  char *p = (char *) mem;
  s->rec = p; p += m * rec;
  s->tmp = p; p += m * rec;
  s->perm = (zt_row *) p; p += m * sizeof(zt_row);
  s->cnt = (uint32_t *) p;
}

/* ---- the normalised key ------------------------------------------------ */

/* A key's code book: valid values map to [lo, lo + range], missing to
   `na_code` (unused when has_na is 0 or missing rows are dropped). And
   what one pass saw of its order, for the fast paths. */
typedef struct {
  uint64_t umin, umax, range;
  uint64_t lo, na_code;
  int has_na, width; /* width: bits of the largest code */
  int any_missing;   /* a missing cell, whatever na_last */
  int nondec, noninc; /* ordinals never fall, never rise; no missing cell */
} zt_codebook;

/* The ordinal of a valid value: int32 and int64 offset to unsigned, a
   double's bits twiddled so their unsigned order is its order, -0 as 0. */
ZT_INLINE uint64_t zt_ord_i32(int32_t x) { return (uint64_t) ((uint32_t) x ^ UINT32_C(0x80000000)); }
ZT_INLINE uint64_t zt_ord_i64(int64_t x) { return (uint64_t) x ^ UINT64_C(0x8000000000000000); }
ZT_INLINE uint64_t zt_ord_f64(double x) {
  uint64_t b;
  if (x == 0.0) x = 0.0;
  memcpy(&b, &x, sizeof b);
  return (b >> 63) ? ~b : (b | UINT64_C(0x8000000000000000));
}
#define ZT_MISS_I32(x) ((x) == INT32_MIN)
#define ZT_MISS_I64(x) ((x) == INT64_MIN)
#define ZT_MISS_F64(x) ((x) != (x))

/* The ordinal of a cell and whether it is missing. */
ZT_INLINE int zt_sort_ordinal(const zt_sort_col *c, zt_row i, uint64_t *u) {
  switch (c->kind) {
  case ZT_KIND_INT32:
  case ZT_KIND_LGL: {
    int32_t x = ((const int32_t *) c->data)[i];
    if (ZT_MISS_I32(x)) return 1;
    *u = zt_ord_i32(x);
    return 0;
  }
  case ZT_KIND_I64: {
    int64_t x = ((const int64_t *) c->data)[i];
    if (ZT_MISS_I64(x)) return 1;
    *u = zt_ord_i64(x);
    return 0;
  }
  case ZT_KIND_F64: {
    double x = ((const double *) c->data)[i];
    if (ZT_MISS_F64(x)) return 1;
    *u = zt_ord_f64(x);
    return 0;
  }
  default:
    *u = 0;
    return 1;
  }
}

ZT_INLINE int zt_bits_of(uint64_t v) {
  int b = 0;
  while (v) { b++; v >>= 1; }
  return b;
}

/* One pass over a column, a loop per kind: its range, whether it has
   missing values, and whether its ordinals already run in order; then
   the code book for na_last (1 last, 0 first, -1 dropped). */
#define ZT_CB_LOOP(TYPE, MISS, ORD) do {                                     \
    const TYPE *x = (const TYPE *) c->data;                                   \
    uint64_t prev = 0;                                                         \
    for (zt_row i = 0; i < n; i++) {                                           \
      TYPE v = x[i];                                                           \
      if (MISS(v)) { any_missing = 1; continue; }                              \
      uint64_t u = ORD(v);                                                     \
      if (u < umin) umin = u;                                                  \
      if (u > umax) umax = u;                                                  \
      if (i > 0) {                                                             \
        nondec &= u >= prev; noninc &= u <= prev;                              \
      }                                                                        \
      prev = u;                                                                \
    }                                                                          \
  } while (0)

ZT_INLINE void zt_codebook_build(const zt_sort_col *c, zt_row n, int na_last,
                                 zt_codebook *cb) {
  uint64_t umin = UINT64_MAX, umax = 0;
  int any_missing = 0, nondec = 1, noninc = 1;
  switch (c->kind) {
  case ZT_KIND_INT32:
  case ZT_KIND_LGL: ZT_CB_LOOP(int32_t, ZT_MISS_I32, zt_ord_i32); break;
  case ZT_KIND_I64: ZT_CB_LOOP(int64_t, ZT_MISS_I64, zt_ord_i64); break;
  case ZT_KIND_F64: ZT_CB_LOOP(double, ZT_MISS_F64, zt_ord_f64); break;
  default: any_missing = n > 0; break;
  }
  if (umin > umax) { umin = 0; umax = 0; }
  cb->umin = umin;
  cb->umax = umax;
  cb->range = umax - umin;
  cb->any_missing = any_missing;
  cb->has_na = any_missing && na_last >= 0;
  cb->lo = (cb->has_na && na_last == 0) ? 1 : 0;
  cb->na_code = na_last == 0 ? 0 : cb->lo + cb->range + 1;
  cb->width = zt_bits_of(cb->has_na ? cb->lo + cb->range + (na_last != 0) : cb->range);
  cb->nondec = nondec && !any_missing;
  cb->noninc = noninc && !any_missing;
}
#undef ZT_CB_LOOP

/* The code of row i; 1 if the cell is missing (its code is na_code). */
ZT_INLINE int zt_code(const zt_sort_col *c, const zt_codebook *cb, zt_row i,
                      uint64_t *code) {
  uint64_t u;
  if (zt_sort_ordinal(c, i, &u)) { *code = cb->na_code; return 1; }
  *code = cb->lo + (c->decreasing ? cb->umax - u : u - cb->umin);
  return 0;
}

/* Shift each row's code into acc[j * stride], a loop per kind: rows[j]
   is the row (j itself when rows is NULL). */
#define ZT_ENC_LOOP(TYPE, MISS, ORD) do {                                    \
    const TYPE *x = (const TYPE *) c->data;                                   \
    for (zt_row j = 0; j < m; j++) {                                           \
      TYPE v = x[rows ? rows[j] : j];                                          \
      uint64_t code;                                                           \
      if (MISS(v)) code = na;                                                  \
      else { uint64_t u = ORD(v); code = lo + (dec ? umax - u : u - umin); }   \
      uint64_t *p = acc + (size_t) j * stride;                                 \
      *p = w >= 64 ? code : ((*p << w) | code);                                \
    }                                                                          \
  } while (0)

ZT_INLINE void zt_encode_col(const zt_sort_col *c, const zt_codebook *cb,
                             const zt_row *rows, zt_row m, uint64_t *acc, size_t stride) {
  const uint64_t na = cb->na_code, lo = cb->lo, umin = cb->umin, umax = cb->umax;
  const int dec = c->decreasing, w = cb->width;
  switch (c->kind) {
  case ZT_KIND_INT32:
  case ZT_KIND_LGL: ZT_ENC_LOOP(int32_t, ZT_MISS_I32, zt_ord_i32); break;
  case ZT_KIND_I64: ZT_ENC_LOOP(int64_t, ZT_MISS_I64, zt_ord_i64); break;
  case ZT_KIND_F64: ZT_ENC_LOOP(double, ZT_MISS_F64, zt_ord_f64); break;
  default: break;
  }
}
#undef ZT_ENC_LOOP

/* ---- the hybrid -------------------------------------------------------- */

typedef struct {
  int kbits;
  uint64_t range;
  uint32_t *cnt;
} zt_hybrid_ctx;

#define ZT_SORT_T zt_w64
#define ZT_SORT_SUF w64
#define ZT_SORT_NBYTES ZT_NBYTES_w64
#include "hybrid.inc"
#undef ZT_SORT_T
#undef ZT_SORT_SUF
#undef ZT_SORT_NBYTES

#define ZT_SORT_T zt_r128
#define ZT_SORT_SUF r128
#define ZT_SORT_NBYTES ZT_NBYTES_r128
#include "hybrid.inc"
#undef ZT_SORT_T
#undef ZT_SORT_SUF
#undef ZT_SORT_NBYTES


/* ---- order ------------------------------------------------------------- */

/* What zt_order_prepare decided: 16-byte records needed, and a fast path
   (1: the codes never decrease, so the rows are in order; 2: they never
   increase, so the order is the runs of equal codes, last run first, each
   in row order). */
typedef struct {
  int wide;
  int fast;
} zt_order_plan;

/* The chunks of keys, at most 64 bits each, last chunk first: [k0, k1)
   for the chunk ending at k1. */
ZT_INLINE int zt_chunk_start(const zt_codebook *cb, int k1) {
  int k0 = k1 - 1, width = cb[k0].width;
  while (k0 > 0 && width + cb[k0 - 1].width <= 64) width += cb[--k0].width;
  return k0;
}

/* Builds the code books and returns the scratch bytes the order needs (0
   for a fast path). */
ZT_INLINE size_t zt_order_prepare(const zt_sort_col *cols, int ncol, zt_row n,
                                  int na_last, zt_codebook *cb, zt_order_plan *p) {
  for (int k = 0; k < ncol; k++) zt_codebook_build(&cols[k], n, na_last, &cb[k]);
  p->wide = 0;
  p->fast = 0;
  for (int k1 = ncol; k1 > 0;) {
    int k0 = zt_chunk_start(cb, k1), width = 0;
    for (int k = k0; k < k1; k++) width += cb[k].width;
    if (width > 32) p->wide = 1;
    k1 = k0;
  }
  if (ncol == 1 && n > 1) {
    const zt_codebook *c = &cb[0];
    int dec = cols[0].decreasing;
    if (dec ? c->noninc : c->nondec) p->fast = 1;
    else if (dec ? c->nondec : c->noninc) p->fast = 2;
  }
  return p->fast ? 0 : zt_sort_scratch_bytes_for(n, p->wide);
}

/* Sort the m rows of `rows` (NULL: rows 0 .. m - 1) by keys [k0, k1),
   stably, writing the sorted rows to out (which may be rows). */
ZT_INLINE void zt_order_chunk(const zt_sort_col *cols, const zt_codebook *cb,
                              int k0, int k1, const zt_row *rows, zt_row m,
                              zt_row *out, zt_sort_scratch *s) {
  int width = 0;
  for (int k = k0; k < k1; k++) width += cb[k].width;
  /* The packed code's range: exact for one key, bounded for several. */
  uint64_t range;
  if (k1 - k0 == 1) {
    range = cb[k0].has_na ? cb[k0].lo + cb[k0].range + (cb[k0].na_code != 0) : cb[k0].range;
  } else {
    range = width >= 64 ? UINT64_MAX : ((UINT64_C(1) << width) - 1);
  }
  /* Writing in place needs the permutation as a buffer. */
  zt_row *dst = rows == out ? s->perm : out;
  if (width <= 32) {
    zt_w64 *a = (zt_w64 *) s->rec;
    memset(a, 0, (size_t) m * sizeof *a);
    for (int k = k0; k < k1; k++) zt_encode_col(&cols[k], &cb[k], rows, m, a, 1);
    for (zt_row j = 0; j < m; j++) a[j] = (a[j] << 32) | (uint64_t) (uint32_t) j;
    zt_hybrid_w64(a, (size_t) m, width, range, (zt_w64 *) s->tmp, s->cnt);
    if (rows) for (zt_row j = 0; j < m; j++) dst[j] = rows[(uint32_t) a[j]];
    else for (zt_row j = 0; j < m; j++) dst[j] = (zt_row) (uint32_t) a[j];
  } else {
    zt_r128 *a = (zt_r128 *) s->rec;
    for (zt_row j = 0; j < m; j++) { a[j].k = 0; a[j].i = (uint64_t) j; }
    for (int k = k0; k < k1; k++) zt_encode_col(&cols[k], &cb[k], rows, m, &a[0].k, 2);
    zt_hybrid_r128(a, (size_t) m, width, range, (zt_r128 *) s->tmp, s->cnt);
    if (rows) for (zt_row j = 0; j < m; j++) dst[j] = rows[a[j].i];
    else for (zt_row j = 0; j < m; j++) dst[j] = (zt_row) a[j].i;
  }
  if (dst != out) memcpy(out, dst, (size_t) m * sizeof(zt_row));
}

/* The order zt_order_prepare planned, in out (0-based); mem holds the
   bytes it asked for. Returns the permutation's length. */
ZT_INLINE zt_row zt_order_run(const zt_sort_col *cols, int ncol, zt_row n, int na_last,
                              const zt_codebook *cb, const zt_order_plan *p,
                              zt_row *out, void *mem) {
  if (p->fast == 1) { for (zt_row i = 0; i < n; i++) out[i] = i; return n; }
  if (p->fast == 2) {
    /* A stable reverse: each run of equal values keeps its row order. */
    zt_row j = 0, e = n;
    while (e > 0) {
      zt_row b = e - 1;
      uint64_t ub, u;
      (void) zt_sort_ordinal(&cols[0], b, &ub);
      while (b > 0 && !zt_sort_ordinal(&cols[0], b - 1, &u) && u == ub) b--;
      for (zt_row i = b; i < e; i++) out[j++] = i;
      e = b;
    }
    return n;
  }
  /* Rows with a missing key are dropped first when na_last < 0. */
  int drop = 0;
  if (na_last < 0) for (int k = 0; k < ncol; k++) drop |= cb[k].any_missing;
  zt_row m = n;
  if (drop) {
    m = 0;
    for (zt_row i = 0; i < n; i++) {
      int miss = 0;
      for (int k = 0; k < ncol && !miss; k++) {
        uint64_t u;
        miss = zt_sort_ordinal(&cols[k], i, &u);
      }
      if (!miss) out[m++] = i;
    }
  } else if (ncol == 0 || n < 2) {
    for (zt_row i = 0; i < n; i++) out[i] = i;
  }
  if (ncol == 0 || m < 2) return m;
  zt_sort_scratch s;
  zt_sort_scratch_init(&s, mem, m, p->wide);
  const zt_row *rows = drop ? out : NULL;
  for (int k1 = ncol; k1 > 0;) {
    int k0 = zt_chunk_start(cb, k1);
    zt_order_chunk(cols, cb, k0, k1, rows, m, out, &s);
    rows = out;
    k1 = k0;
  }
  return m;
}

/* The stable permutation of rows by the keys, in out (0-based, n rows at
   most); na_last 1 puts missing last, 0 first, -1 drops rows with any
   missing key. Returns the permutation's length. cb holds ncol code books
   (filled here); mem holds zt_sort_scratch_bytes(n). */
ZT_INLINE zt_row zt_order(const zt_sort_col *cols, int ncol, zt_row n, int na_last,
                          zt_codebook *cb, zt_row *out, void *mem) {
  zt_order_plan p;
  (void) zt_order_prepare(cols, ncol, n, na_last, cb, &p);
  return zt_order_run(cols, ncol, n, na_last, cb, &p, out, mem);
}

/* ---- rank -------------------------------------------------------------- */

typedef enum { ZT_TIES_MIN = 1, ZT_TIES_FIRST = 2, ZT_TIES_DENSE = 3 } zt_ties;

/* Whether row i has a missing key. */
ZT_INLINE int zt_row_missing(const zt_sort_col *cols, int ncol, zt_row i) {
  for (int k = 0; k < ncol; k++) {
    uint64_t u;
    if (zt_sort_ordinal(&cols[k], i, &u)) return 1;
  }
  return 0;
}

/* Whether rows i and j have the same code in every key. */
ZT_INLINE int zt_rows_tie(const zt_sort_col *cols, const zt_codebook *cb, int ncol,
                          zt_row i, zt_row j) {
  for (int k = 0; k < ncol; k++) {
    uint64_t a, b;
    (void) zt_code(&cols[k], &cb[k], i, &a);
    (void) zt_code(&cols[k], &cb[k], j, &b);
    if (a != b) return 0;
  }
  return 1;
}

/* Ranks in out[0, n), by row, 1-based, as rank() gives them: equal keys
   share the lowest rank of their run ("min"), take their place in row
   order ("first") or number the distinct keys ("dense"). For "min" and
   "first" a row with a missing key ranks apart from every other, as
   rank() ranks NA; for "dense" the rows of one missing key share a rank.
   With na_last < 0 rows with a missing key are left out and get rank 0,
   which the caller drops. ord: n rows of scratch for the order; mem:
   zt_sort_scratch_bytes(n). */
ZT_INLINE void zt_rank(const zt_sort_col *cols, int ncol, zt_row n, int na_last,
                       zt_ties ties, zt_codebook *cb, zt_row *out, void *mem,
                       zt_row *ord) {
  zt_row m = zt_order(cols, ncol, n, na_last, cb, ord, mem);
  for (zt_row i = 0; i < n; i++) out[i] = 0;
  zt_row rank = 0, dense = 0;
  for (zt_row j = 0; j < m; j++) {
    zt_row r = ord[j];
    int tie = j > 0 && zt_rows_tie(cols, cb, ncol, r, ord[j - 1]);
    if (!tie) dense++;
    if (ties == ZT_TIES_DENSE) {
      out[r] = dense;
    } else {
      if (ties == ZT_TIES_FIRST || !tie || zt_row_missing(cols, ncol, r)) rank = j + 1;
      out[r] = rank;
    }
  }
}


#endif /* ZUTABLE_SORT_H */
