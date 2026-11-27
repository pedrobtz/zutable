/*
 * The sorts without R (ZT_STANDALONE): every rung of the ladder and the
 * hybrid against qsort() on the same records, at sizes either side of
 * each threshold, over the shapes of the ladder; and zt_order() against a
 * brute-force stable order written from design-kernel 6.3.
 */
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
static uint64_t rnd(void) {
  rng ^= rng >> 12; rng ^= rng << 25; rng ^= rng >> 27;
  return rng * 0x2545F4914F6CDD1Dull;
}

static int cmp_w64(const void *x, const void *y) {
  zt_w64 a = *(const zt_w64 *) x, b = *(const zt_w64 *) y;
  return (a > b) - (a < b);
}
static int cmp_r128(const void *x, const void *y) {
  zt_r128 a = *(const zt_r128 *) x, b = *(const zt_r128 *) y;
  return zt_lt_r128(b, a) - zt_lt_r128(a, b);
}

/* Keys in a shape: 0 uniform, 1 few, 2 sorted, 3 reversed, 4 sorted with
   the last 1% random, 5 a narrow band; `bits` caps the key. */
static uint64_t key_at(int shape, size_t i, size_t n, int bits) {
  uint64_t mask = bits >= 64 ? UINT64_MAX : ((UINT64_C(1) << bits) - 1);
  switch (shape) {
  case 0: return rnd() & mask;
  case 1: return rnd() % 7;
  case 2: return (uint64_t) i & mask;
  case 3: return (uint64_t) (n - i) & mask;
  case 4: return (i < n - n / 100 ? (uint64_t) i : rnd() % (n + 1)) & mask;
  default: return (rnd() % (n / 2 + 1)) & mask;
  }
}

static int bits_of(uint64_t v) { int b = 0; while (v) { b++; v >>= 1; } return b; }

static void test_rungs(void) {
  /* ZT_TEST_QUICK (the mutation build, where Mull's instrumentation makes
     this sweep ten times slower) stops at 20000 records: every rung still
     runs at every size, and only the hybrid's switch to the MSD pass at
     1e6 goes unvisited. */
  static const size_t sizes[] = {0, 1, 2, 23, 24, 25, 127, 128, 129, 999, 1000, 1001,
                                 1023, 1024, 1025, 20000
#ifndef ZT_TEST_QUICK
                                 , 1000000, 1000001
#endif
  };
  size_t cap = 1000001;
  zt_w64 *w = malloc(cap * sizeof *w), *w0 = malloc(cap * sizeof *w),
         *wt = malloc(cap * sizeof *w), *wr = malloc(cap * sizeof *w);
  zt_r128 *q = malloc(cap * sizeof *q), *q0 = malloc(cap * sizeof *q),
          *qt = malloc(cap * sizeof *q), *qr = malloc(cap * sizeof *q);
  uint32_t *cnt = malloc((cap + 2) * sizeof *cnt);
  for (size_t si = 0; si < sizeof sizes / sizeof sizes[0]; si++) {
    size_t n = sizes[si];
    for (int shape = 0; shape < 6; shape++) {
      if (n >= 1000000 && shape != 0 && shape != 4) continue;
      int bits = shape == 0 ? (si % 2 ? 32 : 20) : 32;
      uint64_t kmax = 0, wmax = 0;
      for (size_t i = 0; i < n; i++) {
        uint64_t k = key_at(shape, i, n, bits);
        w0[i] = (k << 32) | (uint64_t) i;
        uint64_t k2 = shape == 0 ? rnd() >> (si % 3) * 9 : k;
        q0[i].k = k2;
        q0[i].i = i;
        if (k > kmax) kmax = k;
        if (k2 > wmax) wmax = k2;
      }
      memcpy(wr, w0, n * sizeof *w);
      memcpy(qr, q0, n * sizeof *q);
      if (n) { qsort(wr, n, sizeof *w, cmp_w64); qsort(qr, n, sizeof *q, cmp_r128); }
      int kb = bits_of(kmax), qb = bits_of(wmax);
#define RUN_W(stmt) do { memcpy(w, w0, n * sizeof *w); stmt; \
        if (memcmp(w, wr, n * sizeof *w)) { fprintf(stderr, "  %s n=%zu shape=%d\n", #stmt, n, shape); CHECK(0); } } while (0)
#define RUN_Q(stmt) do { memcpy(q, q0, n * sizeof *q); stmt; \
        if (memcmp(q, qr, n * sizeof *q)) { fprintf(stderr, "  %s n=%zu shape=%d\n", #stmt, n, shape); CHECK(0); } } while (0)
      /* Insertion sort is quadratic: under ZT_TEST_QUICK it stops past the
         sizes the hybrid gives it (fewer than 24 records). */
#ifdef ZT_TEST_QUICK
      if (n <= 1025) { RUN_W(zt_insertion_w64(w, w + n)); RUN_Q(zt_insertion_r128(q, q + n)); }
#else
      if (n <= 20000) { RUN_W(zt_insertion_w64(w, w + n)); RUN_Q(zt_insertion_r128(q, q + n)); }
#endif
      RUN_W(zt_pdqsort_w64(w, w + n));
      RUN_Q(zt_pdqsort_r128(q, q + n));
      RUN_W(zt_heapsort_w64(w, w + n));
      RUN_Q(zt_heapsort_r128(q, q + n));
      RUN_W(zt_vergesort_pdq_w64(w, w + n, wt));
      RUN_Q(zt_vergesort_pdq_r128(q, q + n, qt));
      RUN_W(zt_ska_sort_from_w64(w, w + n, 0, 8));
      RUN_Q(zt_ska_sort_from_r128(q, q + n, 0, 12));
      RUN_W(zt_lsd_w64(w, n, kb, 8, wt));
      RUN_W(zt_lsd_w64(w, n, kb, 11, wt));
      RUN_Q(zt_lsd_r128(q, n, qb, 8, qt));
      RUN_Q(zt_lsd_r128(q, n, qb, 11, qt));
      RUN_W(zt_msd_lsd_w64(w, n, kb, wt));
      RUN_Q(zt_msd_lsd_r128(q, n, qb, qt));
      if (kmax < n) RUN_W(zt_counting_w64(w, n, 0, kmax, wt, cnt));
      if (wmax < n) RUN_Q(zt_counting_r128(q, n, 0, wmax, qt, cnt));
      RUN_W(zt_hybrid_w64(w, n, kb, kmax, wt, cnt));
      RUN_Q(zt_hybrid_r128(q, n, qb, wmax, qt, cnt));
#undef RUN_W
#undef RUN_Q
    }
  }
  free(w); free(w0); free(wt); free(wr); free(q); free(q0); free(qt); free(qr); free(cnt);
}

/* ---- zt_order against a brute-force order ------------------------------ */

typedef struct { const zt_sort_col *cols; int ncol; int na_last; } ref_ctx;
static ref_ctx RC;

static int is_missing(const zt_sort_col *c, zt_row i) {
  switch (c->kind) {
  case ZT_KIND_F64: { double x = ((const double *) c->data)[i]; return x != x; }
  case ZT_KIND_I64: return ((const int64_t *) c->data)[i] == INT64_MIN;
  default: return ((const int32_t *) c->data)[i] == INT32_MIN;
  }
}

/* -1, 0, 1 for two valid cells of a column, ascending. */
static int cmp_valid(const zt_sort_col *c, zt_row i, zt_row j) {
  switch (c->kind) {
  case ZT_KIND_F64: {
    double a = ((const double *) c->data)[i], b = ((const double *) c->data)[j];
    return (a > b) - (a < b); /* -0 == 0 */
  }
  case ZT_KIND_I64: {
    int64_t a = ((const int64_t *) c->data)[i], b = ((const int64_t *) c->data)[j];
    return (a > b) - (a < b);
  }
  default: {
    int32_t a = ((const int32_t *) c->data)[i], b = ((const int32_t *) c->data)[j];
    return (a > b) - (a < b);
  }
  }
}

static int cmp_rows(const void *x, const void *y) {
  zt_row i = *(const zt_row *) x, j = *(const zt_row *) y;
  for (int k = 0; k < RC.ncol; k++) {
    const zt_sort_col *c = &RC.cols[k];
    int mi = is_missing(c, i), mj = is_missing(c, j);
    int r;
    if (mi || mj) {
      r = mi && mj ? 0 : (mi ? 1 : -1);
      if (RC.na_last == 0) r = -r;
    } else {
      r = cmp_valid(c, i, j);
      if (c->decreasing) r = -r;
    }
    if (r) return r;
  }
  return (i > j) - (i < j); /* stable */
}

static void test_order(void) {
  enum { N = 3000 };
  static int32_t a[N], l[N];
  static double d[N];
  static int64_t e[N];
  static zt_row got[N], want[N];
  static const zt_row sizes[] = {0, 1, 2, 30, 200, 1500, N};
  void *mem = malloc(zt_sort_scratch_bytes(N));
  static int32_t up[N];
  static double down[N];
  static const double dv[] = {NAN, -NAN, 0.0, -0.0, INFINITY, -INFINITY, 1.5, -2.5, 1e300, 5e-324};
  for (zt_row i = 0; i < N; i++) {
    a[i] = (rnd() % 11 == 0) ? INT32_MIN : (int32_t) (rnd() % 2001) - 1000;
    l[i] = (int32_t) (rnd() % 3) == 2 ? INT32_MIN : (int32_t) (rnd() % 2);
    d[i] = dv[rnd() % 10];
    e[i] = (rnd() % 9 == 0) ? INT64_MIN : (int64_t) (rnd() >> 1) * ((rnd() & 1) ? 1 : -1);
    up[i] = i / 3;                 /* sorted, with ties: the fast path */
    down[i] = (double) (N - i) / 7; /* strictly decreasing: reversed */
  }
  zt_kind kinds[] = {ZT_KIND_INT32, ZT_KIND_LGL, ZT_KIND_F64, ZT_KIND_I64, ZT_KIND_INT32, ZT_KIND_F64};
  const void *data[] = {a, l, d, e, up, down};
  for (size_t si = 0; si < sizeof sizes / sizeof sizes[0]; si++) {
    zt_row n = sizes[si];
    for (int combo = 0; combo < 36; combo++) {
      int ncol = 1 + combo % 3;
      zt_sort_col cols[3];
      for (int k = 0; k < ncol; k++) {
        int which = (combo / 3 + k * 3) % 6;
        cols[k].kind = kinds[which];
        cols[k].data = data[which];
        cols[k].decreasing = (combo >> k) & 1;
      }
      for (int na_last = -1; na_last <= 1; na_last++) {
        zt_codebook cb[3];
        zt_row m = zt_order(cols, ncol, n, na_last, cb, got, mem);
        /* The planned path, with exactly the scratch it asks for. */
        zt_order_plan plan;
        size_t bytes = zt_order_prepare(cols, ncol, n, na_last, cb, &plan);
        void *exact = bytes ? malloc(bytes) : NULL;
        static zt_row got2[N];
        zt_row m2 = zt_order_run(cols, ncol, n, na_last, cb, &plan, got2, exact);
        free(exact);
        CHECK(m2 == m && !memcmp(got2, got, (size_t) m * sizeof(zt_row)));
        zt_row wm = 0;
        for (zt_row i = 0; i < n; i++) {
          int miss = 0;
          for (int k = 0; k < ncol; k++) miss |= is_missing(&cols[k], i);
          if (!(na_last < 0 && miss)) want[wm++] = i;
        }
        RC.cols = cols; RC.ncol = ncol; RC.na_last = na_last;
        if (wm) qsort(want, (size_t) wm, sizeof(zt_row), cmp_rows);
        CHECK(m == wm);
        if (m == wm && memcmp(got, want, (size_t) m * sizeof(zt_row))) {
          fprintf(stderr, "  order n=%d combo=%d na_last=%d\n", n, combo, na_last);
          CHECK(0);
        }
      }
    }
  }
  free(mem);
}

/* The packing limits: keys of 31, 32 and 33 bits together (one word, or
   16 bytes), and of 63, 64 and 65 (16 bytes, or two chunks), each against
   the brute-force order. A column spanning 2^w values takes w bits. */
static void test_widths(void) {
  enum { N = 2000 };
  static int32_t a[N], b[N];
  static int64_t c[N];
  static zt_row got[N], want[N];
  void *mem = malloc(zt_sort_scratch_bytes(N));
  const int pairs[][2] = {{16, 15}, {16, 16}, {16, 17}, {31, 32}, {32, 32}, {32, 33}};
  for (int p = 0; p < 6; p++) {
    int wa = pairs[p][0], wb = pairs[p][1];
    for (zt_row i = 0; i < N; i++) {
      /* Values spanning [0, 2^w - 1], or for 32 bits the 2^32 - 1 values
         an int32 holds (2^31 - 1 either side of 0; INT32_MIN is NA). */
      uint64_t ma = wa == 32 ? UINT64_C(4294967294) : (UINT64_C(1) << wa) - 1;
      uint64_t mb = wb == 32 ? UINT64_C(4294967294) : (UINT64_C(1) << wb) - 1;
      uint64_t va = i == 0 ? 0 : i == 1 ? ma : rnd() % (ma + 1);
      uint64_t vb = i == 2 ? 0 : i == 3 ? mb : rnd() % (mb + 1);
      a[i] = (int32_t) (int64_t) (va - (wa == 32 ? UINT64_C(2147483647) : 0));
      if (wb <= 31) b[i] = (int32_t) vb;
      else if (wb == 32) b[i] = (int32_t) (int64_t) (vb - UINT64_C(2147483647));
      c[i] = (int64_t) vb;
    }
    zt_sort_col cols[2] = {{ZT_KIND_INT32, a, 0},
                           {wb <= 32 ? ZT_KIND_INT32 : ZT_KIND_I64, wb <= 32 ? (const void *) b : (const void *) c, 1}};
    zt_codebook cb[2];
    zt_row m = zt_order(cols, 2, N, 1, cb, got, mem);
    for (zt_row i = 0; i < N; i++) CHECK(a[i] != INT32_MIN && b[i] != INT32_MIN);
    CHECK(cb[0].width == wa && cb[1].width == wb);
    for (zt_row i = 0; i < N; i++) want[i] = i;
    RC.cols = cols; RC.ncol = 2; RC.na_last = 1;
    qsort(want, N, sizeof(zt_row), cmp_rows);
    CHECK(m == N && !memcmp(got, want, sizeof want));
  }
  free(mem);
}

/* Counting sort's limits: a range of codes below n and below
   ZT_SORT_DENSE_MAX. Straddled: ranges n - 1, n and n + 1 at n = 3000,
   and ZT_SORT_DENSE_MAX - 1, ZT_SORT_DENSE_MAX and + 1 at n = 5000; each
   against qsort, whichever path takes it. */
static void test_dense_limit(void) {
  enum { M = 5000 };
  static zt_w64 w[M], ref[M], tmp[M];
  static uint32_t cnt[M + 2];
  const size_t ns[] = {3000, 3000, 3000, 5000, 5000, 5000};
  const uint64_t ranges[] = {2999, 3000, 3001, ZT_SORT_DENSE_MAX - 1, ZT_SORT_DENSE_MAX,
                             ZT_SORT_DENSE_MAX + 1};
  for (int t = 0; t < 6; t++) {
    size_t N = ns[t];
    uint64_t range = ranges[t];
    for (size_t i = 0; i < N; i++) {
      uint64_t k = i == 0 ? 0 : i == 1 ? range : rnd() % (range + 1);
      w[i] = (k << 32) | (uint64_t) i;
    }
    memcpy(ref, w, N * sizeof *w);
    qsort(ref, N, sizeof(zt_w64), cmp_w64);
    zt_hybrid_w64(w, N, bits_of(range), range, tmp, cnt);
    CHECK(!memcmp(w, ref, N * sizeof *w));
  }
}

/* The fast paths: which plan each input gets, and the order it gives. */
static void test_fast_paths(void) {
  int32_t inc[] = {1, 2, 3, 4, 5}, tie[] = {1, 2, 2, 3, 3}, dec[] = {9, 7, 5, 3, 1};
  int32_t dtie[] = {9, 7, 7, 3, 1}, na[] = {1, 2, INT32_MIN, 4, 5};
  struct { const int32_t *x; int decreasing; int fast; zt_row want[5]; } cases[] = {
    {inc, 0, 1, {0, 1, 2, 3, 4}},
    {tie, 0, 1, {0, 1, 2, 3, 4}},
    {dec, 0, 2, {4, 3, 2, 1, 0}},
    {inc, 1, 2, {4, 3, 2, 1, 0}},
    {dec, 1, 1, {0, 1, 2, 3, 4}},
    {dtie, 1, 1, {0, 1, 2, 3, 4}},
    {dtie, 0, 2, {4, 3, 1, 2, 0}}, /* reversed by runs: ties keep row order */
    {tie, 1, 2, {3, 4, 1, 2, 0}},
    {na, 0, 0, {0, 1, 3, 4, 2}},  /* a missing value: no fast path */
  };
  char mem[4096];
  for (size_t t = 0; t < sizeof cases / sizeof cases[0]; t++) {
    zt_sort_col c = {ZT_KIND_INT32, cases[t].x, cases[t].decreasing};
    zt_codebook cb;
    zt_order_plan plan;
    size_t bytes = zt_order_prepare(&c, 1, 5, 1, &cb, &plan);
    CHECK(plan.fast == cases[t].fast);
    CHECK((bytes == 0) == (cases[t].fast != 0));
    zt_row got[5];
    CHECK(zt_order_run(&c, 1, 5, 1, &cb, &plan, got, mem) == 5);
    if (memcmp(got, cases[t].want, sizeof got)) {
      fprintf(stderr, "  fast path case %zu\n", t);
      CHECK(0);
    }
  }
}

/* The code book: one key's widths and the slot for missing values. */
static void test_codebook(void) {
  int32_t x[] = {5, INT32_MIN, 7, 5};
  zt_sort_col c = {ZT_KIND_INT32, x, 0};
  zt_codebook cb;
  zt_codebook_build(&c, 4, 1, &cb);
  CHECK(cb.range == 2 && cb.lo == 0 && cb.na_code == 3 && cb.width == 2);
  zt_codebook_build(&c, 4, 0, &cb);
  CHECK(cb.lo == 1 && cb.na_code == 0 && cb.width == 2);
  zt_codebook_build(&c, 4, -1, &cb);
  CHECK(!cb.has_na && cb.width == 2);
  /* A constant key with no missing value takes no bits. */
  int32_t k[] = {9, 9, 9};
  zt_sort_col kc = {ZT_KIND_INT32, k, 1};
  zt_codebook_build(&kc, 3, 1, &cb);
  CHECK(cb.width == 0);
  /* The full int32 range and a missing slot still fit in 32 bits. */
  int32_t f[] = {INT32_MAX, -INT32_MAX, INT32_MIN};
  zt_sort_col fc = {ZT_KIND_INT32, f, 0};
  zt_codebook_build(&fc, 3, 1, &cb);
  CHECK(cb.width == 32 && cb.na_code == UINT32_MAX);
  /* Doubles from -Inf to Inf, with NA: within 64 bits. */
  double g[] = {-INFINITY, INFINITY, NAN};
  zt_sort_col gc = {ZT_KIND_F64, g, 0};
  zt_codebook_build(&gc, 3, 1, &cb);
  CHECK(cb.width == 64 && cb.na_code == cb.range + 1);
}

/* grp(sort = TRUE)'s route (D44): the rule straddled at both thresholds,
   and the groups by sorting against a brute-force count of distinct keys
   below each row's. */
static void test_groups_by_sort(void) {
  zt_row big = ZT_GROUPS_HASH_MIN;
  CHECK(zt_groups_sort_rule(big - 1, 0));
  CHECK(!zt_groups_sort_rule(big, 0));
  CHECK(!zt_groups_sort_rule(big + 1, 0));
  CHECK(!zt_groups_sort_rule(big, 0.01 * big - 1));
  CHECK(zt_groups_sort_rule(big, 0.01 * big));
  CHECK(zt_groups_sort_rule(big, 0.01 * big + 1));
  enum { N = 3000 };
  static int32_t x[N];
  static double y[N];
  static zt_row order[N], ids[N], first[N], starts[N];
  uint64_t r = 7;
  for (int i = 0; i < N; i++) {
    r = r * 6364136223846793005ull + 1442695040888963407ull;
    x[i] = (int32_t) (r >> 33) % 40 - 20;
    if (x[i] == 0) x[i] = INT32_MIN;
    y[i] = (r >> 20) % 3 == 0 ? -0.0 : (double) ((r >> 40) % 5);
  }
  zt_column cols[2] = {{ZT_KIND_INT32, x}, {ZT_KIND_F64, y}};
  zt_key k = {cols, 2};
  zt_sort_col sc[2];
  zt_codebook cb[2];
  void *mem = malloc(zt_sort_scratch_bytes(N));
  zt_row ng = zt_groups_by_sort(&k, N, sc, cb, order, ids, first, starts, mem);
  CHECK(ng > 0);
  /* Brute force: a group's id is the number of distinct keys below it,
     the missing x last; -0 is 0. */
  static int64_t dx[N];
  static double dy[N];
  int nd = 0;
  for (int i = 0; i < N; i++) {
    int64_t xi = x[i] == INT32_MIN ? INT64_MAX : x[i];
    int seen = 0;
    for (int d = 0; d < nd && !seen; d++) seen = dx[d] == xi && dy[d] == y[i];
    if (!seen) { dx[nd] = xi; dy[nd] = y[i]; nd++; }
  }
  CHECK(ng == nd);
  for (int i = 0; i < N; i++) {
    int64_t xi = x[i] == INT32_MIN ? INT64_MAX : x[i];
    int below = 0;
    for (int d = 0; d < nd; d++) below += dx[d] < xi || (dx[d] == xi && dy[d] < y[i]);
    CHECK(ids[i] == below);
  }
  for (zt_row g = 0; g < ng; g++) CHECK(ids[order[starts[g]]] == g && order[starts[g]] == first[g]);
  for (int j = 1; j < N; j++) CHECK(ids[order[j]] >= ids[order[j - 1]]);
  for (int j = 1; j < N; j++) if (ids[order[j]] == ids[order[j - 1]]) CHECK(order[j] > order[j - 1]);
  /* NA beside NaN in one run: -1. */
  static double z[4];
  z[0] = 1; z[1] = NAN; z[3] = 2;
  uint64_t na = UINT64_C(0x7ff00000000007a2);
  memcpy(&z[2], &na, sizeof na);
  zt_column zc = {ZT_KIND_F64, z};
  zt_key kz = {&zc, 1};
  CHECK(zt_groups_by_sort(&kz, 4, sc, cb, order, ids, first, starts, mem) == -1);
  /* A NaN, or an NA, beside numbers only stays on the sort: three groups,
     the missing one last. */
  for (int w = 0; w < 2; w++) {
    z[0] = 1; z[1] = 2; z[3] = 3;
    if (w) memcpy(&z[2], &na, sizeof na); else z[2] = NAN;
    CHECK(zt_groups_by_sort(&kz, 4, sc, cb, order, ids, first, starts, mem) == 4);
    CHECK(ids[0] == 0 && ids[1] == 1 && ids[3] == 2 && ids[2] == 3);
  }
  free(mem);
}

/* A string or bytes column is no key zt_order() can order (sort.h takes
   INT32, LGL, I64 and F64; the R layer ranks strings first): its code book
   counts every row as missing, so na_last = -1 drops them all and
   na_last = 1 keeps them in row order (#76). */
static void test_unordered_kinds(void) {
  enum { N = 5 };
  static const char *s[N] = {"b", "a", "c", "a", "b"};
  static zt_row got[N];
  void *mem = malloc(zt_sort_scratch_bytes(N));
  zt_kind kinds[] = {ZT_KIND_STR, ZT_KIND_BYTES};
  for (int k = 0; k < 2; k++) {
    zt_sort_col col = {kinds[k], s, 0};
    zt_codebook cb[1];
    zt_codebook_build(&col, N, -1, cb);
    CHECK(cb[0].any_missing == 1);
    CHECK(zt_order(&col, 1, N, -1, cb, got, mem) == 0);
    CHECK(zt_order(&col, 1, N, 1, cb, got, mem) == N);
    for (zt_row i = 0; i < N; i++) CHECK(got[i] == i);
    /* No rows, no missing cell. */
    zt_codebook_build(&col, 0, -1, cb);
    CHECK(cb[0].any_missing == 0);
    CHECK(zt_order(&col, 1, 0, -1, cb, got, mem) == 0);
  }
  free(mem);
}

int main(void) {
  test_unordered_kinds();
  test_rungs();
  test_order();
  test_widths();
  test_dense_limit();
  test_fast_paths();
  test_codebook();
  test_groups_by_sort();
  if (failures) { fprintf(stderr, "%d check(s) failed\n", failures); return 1; }
  printf("test-sort: ok\n");
  return 0;
}
