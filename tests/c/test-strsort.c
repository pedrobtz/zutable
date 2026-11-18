/*
 * The string sort without R (ZT_STANDALONE): zt_str_sort() against qsort()
 * with a comparator written from design-kernel 6.3 (memcmp, then the
 * shorter first), at sizes either side of the leaf (ZT_STR_LEAF) and of
 * the hybrid's thresholds, over strings that share long prefixes, that
 * hold zero bytes, that are empty, shorter than eight bytes or equal; and
 * the dense ranks against a walk of that order.
 */
#define ZT_STANDALONE 1
#include <zutable.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { \
  fprintf(stderr, "%s:%d: CHECK failed: %s\n", __FILE__, __LINE__, #cond); \
  failures++; } } while (0)

static uint64_t rng = 20261118;
static uint64_t rnd(void) {
  rng ^= rng >> 12; rng ^= rng << 25; rng ^= rng >> 27;
  return rng * 0x2545F4914F6CDD1Dull;
}

/* The order of 6.3, written without the prefix: memcmp over the common
   length, then the shorter first. */
static const zt_bytes *base;
static int cmp_ref(const void *x, const void *y) {
  const zt_bytes *a = &base[*(const zt_row *) x], *b = &base[*(const zt_row *) y];
  int32_t m = a->len < b->len ? a->len : b->len;
  int c = m ? memcmp(a->data, b->data, (size_t) m) : 0;
  if (c) return c;
  return (a->len > b->len) - (a->len < b->len);
}

enum { SHAPE_RANDOM, SHAPE_PREFIX, SHAPE_ZEROS, SHAPE_SHORT, SHAPE_DUPS, NSHAPE };

/* m strings of one shape in buf (cap bytes); returns the bytes used. */
static void make(int shape, zt_bytes *s, zt_row m, uint8_t *buf) {
  size_t at = 0;
  for (zt_row i = 0; i < m; i++) {
    int32_t len;
    uint8_t *p = buf + at;
    switch (shape) {
    case SHAPE_RANDOM:
      len = (int32_t) (rnd() % 24);
      for (int32_t j = 0; j < len; j++) p[j] = (uint8_t) ('a' + rnd() % 26);
      break;
    case SHAPE_PREFIX: /* 20 shared bytes, then a few that differ */
      len = 20 + (int32_t) (rnd() % 6);
      for (int32_t j = 0; j < len; j++) p[j] = j < 20 ? (uint8_t) "https://example.org/"[j] : (uint8_t) ('0' + rnd() % 3);
      break;
    case SHAPE_ZEROS: /* raw bytes: zero bytes against zero padding */
      len = (int32_t) (rnd() % 12);
      for (int32_t j = 0; j < len; j++) p[j] = (uint8_t) (rnd() % 3 == 0 ? 0 : rnd() % 4);
      break;
    case SHAPE_SHORT:
      len = (int32_t) (rnd() % 3);
      for (int32_t j = 0; j < len; j++) p[j] = (uint8_t) ('x' + rnd() % 3);
      break;
    default: /* many equal strings, a few distinct values */
      len = 9;
      memset(p, 'k', 9);
      p[8] = (uint8_t) ('0' + rnd() % 4);
      break;
    }
    s[i].data = p;
    s[i].len = len;
    at += (size_t) len;
  }
}

static void test_sort(void) {
  const zt_row sizes[] = {0, 1, 2, 15, 16, 17, 23, 24, 25, 127, 128, 129,
                          999, 1000, 1001, 20000};
  for (size_t si = 0; si < sizeof sizes / sizeof sizes[0]; si++) {
    zt_row m = sizes[si];
    for (int shape = 0; shape < NSHAPE; shape++) {
      zt_bytes *s = malloc((size_t) (m ? m : 1) * sizeof *s);
      uint8_t *buf = malloc((size_t) (m ? m : 1) * 32);
      zt_row *perm = malloc((size_t) (m ? m : 1) * sizeof *perm);
      zt_row *want = malloc((size_t) (m ? m : 1) * sizeof *want);
      zt_row *rank = malloc((size_t) (m ? m : 1) * sizeof *rank);
      void *mem = malloc(zt_str_sort_scratch_bytes(m));
      make(shape, s, m, buf);
      zt_str_sort(s, m, perm, mem);
      for (zt_row i = 0; i < m; i++) want[i] = i;
      base = s;
      qsort(want, (size_t) m, sizeof *want, cmp_ref);
      /* Equal strings may come in any order: compare the strings. */
      int ok = 1;
      for (zt_row i = 0; i < m; i++) {
        if (cmp_ref(&perm[i], &want[i]) != 0) { ok = 0; break; }
      }
      CHECK(ok);
      /* perm is a permutation. */
      char *seen = calloc((size_t) (m ? m : 1), 1);
      for (zt_row i = 0; i < m; i++) seen[perm[i]]++;
      for (zt_row i = 0; i < m; i++) if (seen[i] != 1) ok = 0;
      CHECK(ok);
      /* Dense ranks: equal strings share one, each new string the next. */
      zt_str_dense_rank(s, m, perm, rank);
      zt_row r = 0;
      for (zt_row i = 0; i < m; i++) {
        if (i == 0 || cmp_ref(&want[i - 1], &want[i]) != 0) r++;
        if (rank[want[i]] != r) ok = 0;
      }
      CHECK(ok);
      if (!ok) fprintf(stderr, "  m = %d, shape = %d\n", (int) m, shape);
      free(seen); free(s); free(buf); free(perm); free(want); free(rank); free(mem);
    }
  }
}

/* Strings that share thousands of bytes: the stack stays shallow and the
   order is still the reference's. */
static void test_long_prefix(void) {
  enum { M = 3000, L = 5000 };
  uint8_t *buf = malloc((size_t) M * L);
  zt_bytes *s = malloc(M * sizeof *s);
  zt_row *perm = malloc(M * sizeof *perm), *want = malloc(M * sizeof *want);
  void *mem = malloc(zt_str_sort_scratch_bytes(M));
  for (zt_row i = 0; i < M; i++) {
    uint8_t *p = buf + (size_t) i * L;
    memset(p, 'a', L);
    p[L - 2] = (uint8_t) ('a' + i % 26);
    p[L - 1] = (uint8_t) ('a' + (i / 26) % 26);
    s[i].data = p;
    s[i].len = L - (int32_t) (i % 5 == 0);
  }
  zt_str_sort(s, M, perm, mem);
  for (zt_row i = 0; i < M; i++) want[i] = i;
  base = s;
  qsort(want, M, sizeof *want, cmp_ref);
  int ok = 1;
  for (zt_row i = 0; i < M; i++) if (cmp_ref(&perm[i], &want[i]) != 0) ok = 0;
  CHECK(ok);
  free(buf); free(s); free(perm); free(want); free(mem);
}

int main(void) {
  test_sort();
  test_long_prefix();
  if (failures) {
    fprintf(stderr, "%d failure(s)\n", failures);
    return 1;
  }
  printf("test-strsort: ok\n");
  return 0;
}
