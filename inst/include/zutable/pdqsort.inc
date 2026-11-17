/*
 * pdqsort, ported to C from Orson Peters' pdqsort.h
 * (https://github.com/orlp/pdqsort, commit b1ef26a55cdb60d236a5cb199c4234c704f46726),
 * specialised to one record type per inclusion (see sortrec.h).
 *
 * Original notice:
 *
 *   pdqsort.h - Pattern-defeating quicksort.
 *
 *   Copyright (c) 2021 Orson Peters
 *
 *   This software is provided 'as-is', without any express or implied
 *   warranty. In no event will the authors be held liable for any damages
 *   arising from the use of this software.
 *
 *   Permission is granted to anyone to use this software for any purpose,
 *   including commercial applications, and to alter it and redistribute it
 *   freely, subject to the following restrictions:
 *
 *   1. The origin of this software must not be misrepresented; you must
 *      not claim that you wrote the original software. If you use this
 *      software in a product, an acknowledgment in the product
 *      documentation would be appreciated but is not required.
 *
 *   2. Altered source versions must be plainly marked as such, and must
 *      not be misrepresented as being the original software.
 *
 *   3. This notice may not be removed or altered from any source
 *      distribution.
 *
 * Altered from the original: C instead of C++ templates; iterators are
 * pointers; the comparison is ZT_SORT_LT on the record type; the
 * branchless partition is used for every record type (the original picks
 * it for arithmetic types under std::less); the heapsort fallback is
 * written out in place of std::make_heap and std::sort_heap.
 */

#define T ZT_SORT_T
#define LT ZT_SORT_LT

ZT_INLINE void ZT_SORT_FN(zt_swap)(T *a, T *b) {
  T t = *a; *a = *b; *b = t;
}

/* Sorts [b, e) by insertion. */
ZT_INLINE void ZT_SORT_FN(zt_insertion)(T *b, T *e) {
  if (b == e) return;
  for (T *cur = b + 1; cur != e; ++cur) {
    T *sift = cur, *sift_1 = cur - 1;
    if (LT(*sift, *sift_1)) {
      T tmp = *sift;
      do { *sift-- = *sift_1; } while (sift != b && LT(tmp, *--sift_1));
      *sift = tmp;
    }
  }
}

/* As above, assuming *(b - 1) is no greater than any element of [b, e). */
ZT_INLINE void ZT_SORT_FN(zt_insertion_unguarded)(T *b, T *e) {
  if (b == e) return;
  for (T *cur = b + 1; cur != e; ++cur) {
    T *sift = cur, *sift_1 = cur - 1;
    if (LT(*sift, *sift_1)) {
      T tmp = *sift;
      do { *sift-- = *sift_1; } while (LT(tmp, *--sift_1));
      *sift = tmp;
    }
  }
}

/* Insertion sort that gives up (returns 0) after
   ZT_PDQ_PARTIAL_LIMIT moves. */
ZT_INLINE int ZT_SORT_FN(zt_insertion_partial)(T *b, T *e) {
  if (b == e) return 1;
  size_t limit = 0;
  for (T *cur = b + 1; cur != e; ++cur) {
    T *sift = cur, *sift_1 = cur - 1;
    if (LT(*sift, *sift_1)) {
      T tmp = *sift;
      do { *sift-- = *sift_1; } while (sift != b && LT(tmp, *--sift_1));
      *sift = tmp;
      limit += (size_t) (cur - sift);
    }
    if (limit > ZT_PDQ_PARTIAL_LIMIT) return 0;
  }
  return 1;
}

ZT_INLINE void ZT_SORT_FN(zt_sort2)(T *a, T *b) {
  if (LT(*b, *a)) ZT_SORT_FN(zt_swap)(a, b);
}

ZT_INLINE void ZT_SORT_FN(zt_sort3)(T *a, T *b, T *c) {
  ZT_SORT_FN(zt_sort2)(a, b);
  ZT_SORT_FN(zt_sort2)(b, c);
  ZT_SORT_FN(zt_sort2)(a, b);
}

/* Heapsort of [b, e): the O(n log n) guarantee after too many bad
   partitions, and the ladder's cache-miss control (4.3). */
ZT_INLINE void ZT_SORT_FN(zt_sift_down)(T *a, size_t root, size_t n) {
  T v = a[root];
  for (;;) {
    size_t child = 2 * root + 1;
    if (child >= n) break;
    if (child + 1 < n && LT(a[child], a[child + 1])) child++;
    if (!LT(v, a[child])) break;
    a[root] = a[child];
    root = child;
  }
  a[root] = v;
}

ZT_INLINE void ZT_SORT_FN(zt_heapsort)(T *b, T *e) {
  size_t n = (size_t) (e - b);
  if (n < 2) return;
  for (size_t i = n / 2; i-- > 0;) ZT_SORT_FN(zt_sift_down)(b, i, n);
  for (size_t m = n - 1; m > 0; m--) {
    ZT_SORT_FN(zt_swap)(b, b + m);
    ZT_SORT_FN(zt_sift_down)(b, 0, m);
  }
}

ZT_INLINE void ZT_SORT_FN(zt_swap_offsets)(T *first, T *last,
                                            const unsigned char *offsets_l,
                                            const unsigned char *offsets_r,
                                            size_t num, int use_swaps) {
  if (use_swaps) {
    /* Needed for the descending distribution, where proper swapping keeps
       pdqsort O(n). */
    for (size_t i = 0; i < num; ++i) {
      ZT_SORT_FN(zt_swap)(first + offsets_l[i], last - offsets_r[i]);
    }
  } else if (num > 0) {
    T *l = first + offsets_l[0];
    T *r = last - offsets_r[0];
    T tmp = *l;
    *l = *r;
    for (size_t i = 1; i < num; ++i) {
      l = first + offsets_l[i]; *r = *l;
      r = last - offsets_r[i]; *l = *r;
    }
    *r = tmp;
  }
}

/* Partitions [b, e) around the pivot *b, equal elements to the right.
   Returns the pivot's final place; *already says whether the input was
   already partitioned. Assumes the pivot is a median of at least 3 and
   e - b >= ZT_PDQ_INSERTION. Branchless (BlockQuicksort, Edelkamp and
   Weiss). */
ZT_INLINE T *ZT_SORT_FN(zt_partition_right)(T *b, T *e, int *already) {
  T pivot = *b;
  T *first = b;
  T *last = e;
  while (LT(*++first, pivot));
  if (first - 1 == b) while (first < last && !LT(*--last, pivot));
  else                while (!LT(*--last, pivot));
  *already = first >= last;
  if (!*already) {
    ZT_SORT_FN(zt_swap)(first, last);
    ++first;
    unsigned char offsets_l[ZT_PDQ_BLOCK];
    unsigned char offsets_r[ZT_PDQ_BLOCK];
    T *offsets_l_base = first;
    T *offsets_r_base = last;
    size_t num_l = 0, num_r = 0, start_l = 0, start_r = 0;
    while (first < last) {
      size_t num_unknown = (size_t) (last - first);
      size_t left_split = num_l == 0 ? (num_r == 0 ? num_unknown / 2 : num_unknown) : 0;
      size_t right_split = num_r == 0 ? (num_unknown - left_split) : 0;
      if (left_split >= ZT_PDQ_BLOCK) {
        for (size_t i = 0; i < ZT_PDQ_BLOCK;) {
          offsets_l[num_l] = (unsigned char) i++; num_l += !LT(*first, pivot); ++first;
          offsets_l[num_l] = (unsigned char) i++; num_l += !LT(*first, pivot); ++first;
          offsets_l[num_l] = (unsigned char) i++; num_l += !LT(*first, pivot); ++first;
          offsets_l[num_l] = (unsigned char) i++; num_l += !LT(*first, pivot); ++first;
          offsets_l[num_l] = (unsigned char) i++; num_l += !LT(*first, pivot); ++first;
          offsets_l[num_l] = (unsigned char) i++; num_l += !LT(*first, pivot); ++first;
          offsets_l[num_l] = (unsigned char) i++; num_l += !LT(*first, pivot); ++first;
          offsets_l[num_l] = (unsigned char) i++; num_l += !LT(*first, pivot); ++first;
        }
      } else {
        for (size_t i = 0; i < left_split;) {
          offsets_l[num_l] = (unsigned char) i++; num_l += !LT(*first, pivot); ++first;
        }
      }
      if (right_split >= ZT_PDQ_BLOCK) {
        for (size_t i = 0; i < ZT_PDQ_BLOCK;) {
          offsets_r[num_r] = (unsigned char) ++i; num_r += LT(*--last, pivot);
          offsets_r[num_r] = (unsigned char) ++i; num_r += LT(*--last, pivot);
          offsets_r[num_r] = (unsigned char) ++i; num_r += LT(*--last, pivot);
          offsets_r[num_r] = (unsigned char) ++i; num_r += LT(*--last, pivot);
          offsets_r[num_r] = (unsigned char) ++i; num_r += LT(*--last, pivot);
          offsets_r[num_r] = (unsigned char) ++i; num_r += LT(*--last, pivot);
          offsets_r[num_r] = (unsigned char) ++i; num_r += LT(*--last, pivot);
          offsets_r[num_r] = (unsigned char) ++i; num_r += LT(*--last, pivot);
        }
      } else {
        for (size_t i = 0; i < right_split;) {
          offsets_r[num_r] = (unsigned char) ++i; num_r += LT(*--last, pivot);
        }
      }
      size_t num = num_l < num_r ? num_l : num_r;
      ZT_SORT_FN(zt_swap_offsets)(offsets_l_base, offsets_r_base,
                                  offsets_l + start_l, offsets_r + start_r,
                                  num, num_l == num_r);
      num_l -= num; num_r -= num;
      start_l += num; start_r += num;
      if (num_l == 0) { start_l = 0; offsets_l_base = first; }
      if (num_r == 0) { start_r = 0; offsets_r_base = last; }
    }
    /* [first, last) is placed; swap the last elements. */
    if (num_l) {
      const unsigned char *ol = offsets_l + start_l;
      while (num_l--) ZT_SORT_FN(zt_swap)(offsets_l_base + ol[num_l], --last);
      first = last;
    }
    if (num_r) {
      const unsigned char *orr = offsets_r + start_r;
      while (num_r--) { ZT_SORT_FN(zt_swap)(offsets_r_base - orr[num_r], first); ++first; }
      last = first;
    }
  }
  T *pivot_pos = first - 1;
  *b = *pivot_pos;
  *pivot_pos = pivot;
  return pivot_pos;
}

/* As above, equal elements to the left; used when many equal. */
ZT_INLINE T *ZT_SORT_FN(zt_partition_left)(T *b, T *e) {
  T pivot = *b;
  T *first = b;
  T *last = e;
  while (LT(pivot, *--last));
  if (last + 1 == e) while (first < last && !LT(pivot, *++first));
  else               while (!LT(pivot, *++first));
  while (first < last) {
    ZT_SORT_FN(zt_swap)(first, last);
    while (LT(pivot, *--last));
    while (!LT(pivot, *++first));
  }
  T *pivot_pos = last;
  *b = *pivot_pos;
  *pivot_pos = pivot;
  return pivot_pos;
}

ZT_INLINE void ZT_SORT_FN(zt_pdq_loop)(T *b, T *e, int bad_allowed, int leftmost) {
  for (;;) {
    ptrdiff_t size = e - b;
    if (size < ZT_PDQ_INSERTION) {
      if (leftmost) ZT_SORT_FN(zt_insertion)(b, e);
      else ZT_SORT_FN(zt_insertion_unguarded)(b, e);
      return;
    }
    /* Median of 3, or pseudomedian of 9 above ZT_PDQ_NINTHER. */
    ptrdiff_t s2 = size / 2;
    if (size > ZT_PDQ_NINTHER) {
      ZT_SORT_FN(zt_sort3)(b, b + s2, e - 1);
      ZT_SORT_FN(zt_sort3)(b + 1, b + (s2 - 1), e - 2);
      ZT_SORT_FN(zt_sort3)(b + 2, b + (s2 + 1), e - 3);
      ZT_SORT_FN(zt_sort3)(b + (s2 - 1), b + s2, b + (s2 + 1));
      ZT_SORT_FN(zt_swap)(b, b + s2);
    } else {
      ZT_SORT_FN(zt_sort3)(b + s2, b, e - 1);
    }
    /* A pivot equal to the element before the range: put equal elements
       left, and the left part needs no sorting. */
    if (!leftmost && !LT(*(b - 1), *b)) {
      b = ZT_SORT_FN(zt_partition_left)(b, e) + 1;
      continue;
    }
    int already;
    T *pivot_pos = ZT_SORT_FN(zt_partition_right)(b, e, &already);
    ptrdiff_t l_size = pivot_pos - b;
    ptrdiff_t r_size = e - (pivot_pos + 1);
    int highly_unbalanced = l_size < size / 8 || r_size < size / 8;
    if (highly_unbalanced) {
      if (--bad_allowed == 0) {
        ZT_SORT_FN(zt_heapsort)(b, e);
        return;
      }
      if (l_size >= ZT_PDQ_INSERTION) {
        ZT_SORT_FN(zt_swap)(b, b + l_size / 4);
        ZT_SORT_FN(zt_swap)(pivot_pos - 1, pivot_pos - l_size / 4);
        if (l_size > ZT_PDQ_NINTHER) {
          ZT_SORT_FN(zt_swap)(b + 1, b + (l_size / 4 + 1));
          ZT_SORT_FN(zt_swap)(b + 2, b + (l_size / 4 + 2));
          ZT_SORT_FN(zt_swap)(pivot_pos - 2, pivot_pos - (l_size / 4 + 1));
          ZT_SORT_FN(zt_swap)(pivot_pos - 3, pivot_pos - (l_size / 4 + 2));
        }
      }
      if (r_size >= ZT_PDQ_INSERTION) {
        ZT_SORT_FN(zt_swap)(pivot_pos + 1, pivot_pos + (1 + r_size / 4));
        ZT_SORT_FN(zt_swap)(e - 1, e - r_size / 4);
        if (r_size > ZT_PDQ_NINTHER) {
          ZT_SORT_FN(zt_swap)(pivot_pos + 2, pivot_pos + (2 + r_size / 4));
          ZT_SORT_FN(zt_swap)(pivot_pos + 3, pivot_pos + (3 + r_size / 4));
          ZT_SORT_FN(zt_swap)(e - 2, e - (1 + r_size / 4));
          ZT_SORT_FN(zt_swap)(e - 3, e - (2 + r_size / 4));
        }
      }
    } else if (already && ZT_SORT_FN(zt_insertion_partial)(b, pivot_pos)
               && ZT_SORT_FN(zt_insertion_partial)(pivot_pos + 1, e)) {
      return;
    }
    /* Recurse left, loop on the right. */
    ZT_SORT_FN(zt_pdq_loop)(b, pivot_pos, bad_allowed, leftmost);
    b = pivot_pos + 1;
    leftmost = 0;
  }
}

/* Sorts [b, e) with pattern-defeating quicksort. */
ZT_INLINE void ZT_SORT_FN(zt_pdqsort)(T *b, T *e) {
  if (b == e) return;
  ZT_SORT_FN(zt_pdq_loop)(b, e, zt_log2((size_t) (e - b)), 1);
}

#undef T
#undef LT
