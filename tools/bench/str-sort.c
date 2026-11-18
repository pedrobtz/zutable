/*
 * Axis N (design-kernel 4.2): three ways to sort distinct byte strings,
 * over the shapes R's string keys have. Prints one TSV row per cell:
 * shape, n, variant, nanoseconds per string (the median of the repeats).
 * Every variant's order is checked against full comparison's before it
 * is timed (section 9.2): a variant that disagrees stops the run.
 *
 *   compare  merge sort with memcmp() on each pair: what base radix does
 *            on the distinct set (strcmp), the control
 *   prefix   the header's zt_str_sort(): the first eight bytes as an
 *            integer through the hybrid, multikey quicksort on ties
 *   msd      MSD radix over the bytes (American flag sort), insertion
 *            sort below 32 strings, the other control
 *
 * Only the winner ships in the header (D14); the controls live here so
 * the measurement can be repeated.
 *
 * Build and run, from the package root, without R:
 *   cc -std=c11 -O2 -DZT_STANDALONE -Iinst/include -I"$(sh tools/ci/zufast-include.sh)" \
 *     tools/bench/str-sort.c -o build/str-sort
 *   build/str-sort [max_n] > build/str-sort.tsv
 */
#define _POSIX_C_SOURCE 199309L
#include <zutable/strsort.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static double now(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return (double) t.tv_sec + 1e-9 * (double) t.tv_nsec;
}

static uint64_t rng = 20261118;
static uint64_t rnd(void) {
  rng ^= rng >> 12; rng ^= rng << 25; rng ^= rng >> 27;
  return rng * 0x2545F4914F6CDD1Dull;
}

/* --- compare: top-down merge sort, insertion below 16 -------------------- */

static int cmp_full(const zt_bytes *a, const zt_bytes *b) { return zt_bytes_cmp_from(a, b, 0); }

static void merge_sort(const zt_bytes *s, zt_row *x, zt_row *tmp, zt_row n) {
  if (n < 16) { zt_str_insertion(s, x, n, 0); return; }
  zt_row h = n / 2;
  merge_sort(s, x, tmp, h);
  merge_sort(s, x + h, tmp, n - h);
  if (cmp_full(&s[x[h - 1]], &s[x[h]]) <= 0) return;
  memcpy(tmp, x, (size_t) h * sizeof *x);
  zt_row i = 0, j = h, k = 0;
  while (i < h && j < n) x[k++] = cmp_full(&s[x[j]], &s[tmp[i]]) < 0 ? x[j++] : tmp[i++];
  while (i < h) x[k++] = tmp[i++];
}

/* --- msd: American flag sort on byte d, 257 buckets (end first) ---------- */

static void msd(const zt_bytes *s, zt_row *x, zt_row *tmp, zt_row n, int32_t d) {
  while (n > 1) {
    if (n < 32) { zt_str_insertion(s, x, n, d); return; }
    zt_row cnt[258] = {0};
    for (zt_row i = 0; i < n; i++) cnt[zt_str_char(&s[x[i]], d) + 1]++;
    for (int b = 0; b < 257; b++) cnt[b + 1] += cnt[b];
    zt_row start[258];
    memcpy(start, cnt, sizeof start);
    for (zt_row i = 0; i < n; i++) tmp[cnt[zt_str_char(&s[x[i]], d)]++] = x[i];
    memcpy(x, tmp, (size_t) n * sizeof *x);
    /* Bucket 0 holds strings that ended: equal, done. Recurse on all but
       the largest bucket, loop on that one. */
    int big = 1;
    for (int b = 1; b < 257; b++) {
      if (start[b + 1] - start[b] > start[big + 1] - start[big]) big = b;
    }
    for (int b = 1; b < 257; b++) {
      if (b != big) msd(s, x + start[b], tmp, start[b + 1] - start[b], d + 1);
    }
    x += start[big];
    n = start[big + 1] - start[big];
    d++;
  }
}

/* --- shapes ---------------------------------------------------------------- */

enum { RANDOM, URL, CODE, WORDS, NSHAPE };
static const char *shape_name[] = {"random", "url", "code", "words"};

/* n distinct strings (duplicates are re-drawn by suffixing the index when
   a shape makes them likely), in buf. */
static void make(int shape, zt_bytes *s, zt_row n, uint8_t *buf) {
  size_t at = 0;
  for (zt_row i = 0; i < n; i++) {
    uint8_t *p = buf + at;
    int len = 0;
    switch (shape) {
    case RANDOM: /* 6 to 24 letters: distinct in practice */
      len = 6 + (int) (rnd() % 19);
      for (int j = 0; j < len; j++) p[j] = (uint8_t) ('a' + rnd() % 26);
      break;
    case URL: /* a 25-byte shared prefix, a path, a unique number */
      len = sprintf((char *) p, "https://example.org/item/%c%c/%d",
                    (char) ('a' + rnd() % 26), (char) ('a' + rnd() % 26), (int) i);
      break;
    case CODE: /* identifiers: two letters and seven digits, unique */
      len = sprintf((char *) p, "%c%c%07d", (char) ('A' + rnd() % 26),
                    (char) ('A' + rnd() % 26), (int) ((i * 2654435761u) % 10000000u));
      break;
    default: /* words from a small alphabet, then the index for uniqueness */
      len = 3 + (int) (rnd() % 8);
      for (int j = 0; j < len; j++) p[j] = (uint8_t) "etaoinshr"[rnd() % 9];
      len += sprintf((char *) p + len, "%d", (int) i);
      break;
    }
    s[i].data = p;
    s[i].len = len;
    at += (size_t) len;
  }
}

#define REPS 5
static int cmp_double(const void *a, const void *b) {
  double x = *(const double *) a, y = *(const double *) b;
  return (x > y) - (x < y);
}

int main(int argc, char **argv) {
  zt_row max_n = argc > 1 ? (zt_row) atof(argv[1]) : 1000000;
  printf("shape\tn\tvariant\tns_per_str\n");
  for (zt_row n = 1000; n <= max_n; n *= 10) {
    zt_bytes *s = malloc((size_t) n * sizeof *s);
    uint8_t *buf = malloc((size_t) n * 48);
    zt_row *x = malloc((size_t) n * sizeof *x), *ref = malloc((size_t) n * sizeof *ref);
    zt_row *tmp = malloc((size_t) n * sizeof *tmp);
    void *mem = malloc(zt_str_sort_scratch_bytes(n));
    for (int shape = 0; shape < NSHAPE; shape++) {
      make(shape, s, n, buf);
      for (zt_row i = 0; i < n; i++) ref[i] = i;
      merge_sort(s, ref, tmp, n);
      for (int v = 0; v < 3; v++) {
        double t[REPS];
        for (int r = 0; r < REPS; r++) {
          for (zt_row i = 0; i < n; i++) x[i] = i;
          /* The same starting order for each variant: shuffled. */
          uint64_t save = rng;
          rng = 7;
          for (zt_row i = n - 1; i > 0; i--) {
            zt_row j = (zt_row) (rnd() % (uint64_t) (i + 1));
            zt_row q = x[i]; x[i] = x[j]; x[j] = q;
          }
          rng = save;
          /* zt_str_sort takes the strings in index order: sort a gathered
             copy so every variant sees the same shuffled input. */
          zt_bytes *g = malloc((size_t) n * sizeof *g);
          for (zt_row i = 0; i < n; i++) g[i] = s[x[i]];
          zt_row *y = malloc((size_t) n * sizeof *y);
          for (zt_row i = 0; i < n; i++) y[i] = i;
          double t0 = now();
          if (v == 0) merge_sort(g, y, tmp, n);
          else if (v == 1) zt_str_sort(g, n, y, mem);
          else msd(g, y, tmp, n, 0);
          t[r] = now() - t0;
          for (zt_row i = 0; i < n; i++) {
            if (cmp_full(&g[y[i]], &s[ref[i]]) != 0) {
              fprintf(stderr, "variant %d disagrees: %s n=%d at %d\n", v,
                      shape_name[shape], (int) n, (int) i);
              return 1;
            }
          }
          free(g); free(y);
        }
        qsort(t, REPS, sizeof t[0], cmp_double);
        static const char *vname[] = {"compare", "prefix", "msd"};
        printf("%s\t%d\t%s\t%.1f\n", shape_name[shape], (int) n, vname[v],
               1e9 * t[REPS / 2] / (double) n);
        fflush(stdout);
      }
    }
    free(s); free(buf); free(x); free(ref); free(tmp); free(mem);
  }
  return 0;
}
