/*
 * zutable.h -- the kernel's header (design-kernel section 4, D56).
 *
 * Other packages reach the kernel through `LinkingTo: zutable` and
 * `#include <zutable.h>`. Each header under zutable/ also compiles alone,
 * as C11 and as C++17, and without R when ZT_STANDALONE is defined, which
 * is how the C tests, the fuzz target and the consumer fixture build it.
 *
 * Layers, each testable without the one above, arrive stage by stage:
 * key.h (the key model), table.h, partition.h, then groups.h, sort.h
 * (over sortrec.h, pdqsort.h, vergesort.h, skasort.h and radix.h),
 * strsort.h (byte strings), join.h and reduce.h.
 */
#ifndef ZUTABLE_H
#define ZUTABLE_H

#include "zutable/config.h"
#include "zutable/version.h"
#include "zutable/key.h"
#include "zutable/table.h"
#include "zutable/partition.h"
#include "zutable/groups.h"
#include "zutable/sort.h"
#include "zutable/strsort.h"
#include "zutable/join.h"

#endif /* ZUTABLE_H */
