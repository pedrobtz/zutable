/*
 * zutable/table.h -- the hash table (design-kernel section 4, layer 2).
 *
 * Open addressing, linear probing, power-of-two capacity, load at most
 * 7/8. One metadata byte per slot: 0 for empty, or 0x80 with seven bits of
 * the hash as a filter. A slot holds a 32-bit row index into the caller's
 * key columns: keys are never copied, so a slot costs five bytes and a
 * probe compares against the caller's own vectors.
 *
 * The caller owns the memory (under R, R_alloc, freed even on an error);
 * zt_table_bytes() says how much a capacity needs.
 */
#ifndef ZUTABLE_TABLE_H
#define ZUTABLE_TABLE_H

#include "config.h"
#include "key.h"

typedef struct {
  uint8_t *meta;
  zt_row *row;
  uint32_t mask;
  zt_row count;
} zt_table;

/* The capacity for n keys at load 7/8: a power of two, at least 16 and at
   most 2^32, which holds the 2^31 - 1 keys a table of that many rows can
   have (a mask of 32 bits). */
ZT_INLINE uint64_t zt_table_capacity(zt_row n) {
  uint64_t need = (uint64_t) (n < 0 ? 0 : n) * 8 / 7 + 1;
  uint64_t cap = 16;
  while (cap < need && cap < (UINT64_C(1) << 32)) cap <<= 1;
  return cap;
}

ZT_INLINE size_t zt_table_bytes(uint64_t cap) {
  return (size_t) cap * (sizeof(uint8_t) + sizeof(zt_row));
}

/* Lay a table over `mem`, of zt_table_bytes(cap) bytes, and empty it. */
ZT_INLINE void zt_table_init(zt_table *t, void *mem, uint64_t cap) {
  t->row = (zt_row *) mem;
  t->meta = (uint8_t *) mem + (size_t) cap * sizeof(zt_row);
  memset(t->meta, 0, (size_t) cap);
  t->mask = (uint32_t) (cap - 1);
  t->count = 0;
}

ZT_INLINE uint8_t zt_tag(uint64_t h) { return (uint8_t) (0x80u | (h >> 57)); }

/* The slot of row i's key: the existing one, or a new one holding i.
   *inserted says which. The table must have a free slot. */
ZT_INLINE uint32_t zt_table_insert(zt_table *t, const zt_key *k, zt_row i,
                                   uint64_t h, int *inserted) {
  uint8_t tag = zt_tag(h);
  uint32_t s = (uint32_t) h & t->mask;
  for (;;) {
    uint8_t m = t->meta[s];
    if (m == 0) {
      t->meta[s] = tag;
      t->row[s] = i;
      t->count++;
      *inserted = 1;
      return s;
    }
    if (m == tag && zt_key_eq(k, t->row[s], i)) {
      *inserted = 0;
      return s;
    }
    s = (s + 1) & t->mask;
  }
}

/* Move every key of `from` into `to`, an empty table with more slots,
   reading each key's hash from h (keys are rows, so nothing is copied but
   the row index): the doubling of section 4. */
ZT_INLINE void zt_table_rehash(const zt_table *from, zt_table *to,
                               const uint64_t *h) {
  for (uint64_t s = 0; s <= from->mask; s++) {
    if (!from->meta[s]) continue;
    zt_row i = from->row[s];
    uint32_t d = (uint32_t) h[i] & to->mask;
    while (to->meta[d]) d = (d + 1) & to->mask;
    to->meta[d] = from->meta[s];
    to->row[d] = i;
  }
  to->count = from->count;
}

/* The slot holding row i's key, or UINT32_MAX when there is none. */
ZT_INLINE uint32_t zt_table_find(const zt_table *t, const zt_key *build,
                                 const zt_key *probe, zt_row i, uint64_t h,
                                 int (*eq)(const zt_key *, zt_row,
                                           const zt_key *, zt_row)) {
  uint8_t tag = zt_tag(h);
  uint32_t s = (uint32_t) h & t->mask;
  for (;;) {
    uint8_t m = t->meta[s];
    if (m == 0) return UINT32_MAX;
    if (m == tag && eq(build, t->row[s], probe, i)) return s;
    s = (s + 1) & t->mask;
  }
}

#endif /* ZUTABLE_TABLE_H */
