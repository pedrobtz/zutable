/*
 * zutable/partition.h -- the partitioner (design-kernel 4, layer 3; 4.1).
 *
 * Rows are split by the top bits of their hash into partitions whose tables
 * fit in L2, with a histogram pass and a scatter pass; rows keep their order
 * within a partition. The input is partitioned only when its table would
 * not fit in L3 (one pass below that): the cost model the Stage 9 spike
 * measured. The number of distinct keys is estimated with Chao1 over 1024
 * strided samples of the hashes (D37).
 */
#ifndef ZUTABLE_PARTITION_H
#define ZUTABLE_PARTITION_H

#include "config.h"

#ifndef ZT_L2_BYTES
#define ZT_L2_BYTES (256u * 1024u)
#endif
#ifndef ZT_L3_BYTES
#define ZT_L3_BYTES (8u * 1024u * 1024u)
#endif
#define ZT_SAMPLE 1024

/* Chao1's estimate of the number of distinct hashes among n, from up to
   ZT_SAMPLE strided samples, scaled to the population. `scratch` holds
   2 * ZT_SAMPLE uint64_t. */
ZT_INLINE double zt_estimate_distinct(const uint64_t *h, zt_row n,
                                      uint64_t *scratch) {
  if (n <= 0) return 0;
  int m = n < ZT_SAMPLE ? (int) n : ZT_SAMPLE;
  uint64_t *s = scratch;
  for (int i = 0; i < m; i++) s[i] = h[(int64_t) i * n / m];
  /* Insertion sort, m <= 1024: counts of each value in the sample. */
  for (int i = 1; i < m; i++) {
    uint64_t v = s[i];
    int j = i - 1;
    while (j >= 0 && s[j] > v) { s[j + 1] = s[j]; j--; }
    s[j + 1] = v;
  }
  double d = 0, f1 = 0, f2 = 0;
  for (int i = 0; i < m;) {
    int j = i;
    while (j < m && s[j] == s[i]) j++;
    int c = j - i;
    d += 1;
    if (c == 1) f1 += 1;
    if (c == 2) f2 += 1;
    i = j;
  }
  double chao = f2 > 0 ? d + f1 * f1 / (2 * f2) : d + f1 * (f1 - 1) / 2;
  if (m == n) return d;
  /* All singletons: the keys look distinct; assume as many as rows. */
  if (f1 == m) return (double) n;
  double scaled = chao * (double) n / (double) m;
  return chao > scaled ? scaled : (chao > (double) n ? (double) n : chao);
}

/* Partition bits for `groups` estimated keys: 0 while one table of five
   bytes a slot fits in L3; otherwise enough that each partition's table
   fits in half of L2. */
ZT_INLINE int zt_partition_bits(double groups) {
  double table = groups * 8.0 / 7.0 * 5.0;
  if (table <= (double) ZT_L3_BYTES) return 0;
  int bits = 0;
  while (bits < 16 && table / (double) (1u << bits) > ZT_L2_BYTES / 2.0) bits++;
  return bits;
}

/* Rows grouped by partition, in row order within one: start[p] .. start[p
   + 1] index into `perm`. `start` has (1 << bits) + 1 entries. */
ZT_INLINE void zt_partition(const uint64_t *h, zt_row n, int bits,
                            zt_row *start, zt_row *perm) {
  int np = 1 << bits;
  int shift = 64 - bits;
  for (int p = 0; p <= np; p++) start[p] = 0;
  for (zt_row i = 0; i < n; i++) start[(h[i] >> shift) + 1]++;
  for (int p = 0; p < np; p++) start[p + 1] += start[p];
  /* start[p] is reused as the write position, then restored. */
  for (zt_row i = 0; i < n; i++) perm[start[h[i] >> shift]++] = i;
  for (int p = np; p > 0; p--) start[p] = start[p - 1];
  start[0] = 0;
}

#endif /* ZUTABLE_PARTITION_H */
