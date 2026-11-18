// Each port against its original on the same inputs (design-kernel 4.3):
// the C++ originals at the commits the ports were made from
// (tools/ci/fetch-originals.sh puts them in build/originals) beside the C
// ports in inst/include/zutable.
//
//   pdqsort    the same output and the same number of comparisons, input
//              by input: the port makes the original's pivot choices, its
//              partitions and its fallbacks, or the counts drift.
//   Vergesort  the same output; its merges go through std::inplace_merge,
//              whose comparisons differ between standard libraries.
//   ska sort   the same output.
//
// Build: c++ -std=c++17 -O1 -DZT_STANDALONE -Iinst/include -Ibuild/originals
//        tests/c/ports/test-ports.cpp
#include <pdqsort.h>
#include <vergesort.h>
#include <ska_sort.hpp>

#include <zutable/pdqsort.h>
#include <zutable/vergesort.h>
#include <zutable/skasort.h>

#include <cstdio>
#include <cstring>
#include <utility>
#include <vector>

static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { \
  std::fprintf(stderr, "%s:%d: CHECK failed: %s\n", __FILE__, __LINE__, #cond); \
  failures++; } } while (0)

// The pdqsort port once more, over records whose comparison counts.
static long port_comparisons = 0;
static inline int zt_lt_counted(zt_w64 a, zt_w64 b) { port_comparisons++; return a < b; }
#define ZT_SORT_T zt_w64
#define ZT_SORT_SUF counted
#define ZT_SORT_LT zt_lt_counted
#include <zutable/pdqsort.inc>
#undef ZT_SORT_T
#undef ZT_SORT_SUF
#undef ZT_SORT_LT

static uint64_t rng = 20261117;
static uint64_t rnd() {
  rng ^= rng >> 12; rng ^= rng << 25; rng ^= rng >> 27;
  return rng * 0x2545F4914F6CDD1Dull;
}

// Inputs: random, few distinct, sorted, reversed, sorted then 1% random,
// organ pipe, sawtooth; as 8-byte words with the row in the low bits, so
// no two are equal.
static std::vector<uint64_t> input(int shape, size_t n) {
  std::vector<uint64_t> v(n);
  for (size_t i = 0; i < n; i++) {
    uint64_t k;
    switch (shape) {
    case 0: k = rnd() & 0xffffffffu; break;
    case 1: k = rnd() % 5; break;
    case 2: k = i; break;
    case 3: k = n - i; break;
    case 4: k = i < n - n / 100 ? i : rnd() % (n + 1); break;
    case 5: k = i < n / 2 ? i : n - i; break;
    default: k = i % 97; break;
    }
    v[i] = (k << 32) | i;
  }
  return v;
}

int main() {
  const size_t sizes[] = {0, 1, 2, 23, 24, 25, 79, 80, 81, 127, 128, 129, 1000, 1023, 1024,
                          1025, 5000, 100000};
  for (size_t n : sizes) {
    for (int shape = 0; shape < 7; shape++) {
      std::vector<uint64_t> in = input(shape, n);

      // pdqsort: output and comparisons.
      std::vector<uint64_t> a = in, b = in;
      long orig_comparisons = 0;
      pdqsort_branchless(a.begin(), a.end(), [&](uint64_t x, uint64_t y) {
        orig_comparisons++;
        return x < y;
      });
      port_comparisons = 0;
      zt_pdqsort_counted(b.data(), b.data() + n);
      CHECK(a == b);
      if (orig_comparisons != port_comparisons) {
        std::fprintf(stderr, "  pdqsort n=%zu shape=%d: %ld comparisons, port %ld\n", n, shape,
                     orig_comparisons, port_comparisons);
        CHECK(0);
      }

      // Vergesort: output, words and 16-byte records.
      std::vector<uint64_t> c = in, d = in, scratch(n + 1);
      vergesort::vergesort(c.begin(), c.end());
      zt_vergesort_pdq_w64(d.data(), d.data() + n, scratch.data());
      CHECK(c == d);
      std::vector<std::pair<uint64_t, uint64_t>> pc(n);
      std::vector<zt_r128> pd(n), ps(n + 1);
      for (size_t i = 0; i < n; i++) {
        pc[i] = {in[i] >> 32 ^ (in[i] * 0x9e3779b97f4a7c15ull), i};
        pd[i].k = pc[i].first;
        pd[i].i = i;
      }
      std::vector<std::pair<uint64_t, uint64_t>> pe = pc;
      vergesort::vergesort(pc.begin(), pc.end());
      zt_vergesort_pdq_r128(pd.data(), pd.data() + n, ps.data());
      for (size_t i = 0; i < n; i++) CHECK(pc[i].first == pd[i].k && pc[i].second == pd[i].i);

      // ska sort: output, words and 16-byte records (key, then row).
      std::vector<uint64_t> e = in, f = in;
      ska_sort(e.begin(), e.end());
      zt_ska_sort_from_w64(f.data(), f.data() + n, 0, 8);
      CHECK(e == f);
      std::vector<zt_r128> pf(n);
      for (size_t i = 0; i < n; i++) { pf[i].k = pe[i].first; pf[i].i = pe[i].second; }
      ska_sort(pe.begin(), pe.end());
      zt_ska_sort_from_r128(pf.data(), pf.data() + n, 0, 12);
      for (size_t i = 0; i < n; i++) CHECK(pe[i].first == pf[i].k && pe[i].second == pf[i].i);
    }
  }
  if (failures) { std::fprintf(stderr, "%d check(s) failed\n", failures); return 1; }
  std::printf("test-ports: ok\n");
  return 0;
}
