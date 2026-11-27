# Assurance

How this package meets the shared `assurance.md` rules. CI checks this
file (r-actions `assurance.yml`), so keep the headings and table
columns as they are.

- **Statuses:** a cell is a fact, `gap #<issue>` or `n/a: <reason>`.
- **Kinds:** delete the ones that do not apply.
- **Tables:** delete a table only when no kind requires it.

Written 2026-11-17 in Stage 0, before any code beyond the scaffold. Every
row comes from [design.md](design.md), [design-kernel.md](design-kernel.md)
and [roadmap.md](roadmap.md), so almost every cell is a gap naming the
stage issue whose pull request turns it into a fact.

## Kinds

`compiled` `lifecycle`

<!-- Evidence: compiled, src/ from the first commit (design §6.4) and the
kernel (design-kernel §4); lifecycle, the materialised table updated in
place through zt_commit() (design §6.4) and the kernel's ALTREP sorted
values (design-kernel §4.1). Not emits in 0.1.0: the SQL emitters (design
§11.4) come after it, and bring the kind with them. Not untrusted-input or
spec: files are parsed by qio, zucsv and zuarrow, not here. -->

## Required checks

`Where` names the workflow file under `.github/workflows/` that runs the
check. Add `(own)` when that workflow is the package's own rather than a
call to r-actions.

| Check         | Status  | Where              |
| ------------- | ------- | ------------------ |
| sanitizers    | done    | native-checks.yaml |
| valgrind      | done    | native-checks.yaml |
| rchk          | done    | native-checks.yaml |
| gctorture     | done    | gctorture.yaml     |
| analyzers     | done    | native-checks.yaml |
| alloc-failure | done    | alloc-failure.yaml |
| mutation      | done    | mutation.yaml      |

Stage 3 (#5) wired the native checks and `alloc-failure` on 2026-11-17,
ahead of the roadmap's Stage 6: `cast()` between text and doubles needs
zufast's correctly rounded parser and shortest formatter, the package's
first C (src/numbers.c). `tools/alloc-exercise.R` reaches both routines.
Stage 9 (#11) wired `mutation` on 2026-11-17 over the kernel's C tests
(tests/c), the first C that builds without R; `platforms.yaml` builds and
runs them on every OS, under ASan and UBSan on Linux.
Stage 15 (#17) added `fuzz.yaml` on 2026-11-19, although the package is
not `untrusted-input`: the kernel's fuzz target (tools/fuzz/) holds groups,
sort, join and reduce to invariants and to second routes, with an
equality of its own, on random key tables of every kind. The same stage
added tests/testthat/test-abi.R (the shared object exports
`R_init_zutable` only) and the consumer fixture, tools/zutabletest, built
by tools/ci/consumer.sh on every OS against the installed header and run
with zutable removed from the library.

Stage 17 (#19) read the gap lists on 2026-11-19.

- **Native coverage.** `coverage.yaml` now runs with `native: true`.
  - The routines' own argument checks, which the R layer never trips, are
    tested in tests/testthat/test-native-guards.R. That file also checks
    that a refused commit writes nothing.
  - The ALTREP class's element, inspect and order paths are tested in
    test-altrep.R.
  - The Get_region methods were removed: base R asks for a region only
    when Dataptr_or_null returns NULL, which this class never does.
  - What the lists still show:
    - The header's static inline functions are reported once per
      translation unit, so a copy that one unit never calls is listed as
      never entered, while another unit runs it in full.
    - numbers.c:30 is a short-circuit no input can take the other way.
    - `zt_str_dataptr_or_null` cannot be reached from base R.
- **Fuzz reach.** The hour's corpus reached 98.6% of the lines of
  tools/fuzz/invariants.c. `fuzz.yaml` holds it to `reach-floor: 97`. The
  unreached lines are the abort macro and `cmp_valid`'s returns, which
  coverage maps to lines no input runs. That floor is over the harness,
  not the kernel; Stage 20 below measures the headers.
- **Mutation.**
  - Earlier runs dropped test-sort, whose warm-up outran Mull's
    per-mutant timeout. The binaries now build with `ZT_TEST_QUICK`
    (sweeps to 20,000 records, quadratic checks to 1,025), the timeout is
    120 s, and the fuzz driver runs as a seventh binary.
  - Run 44490032510 killed 834 mutants. 235 survived every binary.
  - Mutants that were real gaps, now killed, each applied by hand first
    and seen failing:
    - reduce.h:115, the NA bit test (test-reduce.c now has its own
      oracle, without the kernel's `zt_f64_is_na`);
    - reduce.h:136, rounding past DBL_MAX;
    - groups.h:100, the group starts;
    - key.h:125, keys of zero columns;
    - sort.h:518, a NaN beside numbers wrongly sent to the hash fallback.
  - Mull mutates only the header. The new R tests were seen failing on
    hand-made mutants of src/: the frozen check of commit.c and the int
    Elt of altrep.c.
  - The rest are of three kinds:
    - **Equivalent:**
      - the size and range thresholds that choose between insertion,
        counting, pdqsort, LSD, MSD and ska sort (hybrid.inc, radix.inc's
        digit clamps), and the ports' own heuristics (pivot choice,
        partition balance, pattern breaking, run detection);
      - the order of the multikey quicksort's recursion, and its pivot
        (strsort.h);
      - hash mixing (key.h:56, 66), prefetch distance, table capacity and
        load limit (groups.h, join.h, table.h);
      - the partitioner's sizing and estimates (partition.h);
      - zero-length compares, and `kmin`, which is always 0 in
        `zt_counting`;
      - scratch sizing, including sort.h:100, whose permutation buffer is
        written only after the counts it would overlap are used;
      - reduce.h:104, 230 and 244, where a count is used as a flag, and
        243, ties on int max.
    - **Out of bounds:** loop bounds turned from `<` to `<=` read or write
      one past the end. Only ASan sees them, and the C tests run under it
      in `platforms.yaml`.
    - **Faster or slower only:** a bound changed so that the work is
      redone, such as the multikey quicksort resuming from byte `d - 1`.
  - None is left as a gap.

Stage 20 (#22) acted on the review of 2026-11-26.

- **Native coverage.** The hash table's growth, one-pass and partitioned,
  is driven past its estimate against `match()` in test-grp-property.R
  (#70). The key routines' remaining argument checks (row limit, unequal
  lengths, unsupported kinds) are reached in test-native-guards.R (#71).
- **Mutation.** reduce.h's `< -DBL_MAX` and sort.h's `any_missing` for a
  kind it cannot order are killed by test-reduce.c, test-sort.c and
  test-grp-reduce.R, each mutant applied by hand and seen failing (#76).
  The hand mutants of R/ that survived (a zero-length value, a row past
  the last in `[<-`, `cast()` to `timestamp("ns")`, the update routes'
  length rule, the key limit at 2³¹ − 1) are killed by tests in
  test-replace.R, test-cast.R, test-update.R and test-grp.R (#77).
- **Oracles.** The plan's schemas are checked against types and
  nullability derived by hand per clause in test-plan.R (#72). The
  executor differential has int64, enum, zoned-timestamp and struct
  columns (#78). DuckDB compares `date_trunc()` and the date parts over
  UTC timestamps, and through its ICU extension in eight zones; the ICU
  tests run where `ZUTABLE_DUCKDB_ICU=true`, which the native coverage
  run sets, and skip elsewhere (#78). dplyr is in Suggests, so the full
  legs run test-explain.R's dplyr test (#75).
- **Fuzz reach.** fuzz.yml reports reach over its compiled `sources`,
  invariants.c, and cannot name the headers. tools/fuzz/reach.sh replays
  the committed corpus (tools/fuzz/corpus, 13 inputs chosen by coverage
  from 1,500) over the headers and fails below 70%; it reached 71.3% of
  their 1,717 lines on 2026-11-26 and runs on macOS in platforms.yaml.
  c-tests.sh replays the corpus on every platform, and fuzz.yaml seeds
  from it (#73). Outside the harness: strsort.h, the distinct-key
  estimator, more than 1,024 rows and string encodings, which the kernel
  compares as bytes.
- **Floors.** Coverage fails under 90% (#92). alloc-failure has no
  `min-target-hits`: its output cannot tell a failure inside zutable.so
  from one in R, since `Rf_allocVector()`'s error names no call
  (gap #92).
- **R 4.2.** An Ubuntu R 4.2 leg in the full profile checks the
  `Depends` floor and builds altrep.c's branch for R before 4.5 (D64,
  #74).

## Objects

One row per object that outlives the call that made it. "Sequences" is
the test of its out-of-order use (abort then read, use after end, use
after free). The guard columns name the test, or say why the guard
cannot apply.

<!-- markdownlint-disable MD013 -->
| Object | Sequences | Fork | Unwind | Owner |
| --- | --- | --- | --- | --- |
| Materialised `zutable`, updated in place by `zt_commit()` | aliases, a vector shared with a plain data frame, `copy()`, base replacements, updates after queries and chains, an error mid-block then more updates: tests/testthat/test-update-sequences.R; `:=`, the bracket's `update =`, `$<-`, `[[<-`, `[<-` and `[[<-` with a row refuse a frozen table and its alias: tests/testthat/test-freeze.R; `is.na<-` goes through the typed `[<-` and is refused too, and D43's routes (`within()`, `modifyList()`, `replace()`, `droplevels()`) return a plain data frame and write nothing (#79), and `attr<-`, `attributes<-` and `levels<-` bind a changed copy and leave the frozen table and its alias as they were (D60, #69): tests/testthat/test-freeze.R | n/a: holds no OS resource; a forked child gets its own copy-on-write pages | a failing third statement leaves the first two unapplied (value and schema errors): tests/testthat/test-update.R | n/a: every column is an R vector owned by R |
| Sorted values from `key_sort()` and `grp(sort = TRUE)$keys[[1]]` (ALTREP, src/altrep.c) | read then write (`is.unsorted()`, then `[<-` in place: the marks drop and `is.unsorted()` tells the truth), write to a string element, a copy written while the original is read: tests/testthat/test-altrep.R; `serialize()` and `saveRDS()` write the plain payload, no class and no marks, and a saved result reads back in an R without zutable (#80), and hand-built streams of the old ALTREP record with each malformed or lying state give the plain payload or a `zutable_value_error`, never a crash or a believed mark (#52): tests/testthat/test-altrep.R; base reads of marked values (`sort()`, `order()`, `is.unsorted()`, `anyNA()`, with `NA`s) equal those of an unmarked copy for every type, direction and `na.last` (#56), and a wrapper with false marks shows `is.unsorted()`, `sort()` and `anyNA()` answer from them: tests/testthat/test-altrep.R | n/a: holds no OS resource; a forked child gets its own copy-on-write pages | n/a: no native memory; the payload and the marks are R objects the wrapper references, freed by R's collector | a payload shared with the caller's vector or a copy is copied before any write, never changed: tests/testthat/test-altrep.R |
<!-- markdownlint-enable MD013 -->

## Limits

One row per limit the package enforces. "Straddled by" is the test of
`limit - 1`, `limit` and `limit + 1` on every path that reaches it.

| Limit | Unit | Straddled by |
| --- | --- | --- |
| `POSIXct` instants as `timestamp("us")` | seconds from 1970, ±2³³ | tests/testthat/test-types.R: `posixct_to_us()` at ±(2³³ − 1), ±2³³ and ±(2³³ + 1); the same instants through `zutable()`, `as_zutable()`, `:=`, `$<-`, `cast()` from a string column and a string constant, and a string compared with a timestamp; and `cast()` from the last and the first whole day either side of the limit (#69) |
| `int32` arithmetic | value, ±(2³¹ − 1) | tests/testthat/test-vocabulary.R: int32 arithmetic is straddled at the overflow limit |
| Key and table length | rows, 2³¹ − 1 | tests/c/test-groups.c: table capacities for 2³¹ − 2, 2³¹ − 1 and around 7/8 of 2³¹; tests/testthat/test-grp.R: a key of 2³¹ rows is a `zutable_length_error`, and `zt_key_columns()`, every key route's check, takes 2³¹ − 1 rows and refuses 2³¹, on compact sequences (#77); tests/testthat/test-native-guards.R: `zt_grp()`, `zt_grp_sort()`, `zt_key_order()`, `zt_key_rank()` and `zt_strings_rank()` refuse 2³¹ rows before reading one (#71); a grouping of 2³¹ − 1 rows through R needs 16 GB: not run |
| Sort key packed with the row | key bits, 32 in one 64-bit word, 64 in 16 bytes, more in chunks of 64 | tests/c/test-sort.c: two keys of 31, 32 and 33 bits and of 63, 64 and 65 bits together, against a brute-force stable order; tests/testthat/test-key-order.R: three keys wider than 64 bits against `order()` |
| Counting sort's range | code values, fewer than the rows and fewer than 4096 | tests/c/test-sort.c: ranges n − 1, n and n + 1 at n = 3000, and 4095, 4096 and 4097 at n = 5000, against `qsort()` |
| The hybrid's size thresholds | records: 24 (leaf), 128 (Vergesort), 1000 (radix), 10⁶ (MSD pass) | tests/c/test-sort.c: every rung and the hybrid at 23, 24, 25, 127, 128, 129, 999, 1000, 1001, 10⁶ and 10⁶ + 1 against `qsort()`; tests/testthat/test-key-order.R: the same sizes and 1.1 × 10⁶ against `order(method = "radix")` |
| `grp(sort = TRUE)` sorting every row | rows, 10⁶; estimated distinct keys, 1% of rows | tests/c/test-sort.c: the rule at 10⁶ − 1, 10⁶ and 10⁶ + 1 rows and at 1% of 10⁶ − 1, exactly and + 1 distinct keys; tests/testthat/test-grp-sort.R: the route as R reaches it at 10⁶ − 1, 10⁶ and 10⁶ + 1 rows, and both routes against each other and base R |
| A join's pairs | pairs, 2³¹ − 1 | tests/testthat/test-grp-join.R: 2¹⁵ rows of `x` against 2¹⁶ equal keys of `y`, 2³¹ pairs, is a `zutable_length_error` on inner and left joins, raised from the count before any pair is written, while `multiple = "first"` and a semi join of the same keys succeed; 2³¹ − 1 is prime, so no join of equal keys reaches the limit exactly, and a result at or below it needs 16 GB of pairs: not run |
| `zt_reduce()`'s block | rows, 4096 a block | tests/c/test-reduce.c: 4095, 4096, 4097 and 10000 rows, every statistic and kind against a per-group loop, fused against alone; tests/testthat/test-grp-reduce.R: 4500 and 5000 rows against base R |
| The kernel's row loops at the row limit (#53) | rows, 2³¹ − 1: `zt_reduce()`'s block sweeps and the eight-row prefetch of `zt_groups_one()` and `zt_join_probe()` | tests/c/test-reduce.c: a count over 2³¹ − 1 rows and, with `ZT_TEST_LIMITS=all`, 2³¹ − 4097, 2³¹ − 4096 and 2³¹ − 2 rows and a double mean's second sweep at 2³¹ − 1; tests/c/test-groups.c: `zt_groups_one()` over 2³¹ − 1 rows and, with `ZT_TEST_LIMITS=all`, 2³¹ − 9, 2³¹ − 8 and 2³¹ − 2; each against the count it must give, ids read from a mapped sparse file (tests/c/zeros.h), red under UBSan before the fix; POSIX only, and not in the mutation build. `zt_join_probe()` writes a class per row, 8 GB at the limit, so it is fixed by the same rewrite (`i < n - 8`) and not run |
| The partitioner's threshold | estimated groups, 1,468,006.4 (a table of 8/7 slots of five bytes filling the 8 MiB L3); partitions of at most half of L2 and 16 bits | tests/c/test-groups.c: `zt_partition_bits()` at ⌊t⌋ − 1, ⌊t⌋, ⌈t⌉ and ⌈t⌉ + 1, and at 10⁷, 10⁹ and 10¹², against the bits worked out in the test (#69); tests/testthat/test-grp-property.R: forced and chosen partitions against the one-pass path and `match()` |
| The hash table's load | keys, 7/8 of the slots | tests/c/test-groups.c: 13, 14 and 15 distinct keys into 16 slots stop at 14, and repeats are taken below the limit and stopped at it (#69); tests/c/test-groups.c: capacities for 2³¹ − 2, 2³¹ − 1 and around 7/8 of 2³¹; tests/testthat/test-grp-property.R: a table that starts at 16 slots doubles past its estimate, one-pass and partitioned, against `match()` (#70) |
| The string sort's prefix and leaf | bytes, 8 (the packed prefix); strings, 16 (insertion leaf) | tests/c/test-strsort.c: strings of 0 to 23 bytes, zero bytes against the prefix's zero padding, and runs of 15, 16 and 17 strings, against `qsort()` with a full comparison |
