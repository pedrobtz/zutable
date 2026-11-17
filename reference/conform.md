# Check a table against a schema

`conform()` returns `x` as a zutable of schema `s` when its columns
match it, and otherwise raises a `zutable_schema_error` that lists every
mismatch: a missing column, an extra one, another order, a column of the
wrong type. `NA` in a
[`not_null()`](https://pedrobtz.github.io/zutable/reference/schema.md)
field is a `zutable_value_error`. `metadata()` returns a table's own
key-value pairs.

## Usage

``` r
conform(x, s)

metadata(x)
```

## Arguments

- x:

  A zutable or a data frame.

- s:

  A schema from
  [`schema()`](https://pedrobtz.github.io/zutable/reference/schema.md).

## Value

`conform()` a zutable; `metadata()` a named character vector.

## Examples

``` r
conform(data.frame(id = 1:2), schema(id = not_null(int32)))
#> <zutable> 2 rows x 1 column
#>   id
#>   <not_null(int32)>
#> 1 1
#> 2 2
```
