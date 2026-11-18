/*
 * zutable/strsort.h -- byte strings in byte order (design-kernel 6.3;
 * 4.2, axis N).
 *
 * Byte order is lexicographic by unsigned byte, a proper prefix first:
 * memcmp()'s order, the shorter string first when one is the start of the
 * other. It is the order of R's radix sort on UTF-8 text, and the order of
 * a raw vector's bytes.
 *
 * Distinct strings are sorted, never rows: the caller groups the rows
 * (groups.h), sorts the distinct strings here, and keys each row by its
 * string's rank, which the integer sort (sort.h) then orders with every
 * other key. With collated order, the strings sorted here are the
 * collation keys of the distinct strings (stringi's), computed once each.
 *
 * Axis N's answer (.agents/benchmarks.md, Stage 12): the first eight
 * bytes packed big-endian into the key of a zt_r128 and sorted by the
 * hybrid, which resolves most strings as integers; each run of equal
 * prefixes is then finished by multikey quicksort (Bentley and Sedgewick,
 * 1997) from the first byte the run does not share. Full comparison and
 * MSD radix over the bytes, the controls, are in tools/bench/str-sort.c.
 *
 *   zt_str_sort_scratch_bytes(m)  scratch for m strings
 *   zt_str_sort(s, m, perm, mem)  perm: the m indices in byte order
 *   zt_str_dense_rank(s, m, perm, rank)
 *       rank[i], 1-based: equal strings share a rank, as in ties = "dense"
 *
 * No function here allocates.
 */
#ifndef ZUTABLE_STRSORT_H
#define ZUTABLE_STRSORT_H

#include "config.h"
#include "key.h"
#include "sort.h"

/* Strings at or below this many go to insertion sort in a run. */
#ifndef ZT_STR_LEAF
#define ZT_STR_LEAF 16
#endif

/* a against b from byte d on, both known equal before d. */
ZT_INLINE int zt_bytes_cmp_from(const zt_bytes *a, const zt_bytes *b, int32_t d) {
  int32_t la = a->len - d, lb = b->len - d;
  if (la < 0) la = 0;
  if (lb < 0) lb = 0;
  int32_t m = la < lb ? la : lb;
  int c = m > 0 ? memcmp(a->data + d, b->data + d, (size_t) m) : 0;
  if (c) return c;
  return (la > lb) - (la < lb);
}

/* Byte d of s plus one, or 0 past its end: the end sorts first. */
ZT_INLINE int zt_str_char(const zt_bytes *s, int32_t d) {
  return d < s->len ? (int) s->data[d] + 1 : 0;
}

/* The first eight bytes, big-endian, zero past the end. */
ZT_INLINE uint64_t zt_str_prefix(const zt_bytes *s) {
  uint64_t k = 0;
  int32_t l = s->len < 8 ? s->len : 8;
  for (int32_t j = 0; j < 8; j++) k = (k << 8) | (j < l ? (uint64_t) s->data[j] : 0);
  return k;
}

ZT_INLINE void zt_str_insertion(const zt_bytes *s, zt_row *x, zt_row n, int32_t d) {
  for (zt_row i = 1; i < n; i++) {
    zt_row v = x[i];
    zt_row j = i;
    while (j > 0 && zt_bytes_cmp_from(&s[x[j - 1]], &s[v], d) > 0) {
      x[j] = x[j - 1];
      j--;
    }
    x[j] = v;
  }
}

/* Multikey quicksort of x[0 .. n), whose strings agree before byte d.
   Each pass splits on byte d into less, equal and greater; the two
   smaller parts recurse and the largest loops, so the stack stays within
   log2(n) frames whatever the strings. */
ZT_INLINE void zt_str_mkqs(const zt_bytes *s, zt_row *x, zt_row n, int32_t d) {
  while (n > ZT_STR_LEAF) {
    int a = zt_str_char(&s[x[0]], d), b = zt_str_char(&s[x[n / 2]], d),
        c = zt_str_char(&s[x[n - 1]], d);
    int v = a < b ? (b < c ? b : (a < c ? c : a)) : (a < c ? a : (b < c ? c : b));
    /* Dijkstra's three-way partition: [0, lt) < v, [lt, i) == v, (gt, n) > v. */
    zt_row lt = 0, i = 0, gt = n - 1;
    while (i <= gt) {
      int ch = zt_str_char(&s[x[i]], d);
      if (ch < v) {
        zt_row t = x[lt]; x[lt] = x[i]; x[i] = t;
        lt++; i++;
      } else if (ch > v) {
        zt_row t = x[gt]; x[gt] = x[i]; x[i] = t;
        gt--;
      } else {
        i++;
      }
    }
    zt_row nl = lt, ne = gt + 1 - lt, ng = n - (gt + 1);
    zt_row *xl = x, *xe = x + lt, *xg = x + gt + 1;
    /* The equal part past every string's end holds equal strings. */
    if (v == 0) ne = 0;
    if (ne >= nl && ne >= ng) {
      zt_str_mkqs(s, xl, nl, d);
      zt_str_mkqs(s, xg, ng, d);
      x = xe; n = ne; d++;
    } else if (nl >= ng) {
      zt_str_mkqs(s, xe, ne, d + 1);
      zt_str_mkqs(s, xg, ng, d);
      n = nl;
    } else {
      zt_str_mkqs(s, xl, nl, d);
      zt_str_mkqs(s, xe, ne, d + 1);
      x = xg; n = ng;
    }
  }
  if (n > 1) zt_str_insertion(s, x, n, d);
}

ZT_INLINE size_t zt_str_sort_scratch_bytes(zt_row m) {
  size_t k = m > 0 ? (size_t) m : 1;
  return 2 * k * sizeof(zt_r128) + (ZT_SORT_DENSE_MAX + 2) * sizeof(uint32_t);
}

/* The indices 0 .. m - 1 of s in byte order, in perm. No string is
   missing; mem holds zt_str_sort_scratch_bytes(m). */
ZT_INLINE void zt_str_sort(const zt_bytes *s, zt_row m, zt_row *perm, void *mem) {
  if (m <= 0) return;
  zt_r128 *a = (zt_r128 *) mem;
  zt_r128 *tmp = a + m;
  uint32_t *cnt = (uint32_t *) (tmp + m);
  for (zt_row j = 0; j < m; j++) {
    a[j].k = zt_str_prefix(&s[j]);
    a[j].i = (uint64_t) j;
  }
  zt_hybrid_r128(a, (size_t) m, 64, UINT64_MAX, tmp, cnt);
  for (zt_row j = 0; j < m; j++) perm[j] = (zt_row) a[j].i;
  for (zt_row j = 0; j < m;) {
    zt_row e = j + 1;
    while (e < m && a[e].k == a[j].k) e++;
    if (e - j > 1) {
      /* The run shares its first eight bytes, or fewer when a string is
         shorter: zero padding is not a zero byte. */
      int32_t d = 8;
      for (zt_row r = j; r < e; r++) if (s[perm[r]].len < d) d = s[perm[r]].len;
      zt_str_mkqs(s, perm + j, e - j, d);
    }
    j = e;
  }
}

/* Dense ranks, 1-based, from the order perm of zt_str_sort. */
ZT_INLINE void zt_str_dense_rank(const zt_bytes *s, zt_row m, const zt_row *perm,
                                 zt_row *rank) {
  zt_row r = 0;
  for (zt_row j = 0; j < m; j++) {
    if (j == 0 || zt_bytes_cmp_from(&s[perm[j - 1]], &s[perm[j]], 0) != 0) r++;
    rank[perm[j]] = r;
  }
}

#endif /* ZUTABLE_STRSORT_H */
