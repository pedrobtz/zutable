/*
 * zutable/groups.h -- group identifiers (design-kernel 4, layer 4; 6.2).
 *
 * Every row gets the identifier of its key's group, numbered in order of
 * first appearance, and each group records its first row. Below L3 it is
 * one pass inserting each row (zt_groups_one); above, the caller
 * partitions the rows (partition.h), groups each partition with
 * zt_groups_one at an offset, and relabels to first appearance with
 * zt_groups_relabel: one counting pass over a bitmap of n bits and one
 * gather (section 6.2).
 *
 * The caller owns every buffer; no function here allocates.
 */
#ifndef ZUTABLE_GROUPS_H
#define ZUTABLE_GROUPS_H

#include "config.h"
#include "key.h"
#include "table.h"
#include "partition.h"

#define ZT_MAX_BITS 16

/* Insert rows rows[0 .. m) (or base .. base + m when rows is NULL) into t,
   which may already hold groups g0 .. g0 + *ng; ids[i] receives the group,
   first[g] the first row of each new group. Stops before the insert that
   would pass the table's load limit, 7/8, and returns how many rows it
   processed; the caller grows the table (zt_table_grow) and continues.
   Prefetches the slot eight rows ahead (section 4.1). */
ZT_INLINE zt_row zt_groups_one(const zt_key *k, const uint64_t *h,
                               const zt_row *rows, zt_row base, zt_row m,
                               zt_table *t, zt_row *ids, zt_row *first,
                               zt_row g0, zt_row *ng) {
  uint64_t limit = ((uint64_t) t->mask + 1) / 8 * 7;
  for (zt_row r = 0; r < m; r++) {
    if ((uint64_t) t->count >= limit) return r;
    zt_row i = rows ? rows[r] : base + r;
    if (r + 8 < m) {
      zt_row ahead = rows ? rows[r + 8] : base + r + 8;
      ZT_PREFETCH(&t->meta[(uint32_t) h[ahead] & t->mask]);
    }
    int inserted;
    uint32_t s = zt_table_insert(t, k, i, h[i], &inserted);
    if (inserted) {
      first[g0 + *ng] = i;
      ids[i] = g0 + *ng;
      (*ng)++;
    } else {
      ids[i] = ids[t->row[s]];
    }
  }
  return m;
}

/* Renumber ng groups over n rows so identifiers follow first appearance.
   Scratch: bitmap of (n + 63) / 64 words, word_rank of as many entries,
   newid of ng entries. ids and first are rewritten in place. */
ZT_INLINE void zt_groups_relabel(zt_row n, zt_row ng, zt_row *ids,
                                 zt_row *first, uint64_t *bitmap,
                                 zt_row *word_rank, zt_row *newid) {
  size_t words = ((size_t) n + 63) / 64;
  memset(bitmap, 0, words * sizeof(uint64_t));
  for (zt_row g = 0; g < ng; g++) {
    bitmap[first[g] >> 6] |= UINT64_C(1) << (first[g] & 63);
  }
  zt_row acc = 0;
  for (size_t w = 0; w < words; w++) {
    word_rank[w] = acc;
    uint64_t b = bitmap[w];
    while (b) { acc++; b &= b - 1; }
  }
  for (zt_row g = 0; g < ng; g++) {
    zt_row f = first[g];
    uint64_t below = bitmap[f >> 6] & ((UINT64_C(1) << (f & 63)) - 1);
    zt_row r = word_rank[f >> 6];
    while (below) { r++; below &= below - 1; }
    newid[g] = r;
  }
  for (zt_row i = 0; i < n; i++) ids[i] = newid[ids[i]];
  zt_row g = 0;
  for (size_t w = 0; w < words; w++) {
    uint64_t b = bitmap[w];
    while (b) {
      first[g++] = (zt_row) (w * 64 + (size_t) ZT_CTZ64(b));
      b &= b - 1;
    }
  }
}

/* Sizes and starts of each group, and the stable order that puts each
   group's rows together: two counting passes (section 4.1, "count, then
   fill"). sizes and starts have ng entries, order n. */
ZT_INLINE void zt_groups_order(zt_row n, zt_row ng, const zt_row *ids,
                               zt_row *sizes, zt_row *starts, zt_row *order) {
  for (zt_row g = 0; g < ng; g++) sizes[g] = 0;
  for (zt_row i = 0; i < n; i++) sizes[ids[i]]++;
  zt_row acc = 0;
  for (zt_row g = 0; g < ng; g++) { starts[g] = acc; acc += sizes[g]; }
  for (zt_row i = 0; i < n; i++) order[starts[ids[i]]++] = i;
  for (zt_row g = 0; g < ng; g++) starts[g] -= sizes[g];
}

#endif /* ZUTABLE_GROUPS_H */
