/*
 * reduce.h without R (ZT_STANDALONE): every statistic, kind and missing
 * rule against a plain loop over each group's rows, at sizes on both
 * sides of the block; and the columns reduced together against each
 * reduced alone, bit for bit.
 */
#define ZT_STANDALONE 1
#include <zutable.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <float.h>

static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { \
  fprintf(stderr, "%s:%d: CHECK failed: %s\n", __FILE__, __LINE__, #cond); \
  failures++; } } while (0)

static uint64_t rng = 20261119;
static uint32_t next(void) { rng = rng * 6364136223846793005ull + 1442695040888963407ull; return (uint32_t) (rng >> 33); }

static uint64_t bits(double v) { uint64_t b; memcpy(&b, &v, sizeof b); return b; }

/* The oracle's own NA test and sum rounding, not reduce.h's: a mutant in
   the kernel's zt_f64_is_na() or zt_acc_double() must not change the
   reference with it (mutation run, Stage 17). R's NA is a NaN whose low
   word is 1954; a sum past the largest double is infinite. */
static int ref_is_na(double v) {
  uint64_t b = bits(v);
  return (b & 0x7ff0000000000000ull) == 0x7ff0000000000000ull &&
         (b & 0x000fffffffffffffull) != 0 && (b & 0xffffffffull) == 1954u;
}
static double ref_acc_double(zt_acc s) {
  if (s != s) return (double) s;
  return fabsl(s) > (zt_acc) DBL_MAX ? (s > 0 ? INFINITY : -INFINITY) : (double) s;
}

/* Same value: NA is NA, any NaN is NaN (R's identical()), else the bits. */
static int same_f64(double a, double b) {
  if (ref_is_na(a) || ref_is_na(b)) return ref_is_na(a) && ref_is_na(b);
  if (a != a || b != b) return a != a && b != b;
  return bits(a) == bits(b);
}

static int miss(int kind, const void *x, zt_row i, int nan_missing) {
  if (kind == ZT_KIND_F64) {
    double v = ((const double *) x)[i];
    return nan_missing ? v != v : ref_is_na(v);
  }
  return ((const int32_t *) x)[i] == INT32_MIN;
}

static double val(int kind, const void *x, zt_row i) {
  return kind == ZT_KIND_F64 ? ((const double *) x)[i] : (double) ((const int32_t *) x)[i];
}

/* The reference: group g's rows, one at a time, in row order. */
static void reference(zt_fn fn, int kind, const void *x, int na_rm, int nan_missing,
                      const zt_row *ids, zt_row n, zt_row g, double *dv, int32_t *iv) {
  zt_acc s = fn == ZT_FN_PROD ? 1 : 0;
  zt_row cnt = 0, first = -1, last = -1, size = 0, nobs = 0;
  int any_miss = 0, any_na = 0, any_nan = 0;
  double best = 0;
  for (zt_row i = 0; i < n; i++) {
    if (ids[i] != g) continue;
    size++;
    int m = fn == ZT_FN_COUNT ? 0 : miss(kind, x, i, nan_missing);
    if (!m && fn != ZT_FN_COUNT) nobs++;
    if (fn == ZT_FN_FIRST || fn == ZT_FN_LAST) {
      if (na_rm && m) continue;
      if (first < 0) first = i;
      last = i;
      continue;
    }
    if (fn == ZT_FN_MIN || fn == ZT_FN_MAX) {
      double v = val(kind, x, i);
      if (kind == ZT_KIND_F64 && v != v && !m) { any_nan = 1; continue; }
      if (m) {
        if (!na_rm) {
          if (kind != ZT_KIND_F64 || ref_is_na(v)) any_na = 1; else any_miss = 1;
        }
        continue;
      }
      if (!cnt || (fn == ZT_FN_MAX ? v > best : v < best)) best = v;
      cnt++;
      continue;
    }
    if (fn == ZT_FN_SUM || fn == ZT_FN_PROD || fn == ZT_FN_MEAN) {
      if (m && (na_rm || kind != ZT_KIND_F64)) { if (!na_rm) any_miss = 1; continue; }
      if (fn == ZT_FN_PROD) s *= (zt_acc) val(kind, x, i); else s += (zt_acc) val(kind, x, i);
      cnt++;
    }
  }
  switch (fn) {
  case ZT_FN_COUNT: *iv = size; break;
  case ZT_FN_NOBS: *iv = nobs; break;
  case ZT_FN_FIRST: *iv = first; break;
  case ZT_FN_LAST: *iv = last; break;
  case ZT_FN_SUM:
  case ZT_FN_PROD:
    *dv = !cnt || any_miss ? ZT_F64_NA : ref_acc_double(s);
    break;
  case ZT_FN_MEAN:
    if (!cnt || any_miss) { *dv = ZT_F64_NA; break; }
    if (kind != ZT_KIND_F64) { *dv = (double) (s / (zt_acc) cnt); break; }
    /* Base R's real_mean() (R >= 4.2), as written there: a sum that is not
       finite is redone over x / n, and each finite estimate corrected. */
    if (isfinite((double) s)) {
      s /= (zt_acc) cnt;
      zt_acc t = 0;
      for (zt_row i = 0; i < n; i++) {
        if (ids[i] != g || (na_rm && miss(kind, x, i, nan_missing))) continue;
        t += (zt_acc) val(kind, x, i) - s;
      }
      s += t / (zt_acc) cnt;
    } else {
      s = 0;
      for (zt_row i = 0; i < n; i++) {
        if (ids[i] != g || (na_rm && miss(kind, x, i, nan_missing))) continue;
        s += val(kind, x, i) / (double) cnt;
      }
      if (isfinite((double) s)) {
        zt_acc t = 0;
        for (zt_row i = 0; i < n; i++) {
          if (ids[i] != g || (na_rm && miss(kind, x, i, nan_missing))) continue;
          t += ((zt_acc) val(kind, x, i) - s) / (zt_acc) cnt;
        }
        s += t;
      }
    }
    *dv = (double) s;
    break;
  case ZT_FN_MIN:
  case ZT_FN_MAX:
    if (any_na) *dv = ZT_F64_NA;
    else if (any_miss) *dv = ZT_F64_NAN;
    else if (any_nan && (fn == ZT_FN_MAX || !cnt)) *dv = ZT_F64_NAN;
    else if (!cnt) *dv = ZT_F64_NA;
    else *dv = best;
    break;
  }
}

typedef struct { zt_fn fn; int kind; int na_rm; int nan_missing; } spec;

static void setup(zt_reduce_col *c, const spec *s, const void *x, zt_row ng, void *out) {
  int a, a2, cn, fl;
  zt_reduce_scratch(s->fn, s->kind, &a, &a2, &cn, &fl);
  c->fn = s->fn; c->kind = s->kind; c->x = x; c->na_rm = s->na_rm;
  c->nan_missing = s->nan_missing; c->out = out;
  c->acc = a ? malloc(sizeof(zt_acc) * (size_t) (ng + 1)) : NULL;
  c->acc2 = a2 ? malloc(sizeof(zt_acc) * (size_t) (ng + 1)) : NULL;
  c->cnt = cn ? malloc(sizeof(zt_row) * (size_t) (ng + 1)) : NULL;
  c->flag = fl ? malloc((size_t) (ng + 1)) : NULL;
}

static void teardown(zt_reduce_col *c) { free(c->acc); free(c->acc2); free(c->cnt); free(c->flag); }

/* out as a double for comparison; ints as themselves, NA as R's NA. */
static double out_value(const spec *s, const void *out, zt_row g) {
  if (s->fn == ZT_FN_SUM || s->fn == ZT_FN_PROD || s->fn == ZT_FN_MEAN ||
      ((s->fn == ZT_FN_MIN || s->fn == ZT_FN_MAX) && s->kind == ZT_KIND_F64)) {
    return ((const double *) out)[g];
  }
  int32_t v = ((const int32_t *) out)[g];
  return v == INT32_MIN ? ZT_F64_NA : (double) v;
}

/* A sum of exactly the largest double is that double, not infinity: only
   past DBL_MAX does base R's rsum() give Inf. */
static void test_dbl_max(void) {
  double x[2] = {DBL_MAX, 0.0}, out[1];
  zt_row ids[2] = {0, 0};
  int a, a2, cn, fl;
  zt_reduce_scratch(ZT_FN_SUM, ZT_KIND_F64, &a, &a2, &cn, &fl);
  zt_acc acc[1], acc2[1];
  zt_row cnt[1];
  uint8_t flag[1];
  zt_reduce_col c = {ZT_FN_SUM, ZT_KIND_F64, x, 1, 1, out,
                     a ? acc : NULL, a2 ? acc2 : NULL, cn ? cnt : NULL, fl ? flag : NULL};
  zt_reduce(ids, 2, 1, &c, 1);
  CHECK(out[0] == DBL_MAX);
  x[1] = DBL_MAX;
  zt_reduce(ids, 2, 1, &c, 1);
  CHECK(out[0] == INFINITY);
}

int main(void) {
  test_dbl_max();
  static const zt_row sizes[] = {0, 1, 7, 300, 4095, 4096, 4097, 10000};
  static const zt_row groups[] = {1, 3, 50, 2000};
  for (size_t si = 0; si < sizeof sizes / sizeof sizes[0]; si++) {
    for (size_t gi = 0; gi < sizeof groups / sizeof groups[0]; gi++) {
      zt_row n = sizes[si], ng = groups[gi];
      zt_row *ids = malloc(sizeof(zt_row) * (size_t) (n + 1));
      int32_t *xi = malloc(sizeof(int32_t) * (size_t) (n + 1));
      int32_t *xl = malloc(sizeof(int32_t) * (size_t) (n + 1));
      double *xd = malloc(sizeof(double) * (size_t) (n + 1));
      /* 1.5e308, a tenth of the rows: its sums pass DBL_MAX where zt_acc
         is double (ZT_PRECISION 0, arm64 macOS, MSVC), so mean restarts
         its sum (real_mean); an x86 long double holds them. */
      double pool[] = {0.0, -0.0, 1.5, 0.1, -2.25, 1e300, -1e300, 1e-300, 3.0, 1.5e308};
      double not_na;
      { uint64_t b = 0x40000000000007a2ull; memcpy(&not_na, &b, sizeof not_na); }
      for (zt_row i = 0; i < n; i++) {
        ids[i] = (zt_row) (next() % (uint32_t) ng);
        uint32_t r = next() % 20;
        xi[i] = r == 0 ? INT32_MIN : (int32_t) (next() % 2000001) - 1000000;
        xl[i] = r == 1 ? INT32_MIN : (int32_t) (next() % 2);
        /* r == 5: an ordinary number whose low word is NA's, 1954. */
        xd[i] = r == 2 ? ZT_F64_NA : r == 3 ? ZT_F64_NAN : r == 4 ? INFINITY :
                r == 5 ? not_na :
                (r == 6 || r == 7) ? pool[9] :
                pool[next() % 9] * (double) (1 + next() % 7);
      }
      /* Every statistic, kind and missing rule, alone. */
      spec all[9 * 3 * 4];
      int ns = 0;
      for (int fn = 0; fn <= ZT_FN_LAST; fn++) {
        for (int k = 0; k < 3; k++) {
          int kind = k == 0 ? ZT_KIND_INT32 : k == 1 ? ZT_KIND_LGL : ZT_KIND_F64;
          for (int na_rm = 0; na_rm < 2; na_rm++) {
            for (int nm = 0; nm < 2; nm++) {
              if (nm && kind != ZT_KIND_F64) continue;
              spec s = {(zt_fn) fn, kind, na_rm, nm};
              all[ns++] = s;
            }
          }
        }
      }
      double **outs = malloc(sizeof(double *) * (size_t) ns);
      zt_reduce_col *cols = malloc(sizeof(zt_reduce_col) * (size_t) ns);
      for (int k = 0; k < ns; k++) {
        const void *x = all[k].kind == ZT_KIND_INT32 ? (const void *) xi :
                        all[k].kind == ZT_KIND_LGL ? (const void *) xl : (const void *) xd;
        outs[k] = malloc(sizeof(double) * (size_t) (ng + 1));
        setup(&cols[k], &all[k], x, ng, outs[k]);
        zt_reduce(ids, n, ng, &cols[k], 1);
        for (zt_row g = 0; g < ng; g++) {
          double dv = 0;
          int32_t iv = 0;
          reference(all[k].fn, all[k].kind, x, all[k].na_rm, all[k].nan_missing, ids, n, g,
                    &dv, &iv);
          double want = all[k].fn >= ZT_FN_COUNT ? (double) iv : dv;
          double got = all[k].fn >= ZT_FN_FIRST ? (double) ((const zt_row *) outs[k])[g] :
                       out_value(&all[k], outs[k], g);
          /* Arithmetic on NA and NaN together gives either (base R says
             so too): the compiler may commute the operation, and IEEE
             takes the payload from the operand order. */
          int arith = !all[k].na_rm && all[k].kind == ZT_KIND_F64 &&
                      all[k].fn <= ZT_FN_MEAN;
          int ok = arith && got != got && want != want ? 1 : same_f64(got, want);
          if (!ok) {
            fprintf(stderr, "n %d ng %d fn %d kind %d na_rm %d nan %d group %d: %.17g, want %.17g\n",
                    n, ng, all[k].fn, all[k].kind, all[k].na_rm, all[k].nan_missing, g, got, want);
          }
          CHECK(ok);
        }
      }
      /* All of them in one sweep: the same bits as each alone. */
      double **fused = malloc(sizeof(double *) * (size_t) ns);
      zt_reduce_col *fc = malloc(sizeof(zt_reduce_col) * (size_t) ns);
      for (int k = 0; k < ns; k++) {
        fused[k] = malloc(sizeof(double) * (size_t) (ng + 1));
        setup(&fc[k], &all[k], cols[k].x, ng, fused[k]);
      }
      zt_reduce(ids, n, ng, fc, ns);
      for (int k = 0; k < ns; k++) {
        size_t width = all[k].fn >= ZT_FN_COUNT ||
                       ((all[k].fn == ZT_FN_MIN || all[k].fn == ZT_FN_MAX) && all[k].kind != ZT_KIND_F64)
                         ? sizeof(int32_t) : sizeof(double);
        CHECK(memcmp(fused[k], outs[k], width * (size_t) ng) == 0);
        teardown(&fc[k]); teardown(&cols[k]);
        free(fused[k]); free(outs[k]);
      }
      free(fused); free(fc); free(outs); free(cols);
      free(ids); free(xi); free(xl); free(xd);
    }
  }
  if (failures) { fprintf(stderr, "test-reduce: %d failures\n", failures); return 1; }
  printf("test-reduce: ok\n");
  return 0;
}
