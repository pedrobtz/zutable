# Joins without surprises

``` r

library(zutable)
```

A join that runs is not always the join you meant. A key repeated in the
lookup table multiplies rows, a missing key matches or not depending on
the tool, and an integer key against a double one may match by value or
not at all. This article shows what
[`join()`](https://pedrobtz.github.io/zutable/reference/join.md) does in
each case, and how to ask for something else. It assumes you have read
[`vignette("zutable")`](https://pedrobtz.github.io/zutable/articles/zutable.md).

We use two small tables throughout. `people` has a repeated customer,
20, and a row whose key is missing.

``` r

orders <- zutable(order = 1:5, customer = c(10L, 20L, 10L, NA, 30L))
people <- zutable(
  customer = c(10L, 20L, 20L, NA),
  name     = c("Ada", "Linus", "Grace", "Nobody")
)
```

## Rows come in a fixed order

An inner join keeps each pair of matching rows. The pairs come in the
order of `x`’s rows, and within one row of `x` in the order of `y`’s, so
the result reads like `orders` with names attached.

``` r

join(orders, people, on = customer)
#> <zutable> 5 rows x 3 columns
#>   order   customer name
#>   <int32> <int32>  <string>
#> 1 1       10       Ada
#> 2 2       20       Linus
#> 3 2       20       Grace
#> 4 3       10       Ada
#> 5 4       NA       Nobody
```

Order 2 appears twice, because customer 20 is in `people` twice. Order 5
is gone: no person has customer 30.

## A repeated key: choose with `multiple`

`multiple` says what a row of `x` gets when it matches several rows of
`y`. The default, `"all"`, gives every pair, as
[`merge()`](https://rdrr.io/r/base/merge.html) and data.table do.
`"first"` and `"last"` keep one match, in `y`’s order.

``` r

join(orders, people, on = customer, multiple = "first")
#> <zutable> 4 rows x 3 columns
#>   order   customer name
#>   <int32> <int32>  <string>
#> 1 1       10       Ada
#> 2 2       20       Linus
#> 3 3       10       Ada
#> 4 4       NA       Nobody
join(orders, people, on = customer, multiple = "last")
#> <zutable> 4 rows x 3 columns
#>   order   customer name
#>   <int32> <int32>  <string>
#> 1 1       10       Ada
#> 2 2       20       Grace
#> 3 3       10       Ada
#> 4 4       NA       Nobody
```

When a repeated key means the data is wrong, say so, and the join stops
at the first row that fans out:

``` r

join(orders, people, on = customer, multiple = "error")
#> Error in `join()`:
#> ! row 2 of x matches 2 rows of y on key (20); multiple = "error"
```

The error is a `zutable_multiple_error`, and it names the row and the
key.

## A missing key: choose with `na_equal`

By default a missing key matches a missing key, as
[`match()`](https://rdrr.io/r/base/match.html) and data.table have it:
order 4 found “Nobody” above. SQL has `NULL` match nothing, and
`na_equal = FALSE` gives SQL’s behaviour.

``` r

join(orders, people, on = customer, na_equal = FALSE)
#> <zutable> 4 rows x 3 columns
#>   order   customer name
#>   <int32> <int32>  <string>
#> 1 1       10       Ada
#> 2 2       20       Linus
#> 3 2       20       Grace
#> 4 3       10       Ada
```

## Keys must have the same type

A key’s type is part of the schema, and the two sides must agree. An
integer key against a double one is an error, not a match by value that
could silently go wrong on `10.5`.

``` r

rates <- zutable(customer = c(10, 20), rate = c(0.1, 0.2))
join(orders, rates, on = customer)
#> Error in `join()`:
#> ! key `customer` is int32 in x and `customer` is float64 in y; the types must be the same
```

Convert one side with
[`cast()`](https://pedrobtz.github.io/zutable/reference/vocabulary.md)
first, so the conversion is visible where it happens:

``` r

rates_int <- rates[select = .(customer = cast(customer, "int32"), rate)]
join(orders, rates_int, on = customer)
#> <zutable> 3 rows x 3 columns
#>   order   customer rate
#>   <int32> <int32>  <float64>
#> 1 1       10       0.1
#> 2 2       20       0.2
#> 3 3       10       0.1
```

Keys with different names are paired with `==`, as in
`on = .(customer == customer_id)`.

## Clashing column names: give `suffix`

A column that is not a key and is in both tables would be ambiguous in
the result, so
[`join()`](https://pedrobtz.github.io/zutable/reference/join.md) refuses
it unless you give the two suffixes.

``` r

returns <- zutable(customer = c(10L, 20L), order = 7:8)
join(orders, returns, on = customer)
#> Error in `join()`:
#> ! both tables have a column `order` that is not a key; give `suffix`, as in suffix = c(".x", ".y")
join(orders, returns, on = customer, suffix = c(".x", ".y"))
#> <zutable> 3 rows x 3 columns
#>   order.x customer order.y
#>   <int32> <int32>  <int32>
#> 1 1       10       7
#> 2 2       20       8
#> 3 3       10       7
```

## Which rows to keep: `how`

`how` picks the rows. `"left"` keeps every row of `x`, `"right"` every
row of `y`, `"full"` both. `"semi"` keeps the rows of `x` that have a
match, once each and with `x`’s columns only, and `"anti"` the rows that
have none.

``` r

join(orders, people, on = customer, how = "full")
#> <zutable> 6 rows x 3 columns
#>   order   customer name
#>   <int32> <int32>  <string>
#> 1 1       10       Ada
#> 2 2       20       Linus
#> 3 2       20       Grace
#> 4 3       10       Ada
#> 5 4       NA       Nobody
#> 6 5       30       NA
join(orders, people, on = customer, how = "semi")
#> <zutable> 4 rows x 2 columns
#>   order   customer
#>   <int32> <int32>
#> 1 1       10
#> 2 2       20
#> 3 3       10
#> 4 4       NA
join(orders, people, on = customer, how = "anti")
#> <zutable> 1 row x 2 columns
#>   order   customer
#>   <int32> <int32>
#> 1 5       30
```

`"semi"` keeps order 2 once, although it matches two people, which makes
it the safe way to filter by another table.

## The index pairs underneath

[`join()`](https://pedrobtz.github.io/zutable/reference/join.md) runs on
the kernel’s
[`grp_join()`](https://pedrobtz.github.io/zutable/reference/grp_join.md),
which works on plain vectors and returns the matching row numbers
instead of a table. It follows the same rules: `x`’s order, then `y`’s,
and a missing key matching a missing key.

``` r

grp_join(c(10L, 20L, 10L, NA), c(10L, 20L, 20L, NA))
#> $x
#> [1] 1 2 2 3 4
#> 
#> $y
#> [1] 1 2 3 1 4
```

[`grp_match()`](https://pedrobtz.github.io/zutable/reference/grp_join.md)
is its single-index form, and agrees with
[`match()`](https://rdrr.io/r/base/match.html):

``` r

x <- c(10L, 20L, 10L, NA, 30L)
y <- c(10L, 20L, 20L, NA)
identical(grp_match(x, y), match(x, y))
#> [1] TRUE
```

Unlike [`match()`](https://rdrr.io/r/base/match.html), it takes several
key columns at once, as a list or a data frame, without pasting them
into one string. Here the rows of `x` are the pairs (1, 1), (2, 1) and
(3, 2), and `y` holds (2, 1) and (3, 2):

``` r

grp_match(list(1:3, c(1L, 1L, 2L)), list(2:3, 1:2))
#> [1] NA  1  2
```

## See also

[Measuring the
kernel](https://pedrobtz.github.io/zutable/articles/measurements.md) has
the join’s timings against data.table and
[`match()`](https://rdrr.io/r/base/match.html).
