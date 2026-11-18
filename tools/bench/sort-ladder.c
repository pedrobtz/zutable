/*
 * The sort ladder (design-kernel 4.3): every rung over n from 10 up, over
 * 8-byte words (a 32-bit key and the row) and 16-byte records (a 64-bit
 * key and the row), over the shapes R data has. Prints one TSV row per
 * cell: record, shape, n, rung, nanoseconds per element (the median of
 * the repeats). Every rung's output is checked against pdqsort's before
 * it is timed (section 9.2): a rung that disagrees stops the run.
 *
 * Build and run, from the package root, without R:
 *   cc -std=c11 -O2 -DZT_STANDALONE -Iinst/include -I"$(sh tools/ci/zufast-include.sh)" \
 *     tools/bench/sort-ladder.c -o build/sort-ladder -lm
 *   build/sort-ladder [max_n] > build/sort-ladder.tsv
 */
#define _POSIX_C_SOURCE 199309L
#include <zutable/pdqsort.h>
#include <zutable/vergesort.h>
#include <zutable/skasort.h>
#include <zutable/radix.h>
#include <zutable/sort.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static double now(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return (double) t.tv_sec + 1e-9 * (double) t.tv_nsec;
}

static uint64_t rng = 20261117;
static uint64_t rnd(void) {
  rng ^= rng >> 12; rng ^= rng << 25; rng ^= rng >> 27;
  return rng * 0x2545F4914F6CDD1Dull;
}

enum { UNIFORM, FEW, ZIPF, SORTED, REVERSED, APPENDED, NSHAPES };
static const char *shape_name[] = {"uniform", "few", "zipf", "sorted", "reversed", "sorted+1%"};

/* The key for row i of n in a shape, `wide` for 64 key bits. */
static uint64_t make_key(int shape, size_t i, size_t n, int wide) {
  uint64_t top = wide ? UINT64_MAX : UINT32_MAX;
  switch (shape) {
  case UNIFORM: return rnd() & top;
  case FEW: return rnd() % 16;
  case ZIPF: {
    double u = (double) (rnd() >> 11) / 9007199254740992.0;
    return (uint64_t) floor(exp(u * log((double) n + 1))) - 1;
  }
  case SORTED: return wide ? (uint64_t) i * 2654435761u : (uint64_t) i;
  case REVERSED: return wide ? (uint64_t) (n - i) * 2654435761u : (uint64_t) (n - i);
  default: /* sorted, with the last 1% random */
    if (i < n - n / 100) return wide ? (uint64_t) i * 2654435761u : (uint64_t) i;
    return rnd() % ((uint64_t) n + 1) * (wide ? 2654435761u : 1u);
  }
}

static int bits_of(uint64_t range) {
  int b = 0;
  while (range) { b++; range >>= 1; }
  return b;
}

typedef struct {
  const char *name;
  size_t max_n; /* 0: no limit */
  int dense_only;
} rung;

enum { R_INSERTION, R_PDQ, R_HEAP, R_VERGE, R_SKA, R_LSD8, R_LSD11, R_MSDLSD, R_COUNT, R_HYBRID, NRUNGS };
static const rung rungs[NRUNGS] = {
  {"insertion", 10000, 0}, {"pdqsort", 0, 0}, {"heapsort", 0, 0},
  {"vergesort+pdq", 0, 0}, {"ska", 0, 0}, {"lsd8", 0, 0}, {"lsd11", 0, 0},
  {"msd+lsd", 0, 0}, {"counting", 0, 1}, {"hybrid", 0, 0},
};

typedef struct { uint64_t kmin, range; int kbits; } keyinfo;

static void run_w64(int r, zt_w64 *a, size_t n, zt_w64 *tmp, uint32_t *cnt, keyinfo ki) {
  switch (r) {
  case R_INSERTION: zt_insertion_w64(a, a + n); break;
  case R_PDQ: zt_pdqsort_w64(a, a + n); break;
  case R_HEAP: zt_heapsort_w64(a, a + n); break;
  case R_VERGE: zt_vergesort_pdq_w64(a, a + n, tmp); break;
  case R_SKA: zt_ska_sort_from_w64(a, a + n, 0, 8); break;
  case R_LSD8: zt_lsd_w64(a, n, ki.kbits, 8, tmp); break;
  case R_LSD11: zt_lsd_w64(a, n, ki.kbits, 11, tmp); break;
  case R_MSDLSD: zt_msd_lsd_w64(a, n, ki.kbits, tmp); break;
  case R_COUNT: zt_counting_w64(a, n, ki.kmin, ki.range, tmp, cnt); break;
  case R_HYBRID: zt_hybrid_w64(a, n, ki.kbits, ki.range, tmp, cnt); break;
  }
}

static void run_r128(int r, zt_r128 *a, size_t n, zt_r128 *tmp, uint32_t *cnt, keyinfo ki) {
  switch (r) {
  case R_INSERTION: zt_insertion_r128(a, a + n); break;
  case R_PDQ: zt_pdqsort_r128(a, a + n); break;
  case R_HEAP: zt_heapsort_r128(a, a + n); break;
  case R_VERGE: zt_vergesort_pdq_r128(a, a + n, tmp); break;
  case R_SKA: zt_ska_sort_from_r128(a, a + n, 0, 12); break;
  case R_LSD8: zt_lsd_r128(a, n, ki.kbits, 8, tmp); break;
  case R_LSD11: zt_lsd_r128(a, n, ki.kbits, 11, tmp); break;
  case R_MSDLSD: zt_msd_lsd_r128(a, n, ki.kbits, tmp); break;
  case R_COUNT: zt_counting_r128(a, n, ki.kmin, ki.range, tmp, cnt); break;
  case R_HYBRID: zt_hybrid_r128(a, n, ki.kbits, ki.range, tmp, cnt); break;
  }
}

static int cmp_double(const void *x, const void *y) {
  double a = *(const double *) x, b = *(const double *) y;
  return (a > b) - (a < b);
}

int main(int argc, char **argv) {
  size_t max_n = argc > 1 ? (size_t) atof(argv[1]) : 10000000;
  size_t cap = max_n;
  zt_w64 *w = malloc(cap * sizeof *w), *wi = malloc(cap * sizeof *wi),
         *wt = malloc(cap * sizeof *wt), *wref = malloc(cap * sizeof *wref);
  zt_r128 *q = malloc(cap * sizeof *q), *qi = malloc(cap * sizeof *qi),
          *qt = malloc(cap * sizeof *qt), *qref = malloc(cap * sizeof *qref);
  uint32_t *cnt = malloc((cap + 2) * sizeof *cnt);
  if (!w || !wi || !wt || !wref || !q || !qi || !qt || !qref || !cnt) return 2;
  printf("record\tshape\tn\trung\tns_per_elt\n");
  for (size_t n = 10; n <= max_n; n *= 10) {
    for (int shape = 0; shape < NSHAPES; shape++) {
      for (int wide = 0; wide <= 1; wide++) {
        keyinfo ki = {UINT64_MAX, 0, 0};
        uint64_t kmax = 0;
        for (size_t i = 0; i < n; i++) {
          uint64_t k = make_key(shape, i, n, wide);
          if (k < ki.kmin) ki.kmin = k;
          if (k > kmax) kmax = k;
          if (wide) { qi[i].k = k; qi[i].i = i; }
          else wi[i] = (k << 32) | (uint64_t) i;
        }
        /* The encoder shifts keys to start at 0 (range compression). */
        for (size_t i = 0; i < n; i++) {
          if (wide) qi[i].k -= ki.kmin;
          else wi[i] = ((((wi[i] >> 32) - ki.kmin)) << 32) | (wi[i] & 0xffffffffu);
        }
        ki.range = kmax - ki.kmin;
        ki.kbits = bits_of(ki.range);
        ki.kmin = 0;
        if (wide) { memcpy(qref, qi, n * sizeof *q); zt_pdqsort_r128(qref, qref + n); }
        else { memcpy(wref, wi, n * sizeof *w); zt_pdqsort_w64(wref, wref + n); }
        /* Repeat small sorts so each cell runs for about 50 ms. */
        size_t reps = n >= 1000000 ? 3 : (size_t) (5e6 / (double) n) + 3;
        for (int r = 0; r < NRUNGS; r++) {
          if (rungs[r].max_n && n > rungs[r].max_n) continue;
          if (rungs[r].dense_only && ki.range >= (uint64_t) n) continue;
          double t[64];
          int nt = 0;
          size_t inner = reps > 5 ? reps / 5 : 1;
          int outer = reps > 5 ? 5 : (int) reps;
          for (int o = 0; o < outer; o++) {
            double el = 0;
            for (size_t k = 0; k < inner; k++) {
              if (wide) memcpy(q, qi, n * sizeof *q); else memcpy(w, wi, n * sizeof *w);
              double t0 = now();
              if (wide) run_r128(r, q, n, qt, cnt, ki); else run_w64(r, w, n, wt, cnt, ki);
              el += now() - t0;
            }
            t[nt++] = el / (double) inner;
            if (wide ? memcmp(q, qref, n * sizeof *q) : memcmp(w, wref, n * sizeof *w)) {
              fprintf(stderr, "%s disagrees with pdqsort: %s %s n=%zu\n",
                      rungs[r].name, wide ? "r128" : "w64", shape_name[shape], n);
              return 1;
            }
          }
          qsort(t, (size_t) nt, sizeof(double), cmp_double);
          printf("%s\t%s\t%zu\t%s\t%.2f\n", wide ? "r128" : "w64", shape_name[shape], n,
                 rungs[r].name, 1e9 * t[nt / 2] / (double) n);
          fflush(stdout);
        }
      }
    }
  }
  return 0;
}
