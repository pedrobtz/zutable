# Fields and schemas

`schema()` builds a schema from named fields, each a type such as
`int32`, `decimal(18, 4)` or `list(string)`, or the fields made by
`field()` and `not_null()`. Called with one unnamed argument it returns
the schema of that table instead: a data frame's is inferred from its
columns.

## Usage

``` r
schema(..., .metadata = NULL)

field(type, nullable = TRUE, metadata = NULL)

not_null(type)
```

## Arguments

- ...:

  Named fields, or one table.

- .metadata:

  Table metadata, a named character vector.

- type:

  A type, as in `schema()`.

- nullable:

  Whether the field may hold `NA`.

- metadata:

  Field metadata, a named character vector.

## Value

`schema()` a `zutable_schema`; `field()` and `not_null()` a
`zutable_field`.

## Details

Type names are read only inside these functions (and
[`na()`](https://pedrobtz.github.io/zutable/reference/na.md)); they are
not R objects. A string is accepted wherever a type is, as is a variable
holding a type or a string. The types are:

- `bool`, `int32`, `int64`, `float64`, `string`, `date`, `binary`;

- `timestamp(unit, tz)`, with `unit` one of `"s"`, `"ms"`, `"us"` and
  `"ns"` and `tz` a zone name, or `NULL` for a time without a zone; bare
  `timestamp` is `timestamp("us", "UTC")`;

- `decimal(precision, scale)`, `enum(levels)`, `list(type)`,
  `struct(name = type, ...)`;

- `r_class("cls")`, any S3 vector held as it is, and `extension(name)`,
  a class registered with
  [`register_extension_type()`](https://pedrobtz.github.io/zutable/reference/register_extension_type.md).

`int8`, `int16` and `float32` read as `int32` and `float64`, which is
exact. `int64` needs the 'zuint' package, `decimal` the 'decimal'
package, and `timestamp("ns")` the 'zutempo' package; without them the
type is a `zutable_type_error`.

A `POSIXct` with no time zone is an instant shown in local time, and is
typed `timestamp("us", "UTC")`, so the type of a vector never depends on
the session (design D38).

## Examples

``` r
s <- schema(
  id   = not_null(int32),
  px   = field(float64, metadata = c(unit = "USD")),
  day  = date,
  tags = list(string)
)
s
#> <zutable_schema> 4 fields
#>   id not_null(int32)
#>   px float64
#>     unit: USD
#>   day date
#>   tags list(string)
schema(data.frame(x = 1:3, y = c("a", "b", "c")))
#> <zutable_schema> 2 fields
#>   x int32
#>   y string
```
