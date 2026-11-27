# Sort values

`key_sort()` returns `x` sorted, as `sort(x, method = "radix")` does, by
the order of
[`key_order()`](https://pedrobtz.github.io/zutable/reference/key_order.md).
The result remembers whether it holds a missing value and, when it holds
none, that it is sorted, so a later
[`sort()`](https://rdrr.io/r/base/sort.html),
[`is.unsorted()`](https://rdrr.io/r/base/is.unsorted.html) or
[`anyNA()`](https://rdrr.io/r/base/NA.html) on it answers at once,
without a pass over the values. Modifying the result in place forgets
both.

## Usage

``` r
key_sort(x, decreasing = FALSE, na.last = TRUE, collate = FALSE)
```

## Arguments

- x:

  A key vector: integer, double, logical, character, factor,
  `integer64`, `Date`, `POSIXct`, or a list of raw vectors.

- decreasing:

  `TRUE` or `FALSE`.

- na.last:

  `TRUE`, `FALSE` or `NA`; for
  [`key_rank()`](https://pedrobtz.github.io/zutable/reference/key_order.md)
  also `"keep"`, which ranks a row with a missing key `NA`.

- collate:

  `FALSE` sorts strings by bytes; `TRUE` in the order of the current
  locale, as
  [`stringi::stri_order()`](https://rdrr.io/pkg/stringi/man/stri_order.html)
  does. `TRUE` needs the `stringi` package, and is a
  `zutable_collate_error` without it.

## Value

`x` in sorted order, with its class and levels; without its missing
values when `na.last = NA`.

## Details

Numbers, logicals, factors and dates are marked. Strings are not marked
sorted, since base R's sortedness of strings is its own collation, which
byte order and `stringi`'s need not match, and base R reads no missing
value mark on strings; nor is an `integer64` vector, whose order is not
that of its doubles.

## Examples

``` r
s <- key_sort(c(3, 1, NA, 2))
s
#> [1]  1  2  3 NA
is.unsorted(s, na.rm = TRUE)
#> [1] FALSE
key_sort(c("b", "A", "a"))
#> [1] "A" "a" "b"
if (requireNamespace("stringi", quietly = TRUE)) {
  key_sort(c("b", "A", "a"), collate = TRUE)
}
#> [1] "a" "A" "b"
```
