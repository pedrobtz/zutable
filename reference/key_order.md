# Order and rank rows by keys

`key_order()` gives the stable permutation that sorts rows by one or
more keys, as `order(method = "radix")` does; `key_rank()` gives each
row's rank, as [`rank()`](https://rdrr.io/r/base/rank.html) does. Both
run the kernel's hybrid sort: the keys become one normalised integer per
row, sorted by radix, counting sort, Vergesort or pdqsort, whichever its
size and shape favour.

## Usage

``` r
key_order(..., decreasing = FALSE, na.last = TRUE)

key_rank(
  ...,
  ties = c("min", "first", "dense"),
  decreasing = FALSE,
  na.last = TRUE
)
```

## Arguments

- ...:

  Key vectors of one length (integer, double, logical, character,
  factor, `integer64`, `Date`, `POSIXct`, or a list of raw vectors), or
  a data frame or list of them.

- decreasing:

  One logical, or one per key column.

- na.last:

  `TRUE`, `FALSE` or `NA`; for `key_rank()` also `"keep"`, which ranks a
  row with a missing key `NA`.

- ties:

  For `key_rank()`: `"min"` gives equal keys the lowest rank of their
  run, as `rank(ties.method = "min")`; `"first"` ranks them in row
  order; `"dense"` numbers the distinct keys 1, 2, ... A row with a
  missing key ranks on its own under `"min"`, as
  [`rank()`](https://rdrr.io/r/base/rank.html) ranks `NA`; under
  `"dense"` the rows of one missing key share a rank.

## Value

An integer vector: for `key_order()` a permutation (shorter than the
input when `na.last = NA` drops rows), for `key_rank()` one rank per
row.

## Details

The order is base R's: numbers ascending, `FALSE` before `TRUE`, factors
by level, `-0` equal to `0`. `NA` and `NaN` are equal, and go last with
`na.last = TRUE`, first with `FALSE`, and with `NA` their rows are left
out. `decreasing` reverses a key's order but not the stability: equal
keys keep row order. Strings sort by the bytes of their UTF-8 text.

## Examples

``` r
x <- c(3, 1, NA, 2, 1)
key_order(x)
#> [1] 2 5 4 1 3
key_order(x, decreasing = TRUE, na.last = FALSE)
#> [1] 3 1 4 2 5
key_order(c("b", "a", "b"), c(2, 1, 1))
#> [1] 2 3 1
key_rank(x)
#> [1] 4 1 5 3 1
key_rank(x, ties = "dense")
#> [1] 3 1 4 2 1
```
