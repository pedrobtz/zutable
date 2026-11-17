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
```

## Schemas are known before data is

Every function comes from a closed, typed vocabulary, so the result’s
schema follows from the input’s. A value that would change a column’s
type is an error, not a silent conversion.

``` r

schema(trades[select = .(.all, value = px * qty)])
trades[, { qty := px * 2 }]   # zutable_schema_error: qty is int32
```

## Update in place, then freeze

`:=` writes into existing columns in place, and never adds one. A block
is checked as a whole and committed at once. `freeze()` marks where a
table’s values are final.

``` r

trades[, {
  notional := px * qty
}]
freeze(trades)
```

## One plan, several engines

A lazy table records steps instead of running them. `explain()` shows
the plan with each step’s schema, and `collect()` runs it locally or as
SQL.

``` r

r <- lazy(trades)[select = .(n = count()), by = id]
explain(r)
collect(r)
collect(r, engine = "duckdb")
```

## Where next

Every function is in the [reference
index](https://pedrobtz.github.io/zutable/reference/index.html).
