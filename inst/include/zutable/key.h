/*
 * zutable/key.h -- the key model (design-kernel sections 4 and 6.1).
 *
 * A key is one or several columns of one length. A column is one of six
 * kinds; each is hashed with the mixer for its kind and compared by the
 * equality rule of section 6.1. A composite key combines its columns'
 * hashes and compares column by column. Column-at-a-time hashing: the
 * first column is hashed into an array, then each further column is
 * folded in by its own contiguous loop (section 4.1).
 *
 * Strings are opaque interned pointers here: under R, CHARSXPs already
 * translated to UTF-8 by the caller, so equal text is an equal pointer.
 */
#ifndef ZUTABLE_KEY_H
#define ZUTABLE_KEY_H

#include "config.h"
#include <zufast/hash.h>

typedef enum {
  ZT_KIND_INT32 = 1, /* int32_t: integer, factor codes; NA is INT32_MIN */
  ZT_KIND_I64 = 2,   /* int64_t: integer64, no folding */
  ZT_KIND_F64 = 3,   /* double: -0 folded to 0, NaNs folded but for R's NA */
  ZT_KIND_LGL = 4,   /* int32_t: logical */
  ZT_KIND_STR = 5,   /* const void *: interned string pointers */
  ZT_KIND_BYTES = 6  /* zt_bytes: length and pointer */
} zt_kind;

typedef struct {
  const uint8_t *data;
  int32_t len;       /* -1 for a missing element */
} zt_bytes;

typedef struct {
  zt_kind kind;
  const void *data;
} zt_column;

typedef struct {
  const zt_column *cols;
  int ncol;
} zt_key;

/* A 64-bit finalizer (splitmix64's), the mixer for every fixed-width kind. */
ZT_INLINE uint64_t zt_mix64(uint64_t x) {
  x ^= x >> 30;
  x *= UINT64_C(0xbf58476d1ce4e5b9);
  x ^= x >> 27;
  x *= UINT64_C(0x94d049bb133111eb);
  x ^= x >> 31;
  return x;
}

/* Combine a column's hash into a composite key's. */
ZT_INLINE uint64_t zt_hash_combine(uint64_t h, uint64_t k) {
  return zt_mix64(h ^ (k + UINT64_C(0x9e3779b97f4a7c15) + (h << 6) + (h >> 2)));
}

/* The bits a double is keyed by: -0 as 0, every NaN as one NaN except R's
   NA (low word 1954), which stays a key of its own. */
ZT_INLINE uint64_t zt_f64_bits(double v) {
  uint64_t b;
  if (v == 0.0) return 0;
  memcpy(&b, &v, sizeof b);
  if (v != v) {
    if ((uint32_t) b == 1954u) return UINT64_C(0x7ff00000000007a2);
    return UINT64_C(0x7ff8000000000000);
  }
  return b;
}

ZT_INLINE uint64_t zt_hash_cell(const zt_column *c, zt_row i) {
  switch (c->kind) {
  case ZT_KIND_INT32:
  case ZT_KIND_LGL:
    return zt_mix64((uint64_t) (uint32_t) ((const int32_t *) c->data)[i]);
  case ZT_KIND_I64:
    return zt_mix64((uint64_t) ((const int64_t *) c->data)[i]);
  case ZT_KIND_F64:
    return zt_mix64(zt_f64_bits(((const double *) c->data)[i]));
  case ZT_KIND_STR:
    return zt_mix64((uint64_t) (uintptr_t) ((const void *const *) c->data)[i]);
  case ZT_KIND_BYTES: {
    const zt_bytes *b = &((const zt_bytes *) c->data)[i];
    if (b->len < 0) return UINT64_C(0x5bd1e9955bd1e995);
    return zuf_hash64(b->data, (size_t) b->len);
  }
  }
  return 0;
}

ZT_INLINE int zt_cell_eq(const zt_column *c, zt_row i, zt_row j) {
  switch (c->kind) {
  case ZT_KIND_INT32:
  case ZT_KIND_LGL:
    return ((const int32_t *) c->data)[i] == ((const int32_t *) c->data)[j];
  case ZT_KIND_I64:
    return ((const int64_t *) c->data)[i] == ((const int64_t *) c->data)[j];
  case ZT_KIND_F64:
    return zt_f64_bits(((const double *) c->data)[i]) ==
           zt_f64_bits(((const double *) c->data)[j]);
  case ZT_KIND_STR:
    return ((const void *const *) c->data)[i] == ((const void *const *) c->data)[j];
  case ZT_KIND_BYTES: {
    const zt_bytes *a = &((const zt_bytes *) c->data)[i];
    const zt_bytes *b = &((const zt_bytes *) c->data)[j];
    if (a->len != b->len) return 0;
    return a->len <= 0 || memcmp(a->data, b->data, (size_t) a->len) == 0;
  }
  }
  return 0;
}

/* Rows i and j of a key are equal in every column. */
ZT_INLINE int zt_key_eq(const zt_key *k, zt_row i, zt_row j) {
  for (int c = 0; c < k->ncol; c++) {
    if (!zt_cell_eq(&k->cols[c], i, j)) return 0;
  }
  return 1;
}

/* The hash of every row, column at a time, into out[0, n). */
ZT_INLINE void zt_key_hash(const zt_key *k, zt_row n, uint64_t *out) {
  if (k->ncol == 0) {
    for (zt_row i = 0; i < n; i++) out[i] = 0;
    return;
  }
  for (zt_row i = 0; i < n; i++) out[i] = zt_hash_cell(&k->cols[0], i);
  for (int c = 1; c < k->ncol; c++) {
    for (zt_row i = 0; i < n; i++) {
      out[i] = zt_hash_combine(out[i], zt_hash_cell(&k->cols[c], i));
    }
  }
}

#endif /* ZUTABLE_KEY_H */
