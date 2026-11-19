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

## Objects

One row per object that outlives the call that made it. "Sequences" is
the test of its out-of-order use (abort then read, use after end, use
after free). The guard columns name the test, or say why the guard
cannot apply.

<!-- markdownlint-disable MD013 -->
| Object | Sequences | Fork | Unwind | Owner |
| --- | --- | --- | --- | --- |
| Materialised `zutable`, updated in place by `zt_commit()` | aliases, a vector shared with a plain data frame, `copy()`, base replacements, updates after queries and chains, an error mid-block then more updates: tests/testthat/test-update-sequences.R; every write route on a frozen table and its alias: tests/testthat/test-freeze.R | n/a: holds no OS resource; a forked child gets its own copy-on-write pages | a failing third statement leaves the first two unapplied (value and schema errors): tests/testthat/test-update.R | n/a: every column is an R vector owned by R |
| Sorted values from `key_sort()` and `grp(sort = TRUE)$keys[[1]]` (ALTREP, src/altrep.c) | read then write (`is.unsorted()`, then `[<-` in place: the marks drop and `is.unsorted()` tells the truth), write to a string element, a copy written while the original is read, `serialize()` and `saveRDS()` round trips before and after a write: tests/testthat/test-altrep.R; a wrapper with false marks shows `is.unsorted()`, `sort()` and `anyNA()` answer from them | n/a: holds no OS resource; a forked child gets its own copy-on-write pages | n/a: no native memory; the payload and the marks are R objects the wrapper references, freed by R's collector | a payload shared with the caller's vector or a copy is copied before any write, never changed: tests/testthat/test-altrep.R |
<!-- markdownlint-enable MD013 -->

## Limits

One row per limit the package enforces. "Straddled by" is the test of
`limit - 1`, `limit` and `limit + 1` on every path that reaches it.

| Limit | Unit | Straddled by |
| --- | --- | --- |
| `POSIXct` instants as `timestamp("us")` | seconds from 1970, ±2³³ | tests/testthat/test-types.R: the 2^33-second limit is straddled on both sides |
| `int32` arithmetic | value, ±(2³¹ − 1) | tests/testthat/test-vocabulary.R: int32 arithmetic is straddled at the overflow limit |
| Key and table length | rows, 2³¹ − 1 | tests/c/test-groups.c: table capacities for 2³¹ − 2, 2³¹ − 1 and around 7/8 of 2³¹; tests/testthat/test-grp.R: a key of 2³¹ rows is a `zutable_length_error` |
| Sort key packed with the row | key bits, 32 in one 64-bit word, 64 in 16 bytes, more in chunks of 64 | tests/c/test-sort.c: two keys of 31, 32 and 33 bits and of 63, 64 and 65 bits together, against a brute-force stable order; tests/testthat/test-key-order.R: three keys wider than 64 bits against `order()` |
| Counting sort's range | code values, fewer than the rows and fewer than 4096 | tests/c/test-sort.c: ranges n − 1, n and n + 1 at n = 3000, and 4095, 4096 and 4097 at n = 5000, against `qsort()` |
| The hybrid's size thresholds | records: 24 (leaf), 128 (Vergesort), 1000 (radix), 10⁶ (MSD pass) | tests/c/test-sort.c: every rung and the hybrid at 23, 24, 25, 127, 128, 129, 999, 1000, 1001, 10⁶ and 10⁶ + 1 against `qsort()`; tests/testthat/test-key-order.R: the same sizes and 1.1 × 10⁶ against `order(method = "radix")` |
| `grp(sort = TRUE)` sorting every row | rows, 10⁶; estimated distinct keys, 1% of rows | tests/c/test-sort.c: the rule at 10⁶ − 1, 10⁶ and 10⁶ + 1 rows and at 1% of 10⁶ − 1, exactly and + 1 distinct keys; tests/testthat/test-grp-sort.R: the route as R reaches it at 10⁶ − 1, 10⁶ and 10⁶ + 1 rows, and both routes against each other and base R |
| A join's pairs | pairs, 2³¹ − 1 | tests/testthat/test-grp-join.R: 2¹⁵ rows of `x` against 2¹⁶ equal keys of `y`, 2³¹ pairs, is a `zutable_length_error` on inner and left joins, raised from the count before any pair is written, while `multiple = "first"` and a semi join of the same keys succeed; 2³¹ − 1 is prime, so no join of equal keys reaches the limit exactly, and a result at or below it needs 16 GB of pairs: not run |
| `zt_reduce()`'s block | rows, 4096 a block | tests/c/test-reduce.c: 4095, 4096, 4097 and 10000 rows, every statistic and kind against a per-group loop, fused against alone; tests/testthat/test-grp-reduce.R: 4500 and 5000 rows against base R |
| The string sort's prefix and leaf | bytes, 8 (the packed prefix); strings, 16 (insertion leaf) | tests/c/test-strsort.c: strings of 0 to 23 bytes, zero bytes against the prefix's zero padding, and runs of 15, 16 and 17 strings, against `qsort()` with a full comparison |
