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

| Check         | Status  | Where |
| ------------- | ------- | ----- |
| sanitizers    | gap #8  |       |
| valgrind      | gap #8  |       |
| rchk          | gap #8  |       |
| gctorture     | gap #8  |       |
| analyzers     | gap #8  |       |
| alloc-failure | gap #8  |       |
| mutation      | gap #11 |       |

Stage 6 (#8) wires the native checks and `alloc-failure` with
`zt_commit()`, the first C. Stage 9 (#11) wires `mutation` over the
kernel's C test binary, the first C that builds without R.

## Objects

One row per object that outlives the call that made it. "Sequences" is
the test of its out-of-order use (abort then read, use after end, use
after free). The guard columns name the test, or say why the guard
cannot apply.

<!-- markdownlint-disable MD013 -->
| Object | Sequences | Fork | Unwind | Owner |
| --- | --- | --- | --- | --- |
| Materialised `zutable`, updated in place by `zt_commit()` | gap #8 | n/a: holds no OS resource; a forked child gets its own copy-on-write pages | gap #8 | n/a: every column is an R vector owned by R |
| Sorted values from `key_sort()` (ALTREP) | gap #14 | n/a: holds no OS resource | gap #14 | gap #14 |
<!-- markdownlint-enable MD013 -->

## Limits

One row per limit the package enforces. "Straddled by" is the test of
`limit - 1`, `limit` and `limit + 1` on every path that reaches it.

| Limit | Unit | Straddled by |
| --- | --- | --- |
| `POSIXct` instants as `timestamp("us")` | seconds from 1970, ±2³³ | gap #3 |
| `int32` arithmetic | value, ±(2³¹ − 1) | gap #5 |
| Key and table length | rows, 2³¹ − 1 | gap #12 |
