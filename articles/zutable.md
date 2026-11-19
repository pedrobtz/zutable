# Get started with zutable

``` r

library(zutable)
```

A data.frame does not know its types: a column can change from integer
to character with one assignment, and the error surfaces only when the
data reaches the code that breaks. A zutable always knows its schema,
and every query is checked against it before any data is read. This page
builds one small table of trades and takes it through a query, a type
error, a join, an update and its plan. How the joins behave, and how
fast the kernel underneath is, are left to the articles.

## A table with a schema

[`zutable()`](https://pedrobtz.github.io/zutable/reference/zutable.md)
builds a table from columns, as
[`data.frame()`](https://rdrr.io/r/base/data.frame.html) does, and gives
each column a logical type.
[`schema()`](https://pedrobtz.github.io/zutable/reference/schema.md)
shows them: the name, the type, and whether the column may hold missing
values.

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
names: `where`, `select`, `by`, `having`, `order`, `limit` and
`distinct`. They run in SQL’s logical order, whatever order they are
written in. Here the filter drops the first day before the
volume-weighted price is computed per `id`. `.()` lists the output
columns, and `count()` and `desc()` are two of the bracket’s functions,
listed in
[`?vocabulary`](https://pedrobtz.github.io/zutable/reference/vocabulary.md).
The string `"2026-01-02"` is compared with a date column, so it is read
as an ISO 8601 date; a string that is not one is a type error.

``` r

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

The result is a zutable too, with a type for every column. `n` is
`not_null(int32)`: a count is never missing, and the schema says so.

## Schemas are known before data is

Every function in the bracket comes from a closed, typed vocabulary, so
a result’s schema follows from its input’s. Asking for the schema of a
query tells you what it will return.

``` r

schema(trades[select = .(.all, value = px * qty)])
#> <zutable_schema> 6 fields
#>   id int32
#>   day date
#>   px float64
#>   qty int32
#>   notional float64
#>   value float64
```

A value that would change a column’s type is an error, not a silent
conversion. `qty` is an integer column, and `px * 2` is a double.

``` r

trades[, { qty := px * 2 }]
#> Error in `[.zutable`:
#> ! column `qty` is int32; the update would make it float64
```

The error has the class `zutable_schema_error`, so code can catch it
without matching its message.

## Join another table

[`join()`](https://pedrobtz.github.io/zutable/reference/join.md) matches
rows on key columns, as an inner join unless `how` says otherwise. The
pairs come in `x`’s row order, and a key that matches several rows of
`y` gives every pair unless `multiple` asks for the first, the last, or
an error.

``` r

firms <- zutable(id = c(1L, 2L, 4L), name = c("Acme", "Globex", "Initech"))
join(trades, firms, on = id)
#> <zutable> 4 rows x 6 columns
#>   id      day        px        qty     notional  name
#>   <int32> <date>     <float64> <int32> <float64> <string>
#> 1 1       2026-01-01 10.5      100     NA        Acme
#> 2 1       2026-01-02 11.0      50      NA        Acme
#> 3 2       2026-01-03 20.0      10      NA        Globex
#> 4 2       2026-01-04 19.5      30      NA        Globex
join(trades, firms, on = id, how = "left")
#> <zutable> 5 rows x 6 columns
#>   id      day        px        qty     notional  name
#>   <int32> <date>     <float64> <int32> <float64> <string>
#> 1 1       2026-01-01 10.5      100     NA        Acme
#> 2 1       2026-01-02 11.0      50      NA        Acme
#> 3 2       2026-01-03 20.0      10      NA        Globex
#> 4 2       2026-01-04 19.5      30      NA        Globex
#> 5 3       2026-01-05 7.0       200     NA        NA
```

The inner join drops `id` 3, which has no firm; the left join keeps it
with a missing `name`.

## Update in place, then freeze

`:=` writes into existing columns in place, and never adds one. A block
of updates is checked as a whole before anything is written.
[`freeze()`](https://pedrobtz.github.io/zutable/reference/zutable-update.md)
marks the point where a table’s values are final; a later update is an
error.

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

## See how a table was made

Each table keeps the plan that made it.
[`explain()`](https://pedrobtz.github.io/zutable/reference/explain.md)
prints it one step per line: the source with its schema, the update made
earlier, then the filter of this query. The plan is a record of how the
values came to be; printing it runs nothing.

``` r

big <- trades[where = qty > 20L]
explain(big)
#> source  <anonymous table>  id int32, day date, px float64, qty int32, notional float64
#> update  notional := (px * qty)
#> filter  (qty > 20L)
```

## Where next

- [Joins without
  surprises](https://pedrobtz.github.io/zutable/articles/joins.html):
  what `multiple`, missing keys and key types do in a join.
- [Measuring the
  kernel](https://pedrobtz.github.io/zutable/articles/measurements.html):
  how the grouping, sorting, join and reduction kernel compares with
  collapse, data.table and base R, and how the numbers are checked.
- The [reference
  index](https://pedrobtz.github.io/zutable/reference/index.html) lists
  every function.
