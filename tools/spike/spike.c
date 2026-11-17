/*
 * The cost-model spike of design-kernel section 11 (piece a): group and sum
 * 1e7 rows with G groups three ways, and print the median of five timings.
 *
 *   single     one open-addressing table and one accumulator array, row by
 *              row, as collapse does;
 *   prefetch   the same, prefetching the slot eight rows ahead;
 *   partition  rows split by the top bits of their hash into partitions
 *              sized to L2, then one small table per partition.
 *
 * A throwaway program, not part of the package. Every method must agree on
 * the group count and the total before a timing counts (design-kernel 9.2,
 * rule 1). Build: cc -O2 -o spike tools/spike/spike.c; run: ./spike [n].
 */
#define _POSIX_C_SOURCE 199309L
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static double now(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return t.tv_sec + t.tv_nsec * 1e-9;
}

static inline uint64_t mix(uint32_t k) {   /* multiply-shift mixer */
  uint64_t h = (uint64_t) k * 0x9E3779B97F4A7C15ull;
  return h ^ (h >> 29);
}

static uint32_t next_pow2(uint64_t x) {
  uint32_t p = 1;
  while (p < x) p <<= 1;
  return p;
}

/* L3 size: the third argument, in MiB, else 8 MiB. */
static uint64_t l3_bytes = 8u << 20;

/* A table of keys and group ids, capacity a power of two, load <= 1/2. */
typedef struct { uint32_t *key; int32_t *gid; uint32_t mask; } table;

static void table_init(table *t, uint64_t groups) {
  uint32_t cap = next_pow2(groups * 2 + 16);
  t->key = malloc(sizeof(uint32_t) * cap);
  t->gid = malloc(sizeof(int32_t) * cap);
  for (uint32_t i = 0; i < cap; i++) t->gid[i] = -1;
  t->mask = cap - 1;
}

static void table_free(table *t) { free(t->key); free(t->gid); }

static inline int32_t table_find(table *t, uint32_t k, uint64_t h,
                                 int32_t *ngroups) {
  uint32_t s = (uint32_t) h & t->mask;
  for (;;) {
    int32_t g = t->gid[s];
    if (g < 0) { t->key[s] = k; t->gid[s] = *ngroups; return (*ngroups)++; }
    if (t->key[s] == k) return g;
    s = (s + 1) & t->mask;
  }
}

static double run_single(const uint32_t *k, const double *v, int n,
                         uint64_t groups, int prefetch, int *out_groups) {
  table t;
  table_init(&t, groups);
  double *sum = calloc(groups + 1, sizeof(double));
  int32_t ng = 0;
  for (int i = 0; i < n; i++) {
    if (prefetch && i + 8 < n) {
      uint32_t s = (uint32_t) mix(k[i + 8]) & t.mask;
      __builtin_prefetch(&t.gid[s]);
      __builtin_prefetch(&t.key[s]);
    }
    int32_t g = table_find(&t, k[i], mix(k[i]), &ng);
    sum[g] += v[i];
  }
  double total = 0;
  for (int32_t g = 0; g < ng; g++) total += sum[g];
  *out_groups = ng;
  table_free(&t);
  free(sum);
  return total;
}

/* Partitioned: histogram, scatter by the top bits of the hash, then a
   table per partition sized to the partition's share of the groups. */
static double run_partition(const uint32_t *k, const double *v, int n,
                            uint64_t groups, int *out_groups) {
  /* Partitions so that a partition's table (8 bytes a slot, load 1/2) and
     accumulators fit in about 128 KiB, half of L2. */
  uint64_t per = 128 * 1024 / 24;
  /* The cost model's rule (design-kernel 4.1): one pass while the table
     fits in L3, partitions above it. */
  if (groups * 2 * 8 <= l3_bytes) return run_single(k, v, n, groups, 1, out_groups);
  int bits = 0;
  while (bits < 12 && (groups >> bits) > per) bits++;
  int np = 1 << bits;
  if (np == 1) return run_single(k, v, n, groups, 0, out_groups);
  int shift = 64 - bits;
  int *count = calloc(np + 1, sizeof(int));
  uint64_t *h = malloc(sizeof(uint64_t) * n);
  for (int i = 0; i < n; i++) { h[i] = mix(k[i]); count[(h[i] >> shift) + 1]++; }
  for (int p = 0; p < np; p++) count[p + 1] += count[p];
  uint32_t *pk = malloc(sizeof(uint32_t) * n);
  double *pv = malloc(sizeof(double) * n);
  int *pos = malloc(sizeof(int) * np);
  memcpy(pos, count, sizeof(int) * np);
  for (int i = 0; i < n; i++) {
    int p = (int) (h[i] >> shift);
    int j = pos[p]++;
    pk[j] = k[i];
    pv[j] = v[i];
  }
  free(h);
  double total = 0;
  int ng_all = 0;
  uint64_t gper = groups / np + 16;
  table t;
  table_init(&t, gper);
  double *sum = calloc(gper * 4 + 64, sizeof(double));
  for (int p = 0; p < np; p++) {
    for (uint32_t s = 0; s <= t.mask; s++) t.gid[s] = -1;
    int32_t ng = 0;
    for (int j = count[p]; j < count[p + 1]; j++) {
      int32_t g = table_find(&t, pk[j], mix(pk[j]) >> bits, &ng);
      sum[g] += pv[j];
    }
    for (int32_t g = 0; g < ng; g++) { total += sum[g]; sum[g] = 0; }
    ng_all += ng;
  }
  table_free(&t);
  free(sum); free(pk); free(pv); free(pos); free(count);
  *out_groups = ng_all;
  return total;
}

static int cmp_double(const void *a, const void *b) {
  double x = *(const double *) a, y = *(const double *) b;
  return (x > y) - (x < y);
}

int main(int argc, char **argv) {
  int n = argc > 1 ? atoi(argv[1]) : 10000000;
  if (argc > 2) l3_bytes = (uint64_t) atoi(argv[2]) << 20;
  uint64_t gs[] = {1000, 100000, 1000000, 10000000};
  uint32_t *k = malloc(sizeof(uint32_t) * n);
  double *v = malloc(sizeof(double) * n);
  srand(20261117);
  printf("groups,method,seconds,groups_found\n");
  for (int gi = 0; gi < 4; gi++) {
    uint64_t G = gs[gi];
    /* Keys from G distinct values spread over 32 bits, each value present. */
    for (int i = 0; i < n; i++) {
      uint64_t r = ((uint64_t) rand() << 16) ^ (uint64_t) rand();
      uint32_t id = (uint32_t) (i < (int) G ? (uint64_t) i : r % G);
      k[i] = id * 2654435761u + 12345u;
      v[i] = (double) (r % 1000) / 8.0;
    }
    for (int i = n - 1; i > 0; i--) {   /* shuffle, so ids are not ordered */
      int j = (int) ((((uint64_t) rand() << 16) ^ (uint64_t) rand()) % (uint64_t) (i + 1));
      uint32_t tk = k[i]; k[i] = k[j]; k[j] = tk;
      double tv = v[i]; v[i] = v[j]; v[j] = tv;
    }
    const char *names[] = {"single", "prefetch", "partition"};
    double ref_total = 0;
    int ref_groups = 0;
    for (int m = 0; m < 3; m++) {
      double t[5];
      for (int rep = 0; rep < 5; rep++) {
        int ng;
        double t0 = now();
        double total = m == 2 ? run_partition(k, v, n, G, &ng)
                              : run_single(k, v, n, G, m == 1, &ng);
        t[rep] = now() - t0;
        if (m == 0 && rep == 0) { ref_total = total; ref_groups = ng; }
        /* Sums of eighths below 2^53 are exact, so they agree exactly. */
        if (ng != ref_groups || total != ref_total) {
          fprintf(stderr, "disagreement: groups %d vs %d, total %.17g vs %.17g\n",
                  ng, ref_groups, total, ref_total);
          return 1;
        }
      }
      qsort(t, 5, sizeof(double), cmp_double);
      printf("%llu,%s,%.4f,%d\n", (unsigned long long) G, names[m], t[2], ref_groups);
      fflush(stdout);
    }
  }
  free(k); free(v);
  return 0;
}
