# Join two tables

`join()` matches the rows of `x` and `y` on key columns. Pairs come in
`x`'s row order and, within a row of `x`, in `y`'s; `right` and `full`
joins add `y`'s rows in `y`'s order. Key columns appear once, under
`x`'s names; for a row only `y` has, they take `y`'s values.

## Usage

``` r
join(x, y, on, how = "inner", multiple = "all", na_equal = TRUE, suffix = NULL)
```

## Arguments

- x, y:

  Zutables.

- on:

  The keys: a column, `.(a, b)` or `c(a, b)`, or `.(id == customer_id)`
  where the names differ. A quoted string, or
  [`c()`](https://rdrr.io/r/base/c.html) of them, names columns
  literally; names held in a variable `keys` are passed as `..keys`,
  evaluated in the caller's frame. Each pair of keys must have the same
  type.

- how:

  `"inner"`, `"left"`, `"right"`, `"full"`, `"semi"` (the rows of `x`
  with a match) or `"anti"` (those without).

- multiple:

  When a row of `x` matches several rows of `y` (for a right join, a row
  of `y` several of `x`): `"all"` pairs, the `"first"` or `"last"`
  match, or `"error"`, a `zutable_multiple_error`.

- na_equal:

  Whether a missing key matches a missing key: `TRUE`, as R and
  data.table do, or `FALSE`, as SQL does.

- suffix:

  Two suffixes for non-key columns both tables have, such as
  `c(".x", ".y")`; without it such a clash is a `zutable_schema_error`.

## Value

A zutable.

## Examples

``` r
orders <- zutable(id = c(1L, 2L, 3L), customer = c(10L, 20L, 10L))
people <- zutable(customer_id = c(10L, 20L), name = c("Ada", "Linus"))
join(orders, people, on = .(customer == customer_id))
#> <zutable> 3 rows x 3 columns
#>   id      customer name
#>   <int32> <int32>  <string>
#> 1 1       10       Ada
#> 2 2       20       Linus
#> 3 3       10       Ada
join(orders, people, on = .(customer == customer_id), how = "anti")
#> <zutable> 0 rows x 2 columns
#>  id      customer
#>  <int32> <int32>
```
