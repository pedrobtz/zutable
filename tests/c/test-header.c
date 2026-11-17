/*
 * The kernel header built without R (ZT_STANDALONE): the build itself is
 * the first check, and this binary checks the configuration it states.
 * Later stages add a file per layer. Exits non-zero on the first failure.
 */
#define ZT_STANDALONE 1
#include <zutable.h>
#include <stdio.h>
#include <stdlib.h>

static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { \
  fprintf(stderr, "%s:%d: CHECK failed: %s\n", __FILE__, __LINE__, #cond); \
  failures++; } } while (0)

int main(void) {
  char want[32];
  snprintf(want, sizeof want, "%d.%d.%d.%d", ZUTABLE_VERSION_MAJOR,
           ZUTABLE_VERSION_MINOR, ZUTABLE_VERSION_PATCH, ZUTABLE_VERSION_DEV);
  CHECK(strcmp(want, ZUTABLE_VERSION) == 0);
  CHECK(ZT_MAX_ROWS == 2147483647);
  CHECK(sizeof(zt_row) == 4);
  CHECK(ZT_LIKELY(1) && !ZT_UNLIKELY(0));
  if (failures) {
    fprintf(stderr, "%d check(s) failed\n", failures);
    return 1;
  }
  printf("test-header: ok\n");
  return 0;
}
