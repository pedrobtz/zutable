# Reduce values by group

`grp_reduce()` computes a statistic of `x` for each group of `by`, in
one pass over the rows. With several columns in `x`, each with its own
`fn`, all of them are reduced in that one pass, and the rows are grouped
once.

## Usage

``` r
grp_reduce(x, by, fn = "sum", na.rm = TRUE, broadcast = "none")
```

## Arguments

- x:

  A vector, or a list or data frame of vectors as long as the keys; a
  list is several columns, so a list column goes inside one. `count`,
  `nobs`, `first` and `last` take any vector; `min` and `max` also
  integer, double, logical, character, `Date` and `POSIXct` ones; `sum`,
  `prod` and `mean` take numbers and logicals.

- by:

  The result of
  [`grp()`](https://pedrobtz.github.io/zutable/reference/grp.md), or key
  vectors for
  [`grp()`](https://pedrobtz.github.io/zutable/reference/grp.md) to
  group by: a vector, or a data frame or list of them.

- fn:

  The statistic: `"sum"`, `"prod"`, `"mean"`, `"min"`, `"max"`,
  `"count"`, `"nobs"`, `"first"` or `"last"`; one, or one per column of
  `x`.

- na.rm:

  Leave missing values out.

- broadcast:

  `"none"` for one value per group, in the order of
  [`grp()`](https://pedrobtz.github.io/zutable/reference/grp.md)'s
  identifiers, so that it lines up with `keys`; or one value per row:
  `"replace"`, each row's group value, `"subtract"`, `x` less it, or
  `"divide"`, `x` over it. A character or factor `x` takes `"none"` and
  `"replace"` only.

## Value

A vector when `x` is one vector, else a list with one per column. When
`by` is key vectors, the
[`grp()`](https://pedrobtz.github.io/zutable/reference/grp.md) result is
attached as the attribute `"groups"`, so that its `keys` and `sizes`
need no second grouping.

## Details

The statistics follow base R: `sum`, `prod` and `mean` are base
[`sum()`](https://rdrr.io/r/base/sum.html),
[`prod()`](https://rdrr.io/r/base/prod.html) and
[`mean()`](https://rdrr.io/r/base/mean.html) over each group's values,
bit for bit, and return double, for integer `x` too. `min` and `max`
keep `x`'s type and class; character values compare by their bytes in
UTF-8, not by locale. `count` is the group's size, `nobs` its values
that are not missing, and `first` and `last` its first and last value.

With `na.rm = TRUE`, the default, missing values (`NA`, and `NaN` for
doubles, as [`is.na()`](https://rdrr.io/r/base/NA.html) has them) are
left out; a group with no other value gives `NA` for `sum`, `prod`,
`mean`, `min` and `max`, where base
[`sum()`](https://rdrr.io/r/base/sum.html) would give 0 and
[`min()`](https://rdrr.io/r/base/Extremes.html) `Inf`. With
`na.rm = FALSE` a missing value makes the group's statistic missing, as
in base R, and `first` and `last` return the value in place.

## Examples

``` r
g <- grp(c("a", "b", "a", "b"))
grp_reduce(c(1, 2, 3, NA), g, "sum")
#> [1] 4 2
grp_reduce(c(1, 2, 3, NA), g, "sum", na.rm = FALSE)
#> [1]  4 NA
grp_reduce(list(v = c(1, 2, 3, 4), w = 4:1), g, c("mean", "max"))
#> $v
#> [1] 2 3
#> 
#> $w
#> [1] 4 3
#> 
grp_reduce(c(1, 2, 3, 4), g, "mean", broadcast = "subtract")
#> [1] -1 -1  1  1
s <- grp_reduce(c(5, 1, 2), c("x", "y", "x"), "sum")
attr(s, "groups")$keys
#> [[1]]
#> [1] "x" "y"
#> 
```
