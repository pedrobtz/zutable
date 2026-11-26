# RFC 0074: `zutable`, typed tables behind a SQL-shaped bracket

Adopted from [RFC 0074](https://github.com/pedrobtz/packages/blob/1014fd23b23682451e63be198f770558fa75a8e5/rfcs/not-started/0074-zutable-typed-tables-sql-bracket.md)
on 2026-11-16. This file is the single source of truth for the design;
the RFC is now a pointer here. Its kernel companion, RFC 0037, is
[design-kernel.md](design-kernel.md).

- **Status:** Proposed. Supersedes RFC 0036; RFC 0037 is its kernel
  companion (§17). This is the file `pkg-init` adopts as the package's
  `.agents/design.md`, with RFC 0037 beside it as
  `.agents/design-kernel.md`; each decision in section 15 stays the
  maintainer's until the package repository records it.
- **Date:** 2026-11-16.
- **Packages:** `zutable` (not yet created). No `Imports`. `LinkingTo:
  zufast` from the first kernel code on. `Suggests: testthat, zucsv, qio,
  zuarrow, zuint, decimal, zutempo, zugeo, zuspark, duckdb, DBI`. C of its
  own from the first commit; vendors only what RFC 0037 §4.3 names. MIT.
- **Source:** the brainstorming session of 2026-11-16 with the maintainer,
  which reopened RFC 0036 and RFC 0037 from scratch and fixed the
  decisions marked (M) in §15. An inventory taken that day of what
  `zuarrow`, `qio`, `zucsv`, `zuspark`, `quak` and the column-type
  packages implement. A web survey taken that day of data.table 1.18,
  Polars 2.0, DuckDB 2.0, the Arrow interchange standards and R 4.6's
  C API; its claims were not re-verified for this RFC and are cited as
  "the survey". A parse and dispatch check of every bracket form in §5
  and §6 under R 4.6.2. Nothing has been built.

## 1. What zutable is

A `zutable` is a data.frame that always knows its schema: the name,
logical type and nullability of every column. Queries are written in the
bracket, with SQL's clauses as named arguments and bare column names.
The bracket captures them unevaluated and translates them into typed
expressions over a closed vocabulary, so the schema of every result is
known, and every type error raised, before any data is touched. The same
plan runs in the package's own executor, over a file scan, or as SQL in
DuckDB or Spark. `:=` updates a table in place.

```r
s <- schema(id = int32, day = date, px = float64, qty = int32)
t <- scan_parquet("trades.parquet", schema = s)   # lazy; nothing is read

r <- t[where  = day >= "2026-01-01",
       select = .(vwap = sum(px * qty) / sum(qty), n = count()),
       by     = id,
       having = n > 10,
       order  = desc(vwap),
       limit  = 5]

schema(r)    # id int32, vwap float64, n int32: known before reading
explain(r)   # 4 of 40 columns read; row groups pruned on day
d <- collect(r)                      # the local executor
d <- collect(r, engine = "duckdb")   # the same plan, as SQL

d[, { vwap := round(vwap, 2) }]      # in place
```

The one-line statement that governs every decision below:

> **Every step of a computation has a schema that is known, exact and
> checked before any data is read.**

### 1.1 What changed since RFC 0036

RFC 0036 fixed a table's columns at creation and kept typed expressions,
laziness, lineage and a DuckDB backend for later versions, each waiting
on the one before. The session of 2026-11-16 inverted that order, for
five reasons:

- **A schema contract is the gap in R.** The survey ranks strict types
  and plan-time schema resolution among the best-evidenced demands, and
  found only small run-time validators in R. RFC 0036's lock was the
  right instinct in a narrow form: a restriction on one object, where a
  schema known at every step serves the same reader better.
- **A `j` that evaluates arbitrary R blocks everything else.** It cannot
  be typed, pushed down, sent to an engine or traced for lineage.
- **Speed at scale belongs to engines.** On the survey's reading of
  db-benchmark, DuckDB runs the 5 GB group-by in about 10 s against about
  35 s for data.table and collapse. A hand-off beats a race.
- **The family has no plan layer.** `zuspark` is SQL-only by decision and
  the only lazy layer in the portfolio is dbplyr. Nothing ties `qio`,
  `zucsv`, `zuarrow`, `zuspark` and DuckDB together.
- **The family has time.** Many packages are submitted before this one,
  so the first release need not be the smallest one (D7).

### 1.2 Where it sits among existing packages

- **data.table.** Taken: bare names in a bracket, `:=` in place, `by`.
  Left: untyped `j`, column creation by reference, `X[Y]` joins.
- **Polars.** Taken: strict types, typed expressions, lazy plans, early
  errors. Left: `col()`, its memory layout, unordered results.
- **DuckDB and SQL.** Taken: clause names, logical clause order,
  `UPDATE` semantics, function names. Left: a parser, an optimiser,
  out-of-core execution.
- **Arrow.** Taken: the type system, nullability, metadata, extension
  types, batch streams. Left: buffers, bitmaps, chunked columns.
- **tibble.** Taken: the representation, a plain list with a class.
  Left: its dependencies and its silent retyping.
- **dbplyr.** Taken: the idea of one front end over several engines.
  Left: DBI and the tidyverse as requirements.

No R package today offers a typed, lazy plan that installs from CRAN
without a toolchain or a dependency tree: the survey found r-polars off
CRAN since 2023 and needing Rust.

## 2. Scope

**In the design:**

- the type system and `schema()` (§4);
- the bracket with `where`, `select`, `update`, `by`, `having`, `order`,
  `limit` and `distinct`, and its positional shorthand (§5);
- `:=` in place through C, single-column, in blocks, and frozen tables
  (§6);
- the closed expression vocabulary with its `r()` escape (§7);
- materialised and lazy tables, `schema()`, `explain()`, `collect()` (§8);
- hidden column properties and an explicit index (§9);
- `join()` and `rbind()` (§10);
- the local executor, with the kernel of RFC 0037 beneath it, file scans
  through `qio`, `zucsv` and `zuarrow`, and SQL emitters for DuckDB and
  `zuspark` (§11);
- Arrow schemas and streams in and out through `zuarrow` (§12).

For now 0.1.0 includes the kernel; the cut stays flexible (D35, §16).

**Not in the design, and why:**

- **An engine of the package's own invention.** The kernel ports the
  algorithms DuckDB and Polars have proven; it does not rediscover them
  (D2).
- **Out-of-core joins and sorts, a cost-based optimiser, a SQL parser,
  lakehouse catalogues, object stores.** DuckDB and Spark do these; the
  plan is handed to them. A SQL front end is RFC 0066's to offer later.
- **Substrait.** The survey found it alive as a specification and thin
  in consumers. Engines get SQL text.
- **Adding a column to an existing table**, by reference or otherwise. A
  different column set is a different table (D4).
- **Keys set by reference, `X[Y]` joins, `.SD`, `.I`, `.GRP`,
  `with = FALSE`, `set()`, `setnames()`.** data.table's surface beyond
  the bracket's three slots and `:=` is not copied.
- **Threads, and tables beyond 2³¹ − 1 rows.** As RFC 0037 D11.
- **Pipe verbs, `let()`, `expr()`.** Deferred to the ergonomics tests of
  §19, on a working implementation.

## 3. Position in the `zu*` family

| | zutable |
| --- | --- |
| Role | R API; consumer of the family's readers; provider, header |
| R prefix | none for the table surface; `grp_` and `key_` for the kernel |
| Info function | `zutable_info()` |
| Root condition class | `zutable_error` |
| Public C prefix | `zt_` |
| From C | `LinkingTo`, for the kernel's header |
| Hides symbols | yes (R3) |
| Vendored code | the sort pieces of RFC 0037 §4.3 |
| `Depends: R` | 4.1 (R2) |
| Language | en-GB (R2) |

**Relationships**, all through `Suggests` unless stated:

- **`zufast`**: `LinkingTo`, for hashing, as RFC 0037 D4.
- **`qio`**: the Parquet scan and sink. Projection, row-group selection
  and statistics exist; the predicate logic that uses them is `zutable`'s
  (§11.3).
- **`zucsv`**: the CSV scan. Its `col_types` already error on an
  unconvertible value.
- **`zuarrow`**: Arrow schemas and streams, IPC files, and the transport
  for results from DuckDB and `zuspark`.
- **`zuint`, `decimal`, `zutempo`, `zugeo`**: the R vectors behind
  `int64`, `decimal`, nanosecond timestamps and geometry (§4.1). Absent,
  the type is an error naming the package.
- **`zuspark`, `duckdb`**: engines that receive the plan as SQL (§11.4).
- **`openlineage`**: a later consumer of the plan's column lineage (§18).

## 4. Types and schema

### 4.1 Types

Types are Arrow's logical types under Arrow's names. Each maps to one R
vector representation and one Arrow format string.

| Type | R vector | Needs |
| --- | --- | --- |
| `bool` | logical | |
| `int32` | integer | |
| `int64` | `zu_int64`, in `bit64`'s layout | `zuint` |
| `float64` | double | |
| `string` | character, UTF-8 | |
| `date` | `Date` | |
| `timestamp(unit, tz)` | `POSIXct`; `zutempo` instant for `ns` | `zutempo` |
| `decimal(p, s)` | `decimal` | `decimal` |
| `enum(levels)` | factor | |
| `binary` | list of raw | |
| `list(T)` | list whose elements are vectors of `T` | |
| `struct(...)` | data.frame column | |
| extension types | the registered class | for example `zugeo` |
| `r_class("cls")` | any S3 vector, opaque | |

- **Exact or error.** A type whose R vector lives in a sibling package
  is a `zutable_type_error` naming that package when it is absent. No
  type silently degrades to double or character. This is `zuarrow`'s
  rule, applied to every reader.
- **Extension types.** A type is a storage type, an extension name and
  parameters, as in Arrow. Sibling vector classes register under their
  extension name, in the same registry shape `zuarrow` uses, so `zugeo`
  and later classes arrive without a change here.
- **Opaque classes.** `r_class()` holds any S3 vector to its class, which
  is RFC 0036's rule (its D7) kept as the fallback. An opaque column can
  be selected, filtered on by other columns, joined along and carried;
  it has no vocabulary functions and cannot go to an engine.
- **Nested types are enforced.** A `list(int32)` column whose third
  element is a character vector is an error. R's list columns are
  untyped; this is new.
- **Narrow Arrow types widen.** `int8`, `int16` and `float32` read as
  `int32` and `float64`, which is exact. Unsigned types are Q2.
- **A `POSIXct` column is `timestamp("us", tz)`**, with `tz` from its
  `tzone` attribute (D34). Its value is the whole number of microseconds
  nearest the stored double. That count survives the trip through
  double seconds exactly for instants within 2³³ seconds of 1970, the
  years 1698 to 2242; outside them it is a `zutable_value_error`.
  Microseconds is also what `nanoarrow` and `arrow` infer for a
  `POSIXct` and what DuckDB's `TIMESTAMP` holds, each checked on
  2026-11-16. Columns read as `timestamp("s")` or `timestamp("ms")` are
  held in `POSIXct` too and keep their unit in the schema. Nanoseconds
  are not: at a 2026 date the same test recovered 0.4% of nanosecond
  counts, so `timestamp("ns")` needs `zutempo`.
- **A `POSIXct` with no time zone is `timestamp("us", "UTC")`** (D38).
  Its stored value is already an instant counted from 1970 in UTC; an
  empty `tzone` only means "print in local time". Declaring the session's
  zone would make a type depend on the machine, and a zoneless timestamp
  is wall-clock time, which a `POSIXct` is not. The constructors set such
  a column's `tzone` to `"UTC"`, so it prints in UTC, and a string literal
  compared with it is read in UTC. A file column with no zone stays
  `timestamp(unit)` with no zone, distinct from UTC.

Type names are resolved inside `schema()`, `cast()` and `na()`, which
capture their arguments; they are not exported objects, so `date` and
`list` mask nothing. A string is accepted wherever a type is, for
programmatic use.

### 4.2 Schema

```r
s <- schema(
  id  = not_null(int32),
  px  = field(decimal(18, 4), metadata = c(unit = "USD")),
  day = date,
  tags = list(string)
)
schema(x)          # the schema of any table, materialised or lazy
conform(x, s)      # x, or a zutable_schema_error listing each mismatch
metadata(x)        # table-level key-value pairs
```

A schema is an ordered set of fields. A field is a name, a type, a
nullable flag and key-value metadata; a table adds metadata of its own.
Names are unique and non-empty. `not_null` is a contract checked on every
write and at every scan. Metadata is carried, never interpreted, and
round-trips through `qio`'s and `zuarrow`'s metadata.

A schema converts to and from an Arrow schema without loss, and two
schemas compare with `identical()`.

### 4.3 Strictness

- **Types are static.** The type of an expression follows from the types
  of its inputs and never from their values.
- **Value problems are errors.** Integer overflow, a lossy `cast()`, an
  `NA` written to a `not_null` column: each is a `zutable_value_error`,
  never a changed type, a warning or a silent `NA`.
- **Widening is implicit only where exact:** `int32` to `int64` or
  `float64`. Everything else needs `cast(x, type)`, which errors on the
  first value it cannot represent.
- **A literal takes the type of its context when it is exactly
  representable there.** `A := 1` into an `int32` column is allowed;
  `A := 1.5` is not; `day >= "2026-01-01"` compares dates. A bare `NA` is
  the missing value of whatever type the context needs.

### 4.4 Creating tables

```r
zutable(id = 1:3, name = c("Ada", "Linus", "Grace"), score = NA_real_)
zutable(id = 1:3, total = na(decimal(18, 4)))   # a typed placeholder
as_zutable(x, schema = NULL)    # data.frame, list, Arrow stream or array
is_zutable(x)
copy(x)
freeze(x)                       # §6.7
is_frozen(x)
```

`zutable()` takes named vectors and recycles length-one arguments only.
`as_zutable()` infers each column's type from its R vector, or checks it
against `schema`. A column to be filled later is declared at creation
with a typed missing value, as in RFC 0036; `na(type)` covers the types
base R has no `NA` literal for. Row names are not kept.

## 5. The bracket

One bracket is one SQL statement: a query, or an update.

```r
`[.zutable`(x, i, j, by, ..., where, select, update, having, order,
            limit, distinct = FALSE)
```

### 5.1 Clauses

| SQL | Argument | Shorthand |
| --- | --- | --- |
| `FROM` | the table itself | |
| `WHERE` | `where =` | first position |
| `SELECT` | `select =` | second position |
| `UPDATE ... SET` | `update =` | second position, recognised by `:=` |
| `GROUP BY`, `PARTITION BY` | `by =` | third position |
| `HAVING` | `having =` | |
| `ORDER BY` | `order =` | |
| `LIMIT` | `limit =` | |
| `DISTINCT` | `distinct = TRUE` | |

- **Clauses run in SQL's logical order**, whatever order they are
  written in: `where`, then grouping, then `select`, then `having`,
  `distinct`, `order`, `limit`.
- **Steps are chained brackets.** `x[...][...]` is two statements, the
  second reading the first's result. Clauses inside one bracket and
  steps between brackets never mix meanings.
- **Positions are data.table's.** `x[px > 0, .(n = count()), by = id]`
  reads as it does there.
- **A clause is given once.** Naming `where =` and also filling the
  first position is a `zutable_syntax_error` whose message shows the two
  correct spellings. So is `select` with `update`.
- **A bracket always returns a table.** `x[, score]` is a one-column
  table; `x$score` and `x[["score"]]` give the vector. `drop` is accepted
  and ignored. This answers RFC 0036's Q1 the other way (D23).

### 5.2 `select`

`.(...)` whose elements are:

- a bare column name;
- `name = expression`;
- `.all`, every column of the input, in order;
- `-name` after `.all`, to leave a column out.

`*` cannot be used for the star: `.(*, C = A + B)` is a syntax error in
R, so the star is spelt `.all`. A computed element without a name is a
`zutable_syntax_error`; names in a schema are deliberate (D31).

A new column is a new table:

```r
d2 <- d[select = .(.all, notional = px * qty)]
```

When `select` holds an aggregate, or `by` is given, the statement is an
aggregate query. Every element is then an aggregate or a `by` column,
as in SQL, and anything else is a `zutable_type_error`. The `by` columns
come first in the result without being listed.

### 5.3 `by`, `having`, `order`, `limit`, `distinct`

- **`by`** is a column, `.(a, b)`, or named expressions such as
  `.(week = date_trunc("week", day))`. A character vector of names is
  accepted. `NA` in a `by` column is a group, as in SQL and data.table.
- **`having`** filters groups and may name `select`'s results.
- **`order`** is an expression or `.(...)` of them; `desc(x)` reverses
  one. It names result columns, and input columns when the query is not
  an aggregate. `NA` sorts last.
- **`limit`** is a row count applied after `order`.

### 5.4 Names

- A name that is a column is the column.
- Any other name is looked up in the caller's frame, and its value enters
  the plan as a constant.
- A sub-expression that mentions no column is evaluated once in the
  caller's frame, so `Sys.Date() - 7` and `as.Date(cutoff)` work as
  written. `count()` and `.N` are the exceptions.
- `..name` forces the caller's variable when a column has the same name.

### 5.5 Value forms, for base R

Base functions index a data.frame with values, and those forms keep
their base meaning so that `head()`, `tail()`, `subset()`, `split()`,
`unique()`, `lapply()` and model formulas work:

| Form | Meaning |
| --- | --- |
| first position is an integer or logical vector | those rows |
| second position is a character, integer or logical vector | those columns |
| `x$name`, `x[["name"]]` | the column vector |

A character vector in the first position is a `zutable_syntax_error`.

## 6. Update

### 6.1 The rule

`col := expression` writes values into a column that exists and keeps
its type. A target that does not exist, and a value of another type, are
each a `zutable_schema_error`. `col := NULL` is one too. This is SQL's
`UPDATE`: a table's values change, its schema does not (D4).

Infix `:=` always writes exactly one column. There is no
`c("A", "B") := list(...)` and no `` `:=`(A = , B = ) `` (D9).

### 6.2 Blocks

Several columns are a block:

```r
d[, {
  w <- px * qty            # a local name, not a column
  notional := w
  share    := w / sum(w)
}, by = id]
```

- A statement is `name <- expression` or `name = expression`, a local,
  or `col := expression`, an update. A bare `col := expression` in the
  second position is a block of one.
- **Statements run in order.** Each sees the columns and locals as the
  statements above left them (D10).
- **A local binds a value, not an expression.** After `tmp <- A`, a
  later `A := A + 1` does not change `tmp`. That is how a simultaneous
  update is written when one is wanted.
- **The block is checked as a whole and committed at once.** Every
  statement is typed before any data is touched. Every new column is
  computed before any is written, so a failure in the third statement
  leaves the first two unapplied.
- A block whose last statement is `.(...)` and that holds no `:=` is a
  `select` with locals.

### 6.3 `where` and `by`

With `where`, only the matching rows are written, and aggregates in the
block are computed over those rows. With `by`, an aggregate is computed
per group and written to the group's rows, so `by` acts as SQL's
`PARTITION BY`. Each right-hand side is one value or one value per row
written.

### 6.4 In place

`src/` holds `zt_commit(x, which, columns)` from the first commit. It
replaces the named columns of the data.frame `x` with `SET_VECTOR_ELT`,
clears the properties of §9.2 for those columns, and returns `x`
invisibly. The list never grows, so none of data.table's
over-allocation is needed; the survey reports that R 4.6 hid the
entry points that machinery relied on, and that their replacement is
experimental (D3, D4).

- **A commit swaps column pointers and never writes into a vector.** A
  vector shared with another table or a plain data.frame is therefore
  never corrupted (D27).
- **Aliases see the update.** After `b <- a`, `a[, { x := 1 }]` changes
  `b` too, and a function that updates its argument updates the
  caller's table. This is data.table's behaviour, accepted knowingly
  (D14).
- **`copy(x)`** returns an independent table. Because of the first
  point it duplicates the list and no column, so it costs one
  allocation.

### 6.5 The base replacement functions

`x$col <- v`, `x[["col"]] <- v` and `x[i, "col"] <- v` are R's
copy-on-modify replacements and obey the same rule: the column must
exist and `v` must fit its type under §4.3. `names<-`, `dimnames<-` and
assigning `NULL` are `zutable_schema_error`s. So no route changes a
table's schema, which is RFC 0036's lock, now a consequence and not an
option. Leaving the class with `unclass()` or `as.data.frame()` leaves
the rule.

### 6.6 Lazy tables

`:=` on a lazy table is a `zutable_syntax_error` that says to
`collect()` first. An `UPDATE` applies to a table, not to a query, and a
lazy table has nothing in memory to modify (D12).

### 6.7 Frozen tables

```r
d <- zutable(id = ids, px = prices, notional = NA_real_)
d[, { notional := px * qty }]
freeze(d)        # in place; from here on d's values do not change
```

`freeze(x)` marks a table so that `:=` and the replacement functions of
§6.5 raise `zutable_frozen_error`. Queries read a frozen table as before,
and their results are not frozen. This is data.table's request #1086
(D36).

- **It marks a point in the code.** A table is created with its
  placeholders, filled, and frozen. A reader then knows the lines
  between creation and `freeze()` are the only ones that give its
  columns their values.
- **It is the guard against D14.** `freeze()` works in place, so every
  alias is frozen, and a function handed a frozen table cannot update
  it.
- **It is one-way.** There is no way to thaw a table. `copy(x)` gives
  an independent, updatable table for one allocation (§6.4), so the
  guarantee holds for the object's life and costs nothing to work
  around openly.
- **It is enforced in C.** `zt_commit()` checks the mark, so no R-level
  route writes past it. As with the class, removing the mark by hand is
  leaving the rule.
- **It keeps what was proven.** The properties and index of §9 are
  cleared only by writes, so on a frozen table they last.

`print()` shows `frozen` in the header.

## 7. Expressions

### 7.1 A closed vocabulary

Every function allowed in a clause is a row of one table in the package.
A row gives the function's names, the input types it accepts, its result
type, its `NA` rule, its implementation in the local executor, its
spelling in each SQL dialect, and its lineage kind (§8.5). The
documentation, the type checker, the executor and the emitters are all
generated from that table or tested against it, so they cannot disagree.

A function not in the table is a `zutable_type_error` at plan time,
naming the function and the `r()` escape.

The first vocabulary, to be fixed in the package's design:

| Family | Functions |
| --- | --- |
| arithmetic | `+ - * / %/% %% ^`, `abs`, `sqrt`, `exp`, `log` |
| rounding | `round`, `floor`, `ceiling` |
| comparison | `== != < <= > >=`, `between`, `%in%` |
| logic | `& \| !`, `is.na`, `coalesce`, `ifelse`, `case` |
| types | `cast` |
| strings | `nchar`, `upper`, `lower`, `substr`, `concat`, `trim` |
| patterns | `like`, `starts_with` |
| dates | `year`, `month`, `day`, `date_trunc` |
| aggregates | `count`, `count_distinct`, `sum`, `mean`, `min`, `max` |
| aggregates, continued | `first`, `last`, `any`, `all` |
| windows | `over(aggregate, by = )` |
| ordering | `desc` |

- **Names are SQL's**, with R's spelling as a synonym where one exists:
  `toupper` for `upper`, `paste0` for `concat`, `.N` for `count()`
  (D20).
- **`case()`** takes `condition ~ value` pairs and a `.default`.
- **`over()`** computes an aggregate per partition without collapsing
  rows, for a `select` that keeps `.all`. Order-dependent windows, `lag`,
  `row_number` and running sums, are §18.

### 7.2 Typing

- Comparisons and logic give `bool`, with three-valued `NA` logic, which
  R and SQL share.
- `int32` arithmetic gives `int32` and errors on overflow; `/` always
  gives `float64`, as in R, and the emitters cast to keep SQL's integer
  division out.
- `sum()` and `mean()` of integers give `float64`, as RFC 0037 D18;
  `count()` gives `int32`.
- `where` keeps the rows whose predicate is `TRUE`. `NA` is not `TRUE`,
  as in SQL and data.table.

### 7.3 The escape

```r
d[select = .(.all, score = r(my_model(px, qty), float64))]
```

`r(expression, type)` evaluates arbitrary R with the columns in scope.
The result type is declared and checked at run time. An `r()` node runs
in the local executor only: a plan holding one cannot be handed to an
engine, and `explain()` marks the step.

### 7.4 Programming with the bracket

Caller variables need no special treatment (§5.4). A column whose name
is held in a variable is the one case bare names cannot express; `by`,
`order` and value-form selection accept character vectors, and the
spelling for the general case is left to the ergonomics tests (§19).

## 8. Plans

### 8.1 Two kinds of table

- A **materialised** `zutable` is a data.frame (§9). Each bracket is
  planned, checked and executed at once, as in data.table.
- A **lazy** `zutable_lazy` is a source, a list of steps and a schema.
  It is not a data.frame. Brackets add steps; nothing runs until
  `collect()`.

Which kind a table is follows from where it came from: `zutable()` and
`as_zutable()` materialise, `scan_*()` are lazy, and `lazy(x)` defers a
materialised table. Both kinds accept the same brackets and both answer
`schema()` without running anything.

Nothing materialises a lazy table but `collect()`. Printing one shows
its schema and plan, never rows. The survey reports duckplyr needing
caps on automatic materialisation; an explicit call needs none (D16).

### 8.2 `explain()` and `collect()`

```r
explain(x)                       # the plan, step by step, with schemas
collect(x, engine = "local")     # or "duckdb", or a connection
```

`explain()` prints each step with its output schema, the columns each
scan reads, the row groups it prunes, and any step that cannot leave
the local executor. The output is plain text with one step per line,
written to be read by a person or an agent.

### 8.3 Rewrites

Two rewrites, neither of which can change a result: a scan reads only
the columns the plan mentions, and a `where` directly above a scan is
used to skip row groups by their statistics, then applied exactly to
what was read. There is no cost model.

### 8.4 Row order

Row order is part of every result (D22):

- `where` keeps input order;
- groups come in order of first appearance;
- `join()` gives `x`'s row order, then `y`'s within a row of `x`;
- `order` is stable.

An engine that does not promise order is given a row number and an
`ORDER BY` by the emitter. `collect(x, ordered = FALSE)` waives the
guarantee and its cost.

### 8.5 What a plan keeps, so that lineage can follow

Column lineage, the record that column `X` was computed from `X`, `Y`
and `A`, comes after 0.1.0 (D37). The standard to replicate exists:
OpenLineage's `ColumnLineageDatasetFacet`, version 1-2-0, read on
2026-11-16. For each output column it lists the input fields, each a
dataset namespace, a dataset name and a field, with transformations
typed `DIRECT` or `INDIRECT` and a subtype. A separate `dataset` list
holds the inputs that affect every column, such as a filter. OpenLineage's
Spark integration derives the facet from Spark's logical plan; `zutable`
would derive it from its own.

Nothing is exported for lineage in 0.1.0, but the plan obeys six rules
from the first commit so that nothing has to be rebuilt:

1. **References are resolved.** Every column reference in an expression
   points at a column of a named step's input, not at a bare name.
2. **Expressions are kept.** Each step keeps, for each output column,
   the expression that produced it. Execution discards nothing.
3. **Sources have an identity.** A namespace and a name: a file's URI,
   an engine's table, or a name given to an in-memory table. A table
   without one is anonymous, and says so.
4. **The vocabulary knows its lineage kind.** Each function is an
   identity, a transformation or an aggregation; `case()` and
   `ifelse()` mark which arguments are conditions; functions that hide
   their input, such as `count()`, are marked as masking.
5. **A plan record is metadata only.** It can be detached from the data
   and kept without holding any table alive, so that a materialised
   result can later carry the record of how it was made.
6. **Writes outside the plan are marked, never ignored.** An update
   block is expressions like any other. A value assigned through a
   replacement function comes from outside the plan, and the column's
   lineage becomes unknown, not stale. An `r()` node depends on every
   column it mentions and is flagged opaque.

The clauses map onto the facet as follows. The subtype names are those
of OpenLineage's documentation, recalled and not re-read; the schema
itself leaves `subtype` a free string.

| Here | OpenLineage |
| --- | --- |
| a bare column in `select` | `DIRECT`, `IDENTITY` |
| a computed `select` element, a `:=` | `DIRECT`, `TRANSFORMATION` |
| an aggregate | `DIRECT`, `AGGREGATION` |
| `where`, `having` | `INDIRECT`, `FILTER` |
| `by` | `INDIRECT`, `GROUP_BY` |
| `order` | `INDIRECT`, `SORT` |
| `join()`'s `on` | `INDIRECT`, `JOIN` |
| `over()` | `INDIRECT`, `WINDOW` |
| the conditions of `case()` and `ifelse()` | `INDIRECT`, `CONDITIONAL` |

Lineage comes from the plan and never from the engine, so it is the
same whether the plan ran locally, in DuckDB or in Spark.

## 9. Representation

### 9.1 A plain data.frame

A materialised `zutable` is a list of column vectors with class
`c("zutable", "data.frame")`, compact row names, and three attributes:
`schema`, `metadata` and `properties`. There is no external pointer, no
self-reference and no over-allocation. The alternatives were weighed on
2026-11-16:

| Alternative | Why not |
| --- | --- |
| data.table's over-allocated list | exists to add columns by reference; D4 |
| an ALTREP frame that materialises on touch | hides materialisation; D16 |
| an external pointer to native storage | base R stops working on the table |

ALTREP is welcome inside columns, where siblings own it: `zuint`'s wide
integers already are ALTREP, and an Arrow-backed column class is
`zuarrow`'s to offer.

The schema attribute is checked against the columns in one pass over
the column list whenever a table enters the package, so a stale one
cannot be believed.

### 9.2 Column properties

Each column may carry proven facts: sorted ascending or descending,
unique, free of `NA`, and its minimum and maximum. They let a filter or
lookup use binary search, a join on a unique key skip its fan-out check,
a group-by on a sorted key detect runs, and a dense integer key index
directly. Parquet statistics arrive in this form.

- **Only a proof sets a property:** an `order` step, the keys of a
  group-by, scan statistics, or `assert_sorted()` and `assert_unique()`,
  which verify by scanning. There is no unchecked setter.
- **Every write clears it.** `zt_commit()` and the replacement
  functions of §6.5 are the only routes to a column.
- **A property never changes a result.** A differential test runs every
  operation with properties stripped and compares (§14).

Someone can strip the class, change a column and restore the class.
Sortedness is therefore re-verified with one `is.unsorted()` pass
before it is relied on; uniqueness has no cheap check and is Q5.

### 9.3 The index

`index(x, cols)` builds and stores a reusable index for a key: the
group object of RFC 0037 §5. Joins, lookups and group-bys on that key
reuse it. It is explicit, never automatic, cleared by a write to its
columns, and arrives with the kernel.

## 10. Joins and binding

```r
join(x, y, on, how = "inner", multiple = "all", na_equal = TRUE,
     suffix = NULL)
rbind(x, y, ...)
```

- **`on`** is a column, `.(a, b)`, or `.(id == customer_id)` where names
  differ. Each pair of key columns must have the same type.
- **`how`** is `inner`, `left`, `right`, `full`, `semi` or `anti`.
- **`multiple`** is RFC 0037 §6.4's: `all`, `first`, `last` or `error`.
- **`na_equal`** says whether an `NA` key matches an `NA` key (D33).
  `TRUE` is R's, data.table's and RFC 0037 D7's rule and the default;
  `FALSE` is SQL's. The emitters write `IS NOT DISTINCT FROM` for the
  first and `=` for the second.
- **A name clash** between non-key columns is a `zutable_schema_error`
  unless `suffix` is given. Key columns appear once, under `x`'s name
  when the two sides name them differently.
- **`rbind()`** needs identical schemas, as RFC 0036 §6.4.

`join()` is a function, not a bracket form: data.table's `X[Y]` is the
part of its syntax the session judged most confusing (D21). Asof, range
and other non-equi joins are §18.

## 11. Executors

### 11.1 The local executor

The local executor runs a plan over batches, each a data.frame of one
schema. Expressions are evaluated column at a time; grouping, ordering,
joining and reducing go to the kernel of RFC 0037.

Each operator also has a reference implementation in R over base
functions (`order(method = "radix")`, `match()`, `rowsum()`, `merge()`).
It is written first, it is what runs until a kernel piece lands, and it
stays in the test suite as the oracle the kernel is compared against
(D29).

### 11.2 The kernel

[RFC 0037](design-kernel.md) is the kernel's design and
part of this one: the key model, the table, the partitioner, and the
four families group, sort, join and reduce, with its header for
siblings. It was revised on 2026-11-16 to match this RFC (§17): the
kernel is part of 0.1.0 for now, and it ports proven algorithms and
measures only where R differs from the engines.

### 11.3 Scans and sinks

```r
scan_parquet(path, schema = NULL)   # qio
scan_csv(path, schema = NULL)       # zucsv
scan_arrow(x, schema = NULL)        # zuarrow: IPC file, stream or handle
scan_table(con, name)               # a table in DuckDB or Spark
write_parquet(x, path, ...)         # qio; x materialised or lazy
```

A source is a schema and a function that returns the next batch, the
shape of Arrow's C stream and of `qio`'s `walk_batches()`. Given
`schema`, a scan compares it with the file's schema before reading any
data and raises `zutable_schema_error` on a mismatch.

Over a stream, filters and projections run batch by batch, and the
decomposable aggregates (`count`, `sum`, `min`, `max`, `mean`, `first`,
`last`) are reduced per batch and merged, so a grouped scan of a file
larger than memory runs in bounded memory. `order`, `join()` and
`count_distinct` materialise.

### 11.4 Engines

`collect(x, engine = )` with DuckDB or a `zuspark` connection sends the
plan as SQL text in that engine's dialect, from the vocabulary table.
A materialised source is registered with the engine without a copy
where the engine allows it; a Parquet scan is passed as a path so the
engine applies its own pushdown. The result comes back through
`zuarrow` and is checked against the plan's schema, so an engine that
returns another type is an error, not a surprise (D30).

A plan with an `r()` node, or an opaque column in an expression, is a
`zutable_engine_error` at plan time.

## 12. Arrow

- `as_zutable()` accepts a `zuarrow` schema, array or stream; a stream
  becomes a lazy source.
- `arrow_stream(x)` exports a materialised or lazy table as a stream.
- A `zutable` schema and an Arrow schema convert both ways without loss,
  including nullability, metadata and extension names.

Conversion copies once, as `zuarrow` does today. Columns that stay in
Arrow memory wait on `zuarrow`'s column class.

## 13. Errors

All conditions inherit from `zutable_error`, raised from base R without
`cli` or `rlang`. The first three are raised before any data is read.

| Class | Raised when |
| --- | --- |
| `zutable_syntax_error` | a bracket form is not supported |
| `zutable_type_error` | an expression does not type, or a sibling is missing |
| `zutable_schema_error` | a schema would change, or two schemas disagree |
| `zutable_value_error` | overflow, a lossy cast, `NA` into `not_null` |
| `zutable_frozen_error` | a write to a frozen table |
| `zutable_engine_error` | a plan cannot run on the engine asked for |

A type error covers an unknown function and a wrong input type. A
syntax error's message shows the supported spelling. Messages name the
column, the step, and the types before and after:
``column `score` is float64; the update would make it string``. The
kernel's classes are RFC 0037 §7's.

## 14. Testing

`testthat` 3e. The requirement is the family's: every result is compared
with something that knows the answer.

- **The reference executor is the oracle** for the kernel and for every
  operator, on generated inputs of every type with `NA`, `NaN`, `-0`,
  empty and single-row tables.
- **Base R is the oracle for the reference executor**: `aggregate()`,
  `merge()`, `order()`, with `NA` keys tested apart since `aggregate()`
  drops them.
- **DuckDB is the oracle for the emitters and the vocabulary.** Every
  row of the vocabulary table is run locally and as emitted SQL and the
  results compared, under `skip_if_not_installed("duckdb")`. This is
  the "assert the other side" test for the SQL the package emits.
- **Typing is tested from the vocabulary table**: every accepted and
  rejected input type of every function.
- **The update rules of §6** each have a test, including that a failing
  third statement leaves the first two unapplied, that an alias sees an
  update, and that a vector shared with a plain data.frame is untouched.
- **Frozen tables**: every write route of §6 raises
  `zutable_frozen_error` and leaves the table unchanged, through an
  alias too, and a `copy()` of a frozen table can be updated without
  changing the original.
- **Properties** are tested differentially: stripped and not, same
  result.
- **Base compatibility**: the functions of §5.5 give the same result on
  a `zutable` as on the plain frame.
- **The hostile session** of the family's correctness rules applies to
  the emitters: the same SQL text under `LC_ALL=C`, `OutDec = ","`,
  `scipen = -5` and `digits = 3`.
- **Snapshots** fix the print layout and `explain()` output.

The package's assurance kinds are `compiled`, `emits` (SQL text) and
`lifecycle` (lazy sources hold single-use streams).

## 15. Decisions

Marked **(M)** when the maintainer decided it in the session of
2026-11-16 and **(C)** when this RFC decides it and the maintainer may
overturn it.

- **D1 (M).** The centre of the package is a typed plan: schema,
  expressions, plan. It supersedes RFC 0036's locked frame.
- **D2 (M).** No engine of the package's own invention. The kernel ports
  the algorithms DuckDB and Polars have proven into R's context.
- **D3 (M).** `:=` updates in place, through C from the first commit.
  Chosen again over returning a new table, which this RFC's author had
  recommended.
- **D4 (M).** `:=` only updates existing columns and keeps their types.
  A new column is a new table.
- **D5 (M).** Columns are bare names. There is no `col()`; it exists in
  Python and Rust because they cannot capture an unevaluated argument.
- **D6 (M).** SQL's clauses are named arguments of the bracket:
  `x[select = .(A, B), by = X, where = Y > A]`.
- **D7 (M).** The kernel has no fixed release and may enter 0.1.0. Many
  packages are submitted first, so a more complete first version is
  affordable. This reverses RFC 0036's D5 and its six-stage cap.
- **D8 (M).** A materialised table is a plain data.frame, there being no
  better alternative.
- **D9 (M).** Infix `:=` writes exactly one column. Several columns are
  a block, `{A := 1; B := 2}`, which diverges from data.table to avoid
  `c("A", "B") := list(1, 2)`.
- **D10 (M).** Blocks are sequential; locals bind values; a block is
  checked as a whole and committed at once.
- **D11 (M).** A new column comes from a star in `select`, giving a new
  table, and later-filled columns are typed placeholders. The star is
  spelt `.all` (C), since `*` does not parse.
- **D12 (M).** `:=` on a lazy table is an error.
- **D13 (M).** The vocabulary is closed, with `r()` as the explicit
  escape.
- **D14 (M).** Aliases see in-place updates, as in data.table; `copy()`
  exists.
- **D15 (M).** `let()`, `expr()`, pipe verbs and the spelling of `.()`
  are decided by ergonomics tests on a first implementation (§19).
- **D16 (C).** A lazy table is its own class, not a data.frame, and only
  `collect()` materialises it. ALTREP is used inside columns only.
- **D17 (C).** Column properties are set only by proofs, cleared by every
  write, and never change a result.
- **D18 (C).** The index is explicit and arrives with the kernel.
- **D19 (C).** From Arrow: nullability, field and table metadata,
  extension types as the plug-in mechanism, typed nested columns, and
  the batch stream as the internal interface.
- **D20 (C).** Vocabulary functions carry SQL's names, with R's
  spellings as synonyms.
- **D21 (C).** Joins are a function, `join()`, with RFC 0037's
  `multiple`; a name clash is an error unless `suffix` is given.
- **D22 (C).** Row order is defined for every operation and kept by
  default on every engine.
- **D23 (C).** A bracket always returns a table.
- **D24 (C).** Type names are resolved inside `schema()`, `cast()` and
  `na()` and are not exported objects.
- **D25 (C).** Result types are static. Overflow and lossy casts are
  errors. Integer `sum()` gives `float64`.
- **D26 (C).** `where` keeps `TRUE` only; `NA` in `by` is a group.
- **D27 (C).** A commit swaps column pointers and never writes into a
  vector, so `copy()` duplicates only the list.
- **D28 (C).** A clause given both by name and by position is an error;
  `update =` is the named form of the second position's `:=` block.
- **D29 (C).** Every operator has a reference implementation in R over
  base, kept as the kernel's oracle.
- **D30 (C).** Engines receive SQL text, not Substrait, and their
  results are checked against the plan's schema.
- **D31 (C).** A computed `select` element without a name is an error.
- **D32 (C).** A name that is not a column is a caller variable and
  enters the plan as a constant; a column wins a clash; `..name` forces
  the variable.
- **D33 (M).** Whether `NA` join keys match is a parameter of `join()`.
  Its name, `na_equal`, and its default, `TRUE`, are (C).
- **D34 (C).** A `POSIXct` column declares `timestamp("us", tz)`. The
  maintainer asked what an expert would recommend; this is the
  recommendation, on the evidence in §4.1.
- **D35 (M).** For now 0.1.0 includes the kernel. The cut stays
  flexible.
- **D36 (M).** Frozen tables are in the design, to control in the code
  where a table's columns get their values. That `freeze()` works in
  place and cannot be undone except by `copy()` is (C).
- **D37 (M).** Column lineage comes after 0.1.0, and the implementation
  and architecture must be able to take it. That the model is
  OpenLineage's column-lineage facet, and the six rules of §8.5, are
  (C).

- **D38 (M).** A `POSIXct` with an empty `tzone` declares
  `timestamp("us", "UTC")`, and the constructors set its `tzone` to
  `"UTC"` (§4.1). Agreed with the maintainer on 2026-11-17, on the
  recommendation recorded there; answers Q1.
- **D39 (C).** A `decimal` vector, which holds a scale but no precision,
  is inferred as `decimal(38, s)`, or `decimal(76, s)` when a value needs
  more than 38 digits: Arrow's two decimal widths, so the inferred type
  is the narrowest one an engine stores without loss. A value that is not
  a finite number (`NaN`, `Infinity`) has no Arrow type and is a
  `zutable_type_error`. 2026-11-17, Stage 1.
- **D40 (C).** The extension registry of §4.1 is
  `register_extension_type(name, ptype, storage)`: a zero-length
  prototype names the class and gives the missing value, and inference
  types a vector of that class as the extension. 2026-11-17, Stage 1.
- **D41 (C).** Until `zuint` and `zutempo` are on CRAN they are not in
  `Suggests`, since CI cannot install them; the types ask for them by a
  name held in a variable, and their tests run against hand-built
  vectors in their layouts. `na(timestamp("ns"))` waits on a
  missing-value constructor in `zutempo`. 2026-11-17, Stage 1.

- **D42 (C).** A table's own metadata is the metadata of its schema, so
  it has one home; the attributes of §9.1 are `schema` and `properties`.
  2026-11-17, Stage 2.
- **D43 (C).** Code in a namespace that does not import `zutable`, base
  R's own above all, indexes a zutable as the data frame it is, as
  data.table's `cedta()` arranges: one position selects columns, and
  `$<-`, `[[<-` and `[<-` act on a plain data frame copy, which leaves the
  caller's table untouched. The value forms of §5.5 are otherwise as
  written, which is what makes `duplicated()`, and so `unique()`, work.
  Renaming is refused in every context, since a rename changes the schema
  whoever asks (`colnames<-` reaches `dimnames<-` from base). Logical
  selections recycle as in base R. 2026-11-17, Stage 2.

- **D44 (C).** The first vocabulary covers `bool`, `int32`, `float64`,
  `string`, `date`, `timestamp` and `enum`. `int64`, `decimal`, `binary`,
  `list` and `struct` take only `is.na()`, `count()`, `coalesce()`,
  `ifelse()`, `first()` and `last()` until their siblings can be tested
  in CI; an `r_class()` column takes none (§4.1). Every row is run
  against DuckDB through its SQL spelling (§14). 2026-11-17, Stage 3.
- **D45 (C).** Strings compare by bytes, SQL's and C's order, in every
  engine and whatever the session's collation. `upper()` and `lower()`
  use R's `toupper()` and `tolower()`, which map non-ASCII letters as the
  platform's locale does; ASCII agrees everywhere. 2026-11-17, Stage 3.
- **D46 (C).** NA rules are SQL's: a missing operand gives a missing
  result, so `NA^0` and `1^NA` are `NA` (R gives 1), and `paste0()` gives
  `NA` when a part is `NA` (R writes `"NA"`); aggregates skip missing
  values and give `NA` over none, so `sum()` of nothing is `NA`.
  `ifelse()` keeps R's rule that an `NA` condition gives `NA`; `case()`
  keeps SQL's, which skips it. 2026-11-17, Stage 3.
- **D47 (C).** A `float64`'s missing value is `NA`; `NaN` is a value, as
  in Arrow: `is.na()` is false for it, and it equals itself and sorts
  above every number, as in DuckDB and PostgreSQL. R's `NA op NaN`, which
  may give `NaN`, gives `NA`. 2026-11-17, Stage 3.
- **D48 (C).** A `float64` `%/%` is `floor(x / y)` and `%%` is
  `x - y * floor(x / y)`; R's own operators differ for infinite operands
  (`-3 %/% Inf` is -1 in R). `^` is R's, which differs from IEEE 754's
  `pow()` for a negative base with an infinite exponent and a zero base
  with a negative exponent; the SQL spelling reproduces it. 2026-11-17,
  Stage 3.
- **D49 (C).** `substr(x, start, stop)` is R's, since a user writes R in
  the bracket. The set of `%in%` is constants without `NA`. A string
  literal adapts to a date or timestamp only in ISO 8601 form, read in
  the column's zone. `cast()` to text writes a double's shortest
  round-trip digits and `inf`, `-inf` and `nan`, as DuckDB does. A
  sub-expression that mentions no column is folded in the caller's frame
  unless it is `cast()`, `case()`, `count()` or `r()`. 2026-11-17,
  Stage 3.

- **D50 (C).** `explain()` and, with the lazy class, `collect()` are
  zutable's own S3 generics, and their zutable methods are also
  registered on dplyr's generics whenever dplyr is loaded, so the call
  works whichever package was attached last (dbplyr's and vctrs' pattern).
  `data.table::copy()` is not a generic and already returns an
  independent copy of a zutable, so `copy()` registers nothing. Answers
  Q4; 2026-11-17, Stage 4.
- **D51 (C).** Each result carries its plan record in a `plan`
  attribute: the source, with the record of a chained bracket's input as
  its parent, and the steps with their schemas and resolved expressions.
  Environments are stripped from it, so it holds no table alive (§8.5
  rule 5), and a value written outside the plan adds its column to the
  record's `unknown` (rule 6). `explain()` prints it. A position of the
  bracket is a clause when it is `.()`, a block, or mentions a column
  (outside function position and the right of `$` and `@`); otherwise
  it is a value form (§5.5). Same-type signatures come before mixed ones,
  so a literal takes its column's own type. 2026-11-17, Stage 4.

- **D52 (C).** An aggregate query's `by` keys are of an equatable type
  (§7.1), a sibling's `int64` or `decimal` included. An element of
  `select` that names a key again is that key, already first; any other
  element is an aggregate or an expression of the keys, which takes its
  group's value. `having` sees the result's columns, which win over the
  input's, and may aggregate the input's. `order` in an aggregate query
  names result columns only. A summary without `by` is one row even over
  no rows, as in SQL; with `by`, no rows give no groups. `over()` is for a
  query that is not an aggregate. NaN and NA are different groups; 0 and
  -0 are one. 2026-11-17, Stage 5.

- **D53 (C).** An update takes `where` and `by` only; `order`, `limit`,
  `having`, `distinct` and `select` beside it are syntax errors. A local
  of a block may not take a column's name. A block in the second position
  with no `:=` and a last statement `.(...)` is a select whose locals are
  computed row by row. An update appends an `update` step to the table's
  plan record, in place with the commit. Since the primitive `[` makes
  its result visible, an update arms a one-shot flag, as data.table does,
  so that the autoprint of `x[, a := 1]` at top level prints nothing; an
  explicit `print()` still prints. 2026-11-17, Stage 6.

- **D54 (C).** A right join is the left join of `y` with `x`: rows in
  `y`'s order, and `multiple` per row of `y`. A full join appends `y`'s
  unmatched rows, in `y`'s order, to the left join. A key column keeps
  `x`'s name and, for a row only `y` has, takes `y`'s value; it is
  nullable when either side's key is. `semi` and `anti` return `x`'s
  columns, and `multiple` does not apply to them. Keys are matched by
  value, so NaN matches NaN and 0 matches -0, and with `na_equal = FALSE`
  a row with any missing key matches nothing. `on` also takes a character
  vector of shared names. 2026-11-17, Stage 7.

- **D55 (C).** The ergonomics tests (§19, D15), on the maintainer's
  instruction to decide open questions by an expert recommendation: `.()`
  and `.all` are kept; blocks with locals make `let()` and `expr()`
  unnecessary; there are no pipe verbs in 0.1.0, chained brackets being
  the steps; D28 is kept, and an update or block in the first position is
  a syntax error that shows the second-position spelling; a column named
  by a variable is `.col(name)`, a reserved form resolved at plan time to
  the column, so types stay static (it does not reopen D5: bare names
  remain the way to write a column). 2026-11-17, Stage 8.

- **D56 (C).** The kernel's header is `inst/include/zutable.h`, an
  umbrella that includes `inst/include/zutable/<layer>.h` (`config`,
  `version`, then `key`, `table`, `partition`, `groups`, `sort`, `join`,
  `reduce` as their stages land); each compiles alone, which settles the
  two spellings design-kernel §2 and §4 gave. Its version is the
  package's, which `tools/check-headers` checks. 2026-11-17, Stage 9.

Decisions D57 to D64 were taken in Stage 20's review (#22), on the
maintainer's agreement to the recommendations of 2026-11-26.

- **D57 (M).** How D53's flag works (#61). An update arms the flag only
  when its bracket is a top-level call (`sys.nframe() == 1`). The flag
  holds a token for the update step the plan record gains, not the table,
  and a table's own token decides whether its print is skipped. A task
  callback registered in `.onLoad` clears the flag once the top-level
  expression ends, after autoprint. So `print(x[, a := 1])`, an update
  inside a function or `lapply()`, and a later `x` all print, and the
  flag keeps no table alive. 2026-11-26, Stage 20.
- **D58 (M).** How strings enter (#64), for column values, literals, enum
  levels and names alike:
  - ASCII, UTF-8 or latin1 strings are converted to UTF-8.
  - An unknown-encoded non-ASCII string is converted from the native
    encoding in a UTF-8 or latin1 locale.
  - In a C or POSIX locale it is a `zutable_value_error` naming the column
    and pointing to `Encoding<-` or `iconv()`, since its bytes have no
    meaning there.
  - A string marked `"bytes"` is refused for `string`, which is text; it
    belongs in `binary`.

  2026-11-26, Stage 20.
- **D59 (M).** What carries metadata (#66), as in Arrow, where metadata
  belongs to the field:
  - A bare column reference keeps its field's metadata, renamed or not:
    `select`, `by` keys, and the columns a join carries.
  - A computed expression gets none, `cast()` and aggregates included,
    since the package cannot know what still holds (§4.2: carried, never
    interpreted).
  - A plan over one source keeps the table's metadata, `select` and `by`
    included.
  - A join keeps `x`'s table metadata, and `rbind()` keeps its first
    table's.

  2026-11-26, Stage 20.
- **D60 (M).** D43's route returns an honest data frame (#79).
  - What leaves the class through D43, from base's `is.na<-.default`,
    `within()`, `modifyList()`, `replace()` or `droplevels()`, is a plain
    data frame. It carries no schema, plan or `frozen` attribute.
  - `is.na(x) <- i` is a user's replacement on the table. Its method
    `is.na<-.zutable` goes through the typed `[<-`, so `freeze()`,
    `not_null` and the column types hold.
  - `freeze()` protects the object, which D43's route never writes. It
    does not protect the name it is bound to.

  2026-11-26, Stage 20.
- **D61 (M).** `join(on =)` is spelled as the bracket is (#83):
  - bare names, and `c()` of bare names, are columns;
  - a quoted string is a column's name, literally;
  - names held in a variable are passed as `..keys`, evaluated in the
    caller's frame.

  2026-11-26, Stage 20.
- **D62 (M).** What conditions show (#82, #84).
  - A condition names the exported function's call, never a helper's. The
    constructor takes `call`, and entry points pass theirs.
  - An error caught while evaluating a user's argument (`limit`, `by`,
    `.col()`) keeps its message inside the package's own.

  2026-11-26, Stage 20.
- **D63 (M).** Two answers for time (#58, #63).
  - **Local times that do not exist or repeat.** Casting a date to a zoned
    timestamp, and `date_trunc()` in a zone, work on the local wall clock,
    as DuckDB and PostgreSQL do.
    - A wall time that does not exist (a spring-forward gap) is the first
      instant after the gap.
    - A wall time that occurs twice (a fall-back hour) keeps the input's
      UTC offset when the truncated time exists at that offset, and takes
      the earlier one otherwise.
    - No cast or truncation gives a silent `NA`.
  - **`NaN` behind a date or timestamp.** It is not a value (D47 is
    `float64`'s rule), so it is refused on entry as a
    `zutable_value_error`.

  2026-11-26, Stage 20.
- **D64 (M).** The `Depends: R (>= 4.1)` floor of R2 is checked by an
  Ubuntu R 4.1 leg in the full profile of R CMD check (#74). If that leg
  shows a real cost, the floor rises to the oldest R the leg passes on,
  with a dated reason, not to R 4.5. 2026-11-26, Stage 20.

## 16. Order of work

The order of work, pieces 1 to 8, became the stages of
[roadmap.md](roadmap.md) on 2026-11-17.

**What the siblings need first**, as issues in their repositories, to be
filed later; none is filed as of 2026-11-16:

- **`qio`**: an exact route for `INT64` and `DECIMAL`, or an error;
  today they read as double.
- **`zucsv`**: column selection and chunked reads; today a scan reads
  the whole file.
- **`zuarrow`**: a CRAN release, which waits on `zukomp` 0.2.0, and
  registry handlers from `zuint`, `decimal` and `zutempo`, whose issues
  are open.
- **`zuspark`**: nothing. It takes SQL and returns a stream.

## 17. What this does to RFC 0036 and RFC 0037

**RFC 0036 is superseded.** What survives it, restated here: the schema
shown under the column names in `print()`; typed placeholders; no route
that changes a schema in place; `rbind()` and join keys held to
identical types; `zutable_error` and base-R conditions; base R as
oracle. What does not: `class()` as the type, arbitrary R in `j`, the
bracket over `split()` and `eval()`, the six-stage cap, `merge()` as
the join, and its D5, D6, D12, D15 and Q1.

**RFC 0037 is the kernel companion**, revised on 2026-11-16 to match
this RFC:

- It is no longer `zutable` v0.2.0. It is the implementation of the
  local executor's operators and, for now, part of 0.1.0 (D7, D35).
- **Its §4.2 adopts and measures.** Eleven axes take the best-known
  algorithm without building the alternatives. Four are measured,
  because R differs from the engines there: F and N (interned strings),
  M (matching base `sum()` and `mean()`), and O (sorting only the
  distinct keys).
- **Its Q9 and RFC 0036's Q3 are answered.** Every `select` is
  translated, so reductions always reach `grp_reduce()`; nothing is
  evaluated per group except an `r()` node.
- **Its stage roadmap became an order of work**, pieces a to g, which
  together are piece 5 of §16 above. Its 14-day experiment is kept,
  restated without stage numbers.
- Its exported functions, its header, its §6 semantics and its §9
  harness rules stand. Its §9.3 targets are recorded, not claimed: the
  package's claim is the plan, and at scale the hand-off.

**Adopting the documents.** `pkg-init` finds a package's RFC by the file
name `NNNN-zutable-*`, and three files match:

- **This file** becomes `.agents/design.md`.
- **RFC 0037** is copied beside it as `.agents/design-kernel.md`, with
  the same "Adopted from" line and absolute links. `pkg-init` adopts one
  file, so this copy is a step by hand.
- **RFC 0036** is a pointer and is not adopted.

All three move to `started/` in the one pull request, the first two
becoming pointers to the package's two design files.

**Other documents.** `base-layer-candidates.md` §3.4, §6 and its closing
section, and RFC 0038's mention of the CRAN order, were updated on
2026-11-16. RFCs 0061, 0066, 0067 and 0068 name `zutable` as a later
consumer or as a way to lock a result's columns; a schema contract from
this RFC serves both, and they are not edited.

## 18. Later versions

- **Ordered windows**: `lag`, `lead`, `row_number`, `rank` and running
  aggregates in `over(..., order = )`, on RFC 0037 §14's scans.
- **Non-equi joins**: asof, range and rolling, over the kernel's sort.
- **Column lineage**: `lineage(x)` for any table, the record stored on
  materialised results, and export as OpenLineage's
  `ColumnLineageDatasetFacet`. §8.5 keeps the plan ready for it. The
  `openlineage` package exports no such facet class today and needs one
  first, which is `openlineage#16`.
- **A SQL front end** through `zusql` (RFC 0066), onto the same plan.
- **Sinks beyond Parquet**, and a `zulake` source once that package
  exists.
- **Arrow-backed columns**, when `zuarrow` offers the class.
- **A workspace of tables**, as RFC 0036 §12 described it.
- **Threads**, if the family adopts a pool.

### 18.1 data.table's open requests, read against this design

A second session on 2026-11-16 ranked data.table's 182 open feature
requests by upvotes, read ten in full and the rest by title. The titles,
state and upvotes of the issues below were confirmed against GitHub the
same day. Numbers are `Rdatatable/data.table` issues.

**Answered by the design:**

| Issue | Upvotes | Request | Here |
| --- | ---: | --- | --- |
| [#788](https://github.com/Rdatatable/data.table/issues/788) | 10 | a `having` argument | `having =` (§5.1) |
| [#4804](https://github.com/Rdatatable/data.table/issues/4804), [#623](https://github.com/Rdatatable/data.table/issues/623) | 11, 4 | table metadata, column labels | field and table metadata (§4.2) |
| [#819](https://github.com/Rdatatable/data.table/issues/819) | 2 | stop `NA` matching `NA` in joins | `na_equal` (§10) |
| [#1700](https://github.com/Rdatatable/data.table/issues/1700) | 8 | naming of join columns | one rule, known before the join runs (§10) |
| [#2022](https://github.com/Rdatatable/data.table/issues/2022) | 4 | error on a recycled sub-assignment | one value, or one per row written (§6.3) |
| [#1711](https://github.com/Rdatatable/data.table/issues/1711) | 0 | names in `by` | `by = .(name = expression)` (§5.3) |
| [#857](https://github.com/Rdatatable/data.table/issues/857) | 7 | any fill value for unmatched rows | `coalesce()` after a left join, typed (§7.1) |
| [#5425](https://github.com/Rdatatable/data.table/issues/5425) | 3 | tibble-like printing | the type row under the names |
| [#2334](https://github.com/Rdatatable/data.table/issues/2334) | 3 | `is.valid(DT)` | the schema check on entry (§9.1); an exported `validate()` is a candidate |
| [#1086](https://github.com/Rdatatable/data.table/issues/1086) | 8 | protect a table from any modification | `freeze()` (§6.7) |

**Candidates for later versions**, each needing its own design section:

| Issue | Upvotes | Request | Shape it would take here |
| --- | ---: | --- | --- |
| [#3161](https://github.com/Rdatatable/data.table/issues/3161) | 2 | assert a unique or non-`NA` key | `not_null` exists; declared `unique` and SQL-style `check` constraints in the schema |
| [#3747](https://github.com/Rdatatable/data.table/issues/3747) | 3 | a join followed by `:=` keeps the last match silently | an update from another table, when designed, defaults to `multiple = "error"` |
| [#4636](https://github.com/Rdatatable/data.table/issues/4636) | 1 | a column saying which side matched | `join(indicator = "name")`, an `enum` column in the result's schema |
| [#1717](https://github.com/Rdatatable/data.table/issues/1717), [#5933](https://github.com/Rdatatable/data.table/issues/5933) | 10, 1 | cross join, conditional cross join | `how = "cross"`; the conditional form with the non-equi joins |
| [#4970](https://github.com/Rdatatable/data.table/issues/4970), [#1063](https://github.com/Rdatatable/data.table/issues/1063) | 12, 18 | `across()`, `rowwise()`, `colwise()` | one expression over a set of columns chosen by name or type; the result schema is derivable |
| [#562](https://github.com/Rdatatable/data.table/issues/562) | 0 | unused factor levels as groups | an option on `by`, since an `enum`'s levels are in the schema |
| [#5959](https://github.com/Rdatatable/data.table/issues/5959) | 4 | `summary()` for tables | a summary typed per column |

**Rejected, and kept as test cases:**

| Issue | Upvotes | Request | Why not |
| --- | ---: | --- | --- |
| [#1543](https://github.com/Rdatatable/data.table/issues/1543) | 7 | infer the left side of `:=` | a target is always written out (D9) |
| [#3998](https://github.com/Rdatatable/data.table/issues/3998) | 4 | a function's named list creates columns | columns are never created implicitly (D4, D13) |
| [#3100](https://github.com/Rdatatable/data.table/issues/3100) | 1 | a `by` that persists across brackets | clauses belong to one bracket (§5.1) |

## 19. Open questions and the ergonomics tests

- **Q1.** Answered on 2026-11-16 by D34: microseconds, and on
  2026-11-17 by D38: a `POSIXct` with an empty `tzone` declares
  `timestamp("us", "UTC")`.
- **Q2.** What unsigned Arrow integers read as: `int64`, `float64`, or
  an error. Until it is answered, `schema()` refuses the unsigned
  type names with a `zutable_type_error`.
- **Q3.** Answered on 2026-11-16 by D33: a parameter of `join()`.
- **Q4.** Answered on 2026-11-17 by D50.
- **Q5.** Whether a stale `unique` property after a class round trip
  (§9.2) needs a guard, and what it costs.
- **Q6.** Answered on 2026-11-16 by D35: 0.1.0 includes the kernel for
  now. Whether it also includes the lazy scans stays open.
- **Q7.** Answered on 2026-11-26, Stage 19: 0.1.0 is a CRAN submission.
  The board's `CRAN intent` is `Planned`, and `zufast`, the one
  `LinkingTo`, is on CRAN.

**Ergonomics tests (D15).** Done on 2026-11-17, Stage 8: the
computations and the comparison are in
[ergonomics.md](ergonomics.md), and the choices are D55. On the first
working implementation, a fixed set of real computations is written in
each candidate spelling, choosing:

- `.()` against another spelling inside `select`, and `.all` for the
  star;
- whether blocks with locals make `let()` and `expr()` unnecessary;
- whether a pipe form is wanted, each verb being one bracket step;
- the rule of D28 against accepting a `:=` block in the first position;
- how a column named by a variable is written (§7.4).

## 20. What this RFC does not decide

The full vocabulary and its dialect spellings, the wording of messages
beyond §13's shape, the layout of `explain()`, the internal form of
plans and expression nodes, and the names of the stages.
