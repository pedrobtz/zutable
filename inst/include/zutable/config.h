/*
 * zutable/config.h -- portable definitions shared by every kernel header.
 *
 * ZT_STANDALONE: defined by a build without R (C tests, fuzzing, the
 * consumer fixture). The headers then use no R API; under R they may.
 */
#ifndef ZUTABLE_CONFIG_H
#define ZUTABLE_CONFIG_H

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#ifdef __cplusplus
#define ZT_INLINE inline
#else
#define ZT_INLINE static inline
#endif

/* The kernel's row index: tables hold at most 2^31 - 1 rows (D11). */
typedef int32_t zt_row;
#define ZT_MAX_ROWS INT32_MAX

#if defined(__GNUC__) || defined(__clang__)
#define ZT_LIKELY(x) __builtin_expect(!!(x), 1)
#define ZT_UNLIKELY(x) __builtin_expect(!!(x), 0)
#define ZT_PREFETCH(p) __builtin_prefetch(p)
#else
#define ZT_LIKELY(x) (x)
#define ZT_UNLIKELY(x) (x)
#define ZT_PREFETCH(p) ((void) (p))
#endif

/* Count trailing zeros of a non-zero 64-bit word. */
#if defined(__GNUC__) || defined(__clang__)
#define ZT_CTZ64(x) __builtin_ctzll(x)
#else
static inline int zt_ctz64_portable(uint64_t x) {
  int n = 0;
  while (!(x & 1)) { x >>= 1; n++; }
  return n;
}
#define ZT_CTZ64(x) zt_ctz64_portable(x)
#endif

#if defined(__cplusplus)
#define ZT_STATIC_ASSERT(cond, msg) static_assert(cond, #msg)
#else
#define ZT_STATIC_ASSERT(cond, msg) _Static_assert(cond, #msg)
#endif

ZT_STATIC_ASSERT(sizeof(zt_row) == 4, row_index_is_32_bits);

#endif /* ZUTABLE_CONFIG_H */
