// Kernel edges under ASan/UBSan, against brute force.
#include <stdio.h>
#include <stdlib.h>
#include <zutable.h>
static int fails = 0;
#define CHECK(c, ...) do { if (!(c)) { fails++; if (fails < 20) { printf("FAIL: " __VA_ARGS__); printf("\n"); } } } while (0)
static uint64_t rs = 88172645463325252ull;
static uint64_t rnd(void) { rs ^= rs << 13; rs ^= rs >> 7; rs ^= rs << 17; return rs; }
static int cmp128(const void *a, const void *b) { const zt_r128 *x = a, *y = b; if (x->k != y->k) return x->k < y->k ? -1 : 1; return x->i < y->i ? -1 : x->i > y->i; }
static int cmp64(const void *a, const void *b) { zt_w64 x = *(const zt_w64 *) a, y = *(const zt_w64 *) b; return x < y ? -1 : x > y; }
int main(void) {
  // radix routines called directly at every kbits, small and odd n
  int ns[] = {0, 1, 2, 3, 23, 24, 25, 127, 128, 129, 255, 256, 257, 999, 1000, 1001, 2047, 2048, 2049, 5000};
  for (unsigned q = 0; q < sizeof ns / sizeof *ns; q++) for (int kbits = 0; kbits <= 64; kbits++) {
    size_t n = (size_t) ns[q];
    zt_r128 *a = malloc((n + 1) * sizeof *a), *b = malloc((n + 1) * sizeof *a), *c = malloc((n + 1) * sizeof *a), *t = malloc((n + 1) * sizeof *a);
    uint64_t mask = kbits >= 64 ? UINT64_MAX : ((UINT64_C(1) << kbits) - 1);
    int mode = (int) (rnd() % 3);
    for (size_t i = 0; i < n; i++) { uint64_t k = rnd(); if (mode == 1) k = (k % 3) ? mask : 0; if (mode == 2) k >>= (rnd() % 64); a[i].k = k & mask; a[i].i = i; }
    memcpy(b, a, n * sizeof *a); memcpy(c, a, n * sizeof *a); qsort(b, n, sizeof *b, cmp128);
    zt_lsd_r128(c, n, kbits, 8, t); CHECK(!memcmp(b, c, n * sizeof *b), "lsd8 r128 n %zu kbits %d", n, kbits);
    memcpy(c, a, n * sizeof *a); zt_lsd_r128(c, n, kbits, 11, t); CHECK(!memcmp(b, c, n * sizeof *b), "lsd11 r128 n %zu kbits %d", n, kbits);
    memcpy(c, a, n * sizeof *a); zt_msd_lsd_r128(c, n, kbits, t); CHECK(!memcmp(b, c, n * sizeof *b), "msd r128 n %zu kbits %d", n, kbits);
    uint32_t cnt[ZT_SORT_DENSE_MAX + 2];
    memcpy(c, a, n * sizeof *a); zt_hybrid_r128(c, n, kbits, mask, t, cnt); CHECK(!memcmp(b, c, n * sizeof *b), "hybrid r128 n %zu kbits %d", n, kbits);
    if (kbits <= 32) {
      zt_w64 *w = malloc((n + 1) * 8), *w2 = malloc((n + 1) * 8), *wt = malloc((n + 1) * 8);
      for (size_t i = 0; i < n; i++) w[i] = (a[i].k << 32) | i;
      memcpy(w2, w, n * 8); qsort(w2, n, 8, cmp64);
      zt_w64 *w3 = malloc((n + 1) * 8);
      memcpy(w3, w, n * 8); zt_lsd_w64(w3, n, kbits, 8, wt); CHECK(!memcmp(w2, w3, n * 8), "lsd8 w64 n %zu kbits %d", n, kbits);
      memcpy(w3, w, n * 8); zt_lsd_w64(w3, n, kbits, 11, wt); CHECK(!memcmp(w2, w3, n * 8), "lsd11 w64 n %zu kbits %d", n, kbits);
      memcpy(w3, w, n * 8); zt_msd_lsd_w64(w3, n, kbits, wt); CHECK(!memcmp(w2, w3, n * 8), "msd w64 n %zu kbits %d", n, kbits);
      memcpy(w3, w, n * 8); zt_hybrid_w64(w3, n, kbits, mask, wt, cnt); CHECK(!memcmp(w2, w3, n * 8), "hybrid w64 n %zu kbits %d", n, kbits);
      if (mask < ZT_SORT_DENSE_MAX) { memcpy(w3, w, n * 8); zt_counting_w64(w3, n, 0, mask, wt, cnt); CHECK(!memcmp(w2, w3, n * 8), "counting w64 n %zu kbits %d", n, kbits); }
      free(w); free(w2); free(w3); free(wt);
    }
    free(a); free(b); free(c); free(t);
  }
  // orders with zero columns, zero and one rows, every na_last; ranks
  for (int n = 0; n <= 3; n++) for (int na = -1; na <= 1; na++) for (int ncol = 0; ncol <= 2; ncol++) {
    double d[3] = {0.0 / 0.0, 1, 0.0 / 0.0}; int32_t v[3] = {INT32_MIN, INT32_MIN, 5};
    zt_sort_col cols[2] = {{ZT_KIND_F64, d, 1}, {ZT_KIND_INT32, v, 0}};
    zt_codebook cb[2]; zt_row out[4] = {-7, -7, -7, -7}, rk[4], ord[4];
    void *mem = malloc(zt_sort_scratch_bytes(n));
    zt_row m = zt_order(cols, ncol, n, na, cb, out, mem);
    CHECK(m <= n && m >= 0 && out[n] == -7, "order n %d na %d ncol %d m %d", n, na, ncol, m);
    for (zt_row j = 0; j < m; j++) CHECK(out[j] >= 0 && out[j] < n, "order index");
    for (int ties = 1; ties <= 3; ties++) { zt_rank(cols, ncol, n, na, (zt_ties) ties, cb, rk, mem, ord); for (int i = 0; i < n; i++) CHECK(rk[i] >= 0 && rk[i] <= n, "rank range"); }
    free(mem);
  }
  // table capacities: every n up to 5000 keeps the build under the load limit
  for (zt_row n = 0; n < 5000; n++) { uint64_t cap = zt_table_capacity(n); CHECK(cap / 8 * 7 >= (uint64_t) n && (cap & (cap - 1)) == 0, "capacity %d", n); }
  { zt_row big[] = {INT32_MAX, INT32_MAX - 1, 1879048192, 1879048191, 1879048193, 939524096, 939524095, 939524097}; for (int i = 0; i < 8; i++) { uint64_t cap = zt_table_capacity(big[i]); CHECK(cap / 8 * 7 >= (uint64_t) big[i] && cap <= (UINT64_C(1) << 32), "capacity %d cap %llu", big[i], (unsigned long long) cap); } }
  // joins with empty sides and distinct-key builds of n = 13, 14, 15, 16 (capacity 16/32)
  for (zt_row n = 0; n <= 40; n++) {
    int32_t *x = malloc((n + 1) * 4); for (zt_row i = 0; i < n; i++) x[i] = i * 7 - 3;
    zt_column cx = {ZT_KIND_INT32, x}; zt_key k = {&cx, 1};
    uint64_t *h = malloc((n + 1) * 8); zt_key_hash(&k, n, h);
    uint64_t cap = zt_table_capacity(n); zt_table t; void *mem = malloc(zt_table_bytes(cap)); zt_table_init(&t, mem, cap);
    zt_row *ids = malloc((n + 1) * 4), *first = malloc((n + 1) * 4), *cls = malloc((n + 1) * 4);
    for (zt_row i = 0; i < n; i++) ids[i] = -9;
    zt_row ng = zt_join_build(&k, h, n, &t, ids, first);
    CHECK(ng == n, "join build n %d ng %d", n, ng);
    for (zt_row i = 0; i < n; i++) CHECK(ids[i] == i, "join build id");
    zt_join_probe(&t, &k, ids, &k, h, n, cls);
    for (zt_row i = 0; i < n; i++) CHECK(cls[i] == i, "join probe");
    free(x); free(h); free(mem); free(ids); free(first); free(cls);
  }
  // reduce with no groups and no rows; count with a NULL x
  { zt_reduce_col c; memset(&c, 0, sizeof c); int32_t o[1] = {42}; c.fn = ZT_FN_COUNT; c.kind = ZT_KIND_INT32; c.out = o; zt_row ids[1] = {0}; zt_reduce(ids, 0, 0, &c, 1); CHECK(o[0] == 42, "reduce ng 0 wrote"); zt_reduce(ids, 0, 1, &c, 1); CHECK(o[0] == 0, "reduce empty group"); }
  // strings: empty, zero bytes vs padding, missing-free
  { static const uint8_t z[12] = {0}; static const uint8_t ab[] = "abcdefghZ";
    zt_bytes s[] = {{z, 0}, {z, 1}, {z, 8}, {z, 9}, {z, 7}, {ab, 8}, {ab, 9}, {ab, 7}, {z, 0}, {ab, 8}, {z, 12}, {ab, 0}};
    zt_row m = 12, perm[12], rank[12]; void *mem = malloc(zt_str_sort_scratch_bytes(m));
    zt_str_sort(s, m, perm, mem); zt_str_dense_rank(s, m, perm, rank);
    for (zt_row j = 1; j < m; j++) CHECK(zt_bytes_cmp_from(&s[perm[j - 1]], &s[perm[j]], 0) <= 0, "str order at %d", j);
    free(mem); zt_str_sort(s, 0, perm, NULL); }
  printf("fails: %d\n", fails);
  return fails != 0;
}
