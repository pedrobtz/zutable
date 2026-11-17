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
