# Changelog

## zutable 0.0.0.9000

- [`zutable_info()`](https://pedrobtz.github.io/zutable/reference/zutable_info.md)
  reports the package version.
- Every condition the package raises inherits from `zutable_error`.
- [`schema()`](https://pedrobtz.github.io/zutable/reference/schema.md),
  [`field()`](https://pedrobtz.github.io/zutable/reference/schema.md)
  and
  [`not_null()`](https://pedrobtz.github.io/zutable/reference/schema.md)
  describe a table’s columns with Arrow’s logical types: `int32`,
  `float64`, `string`, `date`, `timestamp(unit, tz)`, `decimal(p, s)`,
  `enum(levels)`, `list(type)`, `struct(...)` and more, read inside the
  call so they mask nothing.
  [`schema()`](https://pedrobtz.github.io/zutable/reference/schema.md)
  of a data frame infers its types.
- A `POSIXct` with no time zone is typed `timestamp("us", "UTC")`.
- `na(type)` gives a typed missing value, for placeholders.
- [`register_extension_type()`](https://pedrobtz.github.io/zutable/reference/register_extension_type.md)
  lets a package type its vector class as an Arrow extension.
- [`zutable()`](https://pedrobtz.github.io/zutable/reference/zutable.md)
  and
  [`as_zutable()`](https://pedrobtz.github.io/zutable/reference/zutable.md)
  create typed tables: plain data frames that carry their schema and
  print it under the column names. Values enter exactly or not at all.
- [`conform()`](https://pedrobtz.github.io/zutable/reference/conform.md)
  checks a table against a schema and lists every mismatch;
  [`metadata()`](https://pedrobtz.github.io/zutable/reference/conform.md)
  returns a table’s key-value pairs.
- Base R’s value forms (`x[i, ]`, `x[, j]`, `x$col`) work, so
  [`head()`](https://rdrr.io/r/utils/head.html),
  [`subset()`](https://rdrr.io/r/base/subset.html),
  [`split()`](https://rdrr.io/r/base/split.html) and
  [`unique()`](https://rdrr.io/r/base/unique.html) return zutables. No
  replacement changes a table’s schema: a value must fit its column’s
  type, and renaming or removing a column is an error.
- Expressions are written in a closed, typed vocabulary of SQL-named
  functions with R synonyms
  ([`?vocabulary`](https://pedrobtz.github.io/zutable/reference/vocabulary.md)):
  arithmetic, comparison, logic, strings, patterns, dates,
  [`cast()`](https://pedrobtz.github.io/zutable/reference/vocabulary.md),
  [`case()`](https://pedrobtz.github.io/zutable/reference/vocabulary.md),
  aggregates, and
  [`r()`](https://pedrobtz.github.io/zutable/reference/vocabulary.md) to
  run arbitrary R. Every expression is typed before any data is read,
  and every function gives the same result locally and in DuckDB.
- The bracket takes SQL’s clauses as named arguments: `where`, `select`
  (with `.all` and `-name`), `order` (with `desc()`), `limit` and
  `distinct`, run in SQL’s logical order. `x[cond, .(...)]` reads as in
  data.table, and a position that mentions no column is a value form.
- [`explain()`](https://pedrobtz.github.io/zutable/reference/explain.md)
  prints the plan that made a table, one step per line;
  `dplyr::explain()` reaches it too.
- `by`, `having` and the aggregates (`count()`,
  [`sum()`](https://rdrr.io/r/base/sum.html),
  [`mean()`](https://rdrr.io/r/base/mean.html),
  [`min()`](https://rdrr.io/r/base/Extremes.html),
  [`max()`](https://rdrr.io/r/base/Extremes.html), `first()`, `last()`,
  [`any()`](https://rdrr.io/r/base/any.html),
  [`all()`](https://rdrr.io/r/base/all.html), `count_distinct()`) make
  aggregate queries; groups come in order of first appearance and `NA`
  is a group. `over(aggregate, by = )` computes an aggregate per
  partition without collapsing rows.
- `x[, col := value]` and blocks `x[, { a := ...; b <- ...; c := ... }]`
  update existing columns in place, keeping their types, with `where`
  and `by`; a block is typed as a whole and committed at once.
  [`copy()`](https://pedrobtz.github.io/zutable/reference/zutable-update.md)
  gives an independent table;
  [`freeze()`](https://pedrobtz.github.io/zutable/reference/zutable-update.md)
  marks a table so that nothing writes to it again.
- [`join()`](https://pedrobtz.github.io/zutable/reference/join.md)
  matches two tables on keys of the same type (inner, left, right, full,
  semi and anti), with `multiple` for fan-out, `na_equal` for missing
  keys and `suffix` for clashing names;
  [`rbind()`](https://rdrr.io/r/base/cbind.html) stacks tables of
  identical schemas.
- `.col(name)` refers to a column whose name is held in a variable.
- [`zutable_info()`](https://pedrobtz.github.io/zutable/reference/zutable_info.md)
  reports the kernel header’s version and the `zufast` headers the
  package was built against; the header `zutable.h` is installed for
  other packages to use through `LinkingTo`.
