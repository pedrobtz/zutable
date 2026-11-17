# Query a zutable with SQL's clauses

The bracket takes SQL's clauses as named arguments over bare column
names: `where`, `select`, `order`, `limit` and `distinct`, run in SQL's
logical order whatever order they are written in. The first two
positions are `where` and `select`, as in data.table:
`x[px > 0, .(id, notional = px * qty)]`. A bracket always returns a
table, and its schema is known, and every type error raised, before any
data is read.

## Usage

``` r
# S3 method for class 'zutable'
`[`(
  x,
  i,
  j,
  by,
  ...,
  where,
  select,
  update,
  having,
  order,
  limit,
  distinct = FALSE,
  drop = FALSE
)
```

## Arguments

- x:

  A zutable.

- i, where:

  Rows to keep: a condition (or, as a value form, an integer or logical
  vector).

- j, select:

  Columns of the result: `.(...)` (or, as a value form, a character,
  integer or logical vector).

- by, update, having:

  Clauses that later stages of the package add.

- ...:

  Not used.

- order:

  Sort keys.

- limit:

  A row count.

- distinct:

  `TRUE` to keep one of each distinct result row.

- drop:

  Ignored: a bracket always returns a table.

## Value

A zutable.

## Details

- `select` is `.(...)` of bare columns, `name = expression`, `.all` for
  every input column, and `-name` after `.all` to leave one out. A
  computed element needs a name.

- `order` is an expression or `.(...)` of them, `desc(x)` reversing one.
  It may name result columns and, unless `distinct`, input columns. It
  is stable, and `NA` sorts last.

- `limit` is a row count, applied after `order`.

- A name that is not a column is a variable of the caller, and enters as
  a constant; `..name` forces the variable when a column has the same
  name.

A position that mentions no column is a value form instead: an integer
or logical vector selects rows and a character, integer or logical
vector selects columns, as for a data frame.

## Examples

``` r
x <- zutable(id = 1:4, px = c(10.5, 11, 20, 7), qty = c(100L, 50L, 10L, 200L))
x[px > 10, .(id, notional = px * qty)]
#> <zutable> 3 rows x 2 columns
#>   id      notional
#>   <int32> <float64>
#> 1 1       1050
#> 2 2       550
#> 3 3       200
x[select = .(.all, -qty), order = desc(px), limit = 2]
#> <zutable> 2 rows x 2 columns
#>   id      px
#>   <int32> <float64>
#> 1 3       20
#> 2 2       11
```
