/*
 * zutable/join.h -- equi-joins as index pairs (design-kernel 4, layer 4;
 * 6.4).
 *
 * The kernel groups the smaller side into a table (the build side) and
 * probes it with the other, so that every row of both sides gets a class:
 * the build side's group of its key, or -1 for none. The y rows are then
 * bucketed by class, stably, and each x row emits its class's y rows. The
 * pairs come in x-row order and, within an x row, in y-row order, whichever
 * side was built on (D23): when x is the build side the bucketing is the
 * reorder, and it is part of the join's cost.
 *
 *   zt_key_eq2(a, i, b, j)      row i of key a equals row j of key b
 *   zt_join_build(...)          group the build side, keeping the table
 *   zt_join_probe(...)          the class of each probe row, -1 for none
 *   zt_join_bucket(...)         y rows by class: sizes, starts, order
 *   zt_join_count(...)          how many pairs, and the first fan-out
 *   zt_join_fill(...)           the pairs
 *   zt_join_filter(...)         semi and anti joins: the x rows alone
 *
 * `multiple` (6.4) is the y rows per x row: all of them, the first, the
 * last, or an error the caller raises, naming the first x row that has
 * several. A left join gives an unmatched x row one pair with y = -1.
 *
 * The two keys have one column kind per position; the caller converts
 * (under R, both sides of a pair to one type, strings to UTF-8). Every
 * buffer is the caller's; no function here allocates.
 */
#ifndef ZUTABLE_JOIN_H
#define ZUTABLE_JOIN_H

#include "config.h"
#include "key.h"
#include "table.h"
#include "groups.h"

typedef enum { ZT_JOIN_INNER = 0, ZT_JOIN_LEFT = 1 } zt_join_type;

typedef enum {
  ZT_MULTIPLE_ALL = 0,
  ZT_MULTIPLE_FIRST = 1,
  ZT_MULTIPLE_LAST = 2,
  ZT_MULTIPLE_ERROR = 3
} zt_multiple;

/* Cell i of column a against cell j of column b, of one kind: the
   equality of section 6.1 across two keys. */
ZT_INLINE int zt_cell_eq2(const zt_column *a, zt_row i, const zt_column *b, zt_row j) {
  switch (a->kind) {
  case ZT_KIND_INT32:
  case ZT_KIND_LGL:
    return ((const int32_t *) a->data)[i] == ((const int32_t *) b->data)[j];
  case ZT_KIND_I64:
    return ((const int64_t *) a->data)[i] == ((const int64_t *) b->data)[j];
  case ZT_KIND_F64:
    return zt_f64_bits(((const double *) a->data)[i]) ==
           zt_f64_bits(((const double *) b->data)[j]);
  case ZT_KIND_STR:
    return ((const void *const *) a->data)[i] == ((const void *const *) b->data)[j];
  case ZT_KIND_BYTES: {
    const zt_bytes *x = &((const zt_bytes *) a->data)[i];
    const zt_bytes *y = &((const zt_bytes *) b->data)[j];
    if (x->len != y->len) return 0;
    return x->len <= 0 || memcmp(x->data, y->data, (size_t) x->len) == 0;
  }
  }
  return 0;
}

ZT_INLINE int zt_key_eq2(const zt_key *a, zt_row i, const zt_key *b, zt_row j) {
  for (int c = 0; c < a->ncol; c++) {
    if (!zt_cell_eq2(&a->cols[c], i, &b->cols[c], j)) return 0;
  }
  return 1;
}

/* Group the n rows of the build key b, with hashes h, into t, which holds
   zt_table_capacity(n) slots so it never fills: ids[i] is row i's group
   in first appearance, first[g] the first row of group g. Returns the
   number of groups. t stays for zt_join_probe. */
ZT_INLINE zt_row zt_join_build(const zt_key *b, const uint64_t *h, zt_row n,
                               zt_table *t, zt_row *ids, zt_row *first) {
  zt_row ng = 0;
  zt_groups_one(b, h, NULL, 0, n, t, ids, first, 0, &ng);
  return ng;
}

/* The class of each of the n rows of the probe key p: the build side's
   group (bids, by build row) of an equal key, or -1. */
ZT_INLINE void zt_join_probe(const zt_table *t, const zt_key *b, const zt_row *bids,
                             const zt_key *p, const uint64_t *hp, zt_row n,
                             zt_row *cls) {
  for (zt_row i = 0; i < n; i++) {
    if (i + 8 < n) ZT_PREFETCH(&t->meta[(uint32_t) hp[i + 8] & t->mask]);
    uint32_t s = zt_table_find(t, b, p, i, hp[i], zt_key_eq2);
    cls[i] = s == UINT32_MAX ? -1 : bids[t->row[s]];
  }
}

/* The ny rows of y bucketed by class, ng classes, stably: class g's rows
   are order[start[g] .. start[g] + size[g]), in row order. Rows of class
   -1 are left out. */
ZT_INLINE void zt_join_bucket(zt_row ny, zt_row ng, const zt_row *ycls,
                              zt_row *size, zt_row *start, zt_row *order) {
  for (zt_row g = 0; g < ng; g++) size[g] = 0;
  for (zt_row j = 0; j < ny; j++) if (ycls[j] >= 0) size[ycls[j]]++;
  zt_row acc = 0;
  for (zt_row g = 0; g < ng; g++) { start[g] = acc; acc += size[g]; }
  for (zt_row j = 0; j < ny; j++) if (ycls[j] >= 0) order[start[ycls[j]]++] = j;
  for (zt_row g = 0; g < ng; g++) start[g] -= size[g];
}

/* The y rows x row i pairs with under `multiple`, before a left join's
   unmatched pair. */
ZT_INLINE zt_row zt_join_hits(zt_row c, const zt_row *size, zt_multiple multiple) {
  zt_row m = c < 0 ? 0 : size[c];
  if (m > 1 && (multiple == ZT_MULTIPLE_FIRST || multiple == ZT_MULTIPLE_LAST)) m = 1;
  return m;
}

/* The number of pairs, as 64 bits: it may pass the 2^31 - 1 rows a result
   can have, which the caller refuses. With ZT_MULTIPLE_ERROR, *bad is the
   first x row with several matches and the count stops there; else -1. */
ZT_INLINE int64_t zt_join_count(zt_row nx, const zt_row *xcls, const zt_row *size,
                                zt_join_type type, zt_multiple multiple, zt_row *bad) {
  int64_t total = 0;
  *bad = -1;
  for (zt_row i = 0; i < nx; i++) {
    zt_row m = zt_join_hits(xcls[i], size, multiple);
    if (m > 1 && multiple == ZT_MULTIPLE_ERROR) { *bad = i; return total; }
    if (m == 0 && type == ZT_JOIN_LEFT) m = 1;
    total += m;
  }
  return total;
}

/* The pairs, as many as zt_join_count gave: ox[k], oy[k], with oy = -1
   for a left join's unmatched x row. */
ZT_INLINE void zt_join_fill(zt_row nx, const zt_row *xcls, const zt_row *size,
                            const zt_row *start, const zt_row *order,
                            zt_join_type type, zt_multiple multiple,
                            zt_row *ox, zt_row *oy) {
  size_t k = 0;
  for (zt_row i = 0; i < nx; i++) {
    zt_row c = xcls[i];
    zt_row m = c < 0 ? 0 : size[c];
    if (m == 0) {
      if (type == ZT_JOIN_LEFT) { ox[k] = i; oy[k] = -1; k++; }
      continue;
    }
    const zt_row *ys = order + start[c];
    if (multiple == ZT_MULTIPLE_FIRST) { ox[k] = i; oy[k] = ys[0]; k++; continue; }
    if (multiple == ZT_MULTIPLE_LAST) { ox[k] = i; oy[k] = ys[m - 1]; k++; continue; }
    for (zt_row r = 0; r < m; r++) { ox[k] = i; oy[k] = ys[r]; k++; }
  }
}

/* Semi join (anti = 0): the x rows with a match, in order; anti join
   (anti = 1): those without. Returns how many, written to out. */
ZT_INLINE zt_row zt_join_filter(zt_row nx, const zt_row *xcls, const zt_row *size,
                                int anti, zt_row *out) {
  zt_row k = 0;
  for (zt_row i = 0; i < nx; i++) {
    int hit = xcls[i] >= 0 && size[xcls[i]] > 0;
    if (hit != anti) out[k++] = i;
  }
  return k;
}

#endif /* ZUTABLE_JOIN_H */
