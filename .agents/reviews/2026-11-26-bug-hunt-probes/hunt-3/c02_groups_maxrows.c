// zt_groups_one() over m rows close to 2^31 - 1: the prefetch's `r + 8 < m`.
// rows[] comes from a sparse file mapped read-only (all zero: every row is row 0), so
// only ids[0] and h[0] are touched; the key has no columns, so there is one group.
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <zutable.h>
int main(int argc, char **argv) {
  zt_row m = argc > 1 ? (zt_row) atoll(argv[1]) : INT32_MAX;
  int fd = open(argc > 2 ? argv[2] : "sparse.bin", O_RDWR | O_CREAT, 0600);
  size_t bytes = ((size_t) INT32_MAX + 1) * sizeof(zt_row);
  if (fd < 0 || ftruncate(fd, (off_t) bytes)) { perror("file"); return 2; }
  const zt_row *rows = (const zt_row *) mmap(NULL, bytes, PROT_READ, MAP_SHARED, fd, 0);
  if (rows == MAP_FAILED) { perror("mmap"); return 2; }
  zt_key k = {NULL, 0};
  uint64_t h[1] = {0};
  zt_row ids[1], first[1], ng = 0;
  uint64_t cap = 16;
  zt_table t;
  zt_table_init(&t, malloc(zt_table_bytes(cap)), cap);
  fprintf(stderr, "m = %d\n", m);
  zt_row done = zt_groups_one(&k, h, rows, 0, m, &t, ids, first, 0, &ng);
  printf("m = %d done = %d groups = %d %s\n", m, done, ng, done == m && ng == 1 ? "ok" : "WRONG");
  return 0;
}
