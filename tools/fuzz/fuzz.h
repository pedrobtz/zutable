/* Between the fuzz target's entry point (harness.c) and its invariants
   (invariants.c). */
#ifndef ZT_FUZZ_H
#define ZT_FUZZ_H

#include <stddef.h>
#include <stdint.h>

/* Rows an input holds at most. */
#define MAXN 1024

/* Decodes one input and checks every invariant on it, aborting on a broken
   one; 0 when the input is too short to decode. */
int zt_fuzz_check(const uint8_t *data, size_t size);

#endif
