# A typed missing value

`na(type)` is a length-one missing value of a type, for the types base R
has no `NA` literal for. It declares a column to be filled later:
`zutable(id = 1:3, total = na(decimal(18, 4)))`.

## Usage

``` r
na(type)
```

## Arguments

- type:

  A type, as in
  [`schema()`](https://pedrobtz.github.io/zutable/reference/schema.md).

## Value

A length-one vector of `type`, missing.

## Examples

``` r
na(int32)
#> [1] NA
na(timestamp("us", "UTC"))
#> [1] NA
na(enum(c("lo", "hi")))
#> [1] <NA>
#> Levels: lo hi
```
