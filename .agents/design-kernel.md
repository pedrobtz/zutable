# RFC 0037: `zutable`'s kernel: group, sort, join, reduce

Adopted from [RFC 0037](https://github.com/pedrobtz/packages/blob/1ee6f757336a130e028bb8ea2c621dcac514682e/rfcs/not-started/0037-zutable-grouped-kernel.md)
on 2026-11-16. This file is the single source of truth for the kernel's
design; the RFC is now a pointer here. The package's design is
[design.md](design.md).

- **Status:** Proposed. The kernel companion to
  [RFC 0074](design.md), which is the
  design of `zutable`. This file is the design of the kernel beneath
  that RFC's local executor and is adopted beside it, as the package's
  `.agents/design-kernel.md`; each decision in section 13 stays the
  maintainer's until the package repository records it. Sections 1.3
  and 10 are experiments with stated hypotheses; the roadmap records
  the results either way.
- **Revised on 2026-11-16** for RFC 0074, which superseded RFC 0036.
  The kernel is part of 0.1.0 for now and no longer a second release;
  §4.2 adopts the best-known algorithm on eleven axes and measures
  four; the stage roadmap of §11 became an order of work; Q2 and Q9 are
  answered.
- **Date:** 2026-10-17. Revised 2026-10-20 to widen the scope from three
  index operations to the grouped-vector algebra that `collapse` covers,
  to reverse the decision against sorting, and to state where and why a
  speed margin over the incumbents is expected. Renamed from `zumap` to
  `zugrp` on 2026-10-21 (D33) and, the same day, folded into `zutable` as
  that package's second release (D34): one package, not two.
- **Packages:** `zutable` (RFC 0074; not yet created). The kernel
  gives the package `LinkingTo: zufast (>= 0.1.0)`
  for hashing; `Suggests: stringi, bit64, collapse, kit, vctrs,
  data.table, duckdb` (`stringi` for collated string order, §6.3; the rest
  for benchmarks only); header-only C under `inst/include/`; the kernel's
  C in the one shared object; vendored sort pieces (§4.3). Still no
  `Imports`. MIT.
- **Source:** the conversation of 2026-10-17 that placed the kernel
  beneath the table of RFC 0036; the conversation of 2026-10-20 that set
  the scope to `collapse`'s algebra, named the fastest sort in R as a
  goal, and worked out the cost model of §1.3; the maintainer's decision
  of 2026-10-21 that two packages were not worth it; this repository's
  `rfcs/base-layer-candidates.md` §3.4 and §6.2; `zu-family-alignment.md`
  R1 to R10; `pedrobtz/zufast`'s `inst/include/zufast/hash.h` as of
  2026-10-17; `pedrobtz/zubin` as the model for a header-only provider
  with an R API; `collapse` 2.1.7, `data.table` 1.17.8, `duckdb` 1.5.5 and
  `stringi` 1.8.9 as installed on 2026-10-20, whose signatures and defaults
  §1.2 describes; DuckDB's sort design as the model for §4.3's target
  shape (the 2021 post "Fastest table sort in the West", Kuiper and
  Mühleisen's ICDE 2023 paper on sorting in DuckDB, and the 2025 post on
  the v1.4 redesign, the last known to this RFC only through the
  maintainer's summary and to be read first, §11). Nothing has been
  built.

## 1. What the kernel is

The kernel is `zutable`'s layer of grouped, keyed and ordered operations
over R vectors: group identifiers, sort permutations, join indices, and
typed per-group reductions, over integer, `integer64`, double, logical,
character and raw keys, singly or several at once as a composite key.
Every operation is C, vectorised, exported as plain R functions beside the
table (§5), and reachable from other packages' C code through a header
that `LinkingTo` installs. It is what the local executor of RFC 0074
§11 calls to group, order, join and reduce, and it ships with the
table, in 0.1.0 for now. Its scope is the vector algebra underneath
`collapse`, and `collapse` is the measured bar.

The one-line statement that governs every decision below:

> **Every "which rows share this key, in what order, and what do they
> add up to" question in R, answered once in C, vectorised, linkable,
> and as fast as one thread allows.**

### 1.1 What the kernel is not

- **Not a data frame, and not data-frame verbs.** It returns indices,
  identifiers, permutations and per-group vectors. `collapse`'s
  `fselect()`, `fsubset()`, `fmutate()`, `collap()` and its summary
  functions are frame operations and belong to the table layer (RFC 0074)
  and to other consumers.
- **Not a query engine.** No planner, no lazy evaluation, no
  expressions. Those are RFC 0074's plan and translator, which sit
  above the kernel and reach it through the functions of §5.
- **Not a collation library.** Strings sort by bytes unless the caller
  supplies collation sort keys; the kernel never implements a locale
  (§6.3).
- **Not a set of pretty verbs.** Four families of functions and an info
  function. A `fsum()`-style function per statistic is an open question
  (§15 Q7), not the design.

### 1.2 Where it sits among existing packages

Base R answers single-key questions: `match()`, `duplicated()`,
`unique()`, `split()`, `order()`, `rowsum()` and `tapply()` take one key
vector. Several keys need `paste()` or `interaction()`, which allocate
strings for every row, or `merge()`, which is slow. `order(method =
"radix")` is data.table's 2016 `forder()`, donated in R 3.3,
single-threaded, and it refuses locale order for strings; `sort()` on
character therefore falls back to a shell sort with one `strcoll()` per
comparison. `utils::hashtab()` is a dictionary keyed by `identical()` on
whole objects, one call per key.

`collapse` (Sebastian Krantz) is the incumbent whose scope this RFC
adopts and whose speed it measures against. As of 2.1.7: `GRP()` defaults
to `sort = TRUE`, which radix-orders every row through the 2016 `forder`
and then detects runs; `sort = FALSE` hashes through a `kit`-derived table
sized about twice the row count, one column at a time, combining the
previous identifier with the next column in a further pass; the fast
statistical functions, `fsum()`, `fmean()` and the rest, take a group
vector or `GRP` object and scatter into one accumulator array per call,
with `TRA` to broadcast the result back to rows and `nthreads` for OpenMP
on several of them. `collapse` imports `Rcpp` and keeps its C private.

`data.table` has the current `forder()`, a parallel radix sort, and
GForce, which rewrites `sum(v)` inside `j` to a grouped C kernel. `vctrs`
has `vec_group_id()` and `vec_match()` over data frames, with the
tidyverse's dependencies. `kit` is the fastest single-key hash grouping on
CRAN and has no imports. `bit64` chooses between hashing and sorting by
the number of distinct keys, the one heuristic in this space worth
copying. `stringi` sorts strings in locale order through ICU and is the
only fast collated sort in R. `duckdb` and `polars` are the engines: they
have the partitioned, vectorised designs of §1.3 and threads, and they
pay a planner and a copy of every R vector across their boundary.

The kernel's claim is therefore not "first" but "the kernel as a
library": no `Imports`, the C behind a `LinkingTo` header so that
`zucsv`, `zuxlsx`, `zudedup` and `zulm`, as well as the table's own
bracket, group, sort, join and reduce without an R round trip, and a
measured speed margin in the regimes of §1.3 that makes the header worth
linking to.

### 1.3 Where the margin is expected, and why

The maintainer's question on 2026-10-20 was whether any algorithm or
technique not yet used in R can beat `collapse`, taking `collapse` as
the fastest in this area and `data.table` and `duckdb` as competitive.
The answer this RFC commits to measuring: in the regime `collapse` is
usually benchmarked on, a few thousand groups and data that fits in
cache, no. Its loops are tight C within about 1.5× of memory bandwidth,
and SIMD does not help a scatter-add. Above cache size the cost is no
longer instructions but DRAM latency, and there a different structure
wins. Five mechanisms, each standard in database engines and in no R
vector package:

1. **Streaming passes instead of one random access per row.** One hash
   table or one accumulator array indexed by group misses cache on every
   row once it exceeds L2. Radix-partitioning rows by the top hash bits
   first turns that into sequential passes plus per-partition work that
   stays in cache.
2. **Composite keys hashed once, not once per column.** Hashing every
   column into one 64-bit word per row is k sequential passes and one
   table build; a one-byte tag per slot means the column-by-column
   comparison runs only on a tag hit; narrow integers bit-packed into one
   word need no hash at all.
3. **Sorting the groups, not the rows.** When groups are far fewer than
   rows, hashing to first-appearance identifiers, sorting only the
   distinct keys and relabelling gives the same sorted identifiers as a
   radix sort of every row for a fraction of the work. This is
   `GRP()`'s default path.
4. **Fusion.** Group identifiers and several accumulators in one pass
   over the data, instead of one grouping pass and one pass per
   statistic. `zutable`'s `by` with several aggregates is exactly this
   caller.
5. **Latency hiding where partitioning cannot apply.** A probe against a
   table that already exists is a random access per row by nature;
   prefetching several rows ahead keeps several misses in flight.

The cost model for the regime where mechanism 1 applies:

| 10⁷ rows, 10⁶ groups | Model |
| --- | --- |
| one DRAM miss per row | 10⁷ × about 80 ns, about 0.8 s before overlap |
| two streaming passes | 10⁷ × 12 bytes twice at 10 GB/s, about 25 ms |

Out-of-order cores overlap several misses, so the realised gap is
smaller than the model; the literature in §4.2 puts it at 2× to 4×.

Two further levers are R-specific and no engine can copy them: strings
are interned, so a `CHARSXP` pointer is the key and bytes are never
read; and ALTREP lets a result carry "sorted, no `NA`" so later base
calls skip whole passes. Those, plus zero transfer cost, are how a kernel
inside R beats `duckdb` below about 10⁷ rows, where its planning and the
copy of R vectors dominate.

What this does not claim: a margin over `collapse` on cache-resident
reductions, where the honest target is parity; or a margin over
`data.table` or `duckdb` with all their threads on 10⁸ rows, which no
single-threaded kernel has. §9 states the targets by regime, and all of
the above is a cost model until the spike measures it (§11).

None of this is a moat. `collapse` could adopt partitioning. The lasting
difference is the linkable header and the absence of imports; the speed
margin is what makes the header worth linking to.

| Feature | Has it today | the kernel |
| --- | --- | --- |
| Group ids on several keys, in C | vctrs, collapse, kit, data.table | yes |
| Partitioned grouping and aggregation | duckdb, polars | yes |
| Sorted groups without sorting rows | none in R | yes |
| Fused group and several aggregates | data.table GForce, partly | yes |
| Fastest single-threaded sort | data.table at one thread | goal, §9 |
| Collated string order, fast | stringi | via stringi keys |
| Join as index pairs, not a table | none in R | yes |
| Fan-out as an error | none in R | `multiple = "error"` |
| Linkable C header | none | `LinkingTo` |
| No `Imports` | kit, bit64 | yes |
| `NA` equals `NA` in keys | data.table, collapse | yes |
| Mixed-encoding strings compared right | vctrs, base | yes (§6.1) |
| 64-bit integer keys | bit64 | `integer64` now, `zuint` later |
| Records, lists, arbitrary classes | vctrs | no, by decision |

## 2. Scope

**In the kernel's first release**, which is `zutable` 0.1.0 for now:

- **Groups.** `grp(...)`: first-appearance or sorted group
  identifiers for one or several key vectors, with group count, sizes,
  starts, the distinct keys, and the row order that puts each group
  together (§6.2).
- **Sort.** `key_order()`, `key_sort()` and `key_rank()`: a stable
  permutation, the sorted values, or ranks, over one or several keys of
  any kind, with per-key direction, `na.last`, and byte or collated
  string order (§6.3).
- **Joins.** `grp_join(x, y, type, multiple)`: the index pairs of an
  inner, left, semi or anti join on one or several key columns, where
  `multiple` says what a one-to-many match does (§6.4). `grp_match(x, y)`
  is the single-index special case that generalises `match()`.
- **Reduce.** `grp_reduce(x, by, fn, ...)`: the one-pass statistics,
  sum, prod, mean, min, max, count, first, last and nobs, per group over
  one or several value columns in one fused pass, with `na.rm` and a
  broadcast mode that writes each group's value back to its rows,
  replacing, subtracting or dividing (§6.5).
- **The header.** `inst/include/zutable.h` with the key model, the table,
  the partitioner and the four algorithm families as `static inline` C,
  usable without R (§4), plus a consumer fixture that proves it (§8).
- `zutable_info()`; a README; one article on joins without surprises; one
  article on the measurements of §9.

**Not in the first release, and why:**

- **The dictionary** (`dict_new()`, `dict_set()`, `dict_get()` and the rest
  of the 2026-10-17 design). Its consumers are `zucsv` and `zuxlsx`
  shared-string tables, neither of which has asked yet, and the widened
  scope needs the time. The design is kept in §14 unchanged and
  returns when a consumer needs it (D17).
- **Order-dependent reductions: median, nth, mode, ndistinct, var, sd.**
  Each needs per-group work on the order permutation or a per-group
  table rather than one scatter pass, and each is a stage of its own.
  §14, first in line.
- **Scans: cumsum, lag, lead, diff, growth, fill forward, rank within
  group, row number within group,** with or without a time index. §14,
  second in line.
- **Weights** on reductions. §14.
- **Pivot** longer and wider as index computations. §14.
- **Compressed bitsets, heaps, top-k.** No consumer today; each is a
  vendoring or a design of its own. §14.
- **64-bit and 128-bit keys through `zuint`.** `zuint` is not released
  and would make a dependency cycle if `zuint` later links to `zutable`.
  `bit64::integer64` is its own kind, recognised by class (§6.1), so
  64-bit keys work today without `zuint`.
- **Long vectors.** Indices are R integers; inputs above 2³¹ − 1 rows
  error with `zutable_length_error`.
- **Threads.** Single-threaded. The partitioned layout of §4.1 is
  thread-ready by construction; a pool is a family decision (§15 Q8).
- **Collation implemented in C.** It needs ICU, a system dependency the
  family rules out; `stringi` already bundles it (§6.3).
- **A sort-merge join for pre-ordered keys.** Only after the hash join
  is measured and found wanting on some real input.

## 3. Position in the `zu*` family

The kernel adds no package to the family. RFC 0074 §3 holds
`zutable`'s row; these are the cells the kernel is responsible for:

| | zutable |
| --- | --- |
| Role | R API; provider, header |
| R prefix | none for the table surface; `grp_` and `key_` for the kernel (D5) |
| Info function | `zutable_info()` |
| Root condition class | `zutable_error`, unchanged |
| Public C prefix | `zt_` |
| From C | `LinkingTo` |
| Vendored code | sort controls and ported sort pieces, §4.3 |

`zubin` is the precedent for a package that is both an R API and a
header provider.

**Relationships:**

- **The table layer** (RFC 0074): the same package. Its local executor
  calls `grp()` and `grp_reduce()` for `by`, `grp_join()` for `join()`
  and `key_order()` for `order`. Every `select` is translated into
  typed expressions, so an aggregate always reaches `grp_reduce()` and
  nothing is evaluated per group except an `r()` node (RFC 0074 §17).
  Each operator also has a reference implementation in R over base,
  which runs until the kernel piece lands and stays as its oracle (RFC
  0074 D29).
- **`zufast`**: `LinkingTo`. `zuf_hash64()` hashes byte keys and string
  bytes when they must be read; the integer mixers and the column combine
  are the kernel's own arithmetic (§4, D4). Source-compatible only
  (R10.3): the consumer fixture is rebuilt against the CRAN tarball of
  `zufast` before every `zutable` submission, and `zutable` cannot
  reach CRAN before `zufast` does; `zufast` 0.1.0 was on CRAN on
  2026-11-16. `Remotes: pedrobtz/zufast@main` during development, removed
  at the release stage (R10.2).
- **`stringi`**: `Suggests`. `stri_sort_key()` supplies collation keys
  when a caller asks for locale order (§6.3). Absent, collated order is
  a `zutable_collate_error` naming the package.
- **`zucsv`, `zuxlsx`**: column grouping and, later, the dictionary,
  through the header, under R10.1 only where the change removes code
  those packages test themselves. A header-only `LinkingTo` costs them no
  run-time dependency on the table class.
- **`zudedup`**: the chunk index; **`zulm`**: vocabularies. Both through
  the header.
- **`zuint`**: a later provider of 64-bit and 128-bit key types (§14).

## 4. Architecture

Four layers, each testable without the one above:

1. **The key model** (`zutable/key.h`). A key is one or several columns of
   the same length. Each column is one of six kinds: `int32`, `i64`,
   `f64bits`, `lgl`, `str` and `bytes`. Each column is hashed with the
   mixer for its kind: a multiply-shift mixer over the value for `int32`,
   `i64`, `f64bits` and `lgl`, the same mixer over the pointer for `str`,
   and `zuf_hash64()` for `bytes` and for string bytes when they must be
   read. A composite key combines its columns' hashes with a hash-combine
   step and compares column by column. The mixers and the combine are a
   few lines of arithmetic in `key.h`; `zufast` is the general hash over
   bytes (D4). §6.1 gives the equality rules per kind. The same layer
   gives each kind its order twiddle: the bijection from a key to an
   unsigned integer whose numeric order is the key's sort order, with
   `NA` placed by `na.last`; and, for a composite key, the normalised key
   of §4.3, the twiddles concatenated into one byte string whose
   `memcmp()` order is the sort order. A `str` column is an array of interned
   pointers plus a bytes accessor supplied by the embedding, `CHAR()` and
   `LENGTH()` under R and the fixture's own string table under
   `ZT_STANDALONE`; equality is by pointer, order reads bytes through the
   accessor, so the fuzz target covers strings with its own interning.
2. **The table** (`zutable/table.h`). Open addressing, linear probing,
   power-of-two capacity, maximum load 7/8, one metadata byte per slot
   (empty, deleted, or seven bits of the hash as a filter), slots holding
   a 32-bit row index into the key columns. Keys are never copied into
   the table: a slot points back at the row that first carried the key,
   so memory is one byte plus four bytes per slot and the probe compares
   against the caller's own vectors. Growth doubles and rehashes.
3. **The partitioner** (`zutable/partition.h`). A histogram pass and a
   scatter pass that split rows by the top bits of their hash, or of
   their order twiddle, into partitions sized to L2, with
   write-combining buffers so the scatter runs at bandwidth. Every
   algorithm below runs per partition when the input exceeds the cache,
   and on the whole input when it does not. Partitions are independent,
   which is what will make threads pay later (§15 Q8).
4. **The algorithms** (`zutable/groups.h`, `zutable/sort.h`, `zutable/join.h`,
   `zutable/reduce.h`). Groups: one pass inserting each row, assigning the
   next identifier on a miss and the slot's identifier on a hit; a
   counting pass gives sizes and starts; the order is a counting sort by
   identifier; sorted identifiers come from sorting the distinct keys and
   relabelling (§1.3, mechanism 3). Sort: an LSD radix over the twiddled
   key with constant-byte skipping, preceded by an MSD pass into
   partitions above cache size, with the string path of §6.3 in front of
   it. Join: build on the smaller side, probe with the larger, emitting
   pairs under the `multiple` rule. Reduce: one pass over the rows that
   updates every requested accumulator for the row's group, per partition
   when the accumulators exceed cache, with the broadcast as a gather by
   identifier afterwards.

The R API in `src/` is a thin translation: validate, call the header,
wrap results in R vectors. Nothing in `src/` is an algorithm. The header
compiles as C11 without R when `ZT_STANDALONE` is defined, which is how
the fuzz target and the consumer fixture build it.

### 4.1 Cache-conscious layout, decided up front

The incumbents hash row by row into one table and scatter row by row
into one accumulator array. At 10⁷ rows neither fits in cache and every
row is a memory miss. Database engines settled this long ago and no R
package uses the answer, so it is where the kernel's margin comes from.
These shape the layout, so they are architecture, not later tuning:

- **Radix partitioning.** Rows are split by the top bits of the hash
  into partitions that fit in L2, then built, probed, sorted and reduced
  per partition. One pass when the key columns fit in L3, two passes
  above that. The gain is largest with many distinct keys and several
  key columns, which is where the incumbents are slowest.
- **Software prefetch** in every probe loop, eight rows ahead.
- **A dense-integer fast path.** When `max - min` is within a small
  multiple of `n`, the table is a direct-indexed array and nothing is
  hashed, and the sort is a counting sort. data.table's `forder()` does
  this; a kernel without it loses on the commonest input.
- **Pointer hashing for strings.** The `CHARSXP` address goes through a
  mixer; the bytes are never read. §6.1 keeps it correct across
  encodings.
- **Unique first, for strings.** Every string operation, including sort,
  runs on the distinct strings and scatters back, since distinct strings
  are almost always far fewer than rows.
- **Column-at-a-time hashing.** Column one is hashed into an array, then
  each further column is folded into it in its own contiguous loop.
- **Count, then fill.** Group sizes, starts and order are two counting
  passes with one allocation each, never a growing vector.
- **The hash tag per slot** means a composite key is compared only on a
  tag hit, which is what makes several key columns cost little more
  than one.
- **Fused reductions.** `grp_reduce()` over several columns and
  statistics is one pass; each accumulator is a typed array indexed by
  group.
- **Scratch is stated.** Partitioning holds a hash and a row index per
  row, 12 bytes; the radix sort holds a twiddled key and an index per
  row. Each algorithm states its scratch per row in the header, the
  table itself stays at five bytes per slot (D9), and the harness proves
  both (§9.2).
- **Sortedness metadata out.** `key_sort()`'s values and `g$keys` with
  `sort = TRUE` are wrapped in a `zutable` ALTREP class carrying sorted and
  no-`NA` metadata, so base `sort()`, `is.unsorted()` and `anyNA()` on
  them return without a pass; a writable `DATAPTR` drops the metadata.
  Permutations and identifiers are plain integer vectors (D22).

`bit64`'s heuristic, sorting instead of hashing when distinct keys are
numerous, is what axis O of §4.2 measures against partitioned hashing on
the §9 inputs. If sorting wins on some region, `grp()` chooses by the
same rule and the RFC records the crossover.

### 4.2 Algorithm choices: eleven adopted, four measured

§4.1 fixes the layout's shape. Within it, each component has two or more
credible algorithms. The 2026-10-20 text made every one an experiment:
fifteen axes, each variant built behind a compile-time switch. RFC 0074
D2 replaced that. The kernel ports what DuckDB, Polars and the
literature have already settled, and builds a second variant only where
R differs from the engines, so that their answer may not transfer (D35).

**Adopted without building the alternatives:**

| Axis | Adopted | Not built |
| --- | --- | --- |
| A. Table | tag + linear probing, as §4 | Robin Hood; unchained, §14 |
| B. Hash | multiply-shift for ints, pointers; xxh3 for bytes | rapidhash |
| C. Partition | one pass, fan-out 256; two passes above L3 | other fan-outs |
| D. Grouping | hash to first-seen ids; sort switch from axis O | |
| E. Join | partitioned hash | no-partition hash; sort-merge, §14 |
| G. Composite | bit-pack narrow integers if they fit, else by column | |
| H. Output | count then fill | chunked lists |
| I. Prefetch | fixed distance | group prefetch |
| J. SIMD | scalar reference; 128-bit paths under the SIMD rule below | AVX2 |
| K. Sort | the hybrid of §4.3 | SIMD quicksorts, §14 |
| L. Aggregate | one array in cache, partitioned above it | sorted runs |

**Measured, because R differs from the engines:**

| Axis | Variants |
| --- | --- |
| F. Strings | pointer mix; dictionary-encode first |
| M. Precision | double; long double; pairwise |
| N. Str sort | full compare; 8-byte prefix + ties; MSD bytes |
| O. Sorted groups | radix all rows; hash then sort distinct |

Why the engines' answer may not transfer: R interns strings, so a
pointer is a key no engine has (F), and the string sort runs on distinct
interned strings, not on rows (N); matching base `sum()` and `mean()`
bit for bit is an R-only goal (M); and §1.3 claims that no R package
sorts only the distinct keys, which one measurement checks (O).

Each measured axis is a compile-time switch in the header
(`ZT_STRINGS`, `ZT_PRECISION`, and so on). `tools/run-benchmarks` builds
the variants and `.agents/benchmarks.md` records the numbers, the default
chosen and the variant rejected. The `ZT_STANDALONE` build makes this
possible without R in the loop. At most two variants are kept on an
axis, and only where the loser is within reach of winning on some §9
input. Each axis has three days; a variant that cannot be measured in
that time is written down as an open question, not kept as dead code
(D14).

What each row rests on:

- **A.** Tag-and-probe is the Swiss-table design (Kulukundis, 2017),
  which Polars uses through `hashbrown`. Robin Hood hashing bounds probe
  length at a cost per insert. Unchained tables (Birler, Radke and
  Neumann, DaMoN 2024) store a directory of tagged pointers into a sorted
  tuple array and were measured faster than both for joins in that
  paper. Whether an engine ships them was for the reading list of §11:
  the paper is Birler, Schmidt, Fent and Neumann, "Simple, Efficient, and
  Robust Hash Tables for Join Processing", DaMoN 2024; it credits HyPer
  with the technique and extends it in the Umbra and CedarDB line, so
  engines do ship them (read 2026-11-17). They still wait in §14: the
  first release's table is the tagged one (D35 answered Q2).
- **B.** xxh3 from `zufast` is the general hash for bytes and composite
  keys. For a single 32-bit or 64-bit integer, a multiply-shift mixer is
  a handful of instructions and is what every engine uses; Richter,
  Alvarez and Dittrich (VLDB 2015) measured hash functions against table
  layouts in seven dimensions and found the pairing matters more than
  either alone, which is why A and B are chosen together.
- **C.** Radix clustering is Manegold, Boncz and Kersten (TKDE 2002).
  Polychroniou and Ross (SIGMOD 2014) give the write-combining buffers
  that make partitioning run at bandwidth. Fan-out is bounded by TLB
  entries, so 256 is the usual answer.
- **D.** Hash first-seen is kit's, through `kit::funique()` (D38). Radix sort with run
  detection is `data.table::forder()` and base R's radix order. `bit64`
  switches between them by cardinality. Müller, Sanders, Lacurie, Lehner
  and Färber (SIGMOD 2015, "Cache-efficient aggregation: hashing is
  sorting") show the two converge on the same recursive partitioning and
  that the best choice is adaptive. The switch needs a cardinality
  estimate, and a sample of rows is the first choice (§15 Q6).
- **E.** Blanas, Li and Patel (SIGMOD 2011) found no-partitioning joins
  competitive on multi-core hardware; Balkesen, Teubner, Alonso and Özsu
  (ICDE 2013) found radix joins win when tuned to the cache; Schuh, Chen
  and Dittrich (SIGMOD 2016) compared thirteen equi-joins and found the
  answer depends on input skew and size. Single-threaded, partitioning is
  expected to win above cache size. Sort-merge waits for the ordered
  joins of §14.
- **F.** Pointer mixing reads no bytes. Dictionary encoding first, as
  Arrow does, turns strings into dense integers and lets every later axis
  run on integers; it costs one pass and is expected to win when the
  same string column is grouped or joined repeatedly, which `zutable`
  will do. `grp()`'s `keys` and `id` fields are that encoding
  made public (§5), so a consumer can keep it.
- **G.** data.table packs several narrow integer columns into one 64-bit
  key before ordering. When ranges allow, the composite key becomes one
  integer and axes B, D and K run on it; otherwise column-at-a-time
  hashing from §4.1.
- **H.** Count-then-fill is two passes and one allocation. Chunked output
  lists avoid the second pass at the cost of a final concatenation. They
  are reconsidered only if `multiple = "all"` joins, whose output size is
  not known in advance, show the second pass in a profile.
- **I.** Chen, Ailamaki, Gibbons and Mowry (TODS 2007) established
  prefetching for hash joins; group prefetching and asynchronous memory
  access chaining (Kocberber, Falsafi and Grot, VLDB 2015) go further by
  interleaving many probes. Fixed distance is the simple variant and is
  expected to capture most of the gain.
- **J.** Three places vectorise naturally: comparing sixteen slot tags
  in one instruction, which is the Swiss-table probe and the reason the
  tag is one byte; the partition histogram and scatter of axis C; and
  hashing four or eight integer keys at once for axis B. Polychroniou,
  Raman and Ross (SIGMOD 2015) vectorised whole hash probes with gathers
  and found the gain depends on the gather's cost, which is poor on many
  x86 parts, so no vector probe is assumed. The
  128-bit baseline is SSE2 on x86-64 and NEON on arm64, both always
  present, written once with GCC vector extensions so one source serves
  both. AVX2 follows the family's rule in `zufast` design §19.3:
  function-level `__attribute__((target("avx2")))` with
  `__builtin_cpu_supports()` dispatch inside the header, since portable
  `make` cannot give one object file its own flags. `zuutf` (RFC 0024)
  carries the same dispatch over simdutf and is the pattern to copy.
- **K.** Base R's radix is pure LSD, eight-bit digits, and skips
  constant byte positions; it is cache-blind above L2. An MSD first pass
  into cache-sized partitions followed by LSD within each is the standard
  fix and is what data.table's 1.12 rewrite did. But a radix has a fixed
  cost per pass, a histogram and a scatter, and loses below a few
  thousand elements to a branchless comparison sort, and comparison
  hybrids such as fluxsort beat LSD radix on 64-bit values at moderate
  sizes, so the shipped sort is a hybrid whose thresholds come from the
  sweep of §4.3 rather than from an assumption that radix wins. SIMD
  quicksorts are §14 (D31). `sort()` without the index payload moves 8
  bytes per element instead of 12 with a random gather at the end, and
  base runs the same order engine for both, so values-only sort is a
  separate code path.
- **L.** One accumulator array is `collapse::fsum()` and base
  `rowsum()`: one pass, one random write per row. Partitioned
  aggregation is the engines' answer when the accumulators exceed cache.
  Sorted runs is data.table's GForce after `forder()`: contiguous
  groups, no random writes, but a sort first. The spike of §11 tests the
  crossover by number of groups.
- **M.** Base `sum()` and `mean()` accumulate in long double where the
  platform has it, and `mean()` makes a correction pass. Bit-identical
  results with base are worth a lot to `zutable`'s tests and users; the
  cost of long double in a scatter loop is measured, and pairwise
  summation is the fallback if it is too high.
- **N.** Distinct strings are sorted, never rows (§4.1). Full
  comparison is `strcmp()` on each pair, which base radix does on the
  distinct set. The first eight bytes packed big-endian into a `uint64`
  sort by radix as an integer and resolve most strings; ties within a
  prefix fall to multikey quicksort (Bentley and Sedgewick, 1997) from
  byte nine. This is DuckDB's string sort key. MSD radix over the bytes
  directly is the control.
- **O.** `collapse::GRP(sort = TRUE)` and data.table radix-sort every
  row and detect runs. Hashing to first-appearance identifiers, sorting
  the distinct keys with axis K or N, and relabelling through a lookup
  gives the same sorted identifiers and the same order permutation. The
  crossover is by distinct keys as a fraction of rows and is recorded.
  (Decided 2026-11-17, Stage 11: D44, sorting below 10^6 rows and from
  1% distinct keys above.)

**The SIMD rule**, taken from `zufast` §19.3 and binding here: the
scalar path is written first and is the reference; a vector path is
admitted only with a benchmark showing a consumer-visible gain on the §9
inputs and results that match the scalar path bit for bit, checked by
the property tests of §8 running both. Measurements are taken on x86-64
with AVX2 and on arm64, since CRAN checks both and a gain on one is not
a gain on the other. Nothing above the 128-bit baseline ships in the
first release unless a benchmark shows at least 1.2× on an operation a
consumer calls.

### 4.3 The sort ladder, and what is vendored

**What `key_order()` sorts.** Not values but key and row index pairs.
The twiddled key goes in the high bits of a 64-bit word and the row
index in the low bits, and the words are sorted as plain unsigned
integers. The index breaks ties, so an unstable sort yields a stable
permutation for free, and the payload travels with the key instead of
being gathered at the end. That covers `int32`, `lgl`, factor and dense
keys outright. `f64bits` and `i64` need 64 key bits plus the index, so
16-byte records, where every algorithm slows and radix's advantage
grows. Which algorithm wins on which record size is a measurement.

**The workload is bimodal.** `order()` on a column is 10⁷ elements once.
Median, nth and rank within group (§14) are 10⁵ sorts of 100 elements
each, where radix is the wrong tool and the leaf sort is everything. A
kernel measured only at 10⁷ ships the wrong small-n path and loses on
the grouped operations `zutable` will call most.

**The ladder.** The sort is built on one harness that holds these, each
under about a hundred lines of C, and runs them over n from 10 to 10⁸,
over 32-bit and 64-bit keys, over values and packed key-index words,
and over the input shapes R data has: uniform, few distinct, Zipf,
sorted, reversed, and sorted with a few rows appended.

| Rung | Role |
| --- | --- |
| insertion sort | the leaf below about 24 elements |
| branchless quicksort, ninther pivot, pattern breaking | small-n engine |
| Vergesort run detection, then merge | adaptive front |
| heapsort | the cache-miss control, never shipped |
| counting sort | the dense-range path |
| LSD radix, 8-bit and 11-bit digits, byte skipping | large-n engine |
| MSD partition then LSD | the above-cache variant |
| fluxsort, crumsort, vendored | state-of-the-art comparison control |

Under RFC 0074 D2 the rungs that make up the target shape below are
built first, and in that shape. Heapsort and the vendored comparison
sorts are controls, added only if the hybrid's numbers against base
radix and data.table need explaining (D29).

The output is a regime map in `.agents/benchmarks.md`: which rung wins
at which n, record size and shape, and where the crossovers lie. The
shipped sort is one hybrid whose thresholds, leaf size, radix crossover,
dense-range ratio and run detection, are read off that map rather than
guessed. Under D14's cap the hybrid counts as one variant and its rungs
are its parameters (D30); the vendored controls are the second variant,
kept only if they win on some §9 input. Heapsort exists to show what a
cache miss costs: if the radix is not far ahead of it at 10⁷, the radix
is wrong.

**The target shape, from DuckDB.** DuckDB's sort is the production
form of the recipe above and the shape the ladder is expected to
converge on, so it is named up front and the ladder measures its
thresholds rather than rediscovering it. Three parts are taken:

1. **The normalised key.** Every key is encoded into bytes whose
   `memcmp()` order is the sort order: the twiddle per kind, keys
   concatenated for a composite, `decreasing` as a byte inversion, and
   for strings the first eight bytes with a tie-break on the full string.
   This is the general form of the twiddle, axis G's packing and axis N's
   prefix, and it is the key model's output for sorting (§4, layer 1).
2. **Vergesort in front.** A scan for runs of length about n over log n
   that merges them when it finds enough and costs almost nothing when
   it finds none, so time-ordered data with a few out-of-order rows
   sorts in O(n). It is the ladder's adaptive rung.
3. **MSD radix with a comparison leaf.** Vergesort, then MSD radix on the
   first eight bytes of the normalised key, then a pattern-defeating
   quicksort below a threshold, then insertion sort at the leaf: the
   American flag sort with a leaf, which is what DuckDB's 2025 redesign
   runs as ska sort over pdqsort.

Two parts are left out, and why:

- **The k-way merge.** DuckDB merges sorted runs because its data arrives
  in chunks per thread through a streaming pipeline and must stream out
  again. An R vector is one array in memory. Partitioning by the top
  bytes of the normalised key gives buckets already ordered relative to
  each other, so concatenation replaces the merge, and threads, when they
  come, take buckets without a merge phase. The merge is the price of
  DuckDB's execution model, not a feature of its sort.
- **The single-thread trade.** DuckDB's redesign accepted about 30% less
  single-threaded throughput than its LSD radix for adaptivity and
  parallel scaling, because its sort cannot see the whole input before
  it starts. This kernel can: it knows n, the key width, whether
  Vergesort found runs, and the distinct count when grouping ran first,
  before it chooses. Choosing per call from the regime map, LSD on packed
  words for random 32-bit keys, MSD and quicksort for 16-byte records,
  Vergesort's merge for sorted runs, quicksort below a few thousand, is
  how the kernel gets the adaptivity without the cost. It is the one place
  the kernel is structurally ahead of the engine, and it follows from
  the kernel's claim being single-threaded speed (D20).

None of the engines, DuckDB, ClickHouse or Polars, uses a SIMD sort for
this workload; the data-frame ecosystem converged on radix with a
comparison leaf, which is D31's position.

**Vendored, ported, or written.** The family's admission test allows
vendored C under a permissive licence with no system dependency. The
reference implementations of the target shape are all C++ templates,
which do not drop into a C11 header, so the distinction that matters is
between code copied as a file, an algorithm ported to C with its licence
and attribution kept as the family does for vendored code, and code
written from the description. Verdicts, as of 2026-10-20:

| Candidate | Licence, language | Verdict |
| --- | --- | --- |
| fluxsort, crumsort (scandum) | Unlicense, C | vendored, as the control |
| swenson/sort | MIT, macro C | vendored, harness rungs |
| wolfsort (scandum) | Unlicense, C | read; measure if cheap |
| Vergesort (Morwenn) | MIT, C++ | ported to C |
| ska sort (Skarupke) | Boost 1.0, C++ | ported to C |
| pdqsort (Peters) | zlib, C++ | ported to C |
| LSD radix, byte skipping | — | written |
| American flag, multikey quicksort | — | written (axis N) |
| DuckDB's sort | MIT, C++ | not vendored; the shape is |
| x86-simd-sort (Intel) | BSD-3, C++ | §14 |
| vqsort (Google Highway) | Apache-2.0, C++ | §14 |
| CAFS (2026) | paper | read first, §11 |

The reasons: fluxsort and crumsort are plain C in one header, and
crumsort's instability is harmless under the packing above; swenson's
`sort.h` gives the comparison rungs of the ladder, insertion, quick,
heap, merge and Tim sort, as tested macro C for the harness, and none of
it ships unless it wins. Vergesort, ska sort and pdqsort are each under
a few hundred lines and are ported specialised to the two record types,
8-byte words and 16-byte records, since templates over a comparator are
the part that does not survive the move to C; each port keeps the
original licence notice and is tested against the original's behaviour
on the same inputs. The LSD radix and the string sorts are written,
because they must integrate with the key model, the byte skipping and
the dense path anyway and have no licence to carry. DuckDB's own sort is
MIT but entangled with its row layout and pipeline; the normalised key
is a specification this RFC implements, not code it copies.
x86-simd-sort is C++ templates that need per-translation-unit AVX flags,
which R's portable `make` cannot give, and AVX-512 is absent on arm64
and most consumer x86. vqsort pulls in Highway, tens of thousands of
lines, for one function. CAFS claims a win at low cardinality, which is
already the dense path and the sort-the-groups path here, and the claim
is unverified at the time of writing.

Two constraints a survey of sort libraries does not see. The header
contract: a C++ sorter can live in the R shared object but not in the
`LinkingTo` header, so consumers calling `zt_order()` from C would get
the radix and only the R API the SIMD path, and two engines for one
function is a cost in itself. And D15: a vector path needs a measured
gain on both architectures CRAN checks, which on arm64 means 128-bit
NEON, where the SIMD sorts lose most of their margin. The scalar hybrid
is the reference; the regime map is what any later vendoring argues
against.

### 4.4 The reading list, read in Stage 9 (2026-11-17)

What each source of the reading list changes, as §11 asked:

- **DuckDB's sorts.** The 2021 post (["Fastest table sort in the
  West"](https://duckdb.org/2021/08/27/external-sorting.html)) gives the
  normalised key exactly as §4.3 takes it: integers big-endian with the
  sign bit flipped, descending columns inverted, strings as a padded
  prefix with a tie-break on the full string, NULL as an extra byte. The
  ICDE 2023 paper used pdqsort when strings were present and radix
  otherwise. The 2025 redesign (["Redesigning DuckDB's Sort,
  Again"](https://duckdb.org/2025/09/24/sorting-again)) runs Vergesort,
  then ska sort (MSD radix on the key's first 64 bits), then pdqsort, the
  upstream C++ of each, and reports about 30% lower single-threaded
  throughput for an in-place MSD over the old out-of-place LSD. Both
  confirm §4.3's target shape and its reason to choose per call; nothing
  changes but the citation.
- **CAFS** (Shlyk, [arXiv:2605.25040](https://arxiv.org/abs/2605.25040)).
  A frequency sort for low-cardinality integers whose hot loop is AVX2,
  so x86-64 only, which D15 rules out of the scalar kernel; its regime is
  the dense and sort-the-groups paths already here. Its cardinality
  estimate is what this design lacked: Chao1 over 1024 strided samples
  in a 40 KB table, which answers Q6 (D37).
- **Vergesort, ska sort, pdqsort** (Morwenn/vergesort, skarupke/ska_sort,
  orlp/pdqsort): the sources DuckDB itself takes, under the licences
  §4.3's table states; Stage 11 ports them.
- **Unchained tables**: see axis A above.

## 5. Public R API (first-release shape)

```r
g <- grp(key1, key2, ..., sort = FALSE)
g$id        # integer, group identifiers, 1-based; first appearance,
            # or sorted key order when sort = TRUE
g$n         # number of groups
g$sizes     # integer, length n
g$starts    # integer, length n, into g$order
g$order     # integer permutation that puts each group together
g$keys      # list of key columns, one row per group, in id order

o <- key_order(key1, key2, ..., decreasing = FALSE, na.last = TRUE,
               collate = FALSE)     # stable permutation
s <- key_sort(x, decreasing = FALSE, na.last = TRUE, collate = FALSE)
r <- key_rank(key1, key2, ..., ties = "min", decreasing = FALSE,
              na.last = TRUE, collate = FALSE)  # na.last also "keep" (D43)

m <- grp_match(x, y)               # integer, like match(), several keys
j <- grp_join(x, y, by = NULL, type = "inner", multiple = "all")
j$x; j$y    # integer index pairs; NA in j$y for unmatched left rows

a <- grp_reduce(x, by = g, fn = "sum", na.rm = TRUE,
                broadcast = "none")
# x:  a vector, or a list of vectors of one length
# by: a grp() result, or key vectors to group by
# fn: one of "sum" "prod" "mean" "min" "max" "count" "first" "last"
#     "nobs", one name or one per element of x
# broadcast: "none" gives one value per group, in id order;
#     "replace", "subtract", "divide" give one value per row
# result: a vector when x is one vector, else a list

zutable_info()                       # zufast version, flags, SIMD level
```

`x` and `y` in `grp_join()` and `grp_match()` are vectors, lists of
vectors or data frames; `by` names the columns when they differ between
sides, as in `merge()`. A data frame key uses all its columns.
`decreasing` in `key_order()` and `key_rank()` is one logical or one per
key. `collate = TRUE` applies to character keys and needs `stringi`
(§6.3).

## 6. Semantics

### 6.1 Key equality, per kind

| Kind | R types | Equal when |
| --- | --- | --- |
| `int32` | integer, factor codes | same value; `NA` equals `NA` |
| `i64` | `integer64` | same 64-bit value; `NA` equals `NA` |
| `f64bits` | double | same 64 bits, after folding `-0` to `0` |
| `lgl` | logical | same value; `NA` equals `NA` |
| `str` | character | same `CHARSXP` after UTF-8 translation (below) |
| `bytes` | raw, list of raw | same length and bytes |

`NA` equals `NA` everywhere, as data.table does and `aggregate()` does
not; a caller who wants `NA` dropped filters first. For doubles, `NA` and
`NaN` are distinct keys because their bit patterns differ, and every
other `NaN` payload is folded to one canonical `NaN` so arithmetic noise
does not create groups. A double column of class `integer64` is `i64`,
compared as a signed 64-bit integer with no folding, since its `NA` is
the bit pattern of `-0` and its large values are `NaN` payloads as
doubles. Factors are hashed by code with levels compared
once up front; two factors with different level sets are an error, not a
silent recode.

**Strings.** R interns strings, so two equal strings in the same encoding
share a `CHARSXP` and compare by pointer. The exception is the same text
in two encodings. the kernel checks each character column once: if every
element is ASCII or marked UTF-8, pointers are the key; otherwise the
column is translated to UTF-8 through `translateCharUTF8()` and the
translated pointers are the key. Encoding thus never changes equality,
and the common case pays nothing.

### 6.2 Groups

With `sort = FALSE`, identifiers follow first appearance in row order, so
`grp(x)$id` equals `match(x, unique(x))` for a single key and the
same thing for several keys without the `paste()`. With `sort = TRUE`,
identifiers follow the sort order of §6.3 over the distinct keys, so
`g$keys` is sorted and `g$id` equals `collapse::GRP(x)$group.id`.
`order` is stable within a group. `keys` holds each key column reduced
to one row per group, in identifier order; for a single character key
with `sort = FALSE` it is `unique(x)`. With `sort = TRUE` the `NA` group
sorts last. Zero rows give `n = 0` and empty vectors.

First appearance is a contract, not an accident of the algorithm.
Partitioned grouping (§4.1) numbers groups per partition, so the R API
relabels: the first row of each group is recorded at insertion, groups
are ordered by first row with one counting pass over a bitmap of `n`
bits, and identifiers are remapped with one gather. The header also
exposes the unrelabelled identifiers, any stable labelling, for
consumers that need nothing more, which is what `grp_reduce()` uses
internally. The 10⁷-distinct target of §9.3 includes the relabel (D24).

### 6.3 Sort order

`key_order()`, `key_sort()` and `key_rank()` agree with base
`order(method = "radix")` and `sort(method = "radix")` wherever both are
defined, and the tests hold them to it:

| Kind | Order |
| --- | --- |
| `int32`, `lgl` | numeric; `FALSE` before `TRUE` |
| `i64` | numeric, as a signed 64-bit integer |
| `f64bits` | numeric; `-0` equals `0`; `-Inf`, `Inf` at the ends |
| `str`, `collate = FALSE` | byte order of the UTF-8 translation |
| `str`, `collate = TRUE` | the locale, through `stringi` sort keys |
| `bytes` | lexicographic by byte, shorter prefix first |

The sort is stable: equal keys keep row order, so `key_order()` of a
constant vector is `seq_len(n)`. `na.last = TRUE` places `NA` and `NaN`
last, `FALSE` first, `NA` drops them from the permutation, as `order()`
does. `NA` and `NaN` are equal in the order, keeping row order between
them, as base R's order and sort have them under every method (corrected
2026-11-17, Stage 11: the 2026-10-20 text had `NA` before `NaN`, which
base R never does); they stay different keys for grouping (§6.1).
`decreasing` reverses the key's order but not the stability. Several
keys sort by the first, then the second within ties, each with its own
direction; the kernel packs their codes into one normalised key when
they fit in 64 bits, reversed per key for `decreasing`, and sorts wider
keys in chunks of at most 64 bits, last chunk first (D40).

**Strings.** Byte order is what base radix gives and what data.table and
`collapse` give, and most callers never notice, because keys are codes,
identifiers and symbols. It is the default because it needs no locale
and is reproducible across machines. `collate = TRUE` is for text a
person will read in order: the kernel takes the distinct strings, asks
`stringi::stri_sort_key()` for each one's collation key, and runs the
byte-order path on the keys. The collation cost is paid once per distinct
string, not per comparison, which is why this beats base `sort()` on
character by a large factor and matches `stringi::stri_order()` exactly.
Without `stringi` installed, `collate = TRUE` is a `zutable_collate_error`.

**Outputs.** `key_sort()` returns an ALTREP-wrapped vector marked sorted,
and marked `NA`-free when `na.last = NA` or the input had none, so a later
`sort()`, `is.unsorted()` or `anyNA()` on it returns at once; the wrapper
is `zutable`'s own class, since base R exposes no API to create its
wrapper, and a writable `DATAPTR` drops the metadata so an in-place edit
cannot make `is.unsorted()` lie. `key_rank()`
with `ties = "min"` equals `rank(ties.method = "min")`; `"first"` equals
`"first"`; `"dense"` is the sorted group identifier of §6.2 and has no
base equivalent.

### 6.4 Joins and `multiple`

`grp_join()` returns index pairs and never a table. `type` is `inner`,
`left`, `semi` or `anti`; `right` and `full` are `left` with the sides
swapped and a union, left to the consumer. `multiple` is about `y` rows
per `x` row, whichever side the kernel builds its table on, and applies
when an `x` row matches several `y` rows:

| `multiple` | Behaviour |
| --- | --- |
| `all` | every pair (the `merge()` default) |
| `first` | the first matching `y` row |
| `last` | the last |
| `error` | `zutable_multiple_error` naming the first offending key |

Pairs come in `x`-row order and, within one `x` row, in `y`-row order,
so `j$x` is non-decreasing and `grp_match()` lines up with `x`. The
kernel builds on the smaller side (§4); when that is `x`, the pairs are
produced in `y` order and reordered, and the reorder is part of the
join's measured cost (D23).

The default is `all`, because it is what `merge()` and data.table do.
`error` exists for callers such as the table's `merge()` and the planned
`zumodel` that treat fan-out as a bug. `grp_match()` is `type = "left"` with
`multiple = "first"` returning `j$y` alone.

### 6.5 Reductions and broadcast

`grp_reduce()` computes each requested statistic per group in one pass
over the rows. The statistics and their result types:

| `fn` | integer `x` | double `x` | character `x` | Base oracle |
| --- | --- | --- | --- | --- |
| `sum` | double | double | error | `rowsum()` |
| `prod` | double | double | error | `tapply(prod)` |
| `mean` | double | double | error | `tapply(mean)` |
| `min`, `max` | integer | double | character, byte order | `tapply` |
| `count` | integer | integer | integer | `tabulate()` |
| `nobs` | integer | integer | integer | `tapply(.., \(v) sum(!is.na(v)))` |
| `first`, `last` | integer | double | character | `tapply(.., head/tail)` |

`count` is the group size and ignores `x`'s values; `nobs` is the count
of non-missing values. Integer `sum` and `prod` return double always,
rather than integer with an overflow `NA` as base `sum()` does, because
a type that depends on the values is what `zutable`'s lock forbids
(D18). `na.rm = TRUE` is the default, as in `collapse`; with
`na.rm = FALSE` a group with any `NA` yields `NA` for `sum`, `prod`,
`mean`, `min` and `max`, and `first` and `last` return the value in
place, `NA` or not. An empty group cannot occur, since groups come from
the rows. Double accumulation follows axis M; the tests of §8 compare
with base at the tolerance that axis's choice allows, and bit-identical
is the target.

**Broadcast.** `broadcast = "none"` returns one value per group in
identifier order, so `grp_reduce(x, g, "sum")` lines up with `g$keys`.
The other modes return one value per row: `"replace"` is the group's
value at every row of the group, which is `collapse`'s `TRA = "replace"`
and the way to compute a group share or a within-group deviation;
`"subtract"` is `x` minus the group value, the within transformation;
`"divide"` is `x` over the group value. The broadcast is a gather by
identifier after the reduction and costs one pass. Character `x`
supports `"replace"` only.

**Fusion.** When `x` is a list, every element is reduced in the same
pass over the rows, each with its own `fn`; grouping is its own pass
and is never repeated. When `by` is key vectors rather than a
`grp()` result, `grp()` runs first and the result carries
the group object as the attribute `groups`, so a consumer that needs
`keys` or `sizes` for its output does not group twice (D25). This is
the call `zutable`'s `by` with several aggregates will make.

## 7. Errors

Every condition inherits from `zutable_error`; tests assert on class, never
on message (R9).

| Class | Raised when |
| --- | --- |
| `zutable_type_error` | a key column is not one of the six kinds |
| `zutable_type_error` | `x` and `y` key kinds differ |
| `zutable_length_error` | key columns differ in length |
| `zutable_length_error` | a key column exceeds 2³¹ − 1 rows |
| `zutable_multiple_error` | `multiple = "error"` and a key matches many rows |
| `zutable_levels_error` | two factor keys have different level sets |
| `zutable_fn_error` | `fn` is unknown or not defined for `x`'s type |
| `zutable_collate_error` | `collate = TRUE` without `stringi` |

Messages name the offending column and, for `multiple`, the key's value
formatted with `format()`.

## 8. Testing

`testthat` 3e. One file per section of §6. Base R is the oracle:
`grp()` against `match(x, unique(x))` and, for several keys, against
`interaction(drop = TRUE)` recoded to first appearance, and with `sort =
TRUE` against `collapse::GRP()` under `skip_if_not_installed()`;
`key_order()` and `key_sort()` against `order(method = "radix")` and
`sort(method = "radix")` on every kind and every combination of `decreasing`
and `na.last`, with character input passed through `enc2utf8()` first since
base radix compares bytes without translation, and with `collate = TRUE`
against `stringi::stri_order()`; `key_rank()` against `rank()`; `grp_join()`
against `merge()` with `sort = FALSE` turned into index pairs; `grp_match()`
against `match()`; `grp_reduce()` against the oracles in §6.5's table, with
`broadcast` against the same oracle indexed by `g$id`. A property file draws
random keys of every kind, with `NA`, `NaN`, `-0`, `Inf`, duplicated and
mixed-encoding strings, sorted, reversed and constant inputs, at lengths 0,
1, 2 and 10⁵, and checks each result against the oracle; it runs every kept
axis variant and checks they agree bit for bit. A file checks the ALTREP
metadata of §6.3 through `is.unsorted()` and `anyNA()`.

Three tests come from the family's providers (R10.4): `test-abi.R`, that
the shared object exports `R_init_zutable` only; `tools/zutabletest`, a
consumer package with a `LinkingTo: zutable` C file calling the header,
installed in CI with `zutable` removed from the library path; and
`check-headers`, that every header compiles alone under `-Wall -Wextra
-pedantic` as C11 and as C++17. A fuzz target under `ZT_STANDALONE` feeds
random key streams through groups, sort, join and reduce and checks the
invariants (every row has an identifier, the permutation is a
permutation and its keys are non-decreasing, every pair's keys are
equal, sums over groups add up to the total).

## 9. Performance targets

Measured by `tools/run-benchmarks` on a fixed machine description and
recorded in `.agents/benchmarks.md`; the targets are relative to
alternatives, so machine speed cancels. The maintainer's machine is arm64;
the x86-64 numbers that D15 needs come from a GitHub Actions runner through
r-actions, five repeats, the median recorded, and a SIMD gain counts only
when every repeat shows it (D26). Inputs: 10⁷ rows, keys drawn from 10³, 10⁵
and 10⁷ distinct values, integer, double and character, single and
two-column; for sort, also already-sorted, reversed, few-distinct, and
all-distinct strings such as identifiers, which is the hard string case; for
reduce, one and four value columns. The sort ladder of §4.3 sweeps n from
10 to 10⁸ and adds Zipf and sorted-with-appended-rows shapes, and one
target below is the small-n regime it exists for.

The 10³ and 10⁵ regimes are where `collapse` is at home and the target
is parity. The 10⁷ regime, and the two-column and string inputs, are
where §1.3's mechanisms apply and the target is a margin.

### 9.1 A realistic input beside the synthetic ones

Synthetic uniform keys flatter hash tables. One input is shaped like the
work people actually bring: a market-data day. Data Intellect's 2023
comparison of DuckDB, Polars and Vaex on one NYSE TAQ day (30 million
trades, 80 million quotes, Arrow files) grouped by symbol and hour, and
the engines separated by an order of magnitude on that one shape. The
benchmark generates the same shape without the licensed data: 3 × 10⁷
rows, a character key of about 10⁴ symbols with the heavy skew of real
tickers, an integer timestamp bucketed to the hour as the second key,
and a double value to aggregate. Two things make it instructive:

- The symbol column has about 10⁴ distinct strings, so the encode-first
  variant of axis F turns it into a code below 2¹⁴ beside an hour below
  2⁵, axis G packs the pair into one integer and the dense fast path of
  §4.1 applies. This is the input where encode-first is expected to beat
  pointer mixing. If the kernel cannot win here, the layout is wrong.
- The comparison that article ran is the one users run: an engine.
  `duckdb` with `SET threads = 1` is the single-threaded engine oracle
  for this input, beside data.table and collapse. Matching an engine
  from R without a query planner is the honest ceiling for a kernel.

### 9.2 Three rules for the harness, learnt from that article

The article's DuckDB query omitted a time filter the other two applied,
its Vaex mid-price formula lacked parentheses and computed the wrong
quantity, and its memory ranking was decided by one engine's
experimental scanner. So `tools/run-benchmarks`:

1. **checks equality before timing.** Every oracle's result is reduced
   to a canonical form (group counts and sizes, sorted index pairs,
   sorted values, per-group sums) and compared across oracles and
   the kernel. A timing is recorded only when all agree; a disagreement is
   a bug report, not a benchmark.
2. **records peak memory for every row**, not only the groups row. The
   article's ranking changed on memory, and the kernel's five bytes per
   slot plus the scratch each algorithm states is a claim the harness
   must prove on each operation.
3. **states what each oracle was given.** Sort requirements, thread
   counts and options are part of the record, so a number is never read
   without the settings that produced it. data.table and duckdb are run
   at one thread and at all threads and both numbers are recorded; the
   first release's targets are against one thread (D20, §15 Q8). Where an oracle
   needs sorted input, the sort is timed and shown separately.

### 9.3 Targets

The bar is measured before any kernel code exists: the harness runs
every incumbent on these inputs and writes the numbers to
`.agents/benchmarks.md`, so each target below is a ratio against a
recorded figure, not a guess. The spike of §11 then tests the cost model
of §1.3 in C before the design is committed to it.

| Operation | Target |
| --- | --- |
| groups, one integer key, 10³ or 10⁵ distinct | parity with `match(x, kit::funique(x))` (D38) |
| groups, one key, 10⁷ distinct | at least 2× faster than `kit` (D38) |
| groups, two keys | at least 1.5× faster than `collapse::GRP()` |
| groups, `sort = TRUE`, 10⁵ distinct | at least 2× faster than `GRP()` |
| groups, any input | at least 2× faster than `vctrs::vec_group_id()` |
| groups, §9.1 input | within 2× of `duckdb`, one thread |
| groups, §9.1 input | at least 1.2× faster than `collapse::GRP()` |
| order, integer or double, 10⁷ rows | at least 1.5× faster than base radix |
| order, any input | parity with `data.table::forder()`, one thread |
| order, n = 100, repeated 10⁵ times | at least 2× faster than base `order()` |
| order, sorted or reversed input | O(n), parity with base radix |
| sort of values, double, 10⁷ rows | at least 2× faster than base radix |
| order, character, 10⁵ distinct | at least 3× faster than base radix |
| order, character, all distinct | at least 1.5× faster than base radix |
| sort, character, `collate = TRUE` | parity with `stringi::stri_order()` |
| sort, character, `collate = TRUE` | at least 20× faster than base `sort()` |
| join, inner, one key | parity with data.table's `x[y, on =]` index |
| join, inner, two keys | at least 1.5× faster than data.table |
| match, one key | faster than `match()` |
| match, one key | parity with `collapse::fmatch()` |
| match, `integer64` | parity with `bit64::match.integer64()` |
| reduce, sum, 10³ or 10⁵ groups | parity with `collapse::fsum()` |
| reduce, sum, 10⁷ groups | at least 2× faster than `fsum()` |
| reduce, four columns fused | at least 1.5× faster than four `f*()` calls |
| reduce, sum, any input | faster than base `rowsum()` |
| reduce, `broadcast = "subtract"` | parity with `collapse::fwithin()` |
| peak memory, groups, joins | input + 5 bytes a slot + 12 bytes a row |
| peak memory, sort | no more than base radix order's peak |

A target missed is recorded, not hidden; the release does not wait on it
(§12). The package's claim is the typed plan of RFC 0074, and the
kernel's is the API and the header; above the sizes where these targets
hold, RFC 0074 hands the plan to an engine. A target beaten by more
than 2× is also recorded, with a check that the oracle was given a fair
input. The "fastest single-threaded in R" claim of §1.3 is made in the
README only for the rows that the record supports.

## 10. The experiment: how fast can a kernel be built from the blocks

The maintainer's question is whether the family's building blocks
(`zufast` for hashing, `r-actions` for CI, the `pkg-*` skills, the
template, the alignment rules) make a core algorithmic package fast to
build. The hypothesis, restated on 2026-11-16 without stage numbers,
since RFC 0074 fixes none:

> **From the first kernel commit, piece a of §11, to groups, sort and
> join working with the header and their tests, in 14 calendar days or
> fewer. The elapsed time of the whole kernel is recorded without a
> target.**

The package's roadmap records the date of the first kernel commit and
the dates on which the join and the last kernel piece merge. Its final
stage writes a short retrospective into `.agents/roadmap.md`: elapsed
days to each, the piece that took longest, which blocks saved time and
which cost it, and what a second kernel would do differently. A miss is
a result, not a failure; the point is a number the next RFC can plan
against.

## 11. Order of work

The order of work, pieces a to g with the spike and its threshold,
became Stages 9 to 16 of [roadmap.md](roadmap.md) on 2026-11-17.

## 12. Acceptance criteria for the kernel

- Every behaviour in §6 and §7 has a passing test with base R as oracle.
- `tools/zutabletest` builds and runs against the installed header with
  `zutable` absent from the library path.
- The shared object exports `R_init_zutable` only.
- `R CMD check --as-cran` is clean on all r-actions legs, including the
  sanitizer and valgrind legs of `native-checks.yaml`.
- `.agents/benchmarks.md` holds a number for every row of §9.3, met or
  not, the spike's result, and the regime map of §4.3.
- `DESCRIPTION` carries no `Remotes:` and `LinkingTo: zufast (>= 0.1.0)`
  names the CRAN version the fixture was last built against.
- Every operator of RFC 0074's local executor gives the same result
  through the kernel as through its reference executor.

## 13. Decisions

Marked **(M)** when the maintainer decided it in conversation and
**(C)** when this RFC decides it and the maintainer may overturn it.

- **D1 (M, revised 2026-10-21).** The kernel is `zutable`'s own layer,
  not a package beneath it (D34). It is still built as a test of the
  building blocks (§10). Revised again on 2026-11-16: it is no longer a
  second release but the engine beneath RFC 0074's local executor, in
  0.1.0 for now (RFC 0074 D35).
- **D2 (M, reversed 2026-10-20).** The kernel sorts. The 2026-10-17 decision
  left sorting to base R because base has data.table's radix order; it
  has the 2016 single-threaded version, and the maintainer named the
  fastest sort for numeric, integer and character vectors in R as a
  goal. Base radix stays the oracle for order semantics (§6.3).
- **D3 (M, widened 2026-10-20).** The scope is `collapse`'s algebra over
  vectors: group, sort, join and reduce, later scans, weights and pivot.
  `collapse`'s data-frame verbs stay out. The first release ships the
  four families of §2 and the one-pass reductions only.
- **D4 (M, scoped 2026-10-20).** General hashing of bytes comes from
  `zufast` through `LinkingTo`, accepting that `zutable` reaches CRAN
  after `zufast`. The multiply-shift mixers for integers and pointers and the
  hash-combine step are the kernel's own few lines in `key.h`: `zufast`'s
  `hash.h`, checked on 2026-10-20, offers one-shot xxh3 and a 640-byte
  streaming state, and neither is a per-row primitive. This is (C); the
  alternative is adding a mixer to `zufast` first, which puts a `zufast`
  release on the critical path.
- **D5 (C, restated 2026-10-21).** `zutable` has no prefix for the table
  surface (RFC 0074 §3); the kernel's functions form two named families
  inside it. `grp_`, read as "group", for every function that takes or
  returns groups: `grp()` builds the group object, and `grp_match()`,
  `grp_join()` and `grp_reduce()` share the prefix, a join being a
  grouping across two vectors. The maintainer relaxed the prefix where it
  misreads: a function that neither takes nor returns groups is named for
  what it does, so the sort family is `key_order()`, `key_sort()` and
  `key_rank()`, and the later dictionary is `dict_*()`. `group_` is
  dplyr's prefix and is avoided. The C prefix is `zt_`, made public
  through the header; `zu_` is `zucbor`'s,
  `zg_` is `zuggml`'s and `zuf_` is `zufast`'s.
- **D6 (C).** Strings compare by `CHARSXP` pointer when a column is all
  ASCII or UTF-8, otherwise by UTF-8-translated pointer (§6.1).
- **D7 (C).** `NA` equals `NA`; `NA` and `NaN` are distinct doubles; all
  other `NaN` payloads fold to one; `-0` folds to `0`.
- **D8 (C).** `multiple = "all"` is the join default, matching `merge()`
  and data.table; `"error"` exists for consumers that forbid fan-out.
- **D9 (C).** Slots store row indices, never key copies. Memory is five
  bytes per slot and the probe reads the caller's vectors.
- **D10 (C).** The dictionary, when it returns, is an external pointer
  whose protected field carries everything, so it serializes without a
  repair step (§14).
- **D11 (C).** Single-threaded; indices are 32-bit; both limits are
  stated in the documentation and enforced with `zutable_length_error`.
- **D12 (C).** Performance targets (§9) are measured and recorded but do
  not gate the first release; the API and the header do.
- **D13 (C, restated 2026-10-20).** The hypothesis of §10 is 14 calendar
  days from the first kernel commit to the join working; the kernel's
  elapsed time is recorded without a target.
- **D14 (C, narrowed 2026-11-16).** The four measured axes of §4.2 run
  behind compile-time switches, three days each, and keep at most two
  variants per axis. A variant not measured in time becomes an open
  question, never dead code.
- **D15 (C).** SIMD follows `zufast` §19.3: scalar reference first,
  vector paths bit-identical and admitted only on a measured gain; the
  128-bit baseline is the most the first release ships unless a
  benchmark shows 1.2× from AVX2 or AVX-512 on an operation a consumer
  calls, on both architectures CRAN checks.
- **D16 (M).** `collapse` is the measured bar and `data.table` and
  `duckdb` are the competitive oracles. The expected margin and its
  mechanisms are stated in §1.3 as a hypothesis and tested by the
  spike of §11 before the design depends on them.
- **D17 (C).** The dictionary leaves the first release to make room for sort and
  reduce; its design is kept in §14 and returns on a consumer's request.
- **D18 (C).** Integer `sum` and `prod` return double always, so a
  result's type never depends on its values.
- **D19 (C).** Strings sort by bytes by default; collated order is
  explicit, through `stringi` sort keys computed once per distinct
  string, and the kernel never implements a locale.
- **D20 (C).** The first release's speed claim is "fastest
  single-threaded", and
  the §9.3 targets compare against each oracle at one thread; the
  all-threads numbers are recorded beside them (§15 Q8).
- **D21 (C).** Reductions are one function, `grp_reduce()`, with `fn`
  naming the statistic, so fusion over several columns is one call and
  the surface stays small (§15 Q7).
- **D22 (C).** `key_sort()` values and sorted `g$keys` carry ALTREP
  sortedness and `NA` metadata through a `zutable` class; nothing else is
  wrapped.
- **D23 (C).** `multiple` counts `y` rows per `x` row whatever side the
  table is built on; pairs come in `x`-row then `y`-row order, and any
  reorder that costs is measured as part of the join.
- **D24 (C).** First-appearance identifiers are the R API's contract and
  are produced by a relabel after partitioned grouping; the header also
  exposes the unrelabelled identifiers.
- **D25 (C).** `grp_reduce()` with key vectors in `by` groups first and
  returns the group object as the attribute `groups`; fusion means
  several statistics in one pass over the rows, never a skipped grouping
  pass.
- **D26 (C).** x86-64 measurements come from a CI runner, five repeats,
  median; a SIMD gain must show in every repeat.
- **D27 (C).** `integer64` is its own kind, `i64`, recognised by class,
  with no `-0` or `NaN` folding and signed order.
- **D28 (C).** Each algorithm states its scratch per row; the memory
  targets of §9.3 are the table's five bytes per slot plus that scratch.
- **D29 (C).** fluxsort, crumsort and swenson's `sort.h` are vendored
  for the harness and ship only if they win on some §9 input; Vergesort,
  ska sort and pdqsort are ported to C for the two record types with
  their licences kept; the radix and string sorts are written; DuckDB's
  code is not copied, its normalised-key design is. Under D35 the
  vendored controls are added only when the hybrid's numbers need
  explaining.
- **D30 (C).** The shipped sort is one hybrid whose thresholds come from
  the regime map of §4.3; it counts as one variant under D14 and its
  rungs are its parameters.
- **D31 (C).** SIMD quicksorts, x86-simd-sort and vqsort, are out of
  the first release: C++, per-translation-unit flags R's `make` cannot give,
  Highway's size, the header contract, and D15's two-architecture rule.
- **D32 (C).** The shipped sort has DuckDB's shape without its merge:
  normalised key, Vergesort, MSD radix, quicksort leaf, chosen per call
  from the regime map, because the kernel sees the whole input first.
- **D33 (M).** The package was named `zugrp` on 2026-10-21, over
  `zumap`, whose name covered neither the sort nor the reductions and
  whose `map_reduce()` read as MapReduce; over `zukey`, `zuorder` and
  `zusort`; and over `zugroup`, the same word spelt out. Grouping is the
  kernel's original idea, a join is a grouping across two vectors, and
  reductions are grouped statistics in `collapse`'s own vocabulary, whose
  `GRP()` the name echoes. D34 retired the package name the same day;
  the reasoning survives as the `grp_` prefix of D5.
- **D34 (M).** One package. On 2026-10-21 the maintainer decided that a
  kernel package and a table package were not worth keeping apart, and
  placed the kernel in `zutable`. The split had been drawn so that
  `zucsv`, `zudedup` and `zulm` could link to the kernel without
  depending on a data frame class; a header-only `LinkingTo` costs them
  no run-time dependency, so the header stays and they link to `zutable`
  instead. What the merge buys: one repository, one CI, one release
  cadence, one CRAN ordering constraint behind `zufast`, and no version
  coupling between the table and the kernel it calls. What it costs:
  `zutable` becomes both an R API and a provider, as `zubin` is. The
  2026-10-21 text also made the kernel v0.2.0 behind a dependency-free
  v0.1.0; RFC 0074 D35 put it in 0.1.0.
- **D35 (M).** On 2026-11-16 the maintainer decided against inventing an
  engine piece by piece: the kernel ports the algorithms DuckDB and
  Polars have proven (RFC 0074 D2). §4.2 therefore adopts the
  best-known choice on eleven axes and measures only F, M, N and O,
  where R differs from the engines.
- **D36 (C).** The kernel is reached by translation. RFC 0074
  translates every `select`, so reductions always go through
  `grp_reduce()`. This answers Q9.
- **D37 (C).** Axis D's cardinality estimate is Chao1 over 1024 strided
  samples of the key, as CAFS reads it (§4.4): no `Suggests` on a
  sibling, a fixed cost, and an estimate that sees the duplicates a plain
  distinct count of the sample would miss. Answers Q6, on the
  maintainer's instruction to decide open questions by an expert
  recommendation; 2026-11-17, Stage 9.
- **D39 (C).** A table starts at twice the Chao1 estimate of its keys
  (or of its partition's share) and doubles when it reaches 7/8, rehashing
  from the hashes it already has; `zt_groups_one()` stops before the
  insert that would pass the limit and the caller grows the table. Its
  capacity is 64-bit, up to 2^32 slots, so a table holds the 2^31 - 1 keys
  a column can have (a 32-bit capacity held only 7/8 of 2^31, found by the
  limit test). 2026-11-17, Stage 10.
- **D38 (C).** `kit` has no `group()`; the §9.3 rows that named it
  compare with `match(x, kit::funique(x))`, kit's hashing route to group
  identifiers. Found writing the harness, 2026-11-17, Stage 9.
- **D40 (C).** The normalised key, as built (`zutable/sort.h`): each
  key's value becomes its ordinal, shifted to start at 0 over the
  column's range (so a narrow key takes few bits and the radix skips
  what it does not use), reversed for `decreasing`, with one slot for
  missing values at the end `na.last` names. Codes of several keys are
  packed, last key lowest, into a 32-bit key beside the row in one
  64-bit word, or a 64-bit key beside it in 16 bytes; keys wider than
  64 bits together are sorted in chunks, last chunk first, each pass
  stable. The hybrid (`hybrid.inc`) is Vergesort in front and, between
  runs, insertion sort below 24, counting sort when the codes span fewer
  values than there are rows and fewer than 4096 (its counts in L1;
  past 2^12 values radix wins at every n on the uniform shapes, not on
  Zipf at 10^4 and 10^5, where the cap costs up to 2x: kept until the
  tuning stage, benchmarks 2026-11-17), pdqsort below 1000, LSD radix with 8-bit
  digits (11-bit for keys of 17 to 22 bits, or 17 to 19 from 10^6 rows)
  up to 32 bits, ska sort
  above, and one MSD pass then LSD from 10^6 rows: each threshold read
  off the regime map in `.agents/benchmarks.md`. 2026-11-17, Stage 11.
- **D41 (C).** The ladder's controls are the heapsort that pdqsort
  already carries and the ported originals; fluxsort, crumsort and
  swenson's `sort.h` are not vendored. §4.3 admits the vendored sorts
  only if the hybrid's numbers against base radix and data.table need
  explaining, and they do not (benchmarks, Stage 11); the ports carry
  their licences in their files and `inst/COPYRIGHTS`, and
  `tests/c/ports` holds each to its original at a pinned commit:
  pdqsort to the same comparisons, input by input, Vergesort and ska
  sort to the same output. 2026-11-17, Stage 11.
- **D42 (C).** Until the string sort (Stage 12), `key_order()` and
  `key_rank()` take character and raw-list keys through base R: each
  string key becomes its rank in base radix order of the UTF-8 text
  (byte order, as §6.3 says), each raw list its rank as hexadecimal
  text, and the kernel sorts the codes. Neither function has `collate`
  yet; Stage 12 adds it with `stringi`. The executor sorts on the kernel
  unless a key is a string. 2026-11-17, Stage 11.
- **D43 (C).** `key_rank()` follows `rank()` for missing values: under
  `"min"` and `"first"` each row with a missing key takes a rank of its
  own, in order, as `rank()` ranks `NA`; `na.last = NA` drops those rows
  and `"keep"` gives them `NA`, the others ranked among themselves.
  Under `"dense"`, which has no base equivalent, the rows of one missing
  key share a rank, as `grp(sort = TRUE)` would number them.
  2026-11-17, Stage 11.
- **D44 (C).** Axis O's answer: `grp(sort = TRUE)` over fixed-width keys
  sorts every row and cuts the runs (`zt_groups_by_sort`) below 10^6
  rows, where it won at every share of distinct keys measured, and from
  10^6 rows when Chao1 over 1024 sampled rows puts the distinct keys at
  1% of the rows or more; otherwise, and for strings and raw lists, it
  hashes and sorts the distinct keys. The sort ties `NA` and `NaN`, which
  are different groups (§6.1), so a run where they meet falls back to
  hashing. Measured from R at 10^3 to 10^7 rows (benchmarks, Stage 11):
  sorting wins by 1.05x to 10x below 10^6 rows, and by up to 2.85x at
  10^7 rows when every row is distinct. 2026-11-17, Stage 11.

## 14. Later versions, in the order they are expected

- **Order-dependent reductions**: median, nth, mode, ndistinct, var and
  sd, over the order permutation or a per-group table, with the same
  `broadcast` modes. `fscale()` and `fbetween()` fall out of var and
  mean.
- **Scans**: cumsum, lag, lead, diff, growth, fill forward, rank and row
  number within group, as segmented passes over `g$order`, optionally
  along a time index for irregular series.
- **Weights** on every reduction.
- **An unchained table for joins** (axis A), if the reading of §11
  finds an engine shipping one and a join profile asks for it.
- **Pivot**: longer and wider as index computations over groups and
  matches.
- **The dictionary**, as designed on 2026-10-17: `dict_new()`,
  `dict_set()`, `dict_get()`, `dict_has()`, `dict_delete()`, `dict_keys()`,
  `dict_values()`, `dict_size()`, `dict_copy()`; an external pointer whose
  protected field holds the key store, the value `VECSXP` and the
  table's metadata as a raw vector, so it survives `saveRDS()` without a
  repair step; copies of the handle are the same map; one key kind per
  dictionary, fixed at creation; deletion marks and compacts on growth.
  Returns when `zucsv` or `zuxlsx` asks for shared-string tables.
- **`zuint` keys**: `int64` and `int128` kinds once `zuint` is on CRAN,
  through its header.
- **Compressed bitsets** (CRoaring, Apache-2.0): row selections as sets,
  with union, intersection and difference; the natural representation of
  a `zutable` filter, and a 32× saving in memory traffic over logical
  vectors.
- **Heaps and top-k**: partial selection without a full sort.
- **SIMD sorting of values**: x86-simd-sort or Highway's vqsort for
  `key_sort()` in the R shared object only, if the regime map of §4.3
  shows the scalar hybrid losing on values by more than D15's margin on
  x86-64 and the arm64 result does not forbid it. The header keeps the
  scalar hybrid either way (D31).
- **Long vectors**: 64-bit indices behind the same API.
- **A sort-merge join and ordered probes**: asof, rolling and interval
  joins over sorted numeric keys, which is where the sort of §6.3 and
  the join of §6.4 meet.
- **Threads**, if the family adopts a pool; the partitioned layout is
  ready for it.
- **The `zumodel` resolver** (candidates §6.4) consumes `grp_join()`
  with `multiple = "error"` and `grp_reduce()` for aggregation.

## 15. Open questions

- **Q1.** Should `grp()` accept a data frame directly, or only
  vectors and lists? This RFC accepts both (§5); a frame is a list.
- **Q2.** Answered on 2026-11-16 by D35: the tagged table of §4 is
  adopted without building the untagged one.
- **Q3.** Removed 2026-10-20 with the dictionary; returns with it.
- **Q4.** Moved on 2026-11-16 to RFC 0074's Q7, since the kernel is no
  longer a release of its own.
- **Q5.** Which variant survives on each measured axis of §4.2, and
  where the crossovers lie (cardinality for axes D, L and O). Answered
  by `.agents/benchmarks.md` as each piece of §11 lands.
- **Q6.** Answered on 2026-11-17 by D37: a row sample, read with the
  Chao1 estimator.
- **Q7.** Whether per-statistic wrappers, `grp_sum()` and so on, should
  exist beside `grp_reduce()` for discoverability, or whether the
  bracket is the only caller that matters and D21 stands.
- **Q8.** Is the ecosystem bar `data.table` and `duckdb` with all their
  threads, or every package at one thread? D20 assumes one thread for
  the first release and records both; the maintainer's answer decides whether a
  thread pool enters `zutable` before the family has one.
- **Q9.** Answered on 2026-11-16 by D36: by translation. Whether that
  needs a `grp_reduce()` entry point taking several statistics over one
  column is decided when RFC 0074's translator is built.
- **Q10.** Whether bit-identical results with base `sum()` and `mean()`
  are worth long double in the scatter loop (axis M), answered in piece
  e of §11 with the cost measured.
- **Q11.** What the maintainer's typical inputs look like, rows,
  distinct groups and key columns at once, so that §9's regimes can be
  weighted; the §9.1 market-data shape is the one stated so far.

## 16. What this RFC does not decide

The exact probe sequence and growth factor beyond "linear, doubling", the
partition fan-out and buffer size beyond "sized to L2", the wording of
error messages beyond §7's shape, the articles' datasets, and whether
`tools/run-benchmarks` is shared through `r-actions` (R6) or stays in
the package.
