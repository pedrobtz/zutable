# Update columns in place

`x[, col := expression]` writes new values into an existing column,
keeping its type: SQL's `UPDATE`. Several columns are a block,
`x[, { a := ...; b := ... }]`, whose statements run in order:
`name <- value` binds a local, and each statement sees the columns and
locals as those above it left them. The block is typed as a whole before
any data is touched, every new column is computed before any is written,
and the commit replaces column pointers, so a failure leaves the table
as it was and a vector shared with another object is never changed.

## Usage

``` r
copy(x)

freeze(x)

is_frozen(x)
```

## Arguments

- x:

  A zutable.

## Value

The bracket returns `x`, invisibly. `copy()` returns a new zutable;
`freeze()` returns `x`, invisibly; `is_frozen()` `TRUE` or `FALSE`.

## Details

With `where`, only the matching rows are written, and aggregates are
computed over those rows. With `by`, an aggregate is computed per group
and written to the group's rows. Each value is one value, or one per row
written.

The table is changed in place: every alias of it sees the update.
`copy()` returns an independent table for one allocation. `freeze()`
marks a table, in place and for good, so that every write route raises a
`zutable_frozen_error`; queries read it as before.

## Examples

``` r
d <- zutable(id = c(1L, 1L, 2L), px = c(10, 20, 30), qty = c(1L, 2L, 3L),
             notional = NA_real_, share = NA_real_)
d[, {
  w <- px * qty
  notional := w
  share := w / sum(w)
}, by = id]
#> <zutable> 3 rows x 5 columns
#>   id      px        qty     notional  share
#>   <int32> <float64> <int32> <float64> <float64>
#> 1 1       10        1       10        0.2
#> 2 1       20        2       40        0.8
#> 3 2       30        3       90        1.0
d
#> <zutable> 3 rows x 5 columns
#>   id      px        qty     notional  share
#>   <int32> <float64> <int32> <float64> <float64>
#> 1 1       10        1       10        0.2
#> 2 1       20        2       40        0.8
#> 3 2       30        3       90        1.0
freeze(d)
is_frozen(d)
#> [1] TRUE
```
