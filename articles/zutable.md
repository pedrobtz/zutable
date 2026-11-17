# Get started with zutable

``` r

library(zutable)
```

A data.frame does not know its types: a column can change from integer
to character with one assignment, and an error surfaces only when the
data reaches the code that breaks. A zutable always knows its schema,
and every query is checked against it before any data is read. This page
uses one small table of trades throughout.

``` r

trades <- zutable(
  id       = c(1L, 1L, 2L, 2L, 3L),
  day      = as.Date("2026-01-01") + 0:4,
  px       = c(10.5, 11, 20, 19.5, 7),
  qty      = c(100L, 50L, 10L, 30L, 200L),
  notional = NA_real_
)
schema(trades)
#> <zutable_schema> 5 fields
#>   id int32
#>   day date
#>   px float64
#>   qty int32
#>   notional float64
```

## Query with SQL’s clauses

The bracket takes SQL’s clauses as named arguments over bare column
names, and runs them in SQL’s logical order whatever order they are
written in.

``` r

# Open: `.()` against another spelling inside `select` (ergonomics tests)
trades[where  = day >= "2026-01-02",
       select = .(vwap = sum(px * qty) / sum(qty), n = count()),
       by     = id,
       order  = desc(vwap)]
#> <zutable> 3 rows x 3 columns
#>   id      vwap      n
#>   <int32> <float64> <not_null(int32)>
#> 1 2       19.625    2
#> 2 1       11.000    1
#> 3 3       7.000     1
```

## Schemas are known before data is

Every function comes from a closed, typed vocabulary, so the result’s
schema follows from the input’s. A value that would change a column’s
type is an error, not a silent conversion.

``` r

schema(trades[select = .(.all, value = px * qty)])
#> <zutable_schema> 6 fields
#>   id int32
#>   day date
#>   px float64
#>   qty int32
#>   notional float64
#>   value float64
trades[, { qty := px * 2 }]   # zutable_schema_error: qty is int32
#> Error in `[.zutable`:
#> ! column `qty` is int32; the update would make it float64
```

## Update in place, then freeze

`:=` writes into existing columns in place, and never adds one. A block
is checked as a whole and committed at once.
[`freeze()`](https://pedrobtz.github.io/zutable/reference/zutable-update.md)
marks where a table’s values are final.

``` r

trades[, {
  notional := px * qty
}]
#> <zutable> 5 rows x 5 columns
#>   id      day        px        qty     notional
#>   <int32> <date>     <float64> <int32> <float64>
#> 1 1       2026-01-01 10.5      100     1050
#> 2 1       2026-01-02 11.0      50      550
#> 3 2       2026-01-03 20.0      10      200
#> 4 2       2026-01-04 19.5      30      585
#> 5 3       2026-01-05 7.0       200     1400
freeze(trades)
trades
#> <zutable> 5 rows x 5 columns, frozen
#>   id      day        px        qty     notional
#>   <int32> <date>     <float64> <int32> <float64>
#> 1 1       2026-01-01 10.5      100     1050
#> 2 1       2026-01-02 11.0      50      550
#> 3 2       2026-01-03 20.0      10      200
#> 4 2       2026-01-04 19.5      30      585
#> 5 3       2026-01-05 7.0       200     1400
```

## One plan, several engines

A lazy table records steps instead of running them.
[`explain()`](https://pedrobtz.github.io/zutable/reference/explain.md)
shows the plan with each step’s schema, and `collect()` runs it locally
or as SQL.

``` r

r <- lazy(trades)[select = .(n = count()), by = id]
explain(r)
collect(r)
collect(r, engine = "duckdb")
```

## Where next

Every function is in the [reference
index](https://pedrobtz.github.io/zutable/reference/index.html).
