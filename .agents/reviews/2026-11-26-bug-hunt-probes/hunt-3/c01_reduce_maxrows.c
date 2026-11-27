// zt_reduce() over n rows close to 2^31 - 1: the block loop's `lo += ZT_REDUCE_BLOCK`.
// ids come from a sparse file mapped read-only (all zero: one group), so no memory is used.
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <zutable.h>
int main(int argc, char **argv) {
  zt_row n = argc > 1 ? (zt_row) atoll(argv[1]) : INT32_MAX;
  const char *path = argc > 2 ? argv[2] : "sparse.bin";
  int fd = open(path, O_RDWR | O_CREAT, 0600);
  size_t bytes = ((size_t) INT32_MAX + 1) * sizeof(zt_row);
  if (fd < 0 || ftruncate(fd, (off_t) bytes)) { perror("file"); return 2; }
  const zt_row *ids = (const zt_row *) mmap(NULL, bytes, PROT_READ, MAP_SHARED, fd, 0);
  if (ids == MAP_FAILED) { perror("mmap"); return 2; }
  int32_t out[1];
  zt_reduce_col c;
  memset(&c, 0, sizeof c);
  c.fn = ZT_FN_COUNT; c.kind = ZT_KIND_INT32; c.x = NULL; c.out = out;
  fprintf(stderr, "n = %d\n", n);
  zt_reduce(ids, n, 1, &c, 1);
  printf("n = %d count = %d %s\n", n, out[0], out[0] == n ? "ok" : "WRONG");
  return 0;
}
