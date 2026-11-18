# zutable: kernel benchmarks

The record design-kernel section 9 asks for: the incumbents' bar before any
kernel code exists (Stage 9), the spike's verdict, and, as the kernel
stages land, the kernel's own rows beside them. A target missed is recorded,
not hidden (section 9.3).

## Machine

Intel Core i5-8500B (x86-64, 6 cores, 3.0 GHz), 8 GB, L2 256 KiB per core,
L3 9 MiB; macOS Sequoia 15.7.9; R 4.6.2; Apple clang 17.0.0. This is the
machine the stages ran on, an x86-64 one; design-kernel section 9 expects
the maintainer's arm64 machine, whose numbers are still to be recorded
beside these (D15 needs both architectures).

## Incumbents (Stage 9, 2026-11-17)

`tools/run-benchmarks 1e7`, with kit 0.0.21, collapse 2.1.8, data.table
1.18.6.1, vctrs 0.7.3, bit64 4.8.6, stringi 1.8.9 and duckdb 2.0.0.
"R heap MB" is the growth of R's heap across a run (rule 2), not the
process's peak; DuckDB's own memory is outside it. The "1e7 distinct" input
draws 1e7 keys with replacement from 1e7 values, so it holds about 6.3e6.

| Target (design-kernel 9.3) | Oracle | Input | Seconds | R heap MB | Settings |
| --- | --- | --- | ---: | ---: | --- |
| groups, one integer key, 1e3 distinct | kit: match(x, funique(x)) | int | 0.159 | 38 | one thread |
| groups, one integer key, 1e3 distinct | collapse::GRP | int | 0.066 | 38 | one thread |
| groups, one integer key, 1e3 distinct | vctrs::vec_group_id | int | 0.096 | 38 | one thread |
| groups, one integer key, 1e3 distinct | base: match(x, unique(x)) | int | 0.278 | 38 | one thread |
| groups, one integer key, 1e5 distinct | kit: match(x, funique(x)) | int | 0.273 | 38 | one thread |
| groups, one integer key, 1e5 distinct | collapse::GRP | int | 0.183 | 39 | one thread |
| groups, one integer key, 1e5 distinct | vctrs::vec_group_id | int | 0.219 | 38 | one thread |
| groups, one integer key, 1e5 distinct | base: match(x, unique(x)) | int | 0.551 | 38 | one thread |
| groups, one key, 1e7 distinct | kit: match(x, funique(x)) | int | 0.999 | 38 | one thread |
| groups, one key, 1e7 distinct | collapse::GRP | int | 0.420 | 72 | one thread |
| groups, one key, 1e7 distinct | vctrs::vec_group_id | int | 0.373 | 38 | one thread |
| groups, two keys | collapse::GRP | int x int | 0.216 | 38 | one thread |
| groups, two keys | vctrs::vec_group_id | int x int | 0.577 | 38 | one thread |
| groups, sort = TRUE, 1e5 distinct | collapse::GRP(sort = TRUE) | int | 0.317 | 40 | one thread |
| groups, 9.1 market-data input | collapse::GRP | chr x int | 0.214 | 38 | one thread |
| groups, 9.1 market-data input | duckdb GROUP BY | chr x int | 0.585 | 1 | threads = 1 |
| order, integer, 1e7 rows | base order(method = 'radix') | int | 0.300 | 38 | one thread |
| order, integer, 1e7 rows | data.table:::forderv | int | 0.888 | 38 | one thread |
| order, double, 1e7 rows | base order(method = 'radix') | dbl | 0.348 | 38 | one thread |
| order, double, 1e7 rows | data.table:::forderv | dbl | 1.170 | 38 | one thread |
| order, n = 100, repeated 1e5 times | base order() | dbl | 2.126 | 39 | one thread |
| order, sorted input | base order(method = 'radix') | dbl | 0.000 | 0 | one thread |
| order, reversed input | base order(method = 'radix') | dbl | 0.361 | 38 | one thread |
| sort of values, double, 1e7 rows | base sort(method = 'radix') | dbl | 0.567 | 76 | one thread |
| order, character, 1e5 distinct | base order(method = 'radix') | chr | 0.289 | 38 | one thread |
| order, character, 1e5 distinct | data.table:::forderv | chr | 0.728 | 38 | one thread |
| order, character, all distinct | base order(method = 'radix') | chr | 5.971 | 38 | one thread |
| sort, character, collate = TRUE (1e6 rows) | stringi::stri_order | chr | 1.040 | 4 | locale en |
| sort, character, collate = TRUE (1e6 rows) | base sort() | chr | 3.492 | 4 | session collation |
| join, inner, one key | data.table x[y, on =] | int | 1.571 | 76 | one thread |
| join, inner, one key | base merge() | int | 1.513 | 76 | one thread |
| join, inner, two keys | data.table x[y, on =] | int x int | 1.287 | 76 | one thread |
| match, one key | base match() | int | 0.388 | 38 | one thread |
| match, one key | collapse::fmatch | int | 0.192 | 38 | one thread |
| match, integer64 | bit64::match.integer64 | i64 | 0.310 | 38 | one thread |
| reduce, sum, 1e3 groups | collapse::fsum | dbl | 0.013 | 0 | one thread |
| reduce, sum, 1e3 groups | base rowsum() | dbl | 0.222 | 0 | one thread |
| reduce, sum, 1e5 groups | collapse::fsum | dbl | 0.024 | 1 | one thread |
| reduce, sum, 1e5 groups | base rowsum() | dbl | 1.769 | 2 | one thread |
| reduce, sum, 1e7 groups | collapse::fsum | dbl | 0.134 | 48 | one thread |
| reduce, sum, 1e7 groups | base rowsum() | dbl | 2.335 | 145 | one thread |
| reduce, four columns | four collapse f*() calls | dbl | 0.112 | 3 | one thread |
| reduce, broadcast = 'subtract' | collapse::fwithin | dbl | 0.182 | 76 | one thread |

## The spike (Stage 9, 2026-11-17)

`tools/spike/spike.c` groups and sums 1e7 rows three ways (median of five,
every method agreeing on the groups and the exact total first);
`tools/spike/collapse.R` times `collapse::fsum(v, g)`, grouping included, on
the same shape of input. The partitioned method follows the cost model's
rule: one pass while the table fits in L3, partitions sized to L2 above it.

| Groups | single | prefetch | partition | partition vs single | collapse `fsum(v, g)` |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 1e+03 | 0.058 | 0.063 | 0.062 | 0.94x | 0.075 |
| 1e+05 | 0.078 | 0.069 | 0.069 | 1.13x | 0.194 |
| 1e+06 | 0.842 | 0.245 | 0.154 | 5.46x | 0.445 |
| 1e+07 | 0.345 | 0.306 | 0.201 | 1.72x | 1.095 |

**Verdict: the cost model holds.** The threshold of design-kernel section 11
was partitioning at least 1.5x faster than the single array at 1e6 and 1e7
groups (5.5x and 1.7x) and within 1.1x of it at 1e3 and 1e5 (1.07x slower
and 1.13x faster). Section 1.3 and axis L stand, and Stage 10 builds on
them. Three notes:

- Partitioning everything above L2, the first run's rule, was 1.7x slower
  than the single table at 1e5 groups, where the table fits in L3: the
  rule "one pass below L3" is part of the model, not a tuning.
- Prefetch alone gave 3.4x at 1e6 groups; the kernel prefetches in every
  probe loop (section 4.1) as well as partitioning.
- At 1e7 groups every key is new, so group ids are assigned in row order
  and the accumulator writes run sequentially; that row flatters the
  single table.

The spike is not the kernel: it carries none of R's costs (result vectors,
`NA` handling), so its gap to collapse is a bound, not a claim.

## Kernel: groups (Stage 10, 2026-11-17)

`ZT_BENCH_SECTIONS=groups tools/run-benchmarks 1e7`, `zutable::grp()`
beside the incumbents; it agreed with every one of them before it was
timed.

Corrected 2026-11-17, Stage 11: the table first recorded here was timed
on a build compiled at `-O0`. `devtools::load_all()` compiles `src/` with
debug flags, and `R CMD INSTALL` then reused those object files, so the
installed `zutable.so` inlined nothing (Stage 11 found it profiling
`key_order()`). These are the same rows from an install with
`--preclean`, as `tools/run-benchmarks` now says to make; the warm
re-measure the first text gave (0.198 s at 1e3 groups) was the optimised
build all along. `grp(sort = TRUE)` here already sorts every row (D44,
Stage 11).

| Target (design-kernel 9.3) | zutable::grp | Best incumbent | Met |
| --- | ---: | ---: | --- |
| groups, one integer key, 1e3 distinct | 0.198 | 0.078 (collapse::GRP) | no |
| groups, one integer key, 1e5 distinct | 0.406 | 0.229 (collapse::GRP) | no |
| groups, one key, 1e7 distinct | 1.160 | 0.429 (vctrs::vec_group_id) | no |
| groups, two keys | 0.575 | 0.238 (collapse::GRP) | no |
| groups, sort = TRUE, 1e5 distinct | 0.551 | 0.354 (collapse::GRP(sort = TRUE)) | no |
| groups, 9.1 market-data input, against collapse | 0.762 | 0.281 (collapse::GRP) | no |
| groups, 9.1 market-data input, within 2x of duckdb | 0.762 | 0.780 (duckdb GROUP BY, one thread) | yes |

**Every groups target against collapse and vctrs is missed so far**, by
1.5x to 2.7x, and the one against duckdb is met; section 9.3 records it
and the release does not wait on it. The kernel is correct first: it
agrees with base R, collapse and itself across both paths. Where the time
goes, at 1e7 rows and 1e3 groups (0.20 s): the grouping loop 0.09 s, a
separate hashing pass 0.04, sizes, starts and order 0.04, the 1-based copy
0.02, preparing the key 0.02. The known next steps, for the tuning stage:
a fused hash-and-insert loop specialised for one fixed-width key (the
generic loop compares keys through a switch on every probe), the 1-based
identifiers written in the order pass, and order computed only when it is
used.

## Kernel: sort (Stage 11, 2026-11-17)

### The ladder and its regime map

`tools/bench/sort-ladder.c` (its header has the build line), every rung
of design-kernel 4.3 over n from 10 to 10^7, six shapes, and two record
types: 8-byte words (a 32-bit key beside the row) and 16-byte records (a
64-bit key and the row). Each cell is the median of five, each rung's
output compared with pdqsort's before it is kept; all 768 timings, 84 cells, agreed.
The rung that wins each cell, in ns a record where it helps:

| 8-byte words | 10 | 100 | 1e3 | 1e4 | 1e5 | 1e6 | 1e7 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| uniform | insertion | ska | vergesort+pdq | lsd8 | msd+lsd | msd+lsd | msd+lsd |
| few (16 values) | insertion | counting | counting | counting | counting | counting | counting |
| zipf | insertion | counting | counting | counting | counting | lsd11 | msd+lsd |
| sorted | ska | insertion | vergesort+pdq | vergesort+pdq | vergesort+pdq | vergesort+pdq | vergesort+pdq |
| reversed | insertion | counting | vergesort+pdq | vergesort+pdq | vergesort+pdq | vergesort+pdq | vergesort+pdq |
| sorted + 1% | insertion | insertion | insertion | counting | counting | counting | vergesort+pdq |

| 16-byte records | 10 | 100 | 1e3 | 1e4 | 1e5 | 1e6 | 1e7 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| uniform | vergesort+pdq | ska | ska | lsd11 | ska | msd+lsd | msd+lsd |
| few (16 values) | ska | counting | counting | lsd11 | counting | lsd11 | lsd11 |
| zipf | pdqsort | counting | counting | counting | counting | lsd11 | msd+lsd |
| sorted | insertion | insertion | vergesort+pdq | vergesort+pdq | vergesort+pdq | vergesort+pdq | vergesort+pdq |
| reversed | vergesort+pdq | ska | vergesort+pdq | vergesort+pdq | vergesort+pdq | vergesort+pdq | vergesort+pdq |
| sorted + 1% | ska | insertion | vergesort+pdq | vergesort+pdq | vergesort+pdq | vergesort+pdq | vergesort+pdq |

The crossovers D40 reads off it: insertion sort wins below a few dozen
records and loses by 100 (13.1 ns a word against pdqsort's 6.7), so the
leaf is 24; counting sort wins wherever the codes span fewer values than
the rows; LSD radix takes over from pdqsort between 10^3 and 10^4
records; one MSD pass in front of LSD wins on uniform 8-byte words from
10^5 and on uniform keys of both widths from 10^6, where it is kept;
Vergesort's run detection wins every sorted and reversed input from 10^3
on, and nearly sorted 16-byte records.

The hybrid against the best rung of each cell, over all 84 cells: median
1.05x the best, 80% of cells within 1.25x, 90% within 1.48x, the worst
2.07x. The worst cells are Zipf keys at 10^4 and 10^5 (2.07x and 1.49x
on 8-byte words, 1.52x and 1.58x on 16-byte records): their codes span
about n values, past the 4096 that D40 caps counting sort at, and the
ladder's uncapped counting rung wins there. D40's reason for the cap,
that radix wins past 2^12 values at every n, holds for the uniform
shapes it was read from but not for Zipf; the cap is kept until the
tuning stage measures a cap that grows with n. From 10^6 records the
hybrid is within 1.65x of the best everywhere and often ahead of every
rung alone (0.66x of the best on 8-byte sorted input at 10^7, from
Vergesort's run test before any pass). The cache-miss control: at 10^7
uniform records LSD radix runs at 10.3 ns a word and 27.1 a 16-byte
record, heapsort at 229 and 618, so the radix is 22x ahead and not
wrong. Fluxsort, crumsort and swenson's sorts are not vendored (D41):
the hybrid's numbers need no comparison sort to explain them.

### Order from R

`ZT_BENCH_SECTIONS=order tools/run-benchmarks 1e7`; `key_order()`
agreed with every oracle before it was timed.

| Target (design-kernel 9.3) | zutable::key_order | Incumbent | Met |
| --- | ---: | ---: | --- |
| order, integer, 1e7 rows: 1.5x faster than base radix | 0.251 | 0.339 (base radix) | no, 1.35x |
| order, double, 1e7 rows: 1.5x faster than base radix | 0.503 | 0.396 (base radix) | no, 0.79x |
| order, any input: parity with data.table, one thread | 0.251 / 0.503 | 0.994 / 1.309 (forderv) | yes, 4.0x and 2.6x |
| order, n = 100, repeated 1e5 times: 2x faster than base | 0.718 | 2.366 (base order) | yes, 3.3x |
| order, sorted input: O(n), parity with base radix | 0.034 | 0.000 (base radix) | no, see below |
| order, reversed input: O(n), parity with base radix | 0.092 | 0.404 (base radix) | yes, 4.4x |
| peak memory, sort: no more than base radix's | 38 MB | 38 MB | yes |

Base radix answers sorted input in no time because the input came from
`sort()`, whose result carries R's sortedness metadata; on a plain copy
of the same values it takes 0.032 s, the kernel 0.034. The metadata path
is `key_sort()`'s ALTREP class, Stage 12. Doubles are the gap: a double
key is 64 bits (57 after range compression for `runif()`), so it takes
16-byte records. Timed standalone at 10^7 on the same build flags, the
sort is 0.35 s, the code book and the encoding 0.07, and the first touch
of the 360 MB of scratch 0.16, which R's 0.50 s overlaps. The known next
steps, for the tuning stage: a 12-byte record (the key and a 32-bit row)
for 64-bit keys, and the radix's first histogram counted in the encoding
pass.

### Axis O: sorting every row against hashing

`grp(sort = TRUE)` by hashing to first-appearance groups and sorting
the distinct keys, against sorting every row and cutting the runs
(`zutable/sort.h`, `zt_groups_by_sort`), one integer key, both from R,
seconds a call (median of five; repeated below 10^6 rows):

| Rows | 0.1% distinct | 0.3% | 1% | 3% | 10% | 100% |
| ---: | --- | --- | --- | --- | --- | --- |
| 1e3 | sort 4.0x | sort 6.5x | sort 8.5x | sort 9.0x | sort 10x | sort 8.3x |
| 1e4 | sort 2.1x | sort 2.2x | sort 2.3x | sort 2.2x | sort 2.3x | sort 2.7x |
| 1e5 | sort 1.07x | sort 1.12x | sort 1.14x | sort 1.17x | sort 1.35x | sort 2.0x |
| 1e6 | hash 1.37x | hash 1.06x | sort 1.15x | sort 1.50x | sort 1.58x | sort 1.63x |
| 1e7 | hash 1.33x | hash 1.25x | sort 1.04x | sort 1.80x | sort 2.32x | sort 2.85x |

With 2 to 1000 distinct keys sorting still wins at 10^5 and 3 x 10^5
rows (1.05x to 1.16x); at 10^6 it is even (0.83x to 1.04x) and at
3 x 10^6 it loses (0.50x to 0.84x). So `grp(sort = TRUE)` sorts every row below 10^6 rows,
and from there when Chao1 over 1024 sampled rows estimates distinct keys
at 1% of the rows or more (D44). The R-level row of the harness
("key_order() of every row, then runs", 0.711 s) cuts the runs in R and
is kept as the route's first measurement; the C route is the
`zutable::grp(sort = TRUE)` row, 0.551 s, against collapse's 0.354.

## Kernel: strings (Stage 12, 2026-11-18)

### Axis N: sorting distinct strings

Three ways to sort distinct byte strings (`tools/bench/str-sort.c`, no R,
`-O2`), nanoseconds a string (median of five), each order checked against
full comparison's before it is timed. *compare* is merge sort with
`memcmp()` on each pair, what base radix does on the distinct set;
*prefix* is the first eight bytes as an integer through the hybrid, then
multikey quicksort on each run of equal prefixes; *msd* is MSD radix over
the bytes, insertion sort below 32. Shapes: *random*, 6 to 24 random
letters; *url*, a 25-byte shared prefix, two letters and a number;
*code*, two letters and seven digits; *words*, 3 to 10 letters from nine,
then a number.

| Shape | n | compare | prefix | msd |
| --- | ---: | ---: | ---: | ---: |
| random | 1e3 | 82 | **25** | 45 |
| random | 1e4 | 139 | **25** | 46 |
| random | 1e5 | 285 | **29** | 49 |
| random | 1e6 | 776 | **44** | 418 |
| url | 1e3 | 186 | **104** | 167 |
| url | 1e4 | 237 | **139** | 167 |
| url | 1e5 | 445 | **190** | 218 |
| url | 1e6 | 1054 | **479** | 3642 |
| code | 1e3 | 87 | **21** | 47 |
| code | 1e4 | 136 | **24** | 46 |
| code | 1e5 | 283 | **30** | 64 |
| code | 1e6 | 678 | **40** | 345 |
| words | 1e3 | 103 | **29** | 52 |
| words | 1e4 | 149 | **29** | 57 |
| words | 1e5 | 297 | **34** | 65 |
| words | 1e6 | 763 | **45** | 470 |

The prefix wins every cell: 2.2x to 18x over full comparison and 1.1x to
9.5x over MSD radix. Its weakest shape is the URL, where the shared
prefix leaves every string to multikey quicksort; there MSD radix comes
within 1.15x at 10^5 and then falls apart at 10^6, when its 257-bucket
passes leave cache. So `zutable/strsort.h` keeps the prefix alone (D45),
and the two controls stay in the bench file only (D14).

### Order and collated sort from R

`tools/bench/str-order.R`, seconds a call, median of three; strings of 4
to 16 random characters (`stringi::stri_rand_strings()`):

| Input | Rows | Distinct | `key_order()` | base radix | `forderv()` | vs base |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| character | 1e7 | 1e5 | 1.192 | 0.181 | 0.710 | 0.15x |
| character | 1e6 | 1e6 | 0.411 | 0.474 | 0.631 | 1.15x |
| character | 1e7 | 1e7 | 8.297 | 6.592 | 9.168 | 0.79x |

| Collated sort | Strings | Distinct | `key_sort()` | `stri_sort()` | `sort()` | vs stringi | vs base |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| words | 1e5 | 1e4 | 0.015 | 0.114 | 0.294 | 7.6x | 19.6x |
| words | 1e6 | 1e5 | 0.184 | 1.377 | 4.419 | 7.5x | 24.0x |
| words | 1e6 | 1e6 | 1.609 | 1.996 | 6.179 | 1.24x | 3.8x |

Against section 9.3: collated sort beats parity with `stri_order()` in
every row, by paying for collation once per distinct string; it is 20x
faster than base `sort()` once strings repeat, and 3.8x when every string
is distinct, a miss. The byte order misses both of its targets (3x base
radix at 10^5 distinct, 1.5x at all distinct): base radix orders strings
by their `CHARSXP`s' truelength scratch, one pass over the rows and a
sort of the distinct set, where `key_order()` hashes the rows into groups
and then sorts every row again by its integer code. A profile of the 10^7
x 10^5 call (0.93 s that run): grouping 0.57 s, the integer order 0.20,
`enc2utf8()` 0.05, the gather of ranks 0.03, ranking the 10^5 distinct
strings 0.008. Recorded, not tuned (section 9.3; the maintainer deferred
tuning, 2026-11-17). The known next steps: a grouping pass that returns
only identifiers and first rows (`zt_grp` also builds sizes, starts and
the group order, which the string path discards), and for a single string
key one counting pass over the groups in rank order instead of a second
sort of every row.

## Kernel: joins and string keys (Stage 13, 2026-11-18)

Apple M-series laptop, one thread, R 4.6.2, an installed build (`R CMD
INSTALL --preclean`); medians of five runs, seconds. data.table and
collapse at one thread.

### Axis F: string keys as pointers, or encoded first

`tools/bench/str-keys.R`. Strings `key-<9 digits>-suffix`. "Pointer" is
the kernel as shipped, hashing each row's interned `CHARSXP`; "encode" is
the one pass that turns the column into integer codes (`grp()$id`, over
both sides for a match); "integer" is the same operation on the codes.
The last column is how many uses repay the encoding.

| Op | Rows | Distinct | Pointer | Encode | Integer | Reuses to repay |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `grp()` | 1e6 | 1e2 | 0.033 | 0.033 | 0.016 | 1.9 |
| `grp_match()` | 1e6 | 1e2 | 0.044 | 0.045 | 0.021 | 2.0 |
| `grp()` | 1e6 | 1e4 | 0.039 | 0.039 | 0.021 | 2.2 |
| `grp_match()` | 1e6 | 1e4 | 0.039 | 0.047 | 0.020 | 2.5 |
| `grp()` | 1e6 | 1e6 | 0.136 | 0.136 | 0.044 | 1.5 |
| `grp_match()` | 1e6 | 1e6 | 0.234 | 0.407 | 0.089 | 2.8 |
| `grp()` | 1e7 | 1e2 | 0.306 | 0.306 | 0.173 | 2.3 |
| `grp_match()` | 1e7 | 1e2 | 0.390 | 0.395 | 0.217 | 2.3 |
| `grp()` | 1e7 | 1e4 | 0.425 | 0.425 | 0.249 | 2.4 |
| `grp_match()` | 1e7 | 1e4 | 0.413 | 0.498 | 0.210 | 2.5 |
| `grp()` | 1e7 | 1e6 | 1.643 | 1.643 | 0.891 | 2.2 |
| `grp_match()` | 1e7 | 1e6 | 1.653 | 2.188 | 0.813 | 2.6 |

Encoding first can only cost more for one use, since it is itself a
pointer pass; it repays itself from the second or third reuse. Decision
D47: the kernel hashes pointers, and a caller that reuses a column keeps
`grp()$id`. The integer pass running at about half the pointer pass's
time is partly the pointer path's own cost: `zt_str_ptrs()` reads every
`CHARSXP`'s encoding flags to decide whether to translate, a pass over
the strings the integer path does not make.

### Joins and matches against section 9.3

`tools/bench/join.R`. Integer keys; `x` has n rows, `y` the distinct keys
once each, shuffled. data.table is `X[Y, on =, which = TRUE, nomatch =
NULL]`, the index pairs of an inner join; two keys split each key into
`k %% 97` and `k %/% 97`. The ratio is the other's time over zutable's.

| Case | Rows | Distinct | zutable | Other | Other's | Ratio |
| --- | ---: | ---: | ---: | --- | ---: | ---: |
| inner, one key | 1e6 | 1e3 | 0.020 | data.table | 0.015 | 0.75x |
| inner, two keys | 1e6 | 1e3 | 0.027 | data.table | 0.018 | 0.67x |
| match, one key | 1e6 | 1e3 | 0.018 | `match()` | 0.005 | 0.28x |
| match, one key | 1e6 | 1e3 | 0.018 | `fmatch()` | 0.001 | 0.06x |
| match, `integer64` | 1e6 | 1e3 | 0.019 | bit64 | 0.013 | 0.68x |
| inner, one key | 1e6 | 1e5 | 0.031 | data.table | 0.054 | 1.74x |
| inner, two keys | 1e6 | 1e5 | 0.040 | data.table | 0.055 | 1.38x |
| match, one key | 1e6 | 1e5 | 0.030 | `match()` | 0.136 | 4.53x |
| match, one key | 1e6 | 1e5 | 0.030 | `fmatch()` | 0.046 | 1.53x |
| match, `integer64` | 1e6 | 1e5 | 0.031 | bit64 | 0.006 | 0.19x |
| inner, one key | 1e7 | 1e3 | 0.230 | data.table | 0.155 | 0.67x |
| inner, two keys | 1e7 | 1e3 | 0.266 | data.table | 0.176 | 0.66x |
| match, one key | 1e7 | 1e3 | 0.189 | `match()` | 0.047 | 0.25x |
| match, one key | 1e7 | 1e3 | 0.189 | `fmatch()` | 0.013 | 0.07x |
| match, `integer64` | 1e7 | 1e3 | 0.197 | bit64 | 0.129 | 0.65x |
| inner, one key | 1e7 | 1e6 | 0.796 | data.table | 0.830 | 1.04x |
| inner, two keys | 1e7 | 1e6 | 1.071 | data.table | 0.561 | 0.52x |
| match, one key | 1e7 | 1e6 | 0.768 | `match()` | 0.272 | 0.35x |
| match, one key | 1e7 | 1e6 | 0.768 | `fmatch()` | 0.133 | 0.17x |
| match, `integer64` | 1e7 | 1e6 | 0.822 | bit64 | 0.384 | 0.47x |

`join()` itself, 10^6 rows of `x` against 10^5 keys: 0.089 s on the
kernel against 2.400 s on the reference executor, and `merge()` 3.366 s.

Against section 9.3: parity with data.table's one-key join holds at 10^5
and 10^6 distinct keys and misses at 10^3 (0.67x to 0.75x); "1.5x faster
than data.table" on two keys misses everywhere but 10^6 x 10^5 (1.38x);
"faster than `match()`" holds only at 10^5 distinct (4.5x); parity with
`fmatch()` and with bit64 misses in all but one row. Recorded, not tuned
(the maintainer deferred tuning, 2026-11-17). Where the time goes, from
the code rather than a profile: `grp_match()` runs the whole join and
keeps one of its two pair vectors; every join buckets `y` by class and
fills both vectors with a count pass first; the probe hashes all of `x`
into an array before probing rather than as it goes; the table is sized
for every build row, so 10^6 distinct keys make a 10 MB table probed at
random; and the R side converts and checks each key column. `match()`
and `fmatch()` hash `y` and write one vector in one pass. The next steps
are a match path that writes `y` indices straight from the probe, and
partitioning the build side above L2 as `grp()` does.
