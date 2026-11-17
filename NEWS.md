# zutable 0.0.0.9000

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
