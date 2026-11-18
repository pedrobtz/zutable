/*
 * The hybrid sort of sort.h, once per record type. Written for zutable.
 * The choices follow the regime map of .agents/benchmarks.md (Stage 11).
 */

#define T ZT_SORT_T

/* The sort of one stretch, chosen by its size and the key: what Vergesort
   calls between runs, and for the whole input when it finds none. */
ZT_INLINE void ZT_SORT_FN(zt_hybrid_piece)(T *b, T *e, T *scratch, void *vctx) {
  const zt_hybrid_ctx *ctx = (const zt_hybrid_ctx *) vctx;
  size_t n = (size_t) (e - b);
  if (n < ZT_SORT_LEAF) { ZT_SORT_FN(zt_insertion)(b, e); return; }
  /* Dense: fewer code values than records, and few enough that the
     counts stay in L1 (ZT_SORT_DENSE_MAX); past that, radix wins. */
  if (ctx->range < (uint64_t) n && ctx->range < ZT_SORT_DENSE_MAX) {
    ZT_SORT_FN(zt_counting)(b, n, 0, ctx->range, scratch, ctx->cnt);
    return;
  }
  if (n < ZT_SORT_RADIX_MIN) { ZT_SORT_FN(zt_pdqsort)(b, e); return; }
  /* Two passes of 11-bit digits beat three of 8 bits for keys of 17 to 22
     bits, and the MSD pass too for 17 to 19 bits even above ZT_SORT_MSD_MIN
     (measured at 1e6 and 1e7). */
  int lsd11 = ctx->kbits > 16 && ctx->kbits <= (n >= ZT_SORT_MSD_MIN ? 19 : 22);
  if (lsd11) { ZT_SORT_FN(zt_lsd)(b, n, ctx->kbits, 11, scratch); return; }
  if (n >= ZT_SORT_MSD_MIN) { ZT_SORT_FN(zt_msd_lsd)(b, n, ctx->kbits, scratch); return; }
  if (ctx->kbits > 32) {
    /* Wide keys: ska sort's in-place MSD from the first byte in use. */
    ZT_SORT_FN(zt_ska_sort_from)(b, e, (64 - ctx->kbits) / 8, ZT_SORT_NBYTES);
    return;
  }
  ZT_SORT_FN(zt_lsd)(b, n, ctx->kbits, 8, scratch);
}

/* Sorts a[0, n) by key, rows in row order to begin with; kbits and range
   describe the codes, cnt holds range + 2 counts when range < n. */
ZT_INLINE void ZT_SORT_FN(zt_hybrid)(T *a, size_t n, int kbits, uint64_t range,
                                      T *tmp, uint32_t *cnt) {
  if (n < 2) return;
  zt_hybrid_ctx ctx = {kbits, range, cnt};
  /* Vergesort's scan costs a few comparisons per log n when it finds no
     run, and turns sorted and nearly sorted input into O(n). */
  if (n < 128) { ZT_SORT_FN(zt_hybrid_piece)(a, a + n, tmp, &ctx); return; }
  (void) ZT_SORT_FN(zt_vergesort)(a, a + n, tmp, ZT_SORT_FN(zt_hybrid_piece), &ctx);
}

#undef T
