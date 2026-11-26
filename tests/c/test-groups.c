/*
 * The key model, table, partitioner and groups without R (ZT_STANDALONE):
 * random keys against a quadratic reference, the partitioned path against
 * the one-pass path, and the limits of the row index.
 */
#include "zeros.h"
#define ZT_STANDALONE 1
#include <zutable.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { \
  fprintf(stderr, "%s:%d: CHECK failed: %s\n", __FILE__, __LINE__, #cond); \
  failures++; } } while (0)

static uint64_t rng = 20261117;
static uint32_t next(void) { rng = rng * 6364136223846793005ull + 1442695040888963407ull; return (uint32_t) (rng >> 33); }

/* First-appearance ids by brute force. */
static int32_t ref_ids(const zt_key *k, int32_t n, int32_t *ids) {
  int32_t ng = 0;
  for (int32_t i = 0; i < n; i++) {
    ids[i] = -1;
    for (int32_t j = 0; j < i; j++) {
      if (zt_key_eq(k, i, j)) { ids[i] = ids[j]; break; }
    }
    if (ids[i] < 0) ids[i] = ng++;
  }
  return ng;
}

static int32_t run(const zt_key *k, int32_t n, int bits, int32_t *ids, int32_t *first) {
  uint64_t *h = malloc(sizeof(uint64_t) * (n + 1));
  zt_key_hash(k, n, h);
  int32_t ng = 0;
  zt_table t;
  if (bits == 0) {
    /* Start tiny, so the growth path runs. */
    uint64_t cap = 16;
    void *mem = malloc(zt_table_bytes(cap));
    zt_table_init(&t, mem, cap);
    zt_row done = 0;
    for (;;) {
      done += zt_groups_one(k, h, NULL, done, n - done, &t, ids, first, 0, &ng);
      if (done >= n) break;
      uint64_t cap2 = 2 * cap;
      void *mem2 = malloc(zt_table_bytes(cap2));
      zt_table bigger;
      zt_table_init(&bigger, mem2, cap2);
      zt_table_rehash(&t, &bigger, h);
      free(mem);
      mem = mem2; t = bigger; cap = cap2;
    }
    free(mem);
  } else {
    int np = 1 << bits;
    zt_row *start = malloc(sizeof(zt_row) * (np + 1));
    zt_row *perm = malloc(sizeof(zt_row) * (n + 1));
    zt_partition(h, n, bits, start, perm);
    for (int p = 0; p < np; p++) {      /* rows keep their order within one */
      for (zt_row j = start[p] + 1; j < start[p + 1]; j++) CHECK(perm[j - 1] < perm[j]);
    }
    CHECK(start[np] == n);
    uint64_t cap = zt_table_capacity(n);
    void *mem = malloc(zt_table_bytes(cap));
    for (int p = 0; p < np; p++) {
      zt_table_init(&t, mem, cap);
      zt_row png = 0;
      zt_row done = zt_groups_one(k, h, perm + start[p], 0, start[p + 1] - start[p], &t,
                                  ids, first, ng, &png);
      CHECK(done == start[p + 1] - start[p]);
      ng += png;
    }
    size_t words = ((size_t) n + 63) / 64;
    uint64_t *bitmap = malloc(sizeof(uint64_t) * (words + 1));
    zt_row *wr = malloc(sizeof(zt_row) * (words + 1));
    zt_row *newid = malloc(sizeof(zt_row) * (ng + 1));
    zt_groups_relabel(n, ng, ids, first, bitmap, wr, newid);
    free(mem); free(start); free(perm); free(bitmap); free(wr); free(newid);
  }
  free(h);
  return ng;
}

/* A key of no columns: every row is the same key, so every row hashes the
   same, and the hash is written, not left as it was. */
static void test_zero_columns(void) {
  zt_key k = {NULL, 0};
  uint64_t h[5] = {1, 2, 3, 4, 5};
  zt_key_hash(&k, 5, h);
  for (int i = 0; i < 5; i++) CHECK(h[i] == h[0]);
  CHECK(h[0] != 1 || h[4] != 5);
}

/* zt_groups_one() over m rows near 2^31 - 1 (#53): its prefetch looks
   eight rows ahead, and `r + 8 < m` overflowed within eight rows of the
   limit, so rows[r + 8] read past the end. rows[] is zeros mapped from a
   sparse file, every row row 0, so only ids[0] and h[0] are touched. */
static void test_max_rows(void) {
#if ZT_HAVE_ZEROS
  const zt_row *rows = zt_test_zeros(((size_t) INT32_MAX + 1) * sizeof(zt_row));
  CHECK(rows != NULL);
  if (rows == NULL) return;
  static const zt_row ms[] = {INT32_MAX, INT32_MAX - 9, INT32_MAX - 8, INT32_MAX - 1};
  for (size_t j = 0; j < zt_test_limit_cases(sizeof ms / sizeof ms[0]); j++) {
    zt_key k = {NULL, 0};
    uint64_t h[1] = {0};
    zt_row ids[1], first[1], ng = 0;
    uint64_t cap = 16;
    void *mem = malloc(zt_table_bytes(cap));
    zt_table t;
    zt_table_init(&t, mem, cap);
    zt_row done = zt_groups_one(&k, h, rows, 0, ms[j], &t, ids, first, 0, &ng);
    CHECK(done == ms[j]);
    CHECK(ng == 1);
    free(mem);
  }
#else
  printf("test-groups: the 2^31 - 1 row case needs POSIX mmap(); skipped\n");
#endif
}

int main(void) {
  test_zero_columns();
  test_max_rows();
  enum { N = 3000 };
  static int32_t a[N], ids[N], first[N], ref[N];
  static double d[N];
  for (int round = 0; round < 6; round++) {
    int32_t card = round == 0 ? 1 : round * 37;
    for (int i = 0; i < N; i++) {
      a[i] = (int32_t) (next() % (uint32_t) card) - 5;
      uint32_t r = next() % 7;
      d[i] = r == 0 ? -0.0 : r == 1 ? 0.0 : r == 2 ? (double) NAN : (double) (r % 3);
    }
    zt_column cols[2] = {{ZT_KIND_INT32, a}, {ZT_KIND_F64, d}};
    for (int ncol = 1; ncol <= 2; ncol++) {
      zt_key k = {cols, ncol};
      int32_t ngr = ref_ids(&k, N, ref);
      for (int bits = 0; bits <= 5; bits += 5) {
        int32_t ng = run(&k, N, bits, ids, first);
        CHECK(ng == ngr);
        int same = 1;
        for (int i = 0; i < N; i++) same &= ids[i] == ref[i];
        CHECK(same);
        for (int32_t g = 0; g < ng; g++) CHECK(ids[first[g]] == g);
        for (int32_t g = 1; g < ng; g++) CHECK(first[g - 1] < first[g]);
        /* order puts each group together, stably */
        zt_row *sizes = malloc(sizeof(zt_row) * ng), *starts = malloc(sizeof(zt_row) * ng);
        zt_row *order = malloc(sizeof(zt_row) * N);
        zt_groups_order(N, ng, ids, sizes, starts, order);
        zt_row total = 0;
        for (int32_t g = 0; g < ng; g++) {
          /* Each size is the group's count, each start the sizes before
             it, and the group's run in order begins at its first row. */
          zt_row count = 0;
          for (int i = 0; i < N; i++) count += ids[i] == g;
          CHECK(sizes[g] == count);
          CHECK(starts[g] == total);
          CHECK(order[starts[g]] == first[g]);
          total += sizes[g];
        }
        CHECK(total == N);
        for (int j = 1; j < N; j++) {
          CHECK(ids[order[j - 1]] <= ids[order[j]]);
          if (ids[order[j - 1]] == ids[order[j]]) CHECK(order[j - 1] < order[j]);
        }
        free(sizes); free(starts); free(order);
      }
    }
  }
  /* Byte strings compare by length, then bytes: a prefix is not equal, a
     missing element (-1) is not the empty one (0). Called directly, since
     through the table equality is reached only on equal hashes. */
  {
    static const uint8_t abc[] = {'a', 'b', 'c'};
    static const uint8_t abd[] = {'a', 'b', 'd'};
    zt_bytes b[] = {{abc, 2}, {abc, 3}, {NULL, -1}, {abc, 0}, {abd, 3},
                    {abc, 3}, {NULL, -1}, {abd, 0}};
    zt_column col = {ZT_KIND_BYTES, b};
    zt_key k = {&col, 1};
    CHECK(!zt_key_eq(&k, 0, 1));
    CHECK(!zt_key_eq(&k, 1, 0));
    CHECK(!zt_key_eq(&k, 2, 3));
    CHECK(!zt_key_eq(&k, 3, 2));
    CHECK(!zt_key_eq(&k, 1, 4));
    CHECK(zt_key_eq(&k, 1, 5));
    CHECK(zt_key_eq(&k, 2, 6));
    CHECK(zt_key_eq(&k, 3, 7));
  }
  /* -0 equals 0, NaNs fold, R's NA stays apart. */
  {
    uint64_t na = UINT64_C(0x7ff00000000007a2);
    double rna;
    memcpy(&rna, &na, 8);
    CHECK(zt_f64_bits(-0.0) == zt_f64_bits(0.0));
    CHECK(zt_f64_bits((double) NAN) == zt_f64_bits(-(double) NAN));
    CHECK(zt_f64_bits(rna) != zt_f64_bits((double) NAN));
  }
  /* The row index's limit: a capacity for 2^31 - 1 keys fits, and is a
     power of two at load 7/8. */
  {
    /* Straddled: every key count up to 2^31 - 1 gets a power of two that
       holds it at load 7/8, and its mask fits 32 bits. */
    zt_row ns[] = {ZT_MAX_ROWS - 1, ZT_MAX_ROWS, 1879048192, 1879048193, 0, 1};
    for (int i = 0; i < 6; i++) {
      uint64_t cap = zt_table_capacity(ns[i]);
      CHECK((cap & (cap - 1)) == 0);
      CHECK(cap * 7 / 8 >= (uint64_t) ns[i]);
      CHECK(cap <= (UINT64_C(1) << 32));
      CHECK((uint64_t) (uint32_t) (cap - 1) == cap - 1);
    }
    CHECK(zt_table_capacity(ZT_MAX_ROWS) == (UINT64_C(1) << 32));
    CHECK(zt_table_capacity(0) == 16);
  }
  /* Chao1: exact for a full sample, and near the truth for a sampled one. */
  {
    static uint64_t h[100000];
    uint64_t scratch[2 * ZT_SAMPLE];
    for (int i = 0; i < 100000; i++) h[i] = zt_mix64((uint64_t) (next() % 50));
    double e = zt_estimate_distinct(h, 100000, scratch);
    CHECK(e >= 45 && e <= 60);
    for (int i = 0; i < 500; i++) h[i] = zt_mix64((uint64_t) i);
    CHECK(zt_estimate_distinct(h, 500, scratch) == 500);
    /* Chao1 by hand: n = 2048 is sampled at every second row; the sample
       holds 100 singletons, 50 doubletons and one value 824 times, so
       d = 151 and d + f1^2 / (2 f2) = 251, below n. */
    for (int i = 0; i < 2048; i++) h[i] = 999;
    for (int i = 0; i < 100; i++) h[2 * i] = (uint64_t) i;
    for (int i = 0; i < 100; i++) h[2 * (100 + i)] = (uint64_t) (100 + i / 2);
    CHECK(zt_estimate_distinct(h, 2048, scratch) == 251);
    CHECK(zt_partition_bits(1e3) == 0);
    CHECK(zt_partition_bits(1e7) > 0);
  }
  if (failures) { fprintf(stderr, "%d check(s) failed\n", failures); return 1; }
  printf("test-groups: ok\n");
  return 0;
}
