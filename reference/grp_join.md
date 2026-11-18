# Join keys as index pairs

`grp_join()` matches the rows of `x` and `y` on key columns and returns
the index pairs, never a table. Pairs come in `x`'s row order and,
within a row of `x`, in `y`'s. `grp_match()` is the first match of each
row of `x`, as [`base::match()`](https://rdrr.io/r/base/match.html)
gives for one key, over one or several keys.

## Usage

``` r
grp_join(x, y, by = NULL, type = "inner", multiple = "all")

grp_match(x, y)
```

## Arguments

- x, y:

  Key vectors (integer, double, logical, character, factor, `integer64`,
  or a list of raw vectors), or a data frame or list of them. A data
  frame uses all its columns, unless `by` names some.

- by:

  `NULL`, to pair the key columns of `x` and `y` by position, or the
  names of the key columns, when `x` and `y` are data frames or named
  lists. A named element, as in `c(customer = "id")`, pairs `x`'s
  `customer` with `y`'s `id`.

- type:

  `"inner"`, `"left"` (every row of `x`, with `NA` in `y` when it has no
  match), `"semi"` (the rows of `x` with a match) or `"anti"` (those
  without).

- multiple:

  When a row of `x` matches several rows of `y`: `"all"` pairs, the
  `"first"` or `"last"` match, or `"error"`, a `zutable_multiple_error`
  naming the first such key.

## Value

`grp_join()`: a list of `x` and `y`, integer row indices of one length;
for `"semi"` and `"anti"`, `x` alone. `grp_match()`: an integer vector
as long as `x`, `NA` where there is no match.

## Details

`NA` matches `NA`; for doubles `NA` and `NaN` are different keys and
`-0` matches `0`. Strings match when their text does, whatever their
encoding; a factor matches by its labels, against a factor or a
character key. Integer, logical and double keys match by value. A
character key against a number, or an `integer64` key against anything
but another, is a `zutable_type_error`.

## Examples

``` r
grp_join(c("a", "b", "a"), c("b", "a", "a"))
#> $x
#> [1] 1 1 2 3 3
#> 
#> $y
#> [1] 2 3 1 2 3
#> 
grp_join(c(1, 2, 3), c(3, 1), type = "left")
#> $x
#> [1] 1 2 3
#> 
#> $y
#> [1]  2 NA  1
#> 
grp_match(c("b", "z", "a"), c("a", "b", "b"))
#> [1]  2 NA  1
orders <- data.frame(customer = c(10L, 20L, 10L), day = 1:3)
people <- data.frame(id = c(10L, 20L), name = c("Ada", "Linus"))
grp_join(orders, people, by = c(customer = "id"))
#> $x
#> [1] 1 2 3
#> 
#> $y
#> [1] 1 2 1
#> 
```
