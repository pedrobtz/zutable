/*
 * The kernel's fuzz invariants (design-kernel 8), without R (ZT_STANDALONE).
 *
 * Each input is a key table of one or two columns, of any fixed-width kind,
 * byte strings or interned strings, with a value column beside it; bytes 0
 * to 3 choose the kinds, the options and the split into a join's two
 * sides, and every row takes one byte a column. The values are drawn from small sets with every
 * edge the key model has (NA, NaN, -0, the extremes, embedded NUL, bytes
 * past ASCII), so that rows collide.
 *
 * Groups, sort, join and reduce run over it and each result is held to an
 * invariant, or to a second route to the same answer:
 *
 *   groups  every row has an identifier below the count; identifiers follow
 *           first appearance; a row's key equals its group's first row's,
 *           and no two groups' keys are equal; the partitioned path gives
 *           the one-pass path's identifiers; grouping by sort gives the
 *           same partition, in key order.
 *   sort    the permutation is a permutation (of the rows kept, under
 *           na_last = -1) and its keys are non-decreasing, ties in row
 *           order.
 *   join    every pair's keys are equal; an unmatched pair is a left
 *           join's row that has no match; the pairs are the nested loop's,
 *           for every `multiple`; semi and anti split x.
 *   reduce  sums over groups add up to the total; counts to the rows;
 *           min <= max; first and last are rows of their group.
 *
 * A broken invariant aborts, which libFuzzer reports with the input.
 * harness.c is the entry point; this file is fuzz.yml's `sources`, so that
 * the reach report shows which of these paths the corpus takes.
 */
#define ZT_STANDALONE 1
/* Inputs hold at most MAXN rows, under the default block of 4096; a small
   block puts block edges inside them (tests/c covers the default). */
#define ZT_REDUCE_BLOCK 61
#include <zutable.h>
#include <float.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#include "fuzz.h"

#define FAIL(what) do { \
  fprintf(stderr, "%s:%d: invariant broken: %s\n", __FILE__, __LINE__, what); \
  abort(); } while (0)
#define REQUIRE(cond) do { if (!(cond)) FAIL(#cond); } while (0)

/* ---- decoding ----------------------------------------------------------- */

static const zt_kind kinds[6] = {ZT_KIND_INT32, ZT_KIND_F64, ZT_KIND_LGL,
                                 ZT_KIND_I64, ZT_KIND_BYTES, ZT_KIND_STR};

static const char *const pool[8] = {"", "a", "b", "ab", "a\0b", "\xc3\xa9", "\xff", "abc"};
static const int32_t pool_len[8] = {0, 1, 1, 2, 3, 2, 1, 3};

/* The fixture's own interning for str columns (design-kernel 4, layer 1):
   one address per distinct string of the pool, and one for NA, as R's
   string cache gives CHARSXPs. */
typedef struct { int index; } zt_interned;
static const zt_interned interned[9] = {{0}, {1}, {2}, {3}, {4}, {5}, {6}, {7}, {-1}};
static double f64_of_bits(uint64_t b) {
  double d;
  memcpy(&d, &b, sizeof d);
  return d;
}

static int32_t i32_of(uint8_t b) {
  switch (b) {
  case 0: return INT32_MIN; /* NA */
  case 1: return INT32_MAX;
  case 2: return INT32_MIN + 1;
  default: return (int32_t) (int8_t) b;
  }
}

static int64_t i64_of(uint8_t b) {
  switch (b) {
  case 0: return INT64_MIN; /* NA */
  case 1: return INT64_MAX;
  case 2: return INT64_MIN + 1;
  default: return (int64_t) (int8_t) b * (INT64_C(1) << 40) + (b & 1);
  }
}

static double f64_of(uint8_t b) {
  switch (b) {
  case 0: return f64_of_bits(UINT64_C(0x7ff00000000007a2)); /* R's NA */
  case 1: return f64_of_bits(UINT64_C(0x7ff8000000000000)); /* NaN */
  case 2: return f64_of_bits(UINT64_C(0xfff8000000000001)); /* another NaN */
  case 3: return -0.0;
  case 4: return 0.0;
  case 5: return INFINITY;
  case 6: return -INFINITY;
  case 7: return DBL_MIN;
  case 8: return DBL_MAX;
  default: return (double) (int8_t) b / 4.0;
  }
}

/* The value column reduce reads: quarters, so that every sum is exact in
   any order, with NA and NaN as its missing values. */
static double value_of(uint8_t b) {
  if (b == 0) return f64_of(0);
  if (b == 1) return f64_of(1);
  return (double) ((int) (b % 64) - 32) / 4.0;
}

typedef struct {
  int ncol, n, nx;
  zt_kind kind[2];
  int decreasing[2], na_last, bits, build_x, join_type, multiple, na_rm;
  int32_t i32[2][MAXN];
  int64_t i64[2][MAXN];
  double f64[2][MAXN];
  zt_bytes str[2][MAXN];
  const void *ptr[2][MAXN];
  double val[MAXN];
} input;

static int decode(const uint8_t *data, size_t size, input *in) {
  if (size < 4) return 0;
  in->ncol = 1 + (data[0] & 1);
  in->kind[0] = kinds[((data[0] >> 1) & 7) % 6];
  in->kind[1] = kinds[((data[0] >> 4) & 7) % 6];
  in->decreasing[0] = data[0] >> 7;
  static const int na_last[4] = {1, 0, -1, 1};
  in->na_last = na_last[data[1] & 3];
  in->decreasing[1] = (data[1] >> 2) & 1;
  in->bits = (data[1] >> 3) & 7;
  in->build_x = (data[1] >> 6) & 1;
  in->join_type = data[1] >> 7;
  in->multiple = data[3] & 3;
  in->na_rm = (data[3] >> 2) & 1;
  size_t width = (size_t) in->ncol + 1;
  size_t n = (size - 4) / width;
  if (n > MAXN) n = MAXN;
  in->n = (int) n;
  in->nx = (int) ((n * data[2]) / 256);
  const uint8_t *row = data + 4;
  for (int i = 0; i < in->n; i++, row += width) {
    for (int c = 0; c < in->ncol; c++) {
      uint8_t b = row[c];
      switch (in->kind[c]) {
      case ZT_KIND_LGL: in->i32[c][i] = b % 3 == 2 ? INT32_MIN : b % 3; break;
      case ZT_KIND_I64: in->i64[c][i] = i64_of(b); break;
      case ZT_KIND_F64: in->f64[c][i] = f64_of(b); break;
      case ZT_KIND_BYTES:
        in->str[c][i].data = (const uint8_t *) pool[b & 7];
        in->str[c][i].len = b >= 0xf0 ? -1 : pool_len[b & 7];
        break;
      case ZT_KIND_STR: in->ptr[c][i] = &interned[b >= 0xf0 ? 8 : b & 7]; break;
      default: in->i32[c][i] = i32_of(b); break;
      }
    }
    in->val[i] = value_of(row[in->ncol]);
  }
  return 1;
}

/* Column c's data from row `from` on. */
static const void *col_data(const input *in, int c, int from) {
  switch (in->kind[c]) {
  case ZT_KIND_I64: return in->i64[c] + from;
  case ZT_KIND_F64: return in->f64[c] + from;
  case ZT_KIND_BYTES: return in->str[c] + from;
  case ZT_KIND_STR: return in->ptr[c] + from;
  default: return in->i32[c] + from;
  }
}

/* ---- key equality, the oracle's own (design 6.1) ------------------------ */

static int is_na_f64(double v) {
  uint64_t b;
  memcpy(&b, &v, sizeof b);
  return v != v && (uint32_t) b == 1954u;
}

/* Cell i of a against cell j of b, of one kind: NA equals NA, any other
   NaN any other NaN, -0 equals 0, byte strings by length and bytes. */
static int cell_eq(const zt_column *a, zt_row i, const zt_column *b, zt_row j) {
  switch (a->kind) {
  case ZT_KIND_I64: return ((const int64_t *) a->data)[i] == ((const int64_t *) b->data)[j];
  case ZT_KIND_F64: {
    double u = ((const double *) a->data)[i], v = ((const double *) b->data)[j];
    if (u != u || v != v) return u != u && v != v && is_na_f64(u) == is_na_f64(v);
    return u == v;
  }
  case ZT_KIND_BYTES: {
    zt_bytes u = ((const zt_bytes *) a->data)[i], v = ((const zt_bytes *) b->data)[j];
    return u.len == v.len && (u.len <= 0 || !memcmp(u.data, v.data, (size_t) u.len));
  }
  case ZT_KIND_STR: {
    /* By the strings' bytes, which interning makes the same as by address. */
    int u = ((const zt_interned *const *) a->data)[i]->index;
    int v = ((const zt_interned *const *) b->data)[j]->index;
    if (u < 0 || v < 0) return u == v;
    return pool_len[u] == pool_len[v] && !memcmp(pool[u], pool[v], (size_t) pool_len[u]);
  }
  default: return ((const int32_t *) a->data)[i] == ((const int32_t *) b->data)[j];
  }
}

static int key_eq(const zt_key *a, zt_row i, const zt_key *b, zt_row j) {
  for (int c = 0; c < a->ncol; c++) if (!cell_eq(&a->cols[c], i, &b->cols[c], j)) return 0;
  return 1;
}

/* ---- groups ------------------------------------------------------------- */

static uint64_t hash[MAXN];
static zt_row ids[MAXN], first[MAXN], ids2[MAXN], first2[MAXN];

/* One pass from a table of 16 slots, growing it, as the caller does. */
static zt_row groups_one_pass(const zt_key *k, zt_row n, zt_row *gid, zt_row *gfirst) {
  uint64_t cap = 16;
  void *mem = malloc(zt_table_bytes(cap));
  zt_table t;
  zt_table_init(&t, mem, cap);
  zt_row ng = 0, done = 0;
  while (done < n) {
    done += zt_groups_one(k, hash, NULL, done, n - done, &t, gid, gfirst, 0, &ng);
    if (done >= n) break;
    uint64_t cap2 = 2 * cap;
    void *mem2 = malloc(zt_table_bytes(cap2));
    zt_table bigger;
    zt_table_init(&bigger, mem2, cap2);
    zt_table_rehash(&t, &bigger, hash);
    free(mem);
    mem = mem2;
    t = bigger;
    cap = cap2;
  }
  free(mem);
  return ng;
}

/* Partitioned by the top `bits` of the hash, then relabelled. */
static zt_row groups_partitioned(const zt_key *k, zt_row n, int bits, zt_row *gid,
                                 zt_row *gfirst) {
  int np = 1 << bits;
  static zt_row start[(1 << 7) + 1], perm[MAXN];
  zt_partition(hash, n, bits, start, perm);
  uint64_t cap = zt_table_capacity(n);
  void *mem = malloc(zt_table_bytes(cap));
  zt_row ng = 0;
  for (int p = 0; p < np; p++) {
    zt_table t;
    zt_table_init(&t, mem, cap);
    zt_row png = 0;
    zt_row m = start[p + 1] - start[p];
    REQUIRE(zt_groups_one(k, hash, perm + start[p], 0, m, &t, gid, gfirst, ng, &png) == m);
    ng += png;
  }
  static uint64_t bitmap[MAXN / 64 + 1];
  static zt_row word_rank[MAXN / 64 + 1], newid[MAXN];
  zt_groups_relabel(n, ng, gid, gfirst, bitmap, word_rank, newid);
  free(mem);
  return ng;
}

static zt_row check_groups(const input *in, const zt_key *k) {
  zt_row n = in->n;
  zt_key_hash(k, n, hash);
  zt_row ng = groups_one_pass(k, n, ids, first);
  REQUIRE(ng >= 0 && ng <= n);
  for (zt_row i = 0; i < n; i++) {
    REQUIRE(ids[i] >= 0 && ids[i] < ng);
    REQUIRE(first[ids[i]] <= i);
    REQUIRE(key_eq(k, i, k, first[ids[i]]));
  }
  for (zt_row g = 0; g < ng; g++) {
    REQUIRE(ids[first[g]] == g);
    if (g) REQUIRE(first[g] > first[g - 1]);
    for (zt_row h = 0; h < g; h++) REQUIRE(!key_eq(k, first[g], k, first[h]));
  }
  if (in->bits) {
    zt_row ng2 = groups_partitioned(k, n, in->bits, ids2, first2);
    REQUIRE(ng2 == ng);
    REQUIRE(!memcmp(ids2, ids, sizeof(zt_row) * (size_t) n));
    REQUIRE(!memcmp(first2, first, sizeof(zt_row) * (size_t) ng));
  }
  if (zt_key_fixed_width(k)) {
    zt_sort_col sc[2];
    zt_codebook cb[2];
    static zt_row order[MAXN], starts[MAXN];
    void *mem = malloc(zt_sort_scratch_bytes(n));
    zt_row ngs = zt_groups_by_sort(k, n, sc, cb, order, ids2, first2, starts, mem);
    free(mem);
    if (ngs >= 0) { /* -1: an NA beside a NaN, which the caller hashes */
      REQUIRE(ngs == ng);
      /* The same partition: one sorted group per hashed group. */
      static zt_row map[MAXN];
      for (zt_row g = 0; g < ng; g++) map[g] = -1;
      for (zt_row i = 0; i < n; i++) {
        REQUIRE(ids2[i] >= 0 && ids2[i] < ng);
        if (map[ids2[i]] < 0) map[ids2[i]] = ids[i];
        REQUIRE(map[ids2[i]] == ids[i]);
      }
      for (zt_row j = 1; j < n; j++) REQUIRE(ids2[order[j]] >= ids2[order[j - 1]]);
      for (zt_row g = 0; g < ng; g++) REQUIRE(order[starts[g]] == first2[g] && ids2[first2[g]] == g);
    }
  }
  return ng;
}

/* ---- sort --------------------------------------------------------------- */

static int is_missing(const zt_sort_col *c, zt_row i) {
  switch (c->kind) {
  case ZT_KIND_F64: { double x = ((const double *) c->data)[i]; return x != x; }
  case ZT_KIND_I64: return ((const int64_t *) c->data)[i] == INT64_MIN;
  default: return ((const int32_t *) c->data)[i] == INT32_MIN;
  }
}

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

static int row_missing(const zt_sort_col *cols, int ncol, zt_row i) {
  for (int k = 0; k < ncol; k++) if (is_missing(&cols[k], i)) return 1;
  return 0;
}

/* Rows i and j in the order's terms, ties broken by row: < 0 when i first. */
static int cmp_rows(const zt_sort_col *cols, int ncol, int na_last, zt_row i, zt_row j) {
  for (int k = 0; k < ncol; k++) {
    int mi = is_missing(&cols[k], i), mj = is_missing(&cols[k], j), r;
    if (mi || mj) {
      r = mi && mj ? 0 : (mi ? 1 : -1);
      if (na_last == 0) r = -r;
    } else {
      r = cmp_valid(&cols[k], i, j);
      if (cols[k].decreasing) r = -r;
    }
    if (r) return r;
  }
  return (i > j) - (i < j);
}

static void check_sort(const input *in, const zt_key *k) {
  if (!zt_key_fixed_width(k)) return;
  zt_row n = in->n;
  zt_sort_col sc[2];
  for (int c = 0; c < in->ncol; c++) {
    sc[c].kind = k->cols[c].kind;
    sc[c].data = k->cols[c].data;
    sc[c].decreasing = in->decreasing[c];
  }
  zt_codebook cb[2];
  static zt_row out[MAXN];
  static uint8_t seen[MAXN];
  void *mem = malloc(zt_sort_scratch_bytes(n));
  zt_row m = zt_order(sc, in->ncol, n, in->na_last, cb, out, mem);
  free(mem);
  zt_row kept = 0;
  for (zt_row i = 0; i < n; i++) {
    seen[i] = 0;
    if (in->na_last >= 0 || !row_missing(sc, in->ncol, i)) kept++;
  }
  REQUIRE(m == kept);
  for (zt_row j = 0; j < m; j++) {
    REQUIRE(out[j] >= 0 && out[j] < n && !seen[out[j]]);
    seen[out[j]] = 1;
    if (in->na_last < 0) REQUIRE(!row_missing(sc, in->ncol, out[j]));
    if (j) REQUIRE(cmp_rows(sc, in->ncol, in->na_last, out[j - 1], out[j]) < 0);
  }
}

/* ---- join --------------------------------------------------------------- */

static void check_join(const input *in) {
  zt_row nx = in->nx, ny = in->n - in->nx;
  zt_column xc[2], yc[2];
  for (int c = 0; c < in->ncol; c++) {
    xc[c].kind = yc[c].kind = in->kind[c];
    xc[c].data = col_data(in, c, 0);
    yc[c].data = col_data(in, c, nx);
  }
  zt_key x = {xc, in->ncol}, y = {yc, in->ncol};
  static uint64_t hx[MAXN], hy[MAXN];
  zt_key_hash(&x, nx, hx);
  zt_key_hash(&y, ny, hy);
  zt_row nb = in->build_x ? nx : ny;
  uint64_t cap = zt_table_capacity(nb);
  void *mem = malloc(zt_table_bytes(cap));
  zt_table t;
  zt_table_init(&t, mem, cap);
  static zt_row xcls[MAXN], ycls[MAXN], bfirst[MAXN], size[MAXN], start[MAXN], order[MAXN];
  zt_row ng;
  if (in->build_x) {
    ng = zt_join_build(&x, hx, nx, &t, xcls, bfirst);
    zt_join_probe(&t, &x, xcls, &y, hy, ny, ycls);
  } else {
    ng = zt_join_build(&y, hy, ny, &t, ycls, bfirst);
    zt_join_probe(&t, &y, ycls, &x, hx, nx, xcls);
  }
  free(mem);
  zt_join_bucket(ny, ng, ycls, size, start, order);

  zt_join_type type = (zt_join_type) in->join_type;
  zt_multiple mult = (zt_multiple) in->multiple;
  zt_row bad;
  int64_t count = zt_join_count(nx, xcls, size, type, mult, &bad);

  /* The nested loop's answer, row by row of x. */
  int64_t want = 0;
  zt_row want_bad = -1;
  for (zt_row i = 0; i < nx; i++) {
    zt_row hits = 0;
    for (zt_row j = 0; j < ny; j++) hits += key_eq(&x, i, &y, j);
    if (hits > 1 && mult == ZT_MULTIPLE_ERROR) { want_bad = i; break; }
    if (hits > 1 && mult != ZT_MULTIPLE_ALL && mult != ZT_MULTIPLE_ERROR) hits = 1;
    want += hits ? hits : (type == ZT_JOIN_LEFT);
  }
  REQUIRE(bad == want_bad);
  if (want_bad >= 0) return;
  REQUIRE(count == want);

  zt_row *ox = malloc(sizeof(zt_row) * (size_t) (count + 1));
  zt_row *oy = malloc(sizeof(zt_row) * (size_t) (count + 1));
  zt_join_fill(nx, xcls, size, start, order, type, mult, ox, oy);
  int64_t k = 0;
  for (zt_row i = 0; i < nx; i++) {
    zt_row fst = -1, lst = -1;
    for (zt_row j = 0; j < ny; j++) {
      if (!key_eq(&x, i, &y, j)) continue;
      if (fst < 0) fst = j;
      lst = j;
      if (mult == ZT_MULTIPLE_ALL || mult == ZT_MULTIPLE_ERROR) {
        REQUIRE(ox[k] == i && oy[k] == j);
        k++;
      }
    }
    if (fst >= 0 && mult == ZT_MULTIPLE_FIRST) { REQUIRE(ox[k] == i && oy[k] == fst); k++; }
    if (fst >= 0 && mult == ZT_MULTIPLE_LAST) { REQUIRE(ox[k] == i && oy[k] == lst); k++; }
    if (fst < 0 && type == ZT_JOIN_LEFT) { REQUIRE(ox[k] == i && oy[k] == -1); k++; }
  }
  REQUIRE(k == count);
  for (int64_t p = 0; p < count; p++) {
    if (oy[p] >= 0) REQUIRE(key_eq(&x, ox[p], &y, oy[p]));
  }
  free(ox);
  free(oy);

  static zt_row semi[MAXN], anti[MAXN];
  zt_row ns = zt_join_filter(nx, xcls, size, 0, semi);
  zt_row na = zt_join_filter(nx, xcls, size, 1, anti);
  REQUIRE(ns + na == nx);
  zt_row a = 0, s = 0;
  for (zt_row i = 0; i < nx; i++) {
    int hit = 0;
    for (zt_row j = 0; j < ny && !hit; j++) hit = key_eq(&x, i, &y, j);
    if (hit) REQUIRE(s < ns && semi[s++] == i);
    else REQUIRE(a < na && anti[a++] == i);
  }
}

/* ---- reduce ------------------------------------------------------------- */

static int missing_value(double v) { return v != v; }

static void check_reduce(const input *in, zt_row ng) {
  zt_row n = in->n;
  if (ng == 0) return;
  enum { NC = 7 };
  static const zt_fn fns[NC] = {ZT_FN_SUM, ZT_FN_COUNT, ZT_FN_NOBS, ZT_FN_MIN,
                                ZT_FN_MAX, ZT_FN_FIRST, ZT_FN_LAST};
  static double sum[MAXN], mn[MAXN], mx[MAXN];
  static int32_t cnt_out[MAXN], nobs[MAXN];
  static zt_row fst[MAXN], lst[MAXN];
  void *outs[NC] = {sum, cnt_out, nobs, mn, mx, fst, lst};
  zt_reduce_col cols[NC];
  void *scratch[NC][4];
  for (int c = 0; c < NC; c++) {
    int a, a2, cn, fl;
    zt_reduce_scratch(fns[c], ZT_KIND_F64, &a, &a2, &cn, &fl);
    scratch[c][0] = a ? malloc(sizeof(zt_acc) * (size_t) ng) : NULL;
    scratch[c][1] = a2 ? malloc(sizeof(zt_acc) * (size_t) ng) : NULL;
    scratch[c][2] = cn ? malloc(sizeof(zt_row) * (size_t) ng) : NULL;
    scratch[c][3] = fl ? malloc((size_t) ng) : NULL;
    zt_reduce_col rc = {fns[c], ZT_KIND_F64, in->val, in->na_rm, 1, outs[c],
                        (zt_acc *) scratch[c][0], (zt_acc *) scratch[c][1],
                        (zt_row *) scratch[c][2], (uint8_t *) scratch[c][3]};
    cols[c] = rc;
  }
  zt_reduce(ids, n, ng, cols, NC);
  for (int c = 0; c < NC; c++) for (int s = 0; s < 4; s++) free(scratch[c][s]);

  /* What each group holds, from the identifiers. */
  static int32_t size[MAXN], valid[MAXN];
  for (zt_row g = 0; g < ng; g++) size[g] = valid[g] = 0;
  double total = 0;
  for (zt_row i = 0; i < n; i++) {
    size[ids[i]]++;
    if (!missing_value(in->val[i])) valid[ids[i]]++;
  }
  /* Sums over groups add up to the total, of the values the rule keeps:
     every value of a group with none missing, or with na.rm every value
     that is not. Quarters, so exact in any order. */
  for (zt_row i = 0; i < n; i++) {
    int keep = in->na_rm ? !missing_value(in->val[i]) : valid[ids[i]] == size[ids[i]];
    if (keep) total += in->val[i];
  }
  double got = 0;
  int64_t rows = 0, kept = 0;
  for (zt_row g = 0; g < ng; g++) {
    int defined = in->na_rm ? valid[g] > 0 : valid[g] == size[g];
    REQUIRE(missing_value(sum[g]) == !defined);
    if (defined) got += sum[g];
    REQUIRE(cnt_out[g] == size[g]);
    REQUIRE(nobs[g] == valid[g]);
    rows += cnt_out[g];
    kept += nobs[g];
    if (defined) REQUIRE(mn[g] <= mx[g] && mn[g] <= sum[g] / valid[g] && sum[g] / valid[g] <= mx[g]);
    else REQUIRE(missing_value(mn[g]) && missing_value(mx[g]));
    if (in->na_rm && valid[g] == 0) {
      REQUIRE(fst[g] == -1 && lst[g] == -1);
    } else {
      REQUIRE(fst[g] >= 0 && fst[g] < n && ids[fst[g]] == g);
      REQUIRE(lst[g] >= fst[g] && lst[g] < n && ids[lst[g]] == g);
      if (!in->na_rm) REQUIRE(fst[g] == first[g]);
      if (in->na_rm) REQUIRE(!missing_value(in->val[fst[g]]) && !missing_value(in->val[lst[g]]));
    }
  }
  REQUIRE(got == total);
  REQUIRE(rows == n);
  int64_t want_kept = 0;
  for (zt_row i = 0; i < n; i++) want_kept += !missing_value(in->val[i]);
  REQUIRE(kept == want_kept);
}

/* ---- one input ---------------------------------------------------------- */

int zt_fuzz_check(const uint8_t *data, size_t size) {
  static input in;
  if (!decode(data, size, &in)) return 0;
  zt_column cols[2];
  for (int c = 0; c < in.ncol; c++) {
    cols[c].kind = in.kind[c];
    cols[c].data = col_data(&in, c, 0);
  }
  zt_key k = {cols, in.ncol};
  zt_row ng = check_groups(&in, &k);
  check_sort(&in, &k);
  check_join(&in);
  check_reduce(&in, ng);
  return 1;
}
