/*
 * The radix and counting sorts of radix.h, once per record type. Written
 * for zutable; no upstream code.
 */

#define T ZT_SORT_T
#define KEY ZT_SORT_KEY

/* LSD radix of a[0, n) by the low kbits of the key, digits of dbits bits,
   stable. Every digit's histogram is taken in one pass, and a digit all
   records share is skipped. The result is in a. */
ZT_INLINE void ZT_SORT_FN(zt_lsd)(T *a, size_t n, int kbits, int dbits, T *tmp) {
  if (n < 2 || kbits <= 0) return;
  if (dbits < 1) dbits = 8;
  if (dbits > ZT_RADIX_MAX_DBITS) dbits = ZT_RADIX_MAX_DBITS;
  int npass = (kbits + dbits - 1) / dbits;
  if (npass > ZT_RADIX_MAX_PASSES) npass = ZT_RADIX_MAX_PASSES;
  const size_t nb = (size_t) 1 << dbits;
  const uint64_t mask = nb - 1;
  uint32_t hist[ZT_RADIX_MAX_PASSES][(size_t) 1 << ZT_RADIX_MAX_DBITS];
  for (int p = 0; p < npass; p++) memset(hist[p], 0, nb * sizeof(uint32_t));
  for (size_t i = 0; i < n; i++) {
    uint64_t k = KEY(a[i]);
    for (int p = 0; p < npass; p++) hist[p][(k >> (p * dbits)) & mask]++;
  }
  T *src = a, *dst = tmp;
  uint64_t k0 = KEY(a[0]);
  for (int p = 0; p < npass; p++) {
    int shift = p * dbits;
    /* Byte skipping: one bucket holds every record. */
    if (hist[p][(k0 >> shift) & mask] == (uint32_t) n) continue;
    uint32_t sum = 0;
    for (size_t d = 0; d < nb; d++) {
      uint32_t c = hist[p][d];
      hist[p][d] = sum;
      sum += c;
    }
    for (size_t i = 0; i < n; i++) {
      T r = src[i];
      dst[hist[p][(KEY(r) >> shift) & mask]++] = r;
    }
    T *t = src; src = dst; dst = t;
  }
  if (src != a) memcpy(a, src, n * sizeof(T));
}

/* One MSD pass on the top 8 of kbits into tmp, then LSD within each
   bucket on the bits below, bucket by bucket; the result is in a. */
ZT_INLINE void ZT_SORT_FN(zt_msd_lsd)(T *a, size_t n, int kbits, T *tmp) {
  if (n < 2 || kbits <= 0) return;
  if (kbits <= 8) { ZT_SORT_FN(zt_lsd)(a, n, kbits, 8, tmp); return; }
  int shift = kbits - 8;
  uint32_t start[257];
  memset(start, 0, sizeof start);
  for (size_t i = 0; i < n; i++) start[((KEY(a[i]) >> shift) & 255u) + 1]++;
  for (int d = 0; d < 256; d++) start[d + 1] += start[d];
  uint32_t pos[256];
  memcpy(pos, start, sizeof pos);
  for (size_t i = 0; i < n; i++) {
    T r = a[i];
    tmp[pos[(KEY(r) >> shift) & 255u]++] = r;
  }
  for (int d = 0; d < 256; d++) {
    size_t lo = start[d], m = start[d + 1] - lo;
    if (!m) continue;
    /* Sort the bucket in tmp with a's slice as scratch, then move it. */
    ZT_SORT_FN(zt_lsd)(tmp + lo, m, shift, 8, a + lo);
    memcpy(a + lo, tmp + lo, m * sizeof(T));
  }
}

/* Counting sort of keys in [kmin, kmin + range], stable. */
ZT_INLINE void ZT_SORT_FN(zt_counting)(T *a, size_t n, uint64_t kmin,
                                        uint64_t range, T *tmp, uint32_t *cnt) {
  if (n < 2) return;
  size_t m = (size_t) range + 1;
  memset(cnt, 0, (m + 1) * sizeof(uint32_t));
  for (size_t i = 0; i < n; i++) cnt[(size_t) (KEY(a[i]) - kmin) + 1]++;
  for (size_t d = 0; d < m; d++) cnt[d + 1] += cnt[d];
  for (size_t i = 0; i < n; i++) {
    T r = a[i];
    tmp[cnt[(size_t) (KEY(r) - kmin)]++] = r;
  }
  memcpy(a, tmp, n * sizeof(T));
}

#undef T
#undef KEY
