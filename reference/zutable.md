# Create a typed table

`zutable()` builds a table from named vectors, recycling only those of
length one. Each column's type is inferred from its vector (see
[`schema()`](https://pedrobtz.github.io/zutable/reference/schema.md));
[`na()`](https://pedrobtz.github.io/zutable/reference/na.md) declares a
column to be filled later with a typed missing value. `as_zutable()`
converts a data frame or a list, inferring the types or checking the
columns against `schema`. Row names are not kept.

## Usage

``` r
zutable(...)

as_zutable(x, schema = NULL)

is_zutable(x)
```

## Arguments

- ...:

  Named column vectors.

- x:

  A data frame, a list of columns, or a zutable.

- schema:

  A schema from
  [`schema()`](https://pedrobtz.github.io/zutable/reference/schema.md)
  to check `x` against, or `NULL` to infer one.

## Value

A zutable. `is_zutable()` returns `TRUE` or `FALSE`.

## Details

Values enter exactly or not at all: strings are converted to UTF-8, a
`POSIXct` with no time zone is given `"UTC"` (it already counts from
1970 in UTC), and a value a type cannot hold, such as a date with a
fraction of a day or `NA` in a
[`not_null()`](https://pedrobtz.github.io/zutable/reference/schema.md)
field, is a `zutable_value_error`.

## Examples

``` r
zutable(id = 1:3, name = c("Ada", "Linus", "Grace"), score = NA_real_)
#> <zutable> 3 rows x 3 columns
#>   id      name     score
#>   <int32> <string> <float64>
#> 1 1       Ada      NA
#> 2 2       Linus    NA
#> 3 3       Grace    NA
as_zutable(data.frame(x = 1:2), schema(x = not_null(int32)))
#> <zutable> 2 rows x 1 column
#>   x
#>   <not_null(int32)>
#> 1 1
#> 2 2
```
