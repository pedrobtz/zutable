# zutable 0.1.0

* Initial CRAN submission.

## Bug fixes

* String keys in `grp()`, `grp_match()`, `grp_join()`, `grp_reduce()`, `by` and `join()` match by text when one is unmarked (native) and its twin UTF-8, and `r()` returns UTF-8 strings (#50).
* A string marked `"bytes"` in a key is a `zutable_value_error` from `grp()`, `grp_match()`, `grp_join()`, `grp_reduce()`, `key_order()`, `key_sort()` and `key_rank()` (#50, #68).
* `key_sort()` and `grp(sort = TRUE)` mark values sorted only when they hold no `NA`, so `sort()` and `order(na.last = NA)` of them drop the `NA`s as base R does (#56).
* `key_sort()` and `grp(sort = TRUE)` results save as plain vectors, so `saveRDS()` of them reads back where zutable is not installed (#80), and a stream with the old sorted class is read as its plain values, its marks never trusted, or is a `zutable_value_error` when corrupt (#52).
* `grp_reduce()` checks a `grp()` result's shape (`id`, `n`, `sizes`, `starts`, `order`, `keys`) and raises a `zutable_type_error` or `zutable_value_error` for a hand-edited one, never coercing `n` (#68).
* `key_order(collate =)` is checked for one plain vector too, and `key_sort()` of a data frame or list of columns is a `zutable_type_error` (#68).
* The native grouping and join routines check every key column's length, not only the first's (#85).
* The kernel's reductions, grouping and join probe stay in range at 2^31 - 1 rows (#53), and `zt_join_build()` in the header returns -1 for a table too small for its rows (#86).
* `coalesce()`, `ifelse()`, `case()`, `first()`, `last()` and `over()` take a struct column's values by row, under both executors (#55).
* An extension or `r_class()` column keeps its class and attributes through `where`, value forms, `order`, `limit`, `distinct`, `join()`, `head()` and `rbind()` (#57).
* The reference join matches an `int64` key's `NA` as missing, not as 0, and keeps apart values whose bits read as NaN (#60).
* Only the autoprint of a top-level update `x[, a := v]` is skipped: `print()` of it, and a later print after an update in a function, a loop, an assignment or `invisible()`, all print (#61).
* A bit64 `integer64` column or value enters as `int64` (`zu_int64`, the same bits), and a matrix or array column is a `zutable_type_error` (or `zutable_schema_error` against a schema) in `zutable()`, `as_zutable()`, `schema()`, `conform()` and replacement (#62).
* `NaN` in a `not_null(float64)` column is a value, as in queries (D47), by every route: constructors, query results, `:=` and `[<-`; `NaN` behind a date or timestamp is a `zutable_value_error` where it enters (#63).
* Strings enter as UTF-8 by D58's rule, for column values, literals, enum levels and column and field names: an unknown-encoded non-ASCII string in a C or POSIX locale is a `zutable_value_error` naming the column, and a string marked `"bytes"` is refused (#64).
* A `left`, `right` or `full` join makes the side it does not preserve nullable from the schemas alone, so the result's schema never depends on which rows matched (#65).
* Metadata follows D59: `select`, `by` keys and `join()` keep a bare column's field metadata, renamed or not, a computed column has none, a query keeps its table's metadata, and a join keeps `x`'s (#66).
* `int32` widens to `int64` where implicit: `:=`, `$<-`, `[[<-` and `[<-` into an `int64` column, and `cast(x, int64)`; without zuint it is a `zutable_type_error` naming it (#67).
* `join()` with no `on`, `schema()` of one unnamed argument that fails, `print(n =)` other than a whole number of rows, and option `zutable.executor` other than `"kernel"` or `"reference"` raise the package's classed errors (#68).
* `within()`, `modifyList()`, `replace()` and `droplevels()` return a plain data frame with no schema, plan or `frozen` attribute, and `is.na(x) <- i` goes through the typed `[<-`, so it respects `freeze()`, `not_null` and the column types (#79).
* An error raised while evaluating `limit`, `by` or `.col()` keeps its message inside the package's (#82).
* `join(on =)` is spelled as the bracket is: bare names and `c()` of them are columns, a quoted string a column's name, and `..keys` the names a variable holds in the caller's frame (#83).
* `cast(timestamp, string)`, `explain()` and the SQL literals round a timestamp to the nearest microsecond before writing it, carrying the second (#51).
* `cast(string, timestamp)`, `%in%` and a string compared with a timestamp read each string by its own ISO 8601 form, and a string in none of them is a `zutable_value_error` from `cast()` (#54).
* `date_trunc()` in a zone and `cast()` of a date to a zoned timestamp work on the local wall clock by D63, so a fall-back hour or a midnight that does not exist gives the right instant, never `NA`; a date outside years 0 to 9999 casts to ISO 8601 expanded text such as `"-000001-01-01"`, and `explain()` and the SQL literals write it too (#58).
* `cast()` to a coarser timestamp unit is a `zutable_value_error` at the first value with a finer part, so its result always conforms to its schema (#59).
* A `POSIXct` constant in another zone, such as `Sys.time()`, compares with a zoned timestamp column as the same instant, in comparisons and `%in%` (#89).

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
