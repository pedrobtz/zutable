# zutable 0.1.0

* Initial CRAN submission.

* `zutable_info()` reports the package version.
* Every condition the package raises inherits from `zutable_error`.
* `schema()`, `field()` and `not_null()` describe a table's columns with
  Arrow's logical types: `int32`, `float64`, `string`, `date`,
  `timestamp(unit, tz)`, `decimal(p, s)`, `enum(levels)`, `list(type)`,
  `struct(...)` and more, read inside the call so they mask nothing.
  `schema()` of a data frame infers its types.
* A `POSIXct` with no time zone is typed `timestamp("us", "UTC")`.
* `na(type)` gives a typed missing value, for placeholders.
* `register_extension_type()` lets a package type its vector class as an
  Arrow extension.
* `zutable()` and `as_zutable()` create typed tables: plain data frames
  that carry their schema and print it under the column names. Values
  enter exactly or not at all.
* `conform()` checks a table against a schema and lists every mismatch;
  `metadata()` returns a table's key-value pairs.
* Base R's value forms (`x[i, ]`, `x[, j]`, `x$col`) work, so `head()`,
  `subset()`, `split()` and `unique()` return zutables. No replacement
  changes a table's schema: a value must fit its column's type, and
  renaming or removing a column is an error.
* Expressions are written in a closed, typed vocabulary of SQL-named
  functions with R synonyms (`?vocabulary`): arithmetic, comparison,
  logic, strings, patterns, dates, `cast()`, `case()`, aggregates, and
  `r()` to run arbitrary R. Every expression is typed before any data is
  read, and every function gives the same result locally and in DuckDB.
* The bracket takes SQL's clauses as named arguments: `where`, `select`
  (with `.all` and `-name`), `order` (with `desc()`), `limit` and
  `distinct`, run in SQL's logical order. `x[cond, .(...)]` reads as in
  data.table, and a position that mentions no column is a value form.
* `explain()` prints the plan that made a table, one step per line;
  `dplyr::explain()` reaches it too.
* `by`, `having` and the aggregates (`count()`, `sum()`, `mean()`,
  `min()`, `max()`, `first()`, `last()`, `any()`, `all()`,
  `count_distinct()`) make aggregate queries; groups come in order of
  first appearance and `NA` is a group. `over(aggregate, by = )` computes
  an aggregate per partition without collapsing rows.
* `x[, col := value]` and blocks `x[, { a := ...; b <- ...; c := ... }]`
  update existing columns in place, keeping their types, with `where` and
  `by`; a block is typed as a whole and committed at once. `copy()` gives
  an independent table; `freeze()` marks a table so that nothing writes
  to it again.
* `join()` matches two tables on keys of the same type (inner, left,
  right, full, semi and anti), with `multiple` for fan-out, `na_equal`
  for missing keys and `suffix` for clashing names; `rbind()` stacks
  tables of identical schemas.
* `.col(name)` refers to a column whose name is held in a variable.
* `zutable_info()` reports the kernel header's version and the `zufast`
  headers the package was built against; the header `zutable.h` is
  installed for other packages to use through `LinkingTo`.
* `grp()` groups rows by keys of any kind (integer, double, logical,
  character, factor, `integer64`, raw), in first-appearance or key order;
  the bracket's `by` runs on it. It is a hash table of five bytes a slot,
  partitioned to the cache above L3.
* `key_order()` gives the stable permutation that sorts rows by one or
  more keys, and `key_rank()` their ranks, as `order(method = "radix")`
  and `rank()` do, with `decreasing` per key and `na.last`. They run the
  kernel's hybrid sort: Vergesort's run detection in front of counting
  sort, pdqsort, LSD radix and ska sort, chosen by size and key width.
  The bracket's `order` and `grp(sort = TRUE)` run on it.
* `grp(sort = TRUE)` sorts every row instead of hashing when that is
  faster: below a million rows, and above when about 1% of the rows or
  more are distinct keys. The result is the same either way.
* `key_order()` and `key_rank()` sort strings in the kernel, by the bytes
  of their UTF-8 text, and with `collate = TRUE` in the locale's order
  through `stringi` (a `Suggests`), whose collation keys are computed once
  per distinct string; without `stringi`, `collate = TRUE` is a
  `zutable_collate_error`.
* `key_sort()` sorts values, as `sort(method = "radix")` does, and the
  result remembers that it is sorted and whether it holds `NA`, so a later
  `sort()`, `is.unsorted()` or `anyNA()` answers without a pass; modifying
  it in place forgets both. `grp(sort = TRUE)`'s first key column carries
  the same.
* `grp_join()` returns the index pairs of an inner, left, semi or anti
  join on one or several keys, in `x`'s row order and then `y`'s, with
  `multiple` to keep every match, the first, the last, or to raise a
  `zutable_multiple_error`; `grp_match()` generalises `match()` to
  several keys. `join()` now runs on them.
* `join(how = "right", multiple = "error")` counts the rows of `x` that
  match each row of `y`, as documented; it used to raise on a row of `x`
  matching several rows of `y`. The error names the side its row is in.
* `grp_reduce()` computes `sum`, `prod`, `mean`, `min`, `max`, `count`,
  `nobs`, `first` and `last` by group in one pass, several columns at once,
  with `na.rm` and a `broadcast` back to the rows (`"replace"`,
  `"subtract"`, `"divide"`). Sums and means are base R's bit for bit, in
  an R built without long double too, and a mean whose sum overflows is
  finite where base `mean()` is; a group with no values left is `NA`.
* The bracket's aggregates, `over()` and `:=` with `by` now reduce every
  group at once through `grp_reduce()`'s kernel, rather than evaluating
  each group in turn: 8 to 130 times faster at 10^6 rows, with the same
  results.
* The kernel's header, `<zutable.h>`, is usable from another package's C
  with `LinkingTo: zutable` alone, as a test package shows on every OS. The
  accumulators a caller passes to `zt_reduce()` must be aligned for
  `zt_acc` (16 bytes on x86_64, beyond what `R_alloc()` promises).
* The Get started vignette runs against the package, and two articles
  join it on the website: "Joins without surprises", on repeated keys,
  missing keys and key types, and "Measuring the kernel", the kernel's
  timings against collapse, data.table, kit and base R.
