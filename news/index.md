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
