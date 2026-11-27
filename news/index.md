# Changelog

## zutable 0.1.0

- Initial CRAN submission.

### Bug fixes

- String keys in
  [`grp()`](https://pedrobtz.github.io/zutable/reference/grp.md),
  [`grp_match()`](https://pedrobtz.github.io/zutable/reference/grp_join.md),
  [`grp_join()`](https://pedrobtz.github.io/zutable/reference/grp_join.md),
  [`grp_reduce()`](https://pedrobtz.github.io/zutable/reference/grp_reduce.md),
  `by` and
  [`join()`](https://pedrobtz.github.io/zutable/reference/join.md) match
  by text when one is unmarked (native) and its twin UTF-8, and
  [`r()`](https://pedrobtz.github.io/zutable/reference/vocabulary.md)
  returns UTF-8 strings
  ([\#50](https://github.com/pedrobtz/zutable/issues/50)).

- A string marked `"bytes"` in a key is a `zutable_value_error` from
  [`grp()`](https://pedrobtz.github.io/zutable/reference/grp.md),
  [`grp_match()`](https://pedrobtz.github.io/zutable/reference/grp_join.md),
  [`grp_join()`](https://pedrobtz.github.io/zutable/reference/grp_join.md),
  [`grp_reduce()`](https://pedrobtz.github.io/zutable/reference/grp_reduce.md),
  [`key_order()`](https://pedrobtz.github.io/zutable/reference/key_order.md),
  [`key_sort()`](https://pedrobtz.github.io/zutable/reference/key_sort.md)
  and
  [`key_rank()`](https://pedrobtz.github.io/zutable/reference/key_order.md)
  ([\#50](https://github.com/pedrobtz/zutable/issues/50),
  [\#68](https://github.com/pedrobtz/zutable/issues/68)).

- [`key_sort()`](https://pedrobtz.github.io/zutable/reference/key_sort.md)
  and `grp(sort = TRUE)` mark values sorted only when they hold no `NA`,
  so [`sort()`](https://rdrr.io/r/base/sort.html) and
  `order(na.last = NA)` of them drop the `NA`s as base R does
  ([\#56](https://github.com/pedrobtz/zutable/issues/56)).

- [`key_sort()`](https://pedrobtz.github.io/zutable/reference/key_sort.md)
  and `grp(sort = TRUE)` results save as plain vectors, so
  [`saveRDS()`](https://rdrr.io/r/base/readRDS.html) of them reads back
  where zutable is not installed
  ([\#80](https://github.com/pedrobtz/zutable/issues/80)), and a stream
  with the old sorted class is read as its plain values, its marks never
  trusted, or is a `zutable_value_error` when corrupt
  ([\#52](https://github.com/pedrobtz/zutable/issues/52)).

- [`grp_reduce()`](https://pedrobtz.github.io/zutable/reference/grp_reduce.md)
  checks a
  [`grp()`](https://pedrobtz.github.io/zutable/reference/grp.md)
  result’s shape (`id`, `n`, `sizes`, `starts`, `order`, `keys`) and
  raises a `zutable_type_error` or `zutable_value_error` for a
  hand-edited one, never coercing `n`
  ([\#68](https://github.com/pedrobtz/zutable/issues/68)).

- `key_order(collate =)` is checked for one plain vector too, and
  [`key_sort()`](https://pedrobtz.github.io/zutable/reference/key_sort.md)
  of a data frame or list of columns is a `zutable_type_error`
  ([\#68](https://github.com/pedrobtz/zutable/issues/68)).

- The native grouping and join routines check every key column’s length,
  not only the first’s
  ([\#85](https://github.com/pedrobtz/zutable/issues/85)).

- The kernel’s reductions, grouping and join probe stay in range at
  2^31 - 1 rows ([\#53](https://github.com/pedrobtz/zutable/issues/53)),
  and `zt_join_build()` in the header returns -1 for a table too small
  for its rows ([\#86](https://github.com/pedrobtz/zutable/issues/86)).

- `coalesce()`, [`ifelse()`](https://rdrr.io/r/base/ifelse.html),
  [`case()`](https://pedrobtz.github.io/zutable/reference/vocabulary.md),
  `first()`, `last()` and `over()` take a struct column’s values by row,
  under both executors
  ([\#55](https://github.com/pedrobtz/zutable/issues/55)).

- An extension or `r_class()` column keeps its class and attributes
  through `where`, value forms, `order`, `limit`, `distinct`,
  [`join()`](https://pedrobtz.github.io/zutable/reference/join.md),
  [`head()`](https://rdrr.io/r/utils/head.html) and
  [`rbind()`](https://rdrr.io/r/base/cbind.html)
  ([\#57](https://github.com/pedrobtz/zutable/issues/57)).

- The reference join matches an `int64` key’s `NA` as missing, not as 0,
  and keeps apart values whose bits read as NaN
  ([\#60](https://github.com/pedrobtz/zutable/issues/60)).

- Only the autoprint of a top-level update `x[, a := v]` is skipped:
  [`print()`](https://rdrr.io/r/base/print.html) of it, and a later
  print after an update in a function, a loop, an assignment or
  [`invisible()`](https://rdrr.io/r/base/invisible.html), all print
  ([\#61](https://github.com/pedrobtz/zutable/issues/61)).

- A bit64 `integer64` column or value enters as `int64` (`zu_int64`, the
  same bits), and a matrix or array column is a `zutable_type_error` (or
  `zutable_schema_error` against a schema) in
  [`zutable()`](https://pedrobtz.github.io/zutable/reference/zutable.md),
  [`as_zutable()`](https://pedrobtz.github.io/zutable/reference/zutable.md),
  [`schema()`](https://pedrobtz.github.io/zutable/reference/schema.md),
  [`conform()`](https://pedrobtz.github.io/zutable/reference/conform.md)
  and replacement
  ([\#62](https://github.com/pedrobtz/zutable/issues/62)).

- `NaN` in a `not_null(float64)` column is a value, as in queries (D47),
  by every route: constructors, query results, `:=` and `[<-`; `NaN`
  behind a date or timestamp is a `zutable_value_error` where it enters
  ([\#63](https://github.com/pedrobtz/zutable/issues/63)).

- Strings enter as UTF-8 by D58’s rule, for column values, literals,
  enum levels and column and field names: an unknown-encoded non-ASCII
  string in a C or POSIX locale is a `zutable_value_error` naming the
  column, and a string marked `"bytes"` is refused
  ([\#64](https://github.com/pedrobtz/zutable/issues/64)).

- A `left`, `right` or `full` join makes the side it does not preserve
  nullable from the schemas alone, so the result’s schema never depends
  on which rows matched
  ([\#65](https://github.com/pedrobtz/zutable/issues/65)).

- Metadata follows D59: `select`, `by` keys and
  [`join()`](https://pedrobtz.github.io/zutable/reference/join.md) keep
  a bare column’s field metadata, renamed or not, a computed column has
  none, a query keeps its table’s metadata, and a join keeps `x`’s
  ([\#66](https://github.com/pedrobtz/zutable/issues/66)).

- `int32` widens to `int64` where implicit: `:=`, `$<-`, `[[<-` and
  `[<-` into an `int64` column, and `cast(x, int64)`; without zuint it
  is a `zutable_type_error` naming it
  ([\#67](https://github.com/pedrobtz/zutable/issues/67)).

- [`join()`](https://pedrobtz.github.io/zutable/reference/join.md) with
  no `on`,
  [`schema()`](https://pedrobtz.github.io/zutable/reference/schema.md)
  of one unnamed argument that fails, `print(n =)` other than a whole
  number of rows, and option `zutable.executor` other than `"kernel"` or
  `"reference"` raise the package’s classed errors
  ([\#68](https://github.com/pedrobtz/zutable/issues/68)).

- [`within()`](https://rdrr.io/r/base/with.html),
  [`modifyList()`](https://rdrr.io/r/utils/modifyList.html),
  [`replace()`](https://rdrr.io/r/base/replace.html) and
  [`droplevels()`](https://rdrr.io/r/base/droplevels.html) return a
  plain data frame with no schema, plan or `frozen` attribute, and
  `is.na(x) <- i` goes through the typed `[<-`, so it respects
  [`freeze()`](https://pedrobtz.github.io/zutable/reference/zutable-update.md),
  `not_null` and the column types
  ([\#79](https://github.com/pedrobtz/zutable/issues/79)).

- An error raised while evaluating `limit`, `by` or
  [`.col()`](https://rdrr.io/r/base/col.html) keeps its message inside
  the package’s ([\#82](https://github.com/pedrobtz/zutable/issues/82)).

- `join(on =)` is spelled as the bracket is: bare names and
  [`c()`](https://rdrr.io/r/base/c.html) of them are columns, a quoted
  string a column’s name, and `..keys` the names a variable holds in the
  caller’s frame
  ([\#83](https://github.com/pedrobtz/zutable/issues/83)).

- `cast(timestamp, string)`,
  [`explain()`](https://pedrobtz.github.io/zutable/reference/explain.md)
  and the SQL literals round a timestamp to the nearest microsecond
  before writing it, carrying the second
  ([\#51](https://github.com/pedrobtz/zutable/issues/51)).

- `cast(string, timestamp)`, `%in%` and a string compared with a
  timestamp read each string by its own ISO 8601 form, and a string in
  none of them is a `zutable_value_error` from
  [`cast()`](https://pedrobtz.github.io/zutable/reference/vocabulary.md)
  ([\#54](https://github.com/pedrobtz/zutable/issues/54)).

- `date_trunc()` in a zone and
  [`cast()`](https://pedrobtz.github.io/zutable/reference/vocabulary.md)
  of a date to a zoned timestamp work on the local wall clock by D63, so
  a fall-back hour or a midnight that does not exist gives the right
  instant, never `NA`; a date outside years 0 to 9999 casts to ISO 8601
  expanded text such as `"-000001-01-01"`, and
  [`explain()`](https://pedrobtz.github.io/zutable/reference/explain.md)
  and the SQL literals write it too
  ([\#58](https://github.com/pedrobtz/zutable/issues/58)).

- [`cast()`](https://pedrobtz.github.io/zutable/reference/vocabulary.md)
  to a coarser timestamp unit is a `zutable_value_error` at the first
  value with a finer part, so its result always conforms to its schema
  ([\#59](https://github.com/pedrobtz/zutable/issues/59)).

- A `POSIXct` constant in another zone, such as
  [`Sys.time()`](https://rdrr.io/r/base/Sys.time.html), compares with a
  zoned timestamp column as the same instant, in comparisons and `%in%`
  ([\#89](https://github.com/pedrobtz/zutable/issues/89)).

- A time zone not in
  [`OlsonNames()`](https://rdrr.io/r/base/timezones.html), in
  [`timestamp()`](https://rdrr.io/r/utils/savehistory.html) or a
  `POSIXct` column, is a `zutable_type_error`, not read as UTC
  ([\#90](https://github.com/pedrobtz/zutable/issues/90)).

- `over(by =)` takes only the key types `by` does, so a struct partition
  is a `zutable_type_error` from either executor, not an internal error
  from the kernel
  ([\#78](https://github.com/pedrobtz/zutable/issues/78)).

- [`cast()`](https://pedrobtz.github.io/zutable/reference/vocabulary.md)
  of a string or a date to a timestamp, and a string read as a timestamp
  constant, refuse an instant 2^33 seconds or more from 1970, as
  [`zutable()`](https://pedrobtz.github.io/zutable/reference/zutable.md)
  and `:=` do, so no cast gives a timestamp the table would refuse
  ([\#69](https://github.com/pedrobtz/zutable/issues/69)).

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
  [`dplyr::explain()`](https://dplyr.tidyverse.org/reference/explain.html)
  reaches it too.

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

- [`grp()`](https://pedrobtz.github.io/zutable/reference/grp.md) groups
  rows by keys of any kind (integer, double, logical, character, factor,
  `integer64`, raw), in first-appearance or key order; the bracket’s
  `by` runs on it. It is a hash table of five bytes a slot, partitioned
  to the cache above L3.

- [`key_order()`](https://pedrobtz.github.io/zutable/reference/key_order.md)
  gives the stable permutation that sorts rows by one or more keys, and
  [`key_rank()`](https://pedrobtz.github.io/zutable/reference/key_order.md)
  their ranks, as `order(method = "radix")` and
  [`rank()`](https://rdrr.io/r/base/rank.html) do, with `decreasing` per
  key and `na.last`. They run the kernel’s hybrid sort: Vergesort’s run
  detection in front of counting sort, pdqsort, LSD radix and ska sort,
  chosen by size and key width. The bracket’s `order` and
  `grp(sort = TRUE)` run on it.

- `grp(sort = TRUE)` sorts every row instead of hashing when that is
  faster: below a million rows, and above when about 1% of the rows or
  more are distinct keys. The result is the same either way.

- [`key_order()`](https://pedrobtz.github.io/zutable/reference/key_order.md)
  and
  [`key_rank()`](https://pedrobtz.github.io/zutable/reference/key_order.md)
  sort strings in the kernel, by the bytes of their UTF-8 text, and with
  `collate = TRUE` in the locale’s order through `stringi` (a
  `Suggests`), whose collation keys are computed once per distinct
  string; without `stringi`, `collate = TRUE` is a
  `zutable_collate_error`.

- [`key_sort()`](https://pedrobtz.github.io/zutable/reference/key_sort.md)
  sorts values, as `sort(method = "radix")` does, and the result
  remembers that it is sorted and whether it holds `NA`, so a later
  [`sort()`](https://rdrr.io/r/base/sort.html),
  [`is.unsorted()`](https://rdrr.io/r/base/is.unsorted.html) or
  [`anyNA()`](https://rdrr.io/r/base/NA.html) answers without a pass;
  modifying it in place forgets both. `grp(sort = TRUE)`’s first key
  column carries the same.

- [`grp_join()`](https://pedrobtz.github.io/zutable/reference/grp_join.md)
  returns the index pairs of an inner, left, semi or anti join on one or
  several keys, in `x`’s row order and then `y`’s, with `multiple` to
  keep every match, the first, the last, or to raise a
  `zutable_multiple_error`;
  [`grp_match()`](https://pedrobtz.github.io/zutable/reference/grp_join.md)
  generalises [`match()`](https://rdrr.io/r/base/match.html) to several
  keys. [`join()`](https://pedrobtz.github.io/zutable/reference/join.md)
  now runs on them.

- `join(how = "right", multiple = "error")` counts the rows of `x` that
  match each row of `y`, as documented; it used to raise on a row of `x`
  matching several rows of `y`. The error names the side its row is in.

- [`grp_reduce()`](https://pedrobtz.github.io/zutable/reference/grp_reduce.md)
  computes `sum`, `prod`, `mean`, `min`, `max`, `count`, `nobs`, `first`
  and `last` by group in one pass, several columns at once, with `na.rm`
  and a `broadcast` back to the rows (`"replace"`, `"subtract"`,
  `"divide"`). Sums and means are base R’s bit for bit, in an R built
  without long double too, and a mean whose sum overflows is finite
  where base [`mean()`](https://rdrr.io/r/base/mean.html) is; a group
  with no values left is `NA`.

- The bracket’s aggregates, `over()` and `:=` with `by` now reduce every
  group at once through
  [`grp_reduce()`](https://pedrobtz.github.io/zutable/reference/grp_reduce.md)’s
  kernel, rather than evaluating each group in turn: 8 to 130 times
  faster at 10^6 rows, with the same results.

- The kernel’s header, `<zutable.h>`, is usable from another package’s C
  with `LinkingTo: zutable` alone, as a test package shows on every OS.
  The accumulators a caller passes to `zt_reduce()` must be aligned for
  `zt_acc` (16 bytes on x86_64, beyond what `R_alloc()` promises).

- The Get started vignette runs against the package, and two articles
  join it on the website: “Joins without surprises”, on repeated keys,
  missing keys and key types, and “Measuring the kernel”, the kernel’s
  timings against collapse, data.table, kit and base R.
