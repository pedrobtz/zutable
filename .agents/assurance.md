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

## Objects

One row per object that outlives the call that made it. "Sequences" is
the test of its out-of-order use (abort then read, use after end, use
after free). The guard columns name the test, or say why the guard
cannot apply.

<!-- markdownlint-disable MD013 -->
| Object | Sequences | Fork | Unwind | Owner |
| --- | --- | --- | --- | --- |
| Materialised `zutable`, updated in place by `zt_commit()` | aliases, a vector shared with a plain data frame, `copy()`, base replacements, updates after queries and chains, an error mid-block then more updates: tests/testthat/test-update-sequences.R; every write route on a frozen table and its alias: tests/testthat/test-freeze.R | n/a: holds no OS resource; a forked child gets its own copy-on-write pages | a failing third statement leaves the first two unapplied (value and schema errors): tests/testthat/test-update.R | n/a: every column is an R vector owned by R |
| Sorted values from `key_sort()` (ALTREP) | gap #14 | n/a: holds no OS resource | gap #14 | gap #14 |
<!-- markdownlint-enable MD013 -->

## Limits

One row per limit the package enforces. "Straddled by" is the test of
`limit - 1`, `limit` and `limit + 1` on every path that reaches it.

| Limit | Unit | Straddled by |
| --- | --- | --- |
| `POSIXct` instants as `timestamp("us")` | seconds from 1970, ±2³³ | tests/testthat/test-types.R: the 2^33-second limit is straddled on both sides |
| `int32` arithmetic | value, ±(2³¹ − 1) | tests/testthat/test-vocabulary.R: int32 arithmetic is straddled at the overflow limit |
| Key and table length | rows, 2³¹ − 1 | tests/c/test-groups.c: table capacities for 2³¹ − 2, 2³¹ − 1 and around 7/8 of 2³¹; tests/testthat/test-grp.R: a key of 2³¹ rows is a `zutable_length_error` |
