/*
 * Axis M (design-kernel 4.2): the cost of long double accumulation in
 * zt_reduce()'s scatter loop. Build twice and compare:
 *
 *   cc -O2 -std=c11 -DZT_STANDALONE -Iinst/include -I<zufast> \
 *     -DZT_PRECISION=1 tools/bench/reduce-precision.c -o rp1
 *   cc ... -DZT_PRECISION=0 ... -o rp0
 *   ./rp1 1e7; ./rp0 1e7
 *
 * Prints, per group count, the median of 5 runs of sum and of mean over n
 * uniform doubles with uniform group ids, and a checksum so that the work
 * cannot be optimised away.
 */
#define ZT_STANDALONE 1
#include <zutable.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static uint64_t rng = 20261118;
static uint64_t next(void) { rng = rng * 6364136223846793005ull + 1442695040888963407ull; return rng >> 11; }

static double now(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return (double) t.tv_sec + (double) t.tv_nsec * 1e-9;
}

static int cmp(const void *a, const void *b) {
  double x = *(const double *) a, y = *(const double *) b;
  return (x > y) - (x < y);
}

int main(int argc, char **argv) {
  zt_row n = argc > 1 ? (zt_row) atof(argv[1]) : 10000000;
  double *x = malloc(sizeof(double) * (size_t) n);
  zt_row *ids = malloc(sizeof(zt_row) * (size_t) n);
  for (zt_row i = 0; i < n; i++) x[i] = (double) next() / 9007199254740992.0;
  static const zt_row groups[] = {1000, 100000, 10000000};
  printf("ZT_PRECISION %d, sizeof(zt_acc) %d, n %d\n", ZT_PRECISION, (int) sizeof(zt_acc), n);
  for (size_t gi = 0; gi < sizeof groups / sizeof groups[0]; gi++) {
    zt_row ng = groups[gi] < n ? groups[gi] : n;
    for (zt_row i = 0; i < n; i++) ids[i] = (zt_row) (next() % (uint64_t) ng);
    double *out = malloc(sizeof(double) * (size_t) ng);
    zt_acc *acc = malloc(sizeof(zt_acc) * (size_t) ng);
    zt_acc *acc2 = malloc(sizeof(zt_acc) * (size_t) ng);
    zt_row *cnt = malloc(sizeof(zt_row) * (size_t) ng);
    uint8_t *flag = malloc((size_t) ng);
    for (int fn = ZT_FN_SUM; fn <= ZT_FN_MEAN; fn += 2) {
      double t[5], check = 0;
      for (int r = 0; r < 5; r++) {
        zt_reduce_col c = {(zt_fn) fn, ZT_KIND_F64, x, 1, 1, out, acc,
                           fn == ZT_FN_MEAN ? acc2 : NULL, cnt, flag};
        double t0 = now();
        zt_reduce(ids, n, ng, &c, 1);
        t[r] = now() - t0;
        check += out[0] + out[ng - 1];
      }
      qsort(t, 5, sizeof t[0], cmp);
      printf("%s, %d groups: %.4f s (check %.6g)\n", fn == ZT_FN_SUM ? "sum" : "mean", ng, t[2], check);
    }
    free(out); free(acc); free(acc2); free(cnt); free(flag);
  }
  return 0;
}
