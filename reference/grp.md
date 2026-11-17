# Group rows by keys

`grp()` gives each row the identifier of its key's group, with the
number of groups, each group's size, and the order that puts each
group's rows together. It is the kernel the bracket's `by` runs on.

## Usage

``` r
grp(..., sort = FALSE)
```

## Arguments

- ...:

  Key vectors of one length (integer, double, logical, character,
  factor, `integer64`, or a list of raw vectors), or a data frame or
  list of them.

- sort:

  Number the groups in key order rather than first appearance.

## Value

A list: `id` (integer, 1-based), `n`, `sizes`, `starts` (into `order`),
`order` (a permutation, stable within a group) and `keys` (the key
columns, one row per group, in identifier order).

## Details

Identifiers follow first appearance, so for one key `grp(x)$id` is
`match(x, unique(x))`; with `sort = TRUE` they follow the keys' sort
order, `NA` last, and `g$keys` is sorted. `NA` equals `NA`; for doubles
`NA` and `NaN` are different keys and `-0` equals `0`. Strings are equal
when their text is, whatever their encoding.

## Examples

``` r
g <- grp(c("b", "a", "b", NA))
g$id
#> [1] 1 2 1 3
g$keys
#> [[1]]
#> [1] "b" "a" NA 
#> 
grp(c(2, 1, 2), c("x", "x", "y"), sort = TRUE)$id
#> [1] 2 1 3
```
