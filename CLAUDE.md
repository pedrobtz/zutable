# CLAUDE.md

<!-- markdownlint-disable-next-line MD013 -->
This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Shared conventions

<!-- r-skills: shared-rules -->

The portfolio's shared rules (`workflow`, `r-package`, `ci`, `native-code`,
`correctness`, `assurance`) come from the
[r-skills](https://github.com/pedrobtz/r-skills) plugin's `rules/`, loaded at
session start because of the marker above. Never copy them here. Where this
file and a shared rule disagree, this file wins for this package. Cloud
sessions do not load the plugin and run without them.

## What this is

zutable gives R typed tables: a data.frame that always knows the name,
logical type (Arrow's) and nullability of every column, queried through a
bracket whose named arguments are SQL's clauses (`where`, `select`, `by`,
`having`, `order`, `limit`, `distinct`) over bare column names. The bracket
is captured and translated into typed expressions over a closed
vocabulary, so every result's schema and every type error is known before
data is touched; the same plan runs in the package's own executor, over a
file scan, or as SQL in DuckDB or `zuspark`. `:=` updates existing columns
in place through C. Beneath the local executor sits a grouped kernel
(group, sort, join, reduce) with a C header for siblings. No `Imports`;
`LinkingTo: zufast` from the first kernel code; every reader and engine is
in `Suggests`. It deliberately does not invent an engine, add columns to
an existing table, copy data.table's surface beyond the bracket and `:=`,
use threads, or exceed 2³¹ − 1 rows.

The specification is [.agents/design.md](.agents/design.md) (from RFC 0074)
with the kernel in [.agents/design-kernel.md](.agents/design-kernel.md)
(from RFC 0037). They outrank this file: `CLAUDE.md` orients, the design
decides. Decisions marked (C) there are the RFC's and may be overturned by
the maintainer; (M) are the maintainer's.

## Current state

Scaffolded 2026-11-16 with `create-pkg.sh` (C via `use_c()`). Stage 0
(2026-11-17) gave it its identity, conditions and CI; no table
functionality yet. The roadmap in `.agents/roadmap.md` takes it to v0.1.0;
for now 0.1.0 includes the kernel (design D35).

## Versions and dependents

The current version's parent issue is
[#1](https://github.com/pedrobtz/zutable/issues/1) for `v0.1.0`. Sibling packages that depend on
this one before CRAN does: none. Planned header consumers (`zucsv`,
`zuxlsx`, `zudedup`, `zulm`) are listed in design-kernel §3. zutable cannot
reach CRAN before `zufast` (on CRAN since 2026-11-16) and needs `zuarrow`'s
release for its Arrow paths.

## Commands

The shared commands, and for the kernel:

```sh
sh tools/ci/c-tests.sh                        # C tests without R, ports included
R CMD INSTALL --preclean . && Rscript tools/run-benchmarks 1e7
```

Benchmark only after `--preclean`: `load_all()` leaves `-O0` objects in
`src/` that a plain `R CMD INSTALL` reuses.

## Architecture

To be written as stages land; see `.agents/design.md`. The scaffold set up
C through `use_c()`: [src/zutable.c](src/zutable.c) registers the routines
and [src/numbers.c](src/numbers.c) wraps zufast's number parsing and
formatting (`LinkingTo: zufast`). The kernel's header goes under
`inst/include/` and `src/` stays a thin R translation over it
(design-kernel §4).

## Invariants that are easy to break

These are fixed by the design before any code exists:

- **No `Imports`.** Every sibling and engine is `Suggests`; a type whose
  vector lives in an absent sibling is a `zutable_type_error` naming it,
  never a silent degrade to double or character.
- **No route changes a table's schema.** `:=`, `$<-`, `[[<-`, `[<-` keep
  the column set and types; `names<-` and assigning `NULL` are errors.
- **`zt_commit()` swaps column pointers and never writes into a vector**,
  so a vector shared with another object is never corrupted and `copy()`
  duplicates only the list. It also enforces `freeze()` and clears column
  properties.
- **Every operator has a reference implementation in R over base**,
  written first and kept as the oracle for the kernel (D29). Do not delete
  it when the C version lands.
- **The plan keeps the six lineage rules of design §8.5** from the first
  commit (resolved references, kept expressions, source identity, …),
  although lineage is not exported in 0.1.0.
- **The kernel header compiles as C11 without R under `ZT_STANDALONE`**,
  and as C++17 (design-kernel §4, §8); nothing in `src/` is an algorithm.
- **Errors are base-R conditions** under `zutable_error`; no `cli` or
  `rlang`.

## Testing

Conformance suite: none yet; DuckDB is planned as the oracle for the
emitters and vocabulary (design §14). Helpers: none yet. Runtime: none yet.

## Continuous integration

Calls the shared r-actions workflows `r-cmd-check.yml` (profile `auto`, plus
in the full profile a Windows R-devel row, `nosuggests` and `nold`; weekly
on Mondays 02:41 UTC), `native-checks.yaml` (sanitizers with ASan,
valgrind, lto, rchk, analyzers, cran-special; valgrind reads
`tools/valgrind.supp`, which suppresses only findings whose top frame is
in DuckDB, the test oracle), `gctorture.yaml` (step 2000 on pull requests, step 20 daily and on dispatch), `alloc-failure.yaml`
(weekly, through `tools/alloc-exercise.R`, which must reach every native
routine), `coverage.yml` (badge on `gh-pages`) and `assurance.yml`
(`ungated-jobs: fail`), plus r-lib's pkgdown workflow. Dispatch gctorture
at step 20 on the branch (`gh workflow run gctorture.yaml --ref <branch>`)
before merging a change to `PROTECT`s. The kernel stages add
`check-headers`, a consumer fixture and a fuzz target. Stages marked `full`
in the roadmap: 3, 6, 10, 11, 12.

Tests run shuffled everywhere: `tests/testthat.R` and
`tools/ci-run-tests.R` print their seed, and `ZUTABLE_TEST_SEED` replays
an order.

## Vendored native code

Nothing is vendored as a file. Three sorts are ported to C from their C++
originals, each in its own template under `inst/include/zutable/` with the
original's notice and a list of what was altered, and in
`inst/COPYRIGHTS` and `Authors@R`: pdqsort (zlib, orlp/pdqsort at
`b1ef26a`) in `pdqsort.inc`, Vergesort (MIT, Morwenn/vergesort at `a1a5081`)
in `vergesort.inc`, ska sort (Boost 1.0, skarupke/ska_sort at `2c14d4b`) in
`skasort.inc`. `tools/ci/fetch-originals.sh` fetches the originals at those
commits, checking SHA-256, for `tests/c/ports`; a port changes only with
that test. fluxsort, crumsort and swenson/sort are not vendored (D41).

