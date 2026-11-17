# zutable: roadmap

Status: draft 2026-11-17. Implements [design.md](design.md) and
[design-kernel.md](design-kernel.md).
Target: v0.1.0, the first CRAN release.
Tracking: [v0.1.0 (#1)](https://github.com/pedrobtz/zutable/issues/1), with
one sub-issue per stage;
[CRAN-submission (#23)](https://github.com/pedrobtz/zutable/issues/23).

The cut follows design D35: 0.1.0 is the design's pieces 1 to 5, the table,
the bracket, updates, joins and the whole kernel. Pieces 6 to 8 are under
[After 0.1.0](#after-010). Every query operator is built first as the
reference executor in R over base (design D29), and each kernel stage then
moves one family of operators onto C, held to the reference executor's
results.

**Kernel clock** ([design-kernel §10](design-kernel.md#10-the-experiment-how-fast-can-a-kernel-be-built-from-the-blocks)).
First kernel commit (Stage 9): —. Join working (Stage 13): —. Last kernel
piece (Stage 15): —. Hypothesis: Stage 9 to Stage 13 in 14 calendar days or
fewer.

## Stages

| Stage | Title | CI | Issue | Pull request | Done |
| --- | --- | --- | --- | --- | --- |
| 0 | [Package identity](#stage-0--package-identity) | quick | [#2](https://github.com/pedrobtz/zutable/issues/2) | [#26](https://github.com/pedrobtz/zutable/pull/26) | 2026-11-17 |
| 1 | [Types and schema](#stage-1--types-and-schema) | quick | [#3](https://github.com/pedrobtz/zutable/issues/3) | [#27](https://github.com/pedrobtz/zutable/pull/27) | 2026-11-17 |
| 2 | [Tables](#stage-2--tables) | quick | [#4](https://github.com/pedrobtz/zutable/issues/4) | [#28](https://github.com/pedrobtz/zutable/pull/28) | 2026-11-17 |
| 3 | [Vocabulary and typing](#stage-3--vocabulary-and-typing) | full | [#5](https://github.com/pedrobtz/zutable/issues/5) | [#29](https://github.com/pedrobtz/zutable/pull/29) | 2026-11-17 |
| 4 | [Bracket and plans](#stage-4--bracket-and-plans) | quick | [#6](https://github.com/pedrobtz/zutable/issues/6) | [#30](https://github.com/pedrobtz/zutable/pull/30) | 2026-11-17 |
| 5 | [Aggregates](#stage-5--aggregates) | quick | [#7](https://github.com/pedrobtz/zutable/issues/7) | | 2026-11-17 |
| 6 | [Update in place](#stage-6--update-in-place) | full | [#8](https://github.com/pedrobtz/zutable/issues/8) | | |
| 7 | [Joins and binding](#stage-7--joins-and-binding) | quick | [#9](https://github.com/pedrobtz/zutable/issues/9) | | |
| 8 | [Ergonomics tests](#stage-8--ergonomics-tests) | quick | [#10](https://github.com/pedrobtz/zutable/issues/10) | | |
| 9 | [Kernel foundation and spike](#stage-9--kernel-foundation-and-spike) | quick | [#11](https://github.com/pedrobtz/zutable/issues/11) | | |
| 10 | [Kernel groups](#stage-10--kernel-groups) | full | [#12](https://github.com/pedrobtz/zutable/issues/12) | | |
| 11 | [Kernel sort](#stage-11--kernel-sort) | full | [#13](https://github.com/pedrobtz/zutable/issues/13) | | |
| 12 | [Strings and sorted values](#stage-12--strings-and-sorted-values) | full | [#14](https://github.com/pedrobtz/zutable/issues/14) | | |
| 13 | [Kernel join and match](#stage-13--kernel-join-and-match) | quick | [#15](https://github.com/pedrobtz/zutable/issues/15) | | |
| 14 | [Kernel reduce](#stage-14--kernel-reduce) | quick | [#16](https://github.com/pedrobtz/zutable/issues/16) | | |
| 15 | [Consumer fixture, ABI and fuzz](#stage-15--consumer-fixture-abi-and-fuzz) | quick | [#17](https://github.com/pedrobtz/zutable/issues/17) | | |
| 16 | [Benchmarks and documentation](#stage-16--benchmarks-and-documentation) | quick | [#18](https://github.com/pedrobtz/zutable/issues/18) | | |
| 17 | [Assurance](#stage-17--assurance) | quick | [#19](https://github.com/pedrobtz/zutable/issues/19) | | |
| 18 | [Full CI](#stage-18--full-ci) | full | [#20](https://github.com/pedrobtz/zutable/issues/20) | | |
| 19 | [v0.1.0 readiness](#stage-19--v010-readiness) | full | [#21](https://github.com/pedrobtz/zutable/issues/21) | | |
| 20 | [Review](#stage-20--review) | full | [#22](https://github.com/pedrobtz/zutable/issues/22) | | |

## Stage 0 — Package identity

**Issue.** [#2](https://github.com/pedrobtz/zutable/issues/2), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zutable/issues/1).

**CI.** `quick`.

**Goal.** The package has its real identity, its assurance file and a CI
setup whose quick profile runs in under five minutes.

**Work.**

- `DESCRIPTION`: real Title, Description and `Authors@R` (`aut`, `cre`,
  `cph`), `Depends: R (>= 4.1)`, `Language: en-GB`, MIT licence kept,
  `Version: 0.0.0.9000`.
- `.Rbuildignore` checked against the shared `r-package.md` list (already
  complete at scaffold).
- R CMD check caller: the Windows R-devel runner row and the label-skip
  `if:` of the shared `ci.md` rules; a free weekly schedule slot.
- `.agents/assurance.md` from `templates/assurance.md` with kinds
  `compiled` and `lifecycle` (design §14; `emits` arrives with the
  engines, After 0.1.0). Checks not yet wired are `gap #<issue>`.
  `assurance.yml` caller with `ungated-jobs: fail`.
- Labels `full-ci`, `ci:minimal`, `ci:docs`.
- Test runner for CI: `tools/ci-run-tests.R`, shuffled, prints its seed,
  coverage on.
- `zutable_info()` stub and the `zutable_error` condition constructor
  every later stage raises through (design §13).
- `CLAUDE.md` (written by `pkg-init`, 2026-11-16).

**Tests.**

- `zutable_info()`: returns a named list with the package version, in
  `test-info.R`.
- Condition constructor: each class of design §13 inherits from
  `zutable_error`, `expect_error(class =)`, in `test-errors.R`.

**Exit criteria.**

- `R CMD check` passes on the quick r-actions profile, and the pull
  request's quick run finishes in under five minutes.
- `assurance.yml` is green on the pull request.
- The three CI labels exist.

**Design.** [§3](design.md#3-position-in-the-zu-family),
[§13](design.md#13-errors).

## Stage 1 — Types and schema

**Issue.** [#3](https://github.com/pedrobtz/zutable/issues/3), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zutable/issues/1).

**CI.** `quick`.

**Goal.** Types and schemas exist as values: `schema()`, `field()`,
`not_null()`, `na()`, with every type of §4.1 resolved inside the capturing
functions, and the type of every R vector inferred.

**Work.**

- Type objects for every row of §4.1, parsed from bare names and strings.
- `schema()`, `field()`, `not_null()`, field and table metadata.
- `na(type)` for the typed placeholder.
- Type inference from an R vector, including `POSIXct` as
  `timestamp("us", tz)`.
- Sibling-backed types (`int64`, `decimal`, `timestamp("ns")`) raising
  `zutable_type_error` that names the package when it is absent.
- Typed nested columns: `list(T)` and `struct(...)` checked element by
  element.

**Tests.**

- Schema value: built by bare names and by strings gives `identical()`
  schemas; names unique and non-empty; in `test-schema.R`.
- Inference: a table of R vectors to their expected type (one per §4.1
  row), in `test-types.R`.
- `POSIXct` microseconds: exact integer microseconds against a hand
  computed count, and the 2³³-second range straddled at `limit − 1`,
  `limit`, `limit + 1` on both sides of 1970, in `test-types.R`.
- Missing sibling: `requireNamespace()` mocked to `FALSE` gives
  `zutable_type_error` for each sibling-backed type, in `test-types.R`.
- Nested types: a `list(int32)` holding a character element is an error;
  a valid one passes, in `test-types.R`.

**Exit criteria.**

- Every `**Tests.**` line exists, compares against its named oracle, and
  was seen to fail.
- `.agents/assurance.md` has the `POSIXct` range row under Limits.
- `R CMD check` passes on the quick profile.

**Design.** [§4.1](design.md#41-types), [§4.2](design.md#42-schema),
[§4.3](design.md#43-strictness).

## Stage 2 — Tables

**Issue.** [#4](https://github.com/pedrobtz/zutable/issues/4), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zutable/issues/1).

**CI.** `quick`.

**Goal.** A materialised `zutable` exists as a plain data.frame that
prints its schema, works under base R's value forms, and refuses every
route that would change its schema.

**Work.**

- `zutable()`, `as_zutable()` (data.frame and list; Arrow inputs are
  After 0.1.0), `is_zutable()`, `schema()`, `metadata()`, `conform()`.
- The representation of §9.1 and the one-pass schema check on entry.
- `print()` with the type row under the names.
- The value forms of §5.5 and the replacement functions of §6.5, in R.

**Tests.**

- Base compatibility: `head()`, `tail()`, `subset()`, `split()`,
  `unique()`, `lapply()` and a model formula give the same result on a
  `zutable` as on the plain frame, in `test-base-compat.R`.
- Replacement rules: `$<-`, `[[<-`, `[<-` with a fitting value keep the
  schema; a misfitting value, `names<-`, `dimnames<-` and `NULL` raise
  `zutable_schema_error`, and the table is unchanged afterwards, in
  `test-replace.R`.
- Stale schema: a table whose column was changed after `unclass()` is
  caught by the entry check, in `test-zutable.R`.
- `conform()`: one mismatch of each kind listed in the error, in
  `test-conform.R`.
- Printing: snapshot, in `test-print.R`.

**Exit criteria.**

- Every `**Tests.**` line exists, compares against its named oracle, and
  was seen to fail.
- `R CMD check` passes on the quick profile.

**Design.** [§4.4](design.md#44-creating-tables),
[§5.5](design.md#55-value-forms-for-base-r),
[§6.5](design.md#65-the-base-replacement-functions),
[§9.1](design.md#91-a-plain-dataframe).

## Stage 3 — Vocabulary and typing

**Issue.** [#5](https://github.com/pedrobtz/zutable/issues/5), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zutable/issues/1).

**CI.** `full — first Suggests guards (duckdb, DBI); the nosuggests leg
must see the vocabulary tests skip cleanly before later stages copy the
pattern`.

**Goal.** Every function of §7.1 is a row of one vocabulary table that
types it, evaluates it column at a time in R, and spells it in DuckDB's
SQL, and the three cannot disagree.

**Work.**

- The vocabulary table: names and synonyms, accepted input types, result
  type, `NA` rule, local implementation, DuckDB spelling, lineage kind
  (§8.5 rule 4).
- The type checker over expression trees, with the literal rule of §4.3
  and implicit exact widening.
- `cast()`, `case()`, `coalesce()`, `r()` with its declared type.
- Generated documentation for the vocabulary from the table.
- `duckdb` and `DBI` in `Suggests`.

**Tests.**

- Typing: every accepted and rejected input type of every row, generated
  from the table, in `test-typing.R`.
- Local semantics against base R: each row on generated inputs with `NA`,
  `NaN`, `-0`, empty and length-one vectors, in `test-vocabulary.R`.
- Local semantics against DuckDB: each row run as
  `SELECT <spelling>(...)` over the same inputs, results compared, under
  `skip_if_not_installed("duckdb")`, in `test-vocabulary-duckdb.R`.
- `int32` overflow: `+`, `-`, `*` straddled at `.Machine$integer.max ± 1`
  and at the negative end, giving `zutable_value_error`, in
  `test-vocabulary.R`.
- `cast()`: lossy casts error on the first unrepresentable value, exact
  ones round-trip, in `test-cast.R`.
- `r()`: a result of the wrong declared type is a `zutable_type_error`
  at run time, in `test-vocabulary.R`.

**Exit criteria.**

- Every `**Tests.**` line exists, compares against its named oracle, and
  was seen to fail.
- `.agents/assurance.md` has the `int32` overflow row under Limits.
- A full-profile run, `nosuggests` included, is green on the pull
  request.

**Design.** [§7.1](design.md#71-a-closed-vocabulary),
[§7.2](design.md#72-typing), [§7.3](design.md#73-the-escape),
[§4.3](design.md#43-strictness).

**Deviation, 2026-11-17.** The full run found that R's `as.double()` is
not correctly rounded on macOS arm64 (it read the largest double as
`Inf`), so `cast()` between text and doubles uses zufast's parser and
formatter: `LinkingTo: zufast` and the first C arrive here, not in
Stage 9 and Stage 6, and with them the native checks, `gctorture` and
`alloc-failure` of Stage 6's work list. Stage 6 keeps `zt_commit()` and
its `full` tier.

## Stage 4 — Bracket and plans

**Issue.** [#6](https://github.com/pedrobtz/zutable/issues/6), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zutable/issues/1).

**CI.** `quick`.

**Goal.** The bracket captures `where`, `select`, `order`, `limit` and
`distinct` and the positional shorthand, builds a typed plan whose schema
is known before execution, and the reference executor runs it.

**Work.**

- Bracket capture and clause parsing of §5.1, with the syntax errors of
  §5.1 and §5.2, `.()`, `.all` and `-name`.
- Name resolution of §5.4, including `..name` and constant folding of
  sub-expressions that mention no column.
- The plan record, obeying rules 1 to 5 of §8.5.
- `schema()` and `explain()` on plans over materialised tables.
- The reference executor for the non-aggregate clauses, with the row
  order of §8.4.

**Tests.**

- Clauses against base R: `where`, `select`, `order` (stable, `NA` last),
  `limit` and `distinct` against `[`, `order(method = "radix")`,
  `head()` and `unique()` on generated tables, in `test-bracket.R`.
- Plan schema equals result schema: for a generated set of queries,
  `schema()` of the plan is `identical()` to the schema of the executed
  result, in `test-plan.R`.
- Syntax errors: each refused form of §5.1 and §5.2 raises
  `zutable_syntax_error`, in `test-bracket-syntax.R`.
- Names: column wins over caller variable, `..name` forces the variable,
  `Sys.Date() - 7` is evaluated once, in `test-names.R`.
- Lineage readiness: rules 1 to 5 of §8.5 checked by inspecting the plan
  record of each clause, in `test-plan.R`.
- `explain()`: snapshot, in `test-explain.R`.

**Exit criteria.**

- Every `**Tests.**` line exists, compares against its named oracle, and
  was seen to fail.
- `R CMD check` passes on the quick profile.

**Design.** [§5](design.md#5-the-bracket),
[§8.2](design.md#82-explain-and-collect),
[§8.4](design.md#84-row-order),
[§8.5](design.md#85-what-a-plan-keeps-so-that-lineage-can-follow).

## Stage 5 — Aggregates

**Issue.** [#7](https://github.com/pedrobtz/zutable/issues/7), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zutable/issues/1).

**CI.** `quick`.

**Goal.** `by`, `having`, the aggregates and `over()` run in the
reference executor, with groups in order of first appearance and `NA` as
a group.

**Work.**

- Aggregate queries of §5.2 and §5.3: `by` as names, `.()`, named
  expressions and character vectors; `having` naming `select`'s results.
- Aggregates of §7.1 and `over(aggregate, by =)`.
- The reference executor over `match()`, `rowsum()` and
  `order(method = "radix")`.

**Tests.**

- Aggregates against base R: `aggregate()`, `tapply()` and `rowsum()` on
  generated tables, with `NA` keys tested apart since `aggregate()` drops
  them, in `test-aggregate.R`.
- Aggregates against DuckDB: a fixed corpus of queries with their SQL
  written by hand, results compared after sorting, under
  `skip_if_not_installed("duckdb")`, in `test-aggregate-duckdb.R`.
- Group order: first appearance, and `NA` as its own group, in
  `test-aggregate.R`.
- Refusals: a non-aggregate, non-`by` element in an aggregate query is
  `zutable_type_error`, in `test-aggregate.R`.
- `over()`: against `ave()`, in `test-over.R`.

**Exit criteria.**

- Every `**Tests.**` line exists, compares against its named oracle, and
  was seen to fail.
- `R CMD check` passes on the quick profile.

**Design.** [§5.3](design.md#53-by-having-order-limit-distinct),
[§7.1](design.md#71-a-closed-vocabulary),
[§11.1](design.md#111-the-local-executor).

## Stage 6 — Update in place

**Issue.** [#8](https://github.com/pedrobtz/zutable/issues/8), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zutable/issues/1).

**CI.** `full — first compiled code: zt_commit() replaces list elements of
an R object in place; valgrind, ASan and a dispatched step-20 gctorture
run before merging`.

**Goal.** `:=` and update blocks write existing columns in place through
`zt_commit()`, with `where` and `by`, `copy()` and `freeze()`.

**Work.**

- `zt_commit()` in `src/`, with the frozen mark checked in C.
- Infix `:=` and blocks of §6.2: sequential, locals bind values, checked
  as a whole, committed at once.
- `where` and `by` in updates (§6.3), `update =` as the named form.
- `copy()`, `freeze()`, `is_frozen()`, `frozen` in the print header.
- `:=` on anything lazy is not reachable yet; its error lands with the
  lazy class.
- `tools/alloc-exercise.R` extended to reach `zt_commit()` (the checks
  themselves were wired in Stage 3, 2026-11-17).

**Tests.**

- Block atomicity: a failing third statement leaves the first two
  unapplied, in `test-update.R`.
- Blocks against base R: the same computations written with plain
  vector arithmetic on a copy give the same columns, in `test-update.R`.
- Aliases: after `b <- a`, an update to `a` is seen in `b`, in
  `test-update-sequences.R`.
- Shared vectors: a vector shared with a plain data.frame is unchanged
  after a commit (`identical()` to a snapshot taken before), in
  `test-update-sequences.R`.
- Frozen: every write route of §6 raises `zutable_frozen_error` and
  leaves the table unchanged, through an alias too; a `copy()` of a
  frozen table can be updated without changing the original, in
  `test-freeze.R`.
- Type rule: a value of another type, a missing target and `:= NULL`
  raise `zutable_schema_error`, in `test-update.R`.
- `by` updates: one value per group or per row written, against `ave()`,
  in `test-update.R`.

**Exit criteria.**

- Every `**Tests.**` line exists, compares against its named oracle, and
  was seen to fail.
- `.agents/assurance.md` has the materialised table's row under Objects
  (sequences in `test-update-sequences.R`; fork n/a: holds no OS
  resource; unwind in `test-update.R`; owner n/a: columns are owned by
  R).
- A full-profile run is green on the pull request, and a dispatched
  step-20 gctorture run is green on its last commit.

**Design.** [§6](design.md#6-update).

## Stage 7 — Joins and binding

**Issue.** [#9](https://github.com/pedrobtz/zutable/issues/9), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zutable/issues/1).

**CI.** `quick`.

**Goal.** `join()` and `rbind()` run in the reference executor with the
row order and naming rules of §10.

**Work.**

- `join()` with `on`, every `how`, `multiple`, `na_equal`, `suffix`.
- `rbind()` requiring identical schemas.
- The reference join over `match()` and `merge()`.

**Tests.**

- Joins against base R: `merge(sort = FALSE)` turned into index pairs,
  for every `how`, in `test-join.R`.
- Joins against DuckDB: a fixed corpus with hand-written SQL, `=` for
  `na_equal = FALSE` and `IS NOT DISTINCT FROM` for `TRUE`, under
  `skip_if_not_installed("duckdb")`, in `test-join-duckdb.R`.
- Row order: `x`'s order, then `y`'s within a row of `x`, in
  `test-join.R`.
- Refusals: key types differ, a name clash without `suffix`,
  `multiple = "error"` with a duplicated key, in `test-join.R`.
- `rbind()`: identical schemas bind; any difference is a
  `zutable_schema_error`, in `test-rbind.R`.

**Exit criteria.**

- Every `**Tests.**` line exists, compares against its named oracle, and
  was seen to fail.
- `R CMD check` passes on the quick profile.

**Design.** [§10](design.md#10-joins-and-binding).

## Stage 8 — Ergonomics tests

**Issue.** [#10](https://github.com/pedrobtz/zutable/issues/10), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zutable/issues/1).

**CI.** `quick`.

**Goal.** The maintainer has chosen, on the working implementation, the
spellings design D15 leaves open, and the package follows the choice.

**Work.**

- A fixed set of real computations written in each candidate spelling of
  §19, kept in `.agents/ergonomics.md`.
- The maintainer's choices recorded in the design as decisions.
- Any spelling chosen that the package lacks, implemented.

**Tests.**

- The fixed computations: each, in the spelling kept, against a result
  computed with base R, in `test-ergonomics.R`.
- Any new spelling: its behaviours and refusals, in the test file of the
  clause it extends.

**Exit criteria.**

- Every question of the §19 ergonomics list is answered in the design.
- Every `**Tests.**` line exists, compares against its named oracle, and
  was seen to fail.
- `R CMD check` passes on the quick profile.

**Design.** [§19](design.md#19-open-questions-and-the-ergonomics-tests),
D15.

## Stage 9 — Kernel foundation and spike

**Issue.** [#11](https://github.com/pedrobtz/zutable/issues/11), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zutable/issues/1).

**CI.** `quick`.

**Goal.** The kernel's header skeleton compiles alone, the incumbents'
numbers are recorded, and the spike has tested the cost model before any
kernel code is built on it. Starts the kernel clock.

**Work.**

- `Remotes: pedrobtz/zufast@main` if the kernel needs more than the CRAN
  release (`LinkingTo: zufast` arrived in Stage 3, 2026-11-17).
- The `inst/include/zutable/` skeleton and `check-headers` (own
  workflow): every header compiles alone under `-Wall -Wextra -pedantic`
  as C11 and as C++17, and under `ZT_STANDALONE` without R.
- A C test binary that builds the header without R, and the mutation
  workflow pointed at it.
- `tools/run-benchmarks` run against the incumbents only, writing the
  §9 bar to `.agents/benchmarks.md`.
- The spike under `tools/spike/`: group and sum 10⁷ rows three ways, the
  timings beside `collapse`'s.
- The reading list, with what each source changes recorded in the
  design: DuckDB's sort posts and paper (design-kernel's Source line),
  the CAFS paper, the Vergesort, ska sort and pdqsort sources before
  Stage 11 ports them, and, for axis A, whether an engine ships
  unchained tables.
- `zutable_info()` reports the `zufast` version and build flags.

**Tests.**

- Headers: `check-headers` compiles each header alone, C11 and C++17,
  in its workflow.
- Standalone build: the C test binary builds and runs with no R headers,
  in `tests/c/`.
- `zutable_info()`: the `zufast` version matches
  `packageVersion("zufast")`, in `test-info.R`.
- Benchmark harness: every incumbent's result agrees with the others'
  canonical form before a timing is kept (rule 1 of design-kernel §9.2),
  in `tools/run-benchmarks`.

**Exit criteria.**

- `.agents/benchmarks.md` holds the incumbents' figure for every row of
  design-kernel §9.3 and the spike's three timings.
- The spike's verdict is recorded: partitioning at least 1.5× faster than
  the single array at 10⁶ and 10⁷ groups and within 1.1× at 10³ and 10⁵,
  or, below that, design-kernel §1.3 and axis L rewritten before Stage 10
  starts.
- `check-headers` and the mutation workflow run green.
- The kernel clock's first date is filled in above.
- `R CMD check` passes on the quick profile.

**Design.** [design-kernel §4](design-kernel.md#4-architecture),
[§9](design-kernel.md#9-performance-targets),
[§10](design-kernel.md#10-the-experiment-how-fast-can-a-kernel-be-built-from-the-blocks).

## Stage 10 — Kernel groups

**Issue.** [#12](https://github.com/pedrobtz/zutable/issues/12), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zutable/issues/1).

**CI.** `full — the kernel's first C that allocates and returns R vectors
through the header; valgrind, ASan and a dispatched step-20 gctorture run`.

**Goal.** The key model, the table and the partitioner exist, `grp()` is
exported, and the local executor's `by` runs on it.

**Work.**

- `key.h`, `table.h`, `partition.h`, `groups.h`.
- `grp()` with `sort = TRUE`.
- The executor's grouping moved onto `grp()`; the reference executor
  kept as the oracle.

**Tests.**

- `grp()` against base R: `match(x, unique(x))` and, for several keys,
  `interaction(drop = TRUE)` recoded to first appearance, in
  `test-grp.R`.
- `sort = TRUE` against `collapse::GRP()`, under
  `skip_if_not_installed("collapse")`, in `test-grp.R`.
- Property file: random keys of every kind with `NA`, `NaN`, `-0`, `Inf`,
  duplicated and mixed-encoding strings, sorted, reversed and constant,
  at lengths 0, 1, 2 and 10⁵, in `test-grp-property.R`.
- Row limit: 2³¹ − 1 straddled through the standalone C test with a
  declared length, in `tests/c/`.
- Executor differential: every aggregate query of Stage 5 gives the same
  result through `grp()` as through the reference executor, in
  `test-executor-kernel.R`.
- Errors: each class of design-kernel §7 for groups, in `test-grp.R`.

**Exit criteria.**

- Every `**Tests.**` line exists, compares against its named oracle, and
  was seen to fail.
- `.agents/assurance.md` has the row limit under Limits.
- The groups rows of design-kernel §9.3 have kernel numbers in
  `.agents/benchmarks.md`.
- A full-profile run is green on the pull request, and a dispatched
  step-20 gctorture run is green on its last commit.

**Design.** [design-kernel §4](design-kernel.md#4-architecture),
[§6.1](design-kernel.md#61-key-equality-per-kind),
[§6.2](design-kernel.md#62-groups).

## Stage 11 — Kernel sort

**Issue.** [#13](https://github.com/pedrobtz/zutable/issues/13), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zutable/issues/1).

**CI.** `full — C ported from Vergesort, pdqsort and ska sort with their
licences, and any vendored control; sanitizers over the radix's buffer
arithmetic`.

**Goal.** The hybrid sort of §4.3 exists over numeric, logical and
factor keys, `key_order()` and `key_rank()` are exported, and the
executor's `order` runs on them.

**Work.**

- The sort ladder harness and the hybrid, with thresholds read off the
  regime map.
- `key_order()`, `key_rank()`.
- The executor's `order` and sort-based group ids moved onto the kernel.
- Licence notices and attribution for each port; `inst/COPYRIGHTS`.

**Tests.**

- `key_order()` against `order(method = "radix")` on every kind and
  every combination of `decreasing` and `na.last`, in `test-key-order.R`.
- `key_rank()` against `rank()` for each `ties`, in `test-key-order.R`.
- Each port against the original's behaviour on the same inputs, in
  `tests/c/`.
- Executor differential: every ordered query gives the same result
  through the kernel as through the reference executor, in
  `test-executor-kernel.R`.

**Exit criteria.**

- Every `**Tests.**` line exists, compares against its named oracle, and
  was seen to fail.
- `.agents/benchmarks.md` holds the regime map and axis O's result.
- A full-profile run is green on the pull request.

**Design.** [design-kernel §4.3](design-kernel.md#43-the-sort-ladder-and-what-is-vendored),
[§6.3](design-kernel.md#63-sort-order).

## Stage 12 — Strings and sorted values

**Issue.** [#14](https://github.com/pedrobtz/zutable/issues/14), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zutable/issues/1).

**CI.** `full — a new ALTREP class, a long-lived object holding
metadata about its data pointer; valgrind and gctorture over it`.

**Goal.** Strings sort by bytes and, with `collate = TRUE`, by locale,
and `key_sort()` returns values that carry their sortedness.

**Work.**

- The string path of §6.3 and axis N, unique first.
- `collate = TRUE` through `stringi`.
- `key_sort()` and the ALTREP class carrying sorted and no-`NA` metadata.

**Tests.**

- Byte order against `order(method = "radix")` on `enc2utf8()` input, in
  `test-key-order.R`.
- Collated order against `stringi::stri_order()`, under
  `skip_if_not_installed("stringi")`; without it,
  `zutable_collate_error`, in `test-collate.R`.
- ALTREP metadata: `is.unsorted()` and `anyNA()` answer from it; a write
  through a writable `DATAPTR` drops it; `serialize()` round trip keeps
  the values, in `test-altrep.R`.

**Exit criteria.**

- Every `**Tests.**` line exists, compares against its named oracle, and
  was seen to fail.
- `.agents/assurance.md` has the sorted-values ALTREP row under Objects,
  with its write-after-read and serialize sequences.
- `.agents/benchmarks.md` holds axis N's result.
- A full-profile run is green on the pull request.

**Design.** [design-kernel §6.3](design-kernel.md#63-sort-order),
[§4.1](design-kernel.md#41-cache-conscious-layout-decided-up-front).

## Stage 13 — Kernel join and match

**Issue.** [#15](https://github.com/pedrobtz/zutable/issues/15), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zutable/issues/1).

**CI.** `quick`.

**Goal.** `grp_join()` and `grp_match()` exist and `join()` runs on them.
Closes the kernel clock's hypothesis.

**Work.**

- `join.h`, `grp_join()`, `grp_match()`, with `multiple`.
- `join()` moved onto the kernel.
- Axis F measured.

**Tests.**

- `grp_join()` against `merge(sort = FALSE)` turned into index pairs, in
  `test-grp-join.R`.
- `grp_match()` against `match()`, in `test-grp-join.R`.
- `multiple = "error"` raises `zutable_multiple_error` naming the key,
  in `test-grp-join.R`.
- Executor differential: every join of Stage 7 gives the same result
  through the kernel, in `test-executor-kernel.R`.

**Exit criteria.**

- Every `**Tests.**` line exists, compares against its named oracle, and
  was seen to fail.
- The kernel clock's join date is filled in above.
- `R CMD check` passes on the quick profile.

**Design.** [design-kernel §6.4](design-kernel.md#64-joins-and-multiple).

## Stage 14 — Kernel reduce

**Issue.** [#16](https://github.com/pedrobtz/zutable/issues/16), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zutable/issues/1).

**CI.** `quick`.

**Goal.** `grp_reduce()` with broadcast and fusion exists, and every
aggregate of the bracket reaches it.

**Work.**

- `reduce.h`, `grp_reduce()`, broadcast, fused reductions.
- The executor's aggregates moved onto `grp_reduce()`.
- Axis M measured and §6.5's accumulation rule fixed (kernel Q10).

**Tests.**

- `grp_reduce()` against the oracles of design-kernel §6.5's table, and
  `broadcast` against the same oracle indexed by `g$id`, in
  `test-grp-reduce.R`.
- Fused and separate reductions agree bit for bit, in
  `test-grp-reduce.R`.
- Executor differential: every aggregate query of Stage 5 gives the same
  result through `grp_reduce()`, in `test-executor-kernel.R`.

**Exit criteria.**

- Every `**Tests.**` line exists, compares against its named oracle, and
  was seen to fail.
- `R CMD check` passes on the quick profile.

**Design.** [design-kernel §6.5](design-kernel.md#65-reductions-and-broadcast).

## Stage 15 — Consumer fixture, ABI and fuzz

**Issue.** [#17](https://github.com/pedrobtz/zutable/issues/17), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zutable/issues/1).

**CI.** `quick`.

**Goal.** Siblings can link the header, the shared object exports one
symbol, and the fuzz target checks the kernel's invariants. Ends the
kernel clock.

**Work.**

- `tools/zutabletest`, a consumer package with `LinkingTo: zutable`,
  and `consumer.yaml` (own workflow).
- `test-abi.R`.
- The fuzz target under `ZT_STANDALONE` and the `fuzz.yml` caller.

**Tests.**

- Consumer: `tools/zutabletest` builds and runs against the installed
  header with `zutable` removed from the library path, in
  `consumer.yaml`.
- ABI: the shared object exports `R_init_zutable` only, in
  `test-abi.R`.
- Fuzz invariants: every row has an identifier, the permutation is a
  permutation with non-decreasing keys, every join pair's keys are equal,
  group sums add up to the total, in `fuzz/`.

**Exit criteria.**

- Every `**Tests.**` line exists, compares against its named oracle, and
  was seen to fail.
- A dispatched one-hour fuzz run is clean.
- The kernel clock's last date is filled in above.
- `R CMD check` passes on the quick profile.

**Design.** [design-kernel §8](design-kernel.md#8-testing),
[§12](design-kernel.md#12-acceptance-criteria-for-the-kernel).

## Stage 16 — Benchmarks and documentation

**Issue.** [#18](https://github.com/pedrobtz/zutable/issues/18), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zutable/issues/1).

**CI.** `quick`.

**Goal.** Every kernel target has a recorded number, and the Get started
vignette and the two kernel articles run against the real package.

**Work.**

- `tools/run-benchmarks` over the kernel; `.agents/benchmarks.md`
  complete.
- The Get started vignette evaluated (`pkg-docs`), with the sections for
  features After 0.1.0 removed until they land.
- The two kernel articles of piece g, under `vignettes/articles/`.

**Tests.**

- Benchmark harness: equality across oracles and the kernel before every
  timing (design-kernel §9.2), in `tools/run-benchmarks`.
- Vignette and articles: knitted with `eval = TRUE` in R CMD check and
  pkgdown, every shown output produced by the code above it.

**Exit criteria.**

- `.agents/benchmarks.md` has a number for every row of design-kernel
  §9.3, met or not.
- pkgdown builds with the vignette and both articles evaluated.
- `R CMD check` passes on the quick profile.

**Design.** [design-kernel §9](design-kernel.md#9-performance-targets).

## Stage 17 — Assurance

**Issue.** [#19](https://github.com/pedrobtz/zutable/issues/19), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zutable/issues/1).

**CI.** `quick`.

**Goal.** The package meets the shared `assurance.md` rules for
`compiled` and `lifecycle`.

**Work.**

- Every required check wired: `alloc-failure`, `mutation` on a schedule,
  `fuzz` with a `reach-floor`.
- Every row of `.agents/assurance.md` filled.
- The mutation survivors and the fuzz-reach and native-coverage gap lists
  read, missing oracles filed as issues.

**Tests.**

- Each missing oracle found: its test, in the file of the behaviour it
  checks, or a `gap #<issue>`.

**Exit criteria.**

- `assurance.yml` green.
- Every remaining `gap #<issue>` closed or moved under After 0.1.0 with a
  reason.

**Design.** [§14](design.md#14-testing).

## Stage 18 — Full CI

**Issue.** [#20](https://github.com/pedrobtz/zutable/issues/20), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zutable/issues/1).

**CI.** `full — always`.

**Goal.** The full r-actions profile and step-20 gctorture are green on
the default branch's code.

**Work.**

- Run the full profile (`full-ci`) and fix what it finds: valgrind, ASan,
  every platform leg, `nosuggests`, `nold`, cran-special.
- Dispatch gctorture at step 20 and fix what it finds, with any open
  `gctorture` issue.
- Before CRAN: `Remotes:` removed and `LinkingTo: zufast (>= <CRAN
  version>)`, the fixture rebuilt against the CRAN tarball.

**Tests.**

- Each fix: a test that failed before it, in the file of the behaviour.

**Exit criteria.**

- A full-profile run green on the pull request, a dispatched one green on
  the merge commit, and a dispatched step-20 gctorture run green on the
  pull request's last commit.
- `DESCRIPTION` carries no `Remotes:`.

**Design.** [design-kernel §12](design-kernel.md#12-acceptance-criteria-for-the-kernel).

## Stage 19 — v0.1.0 readiness

**Issue.** [#21](https://github.com/pedrobtz/zutable/issues/21), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zutable/issues/1).

**CI.** `full — always`.

**Goal.** The package is versioned and documented for submission.

**Work.**

- `Version: 0.1.0` and the matching `NEWS.md` heading.
- `cran-comments.md` listing the r-actions CI legs as test environments.
- `urlchecker::url_check()` and `spelling::spell_check_package()` clean.
- The kernel retrospective of design-kernel §10 written into this file.

**Tests.**

- None new; the suite and the checks above.

**Exit criteria.**

- A full-profile r-actions run green on the merge commit.
- URL and spelling checks clean.

**Design.** None.

## Stage 20 — Review

**Issue.** [#22](https://github.com/pedrobtz/zutable/issues/22), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zutable/issues/1).

**CI.** `full — always`.

**Goal.** The release candidate has passed the critical review and the
CRAN review.

**Work.**

1. Critical review (`pkg-critical-review`): blocking and required
   findings become sub-issues of the Review issue, fixed in one pull
   request that closes each.
2. CRAN review (`pkg-cran-review`), after those fixes, every FAIL and
   WARN resolved.

**Tests.**

- Each finding fixed: a test that failed before the fix.

**Exit criteria.**

- Every blocking and required review issue closed.
- The `pkg-cran-review` table clean.
- `NEWS.md` reflects any user-visible fix.
- A full-profile run green on the default branch, whose head becomes the
  release commit.

**Design.** None.

## After 0.1.0

- [§8.1](design.md#81-two-kinds-of-table) lazy tables,
  [§11.3](design.md#113-scans-and-sinks) scans and sinks, and
  [§12](design.md#12-arrow) Arrow: design piece 6, outside the D35 cut
  (Q6). Wait on `qio`, `zucsv` and `zuarrow` (design §16).
- [§11.4](design.md#114-engines) DuckDB and `zuspark` emitters: design
  piece 7; bring the `emits` kind and the hostile-session tests of §14.
- [§9.2](design.md#92-column-properties) column properties,
  [§9.3](design.md#93-the-index) the index, and lineage export: design
  piece 8 and D37.
- [§18](design.md#18-later-versions) and
  [design-kernel §14](design-kernel.md#14-later-versions-in-the-order-they-are-expected):
  later versions by the design's own account.

## Blocking open questions

- [design-kernel §15 Q6](design-kernel.md#15-open-questions) blocks
  Stage 10: how axis D estimates cardinality.
- [§19 Q7](design.md#19-open-questions-and-the-ergonomics-tests) blocks
  Stage 19: CRAN submission or GitHub release; the board's `CRAN intent`
  records it, assumed `Planned`.
