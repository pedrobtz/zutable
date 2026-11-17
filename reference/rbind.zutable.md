# Bind the rows of zutables

[`rbind()`](https://rdrr.io/r/base/cbind.html) stacks zutables whose
schemas are identical: the same names, types, nullability and metadata,
in the same order. Anything else is a `zutable_schema_error`.

## Usage

``` r
# S3 method for class 'zutable'
rbind(..., deparse.level = 1)
```

## Arguments

- ...:

  Zutables.

- deparse.level:

  Ignored.

## Value

A zutable.

## Examples

``` r
a <- zutable(id = 1:2, x = c(1.5, 2))
rbind(a, a)
#> <zutable> 4 rows x 2 columns
#>   id      x
#>   <int32> <float64>
#> 1 1       1.5
#> 2 2       2.0
#> 3 1       1.5
#> 4 2       2.0
```
