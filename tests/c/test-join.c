/*
 * join.h without R (ZT_STANDALONE): every join type and `multiple` rule
 * against a nested loop over all pairs, on integer, double, byte-string
 * and two-column keys, with the table built on either side.
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

static uint64_t rng = 20261118;
static uint32_t next(void) { rng = rng * 6364136223846793005ull + 1442695040888963407ull; return (uint32_t) (rng >> 33); }

typedef struct { zt_row nx, ny; zt_row *xcls, *size, *start, *order; } plan;

/* The glue R's side does: build on the smaller side, probe, bucket y. */
static void prepare(const zt_key *x, zt_row nx, const zt_key *y, zt_row ny,
                    int build_x, plan *p) {
  uint64_t *hx = malloc(sizeof(uint64_t) * (size_t) (nx + 1));
  uint64_t *hy = malloc(sizeof(uint64_t) * (size_t) (ny + 1));
  zt_key_hash(x, nx, hx);
  zt_key_hash(y, ny, hy);
  zt_row nb = build_x ? nx : ny;
  uint64_t cap = zt_table_capacity(nb);
  void *mem = malloc(zt_table_bytes(cap));
  zt_table t;
  zt_table_init(&t, mem, cap);
  zt_row *xcls = malloc(sizeof(zt_row) * (size_t) (nx + 1));
  zt_row *ycls = malloc(sizeof(zt_row) * (size_t) (ny + 1));
  zt_row *first = malloc(sizeof(zt_row) * (size_t) (nb + 1));
  zt_row ng;
  if (build_x) {
    ng = zt_join_build(x, hx, nx, &t, xcls, first);
    zt_join_probe(&t, x, xcls, y, hy, ny, ycls);
  } else {
    ng = zt_join_build(y, hy, ny, &t, ycls, first);
    zt_join_probe(&t, y, ycls, x, hx, nx, xcls);
  }
  p->nx = nx; p->ny = ny; p->xcls = xcls;
  p->size = malloc(sizeof(zt_row) * (size_t) (ng + 1));
  p->start = malloc(sizeof(zt_row) * (size_t) (ng + 1));
  p->order = malloc(sizeof(zt_row) * (size_t) (ny + 1));
  zt_join_bucket(ny, ng, ycls, p->size, p->start, p->order);
  free(hx); free(hy); free(mem); free(ycls); free(first);
}

static void release(plan *p) { free(p->xcls); free(p->size); free(p->start); free(p->order); }

/* Every join of x and y against the nested loop. */
static void check_all(const zt_key *x, zt_row nx, const zt_key *y, zt_row ny) {
  size_t cap = (size_t) nx * (size_t) ny + (size_t) nx + 1;
  zt_row *rx = malloc(sizeof(zt_row) * cap), *ry = malloc(sizeof(zt_row) * cap);
  zt_row *ox = malloc(sizeof(zt_row) * cap), *oy = malloc(sizeof(zt_row) * cap);
  for (int build_x = 0; build_x < 2; build_x++) {
    plan p;
    prepare(x, nx, y, ny, build_x, &p);
    for (int type = 0; type < 2; type++) {
      for (int mult = 0; mult < 4; mult++) {
        /* Reference: x order, then y order; first, last, or the first x
           row with two matches. */
        size_t k = 0;
        zt_row bad = -1;
        for (zt_row i = 0; i < nx; i++) {
          zt_row hits = 0, fst = -1, lst = -1;
          for (zt_row j = 0; j < ny; j++) {
            if (!zt_key_eq2(x, i, y, j)) continue;
            if (fst < 0) fst = j;
            lst = j;
            hits++;
            if (mult == ZT_MULTIPLE_ALL || mult == ZT_MULTIPLE_ERROR) { rx[k] = i; ry[k] = j; k++; }
          }
          if (hits > 1 && mult == ZT_MULTIPLE_ERROR && bad < 0) bad = i;
          if (hits && mult == ZT_MULTIPLE_FIRST) { rx[k] = i; ry[k] = fst; k++; }
          if (hits && mult == ZT_MULTIPLE_LAST) { rx[k] = i; ry[k] = lst; k++; }
          if (!hits && type == ZT_JOIN_LEFT) { rx[k] = i; ry[k] = -1; k++; }
        }
        zt_row got_bad;
        int64_t total = zt_join_count(nx, p.xcls, p.size, (zt_join_type) type,
                                      (zt_multiple) mult, &got_bad);
        CHECK(got_bad == bad);
        if (bad >= 0) continue;
        CHECK(total == (int64_t) k);
        if (total != (int64_t) k) continue;
        zt_join_fill(nx, p.xcls, p.size, p.start, p.order, (zt_join_type) type,
                     (zt_multiple) mult, ox, oy);
        for (size_t r = 0; r < k; r++) CHECK(ox[r] == rx[r] && oy[r] == ry[r]);
      }
    }
    for (int anti = 0; anti < 2; anti++) {
      zt_row got = zt_join_filter(nx, p.xcls, p.size, anti, ox);
      zt_row k = 0;
      for (zt_row i = 0; i < nx; i++) {
        int hit = 0;
        for (zt_row j = 0; j < ny && !hit; j++) hit = zt_key_eq2(x, i, y, j);
        if (hit != anti) { CHECK(k < got && ox[k] == i); k++; }
      }
      CHECK(got == k);
    }
    release(&p);
  }
  free(rx); free(ry); free(ox); free(oy);
}

/* A table too small for the build side (a header consumer's own size):
   zt_join_build() says so, -1, rather than leave rows without a group
   (#86); one of zt_table_capacity(n) slots takes every row. */
static void test_build_undersized(void) {
  enum { N = 100 };
  int32_t a[N];
  for (int i = 0; i < N; i++) a[i] = i;
  zt_column col = {ZT_KIND_INT32, a};
  zt_key k = {&col, 1};
  uint64_t h[N];
  zt_key_hash(&k, N, h);
  zt_row ids[N], first[N];
  uint64_t cap = 16;
  zt_table t;
  void *mem = malloc(zt_table_bytes(zt_table_capacity(N)));
  zt_table_init(&t, mem, cap);
  CHECK(zt_join_build(&k, h, N, &t, ids, first) == -1);
  cap = zt_table_capacity(N);
  zt_table_init(&t, mem, cap);
  CHECK(zt_join_build(&k, h, N, &t, ids, first) == N);
  free(mem);
}

int main(void) {
  test_build_undersized();
  static const zt_row sizes[][2] = {{0, 0}, {0, 5}, {5, 0}, {1, 1}, {7, 300},
                                    {300, 7}, {200, 200}, {1000, 30}};
  for (size_t s = 0; s < sizeof sizes / sizeof sizes[0]; s++) {
    zt_row nx = sizes[s][0], ny = sizes[s][1];
    for (int range = 1; range <= 64; range *= 8) {
      /* Integers, NA (INT32_MIN) among them. */
      int32_t *xi = malloc(sizeof(int32_t) * (size_t) (nx + 1));
      int32_t *yi = malloc(sizeof(int32_t) * (size_t) (ny + 1));
      for (zt_row i = 0; i < nx; i++) xi[i] = next() % 10 == 0 ? INT32_MIN : (int32_t) (next() % (uint32_t) range);
      for (zt_row j = 0; j < ny; j++) yi[j] = next() % 10 == 0 ? INT32_MIN : (int32_t) (next() % (uint32_t) range);
      zt_column cx = {ZT_KIND_INT32, xi}, cy = {ZT_KIND_INT32, yi};
      zt_key kx = {&cx, 1}, ky = {&cy, 1};
      check_all(&kx, nx, &ky, ny);

      /* Doubles: -0 is 0, NaN is not NA. */
      double *xd = malloc(sizeof(double) * (size_t) (nx + 1));
      double *yd = malloc(sizeof(double) * (size_t) (ny + 1));
      double pool[] = {0.0, -0.0, 1.5, (double) NAN, -2.0};
      for (zt_row i = 0; i < nx; i++) xd[i] = pool[next() % 5] + (double) (next() % (uint32_t) range);
      for (zt_row j = 0; j < ny; j++) yd[j] = pool[next() % 5] + (double) (next() % (uint32_t) range);
      zt_column dx = {ZT_KIND_F64, xd}, dy = {ZT_KIND_F64, yd};
      zt_key kdx = {&dx, 1}, kdy = {&dy, 1};
      check_all(&kdx, nx, &kdy, ny);

      /* Byte strings, a missing one among them, beside the integers. */
      static const char *words[] = {"a", "ab", "", "b", "abc"};
      zt_bytes *xb = malloc(sizeof(zt_bytes) * (size_t) (nx + 1));
      zt_bytes *yb = malloc(sizeof(zt_bytes) * (size_t) (ny + 1));
      for (zt_row i = 0; i < nx; i++) {
        uint32_t w = next() % 6;
        xb[i].data = w < 5 ? (const uint8_t *) words[w] : NULL;
        xb[i].len = w < 5 ? (int32_t) strlen(words[w]) : -1;
      }
      for (zt_row j = 0; j < ny; j++) {
        uint32_t w = next() % 6;
        yb[j].data = w < 5 ? (const uint8_t *) words[w] : NULL;
        yb[j].len = w < 5 ? (int32_t) strlen(words[w]) : -1;
      }
      zt_column c2x[2] = {{ZT_KIND_BYTES, xb}, {ZT_KIND_INT32, xi}};
      zt_column c2y[2] = {{ZT_KIND_BYTES, yb}, {ZT_KIND_INT32, yi}};
      zt_key k2x = {c2x, 1}, k2y = {c2y, 1};
      check_all(&k2x, nx, &k2y, ny);
      k2x.ncol = k2y.ncol = 2;
      check_all(&k2x, nx, &k2y, ny);
      free(xi); free(yi); free(xd); free(yd); free(xb); free(yb);
    }
  }
  if (failures) { fprintf(stderr, "test-join: %d failures\n", failures); return 1; }
  printf("test-join: ok\n");
  return 0;
}
