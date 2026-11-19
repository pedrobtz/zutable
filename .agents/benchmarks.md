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
| peak memory, sort: no more than base radix's | 38 MB | 38 MB | yes (corrected 2026-11-19, Stage 16: no, see below) |

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

The Intel Core i5-8500B of the header (corrected 2026-11-18, Stage 14:
this line first said an Apple M-series laptop, which it was not), one
thread, R 4.6.2, an installed build (`R CMD
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

## Kernel: reduce (Stage 14, 2026-11-18)

The Intel Core i5-8500B of the header, one thread, R 4.6.2, an installed
build (`R CMD INSTALL --preclean`); medians of five runs, seconds.
collapse at one thread. 10^7 rows of `runif()`.

### Axis M: long double or double accumulation

`tools/bench/reduce-precision.c`, built twice, `-O2`, `ZT_PRECISION` 1
and 0: `zt_reduce()` alone, no R, uniform group ids. On this x86-64
machine long double is the x87's 80 bits (`sizeof` 16).

| Statistic | Groups | Long double | Double | Ratio |
| --- | ---: | ---: | ---: | ---: |
| sum | 1e3 | 0.025 | 0.011 | 2.3x |
| mean | 1e3 | 0.055 | 0.021 | 2.6x |
| sum | 1e5 | 0.043 | 0.039 | 1.1x |
| mean | 1e5 | 0.097 | 0.082 | 1.2x |
| sum | 1e7 | 0.385 | 0.333 | 1.16x |
| mean | 1e7 | 0.822 | 0.769 | 1.07x |

With few groups the accumulators are in cache and the x87's adds are the
cost; with many, the scattered accesses are, and long double adds 7 to
16%. Decision D49: long double, which is what makes `sum`, `prod` and
`mean` base R's bit for bit; double stays behind `ZT_PRECISION=0`. On
arm64 macOS long double is double, so there the two builds are one.

### `grp_reduce()` against section 9.3

`tools/run-benchmarks` (section `reduce`), the groups made once
beforehand for every oracle (`collapse::GRP()`, `zutable::grp()`, both
sorted).

| Case | zutable | collapse | Base | Target | Held |
| --- | ---: | ---: | ---: | --- | --- |
| sum, 1e3 groups | 0.053 | 0.012 `fsum` | 0.225 `rowsum()` | parity with `fsum()` | no, 0.23x |
| sum, 1e5 groups | 0.063 | 0.023 `fsum` | 1.701 `rowsum()` | parity with `fsum()` | no, 0.37x |
| sum, 1e7 groups | 0.411 | 0.126 `fsum` | 1.981 `rowsum()` | 2x faster than `fsum()` | no, 0.31x |
| four columns, fused | 0.307 | 0.113 four `f*()` | | 1.5x faster than four calls | no, 0.37x |
| `broadcast = "subtract"` | 0.166 | 0.172 `fwithin` | | parity with `fwithin()` | yes, 1.04x |
| sum, any | | | | faster than `rowsum()` | yes, 4x to 27x |

The bracket, 10^6 rows, the kernel executor against the reference
executor's loop over groups (D29), results identical:

| Query | Kernel | Reference | Ratio |
| --- | ---: | ---: | ---: |
| `by = g` (1e3 groups), four aggregates | 0.048 | 0.368 | 8x |
| `by = h` (1e5 groups), two aggregates | 0.054 | 7.083 | 131x |
| `over(mean(px), by = g)` | 0.078 | 0.209 | 3x |

Recorded, not tuned (the maintainer deferred tuning, 2026-11-17). Where
the time goes, from the code and the axis M table rather than a profile:
long double is 2.3x at 10^3 groups, and `fsum()` sums in double;
`src/reduce.c` copies the group ids to 0-based with a range check, a
pass over n integers before the reduction; `mean` sweeps twice for the
correction pass, which `fmean()` does not make; the fused reduction runs
each column's loop with its statistic's branches inside, where collapse
has one tight loop per statistic. One cost was a bug and is fixed in
this stage: stripping attributes copied the 80 MB vector even when it had
none, 0.066 s against 0.053 s at 10^3 groups.


## The complete record (Stage 16, 2026-11-19)

The Intel Core i5-8500B of the header, one thread, R 4.6.2, an installed
build (`R CMD INSTALL --preclean`); `tools/run-benchmarks 1e7`, every
section, with kit 0.0.21 installed again for its two rows. Stage 16 gave
the harness a kernel row for every target of design-kernel 9.3 (sort of
values, character order, collated sort, joins and matches had none), and
changed its memory column from the heap's growth across a call, which a
call's freed scratch never shows, to the peak of R's heap during it
(`gc()`'s "max used" after a reset). That peak counts the kernel's whole
scratch, which is `R_alloc()`, but not the `malloc()` of other packages
or of base R's radix sort, so for them it is a floor. The memory targets
below use process peak RSS where that matters.

### Every row

Run on 2026-11-19: x86_64, macOS Sequoia 15.7.9, R 4.6.2, 1e+07 rows, median of 5. Every row's oracles agreed on a canonical result before it was timed.

| Target (design-kernel 9.3) | Oracle | Input | Seconds | Peak MB | Settings |
| --- | --- | --- | ---: | ---: | --- |
| groups, one integer key, 1e3 distinct | kit: match(x, funique(x)) | int | 0.163 | 76 | one thread |
| groups, one integer key, 1e3 distinct | collapse::GRP | int | 0.086 | 38 | one thread |
| groups, one integer key, 1e3 distinct | vctrs::vec_group_id | int | 0.104 | 204 | one thread |
| groups, one integer key, 1e3 distinct | base: match(x, unique(x)) | int | 0.268 | 243 | one thread |
| groups, one integer key, 1e3 distinct | zutable::grp | int | 0.170 | 229 | one thread |
| groups, one integer key, 1e5 distinct | kit: match(x, funique(x)) | int | 0.303 | 78 | one thread |
| groups, one integer key, 1e5 distinct | collapse::GRP | int | 0.218 | 39 | one thread |
| groups, one integer key, 1e5 distinct | vctrs::vec_group_id | int | 0.269 | 204 | one thread |
| groups, one integer key, 1e5 distinct | base: match(x, unique(x)) | int | 0.658 | 244 | one thread |
| groups, one integer key, 1e5 distinct | zutable::grp | int | 0.353 | 232 | one thread |
| groups, one key, 1e7 distinct | kit: match(x, funique(x)) | int | 1.117 | 188 | one thread |
| groups, one key, 1e7 distinct | collapse::GRP | int | 0.493 | 111 | one thread |
| groups, one key, 1e7 distinct | vctrs::vec_group_id | int | 0.415 | 204 | one thread |
| groups, one key, 1e7 distinct | zutable::grp | int | 1.277 | 390 | one thread |
| groups, two keys | collapse::GRP | int x int | 0.273 | 40 | one thread |
| groups, two keys | vctrs::vec_group_id | int x int | 0.789 | 204 | one thread |
| groups, two keys | zutable::grp | int x int | 0.515 | 270 | one thread |
| groups, sort = TRUE, 1e5 distinct | collapse::GRP(sort = TRUE) | int | 0.362 | 78 | one thread |
| groups, sort = TRUE, 1e5 distinct | zutable::grp(sort = TRUE) | int | 0.574 | 536 | one thread |
| groups, sort = TRUE, 1e5 distinct | axis O: key_order() of every row, then runs | int | 0.722 | 534 | one thread |
| groups, 9.1 market-data input | collapse::GRP | chr x int | 0.275 | 41 | one thread |
| groups, 9.1 market-data input | zutable::grp | chr x int | 0.747 | 310 | one thread |
| groups, 9.1 market-data input | duckdb GROUP BY | chr x int | 0.734 | 1 | threads = 1 |
| order, integer, 1e7 rows | base order(method = 'radix') | int | 0.337 | 38 | one thread |
| order, integer, 1e7 rows | data.table:::forderv | int | 0.910 | 38 | one thread |
| order, integer, 1e7 rows | zutable::key_order | int | 0.237 | 229 | one thread |
| order, double, 1e7 rows | base order(method = 'radix') | dbl | 0.378 | 38 | one thread |
| order, double, 1e7 rows | data.table:::forderv | dbl | 1.285 | 38 | one thread |
| order, double, 1e7 rows | zutable::key_order | dbl | 0.495 | 382 | one thread |
| order, n = 100, repeated 1e5 times | base order() | dbl | 2.359 | 40 | one thread |
| order, n = 100, repeated 1e5 times | zutable::key_order | dbl | 0.722 | 362 | one thread |
| order, sorted input | base order(method = 'radix') | dbl | 0.000 | 0 | one thread |
| order, sorted input | zutable::key_order | dbl | 0.033 | 38 | one thread |
| order, reversed input | base order(method = 'radix') | dbl | 0.379 | 38 | one thread |
| order, reversed input | zutable::key_order | dbl | 0.093 | 38 | one thread |
| sort of values, double, 1e7 rows | base sort(method = 'radix') | dbl | 0.628 | 114 | one thread |
| sort of values, double, 1e7 rows | zutable::key_sort | dbl | 0.661 | 458 | one thread |
| order, character, 1e5 distinct | base order(method = 'radix') | chr | 0.336 | 38 | one thread |
| order, character, 1e5 distinct | data.table:::forderv | chr | 1.127 | 38 | one thread |
| order, character, 1e5 distinct | zutable::key_order | chr | 1.895 | 552 | one thread |
| order, character, all distinct | base order(method = 'radix') | chr | 6.926 | 38 | one thread |
| order, character, all distinct | zutable::key_order | chr | 4.877 | 1414 | one thread |
| sort, character, collate = TRUE (1e6 rows) | stringi::stri_order | chr | 1.100 | 4 | locale en |
| sort, character, collate = TRUE (1e6 rows) | zutable::key_sort(collate = TRUE) | chr | 0.096 | 61 | stringi, locale en |
| sort, character, collate = TRUE (1e6 rows) | base sort() | chr | 4.008 | 4 | session collation |
| join, inner, one key | data.table x[y, on =] | int | 1.603 | 576 | one thread |
| join, inner, one key | base merge() | int | 1.596 | 576 | one thread |
| join, inner, one key | zutable::grp_join | int | 1.012 | 270 | one thread |
| join, inner, two keys | data.table x[y, on =] | int x int | 1.351 | 575 | one thread |
| join, inner, two keys | zutable::grp_join | int x int | 1.059 | 294 | one thread |
| match, one key | base match() | int | 0.493 | 88 | one thread |
| match, one key | collapse::fmatch | int | 0.237 | 38 | one thread |
| match, one key | zutable::grp_match | int | 0.957 | 269 | one thread |
| match, integer64 | bit64::match.integer64 | i64 | 0.352 | 130 | one thread |
| match, integer64 | zutable::grp_match | i64 | 1.024 | 311 | one thread |
| reduce, sum, 1e3 groups | collapse::fsum | dbl | 0.012 | 0 | one thread |
| reduce, sum, 1e3 groups | base rowsum() | dbl | 0.212 | 204 | one thread |
| reduce, sum, 1e3 groups | zutable grp_reduce() | dbl | 0.054 | 38 | one thread |
| reduce, sum, 1e5 groups | collapse::fsum | dbl | 0.023 | 1 | one thread |
| reduce, sum, 1e5 groups | base rowsum() | dbl | 1.692 | 209 | one thread |
| reduce, sum, 1e5 groups | zutable grp_reduce() | dbl | 0.062 | 41 | one thread |
| reduce, sum, 1e7 groups | collapse::fsum | dbl | 0.127 | 48 | one thread |
| reduce, sum, 1e7 groups | base rowsum() | dbl | 2.052 | 485 | one thread |
| reduce, sum, 1e7 groups | zutable grp_reduce() | dbl | 0.405 | 213 | one thread |
| reduce, four columns | four collapse f*() calls | dbl | 0.125 | 3 | one thread |
| reduce, four columns | zutable grp_reduce(), fused | dbl | 0.359 | 51 | one thread |
| reduce, broadcast = 'subtract' | collapse::fwithin | dbl | 0.192 | 77 | one thread |
| reduce, broadcast = 'subtract' | zutable grp_reduce() | dbl | 0.178 | 119 | one thread |

### Against section 9.3

The ratio is the oracle's time over the kernel's, so above 1 the kernel
is faster.

| Target (design-kernel 9.3) | Kernel | Oracle | Ratio | Met |
| --- | ---: | ---: | ---: | --- |
| groups, one integer key, 1e3 distinct: parity with kit | 0.170 | 0.163 | 0.96x | yes |
| groups, one integer key, 1e5 distinct: parity with kit | 0.353 | 0.303 | 0.86x | no |
| groups, one key, 1e7 distinct: 2x faster than kit | 1.277 | 1.117 | 0.87x | no |
| groups, two keys: 1.5x faster than `GRP()` | 0.515 | 0.273 | 0.53x | no |
| groups, `sort = TRUE`, 1e5 distinct: 2x faster than `GRP()` | 0.574 | 0.362 | 0.63x | no |
| groups, any input: 2x faster than `vec_group_id()` | | | 0.32x to 1.53x | no |
| groups, 9.1 input: within 2x of duckdb, one thread | 0.747 | 0.734 | 0.98x | yes |
| groups, 9.1 input: 1.2x faster than `GRP()` | 0.747 | 0.275 | 0.37x | no |
| order, integer, 1e7 rows: 1.5x faster than base radix | 0.237 | 0.337 | 1.42x | no |
| order, double, 1e7 rows: 1.5x faster than base radix | 0.495 | 0.378 | 0.76x | no |
| order, any input: parity with `forderv()`, one thread | | | 3.8x int, 2.6x dbl, 0.59x chr | no |
| order, n = 100, repeated 1e5 times: 2x faster than base | 0.722 | 2.359 | 3.3x | yes |
| order, sorted or reversed: O(n), parity with base radix | 0.033 / 0.093 | 0.000 / 0.379 | 4.1x reversed | yes |
| sort of values, double, 1e7 rows: 2x faster than base radix | 0.661 | 0.628 | 0.95x | no |
| order, character, 1e5 distinct: 3x faster than base radix | 1.895 | 0.336 | 0.18x | no |
| order, character, all distinct: 1.5x faster than base radix | 4.877 | 6.926 | 1.42x | no |
| sort, character, `collate = TRUE`: parity with `stri_order()` | 0.096 | 1.100 | 11.5x | yes |
| sort, character, `collate = TRUE`: 20x faster than base `sort()` | 0.096 | 4.008 | 42x | yes, once strings repeat |
| join, inner, one key: parity with data.table | 1.012 | 1.603 | 1.58x | yes |
| join, inner, two keys: 1.5x faster than data.table | 1.059 | 1.351 | 1.28x | no |
| match, one key: faster than `match()` | 0.957 | 0.493 | 0.52x | no |
| match, one key: parity with `fmatch()` | 0.957 | 0.237 | 0.25x | no |
| match, `integer64`: parity with bit64 | 1.024 | 0.352 | 0.34x | no |
| reduce, sum, 1e3 groups: parity with `fsum()` | 0.054 | 0.012 | 0.22x | no |
| reduce, sum, 1e5 groups: parity with `fsum()` | 0.062 | 0.023 | 0.37x | no |
| reduce, sum, 1e7 groups: 2x faster than `fsum()` | 0.405 | 0.127 | 0.31x | no |
| reduce, four columns fused: 1.5x faster than four calls | 0.359 | 0.125 | 0.35x | no |
| reduce, sum, any input: faster than `rowsum()` | | | 3.9x, 27x, 5.1x | yes |
| reduce, `broadcast = "subtract"`: parity with `fwithin()` | 0.178 | 0.192 | 1.08x | yes |
| peak memory, groups: input + 5 bytes a slot + 12 a row | 229 / 390 MiB | 194 MiB | 1.18x / 2.0x over | no |
| peak memory, joins: input + 5 bytes a slot + 12 a row | 270 MiB | 136 MiB | 2.0x over | no |
| peak memory, sort: no more than base radix's | 193 / 344 MiB | 39 / 229 MiB | 5x / 1.5x over | no |

**Nine of the 32 rows are met.** The kernel is ahead of base R wherever
base has no specialised path (small repeated orders, reversed input,
collation, `rowsum()`, joins through `merge()`), level with an engine on
the market-data shape, and ahead of data.table's one-key join and
`forderv()` on numbers; it is behind collapse and kit nearly everywhere
they compete, by 1.1x to 4.5x. Recorded, not tuned (the maintainer
deferred tuning, 2026-11-17); the known next steps are those each stage's
section above lists. The README makes no speed claim.

Notes on the rows:

- *Collated sort* draws 1e6 two-letter words, about 1,400 distinct, which
  is the case collation once per distinct string is for; with every
  string distinct (Stage 12) the kernel is 1.24x `stri_sort()` and 3.8x
  base `sort()`, so the 20x row holds only once strings repeat.
- *Sorted input*: base answers at once from R's sortedness metadata on a
  `sort()` result; on a plain copy it takes 0.032 s (Stage 11), the
  kernel 0.033.
- *Character, all distinct* is `sprintf("u%09d")`, a shared prefix and
  fixed width; Stage 12's random strings of 4 to 16 letters gave 0.79x.
- *Memory, groups and joins*: the bound is computed for the input at
  hand, 5 bytes for each slot of `zt_table_capacity()` (2^24 slots for
  1e7 rows, 2^21 for the join's 1e6 build rows) and 12 bytes for each
  row, both sides for a join, in MiB. The kernel's figure is the peak of
  R's heap, its result included: `id` and `order` alone are 76 MiB at
  1e7 rows, and the 8-byte hash of every row another 76. The 1e3-distinct
  input is the first figure, the 1e7-distinct the second.
- *Memory, sort* is process peak RSS above the input's (`/usr/bin/time
  -l`, one call in a fresh R), integer then double, because base radix's
  scratch is `malloc()` and `gc()` does not see it; the kernel's 16-byte
  records for doubles (Stage 11) and 8-byte words with a code book for
  integers are what it pays for.
- *Machine*: one x86-64 machine. Design-kernel section 9 asks for the
  maintainer's arm64 machine beside it and five runs on a GitHub Actions
  runner for the SIMD rule (D15, D26); the kernel has no SIMD path in
  0.1.0, and the arm64 numbers are still to be recorded.
