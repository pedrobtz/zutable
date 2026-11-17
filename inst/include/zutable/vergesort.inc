/*
 * Vergesort, ported to C from Morwenn's vergesort.h
 * (https://github.com/Morwenn/vergesort, commit a1a5081f4989b0db443e81d0143a3507d16f8195),
 * the random-access version, specialised to one record type per inclusion
 * (see sortrec.h).
 *
 * Original notice:
 *
 *   The MIT License (MIT)
 *
 *   Copyright (c) 2015-2020 Morwenn <morwenn29@hotmail.fr>
 *
 *   Permission is hereby granted, free of charge, to any person obtaining a
 *   copy of this software and associated documentation files (the
 *   "Software"), to deal in the Software without restriction, including
 *   without limitation the rights to use, copy, modify, merge, publish,
 *   distribute, sublicense, and/or sell copies of the Software, and to
 *   permit persons to whom the Software is furnished to do so, subject to
 *   the following conditions:
 *
 *   The above copyright notice and this permission notice shall be included
 *   in all copies or substantial portions of the Software.
 *
 *   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
 *   OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 *   MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 *   IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 *   CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 *   TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 *   SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 *
 * Altered from the original: C instead of C++ templates; iterators are
 * pointers; the sort of the unsorted stretches is a parameter (the
 * original calls pdqsort, which is what zt_vergesort_pdq_* passes); the
 * list of runs is a fixed array, since there are at most about
 * 2 log2(n) of them; std::inplace_merge is a buffered merge into the
 * caller's scratch, as std::inplace_merge does when it can allocate.
 */

#define T ZT_SORT_T
#define LT ZT_SORT_LT

/* Merges the sorted [first, middle) and [middle, last) through buf, which
   holds middle - first records. */
ZT_INLINE void ZT_SORT_FN(zt_merge)(T *first, T *middle, T *last, T *buf) {
  if (first == middle || middle == last) return;
  if (!LT(*middle, *(middle - 1))) return;
  size_t nl = (size_t) (middle - first);
  memcpy(buf, first, nl * sizeof(T));
  T *a = buf, *ae = buf + nl, *b = middle, *out = first;
  while (a < ae && b < last) {
    if (LT(*b, *a)) *out++ = *b++; else *out++ = *a++;
  }
  while (a < ae) *out++ = *a++;
}

/* Reverses [b, e). */
ZT_INLINE void ZT_SORT_FN(zt_reverse)(T *b, T *e) {
  while (b < e) { T t = *b; *b++ = *--e; *e = t; }
}

/* Vergesort of [first, last): finds runs, ascending or descending, of at
   least n / log2(n), sorts what lies between them with `fallback` (given
   `scratch` and `ctx`), then merges the runs pairwise. `scratch` holds last - first
   records. Returns the number of runs it found; 0 means the whole input
   went to the fallback. */
ZT_INLINE int ZT_SORT_FN(zt_vergesort)(T *first, T *last, T *scratch,
                                        void (*fallback)(T *, T *, T *, void *),
                                        void *ctx) {
  ptrdiff_t dist = last - first;
  if (dist < 128) {
    /* Vergesort is inefficient for small collections. */
    fallback(first, last, scratch, ctx);
    return 0;
  }
  const ptrdiff_t unstable_limit = dist / zt_log2((size_t) dist);
  /* The end of each run, in order; at most two per scan step. */
  T *runs[160];
  int nruns = 0, found = 0;
  T *begin_unstable = last;
  T *current = first;
  T *next = first + 1;
  for (;;) {
    T *begin_range = current;
    /* A tail too short to hold a run is unsorted. */
    if ((last - next) <= unstable_limit) {
      if (begin_unstable == last) begin_unstable = begin_range;
      break;
    }
    current += unstable_limit;
    next += unstable_limit;
    T *current2 = current;
    T *next2 = next;
    if (LT(*next, *current)) {
      /* A descending sequence: find its limits. */
      do {
        --current;
        --next;
        if (LT(*current, *next)) break;
      } while (current != begin_range);
      if (LT(*current, *next)) ++current;
      ++current2;
      ++next2;
      while (next2 != last) {
        if (LT(*current2, *next2)) break;
        ++current2;
        ++next2;
      }
      if ((next2 - current) >= unstable_limit) {
        ZT_SORT_FN(zt_reverse)(current, next2);
        if ((current - begin_range) && begin_unstable == last) begin_unstable = begin_range;
        if (begin_unstable != last) {
          fallback(begin_unstable, current, scratch, ctx);
          runs[nruns++] = current;
          begin_unstable = last;
        }
        runs[nruns++] = next2;
        found++;
      } else if (begin_unstable == last) {
        begin_unstable = begin_range;
      }
    } else {
      /* An ascending sequence. */
      do {
        --current;
        --next;
        if (LT(*next, *current)) break;
      } while (current != begin_range);
      if (LT(*next, *current)) ++current;
      ++current2;
      ++next2;
      while (next2 != last) {
        if (LT(*next2, *current2)) break;
        ++current2;
        ++next2;
      }
      if ((next2 - current) >= unstable_limit) {
        if ((current - begin_range) && begin_unstable == last) begin_unstable = begin_range;
        if (begin_unstable != last) {
          fallback(begin_unstable, current, scratch, ctx);
          runs[nruns++] = current;
          begin_unstable = last;
        }
        runs[nruns++] = next2;
        found++;
      } else if (begin_unstable == last) {
        begin_unstable = begin_range;
      }
    }
    if (next2 == last) break;
    current = current2 + 1;
    next = next2 + 1;
  }
  if (begin_unstable != last) {
    runs[nruns++] = last;
    fallback(begin_unstable, last, scratch, ctx);
  }
  /* Merge runs pairwise until one is left. */
  while (nruns > 1) {
    T *begin = first;
    int w = 0, k = 0;
    while (k + 1 < nruns) {
      ZT_SORT_FN(zt_merge)(begin, runs[k], runs[k + 1], scratch);
      begin = runs[k + 1];
      runs[w++] = runs[k + 1];
      k += 2;
    }
    if (k < nruns) runs[w++] = runs[k];
    nruns = w;
  }
  return found;
}

/* The original's fallback, pdqsort; and Vergesort with it. */
ZT_INLINE void ZT_SORT_FN(zt_pdq_fallback)(T *b, T *e, T *scratch, void *ctx) {
  (void) scratch;
  (void) ctx;
  ZT_SORT_FN(zt_pdqsort)(b, e);
}

ZT_INLINE void ZT_SORT_FN(zt_vergesort_pdq)(T *first, T *last, T *scratch) {
  (void) ZT_SORT_FN(zt_vergesort)(first, last, scratch, ZT_SORT_FN(zt_pdq_fallback), NULL);
}

#undef T
#undef LT
