# Explain how a table is computed

`explain()` prints, one step per line, the plan that made a table: its
source, and each step's operation and output schema. It is plain text,
written to be read by a person or an agent.

## Usage

``` r
explain(x, ...)
```

## Arguments

- x:

  A zutable.

- ...:

  Not used.

## Value

`x`, invisibly.

## Details

When the 'dplyr' package is loaded, `dplyr::explain()` reaches the same
method, whichever package was attached last (design D50).

## Examples

``` r
x <- zutable(id = 1:3, px = c(1.5, 2, 2.5))
explain(x[px > 1.6, .(id, twice = px * 2)])
#> source  <anonymous table>  id int32, px float64
#> filter  (px > 1.6)
#> project id int32, twice float64 = (px * 2)
```
