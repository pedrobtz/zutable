/*
 * The kernel's fuzz target (design-kernel 8): libFuzzer's entry point over
 * the invariants in invariants.c, which says what an input is and what is
 * checked.
 *
 * Built with -DZT_FUZZ_MAIN it is a standalone driver instead: with file
 * arguments it replays them, without any it runs ZT_FUZZ_RUNS random
 * inputs (tools/ci/c-tests.sh runs it so, on every platform).
 */
#include <stdio.h>
#include "fuzz.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size);

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  zt_fuzz_check(data, size);
  return 0;
}

#ifdef ZT_FUZZ_MAIN
#ifndef ZT_FUZZ_RUNS
#define ZT_FUZZ_RUNS 20000
#endif
int main(int argc, char **argv) {
  static uint8_t buf[4 + 3 * MAXN];
  if (argc > 1) {
    for (int a = 1; a < argc; a++) {
      FILE *f = fopen(argv[a], "rb");
      if (!f) { fprintf(stderr, "cannot open %s\n", argv[a]); return 1; }
      size_t m = fread(buf, 1, sizeof buf, f);
      fclose(f);
      LLVMFuzzerTestOneInput(buf, m);
    }
    printf("fuzz replay: %d input(s) ok\n", argc - 1);
    return 0;
  }
  uint64_t r = 20261119;
  for (int run = 0; run < ZT_FUZZ_RUNS; run++) {
    r = r * 6364136223846793005ull + 1442695040888963407ull;
    /* Mostly short inputs, some long; rows drawn from a narrow alphabet
       on some runs, so that keys collide. */
    size_t m = 4 + (size_t) ((r >> 33) % (run % 10 == 0 ? sizeof buf - 4 : 200));
    int narrow = (r >> 20) & 1;
    for (size_t i = 0; i < m; i++) {
      r = r * 6364136223846793005ull + 1442695040888963407ull;
      uint8_t b = (uint8_t) (r >> 56);
      buf[i] = narrow && i >= 4 ? (uint8_t) (b % 12) : b;
    }
    LLVMFuzzerTestOneInput(buf, m);
  }
  printf("fuzz smoke: %d random inputs ok\n", ZT_FUZZ_RUNS);
  return 0;
}
#endif
