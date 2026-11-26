/*
 * Read-only zeros as long as 2^31 - 1 rows for the limit tests
 * (test-groups.c, test-reduce.c, #53): a sparse temporary file, mapped,
 * so the pages are the file's holes and no memory is committed. POSIX
 * only: Windows has no ftruncate() and mmap(), and VirtualAlloc() would
 * commit the gigabytes, so there the tests are skipped (ZT_HAVE_ZEROS 0).
 * The mutation build (ZT_TEST_QUICK) skips them too: a pass over 2^31
 * rows under Mull's instrumentation would outlast the job.
 * Each case is a pass over 2^31 rows (half a minute to three minutes
 * under UBSan), so by default only the first, the limit itself, runs;
 * ZT_TEST_LIMITS=all in the environment runs every case, the rows on
 * either side of each boundary too.
 * Include it before any other header.
 */
#ifndef ZT_TEST_ZEROS_H
#define ZT_TEST_ZEROS_H

#if !defined(_WIN32) && !defined(ZT_TEST_QUICK)
#define ZT_HAVE_ZEROS 1
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <unistd.h>

/* bytes of zeros, or NULL when the file or the map cannot be had. */
static const void *zt_test_zeros(size_t bytes) {
  FILE *f = tmpfile();
  if (f == NULL) return NULL;
  int fd = fileno(f);
  if (ftruncate(fd, (off_t) bytes) != 0) return NULL;
  void *p = mmap(NULL, bytes, PROT_READ, MAP_SHARED, fd, 0);
  return p == MAP_FAILED ? NULL : p;
}

/* How many of a test's ncase cases to run: one, or all of them. */
static size_t zt_test_limit_cases(size_t ncase) {
  const char *e = getenv("ZT_TEST_LIMITS");
  return e != NULL && strcmp(e, "all") == 0 ? ncase : 1;
}
#else
#define ZT_HAVE_ZEROS 0
#endif

#endif
