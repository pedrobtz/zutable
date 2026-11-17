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
