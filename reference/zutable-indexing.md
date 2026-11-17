# Index a zutable

The value forms of the bracket keep base R's meaning: a first position
that is an integer or logical vector selects rows, and a second position
that is a character, integer or logical vector selects columns. A
bracket always returns a table, so `x[, "score"]` is a one-column table;
`x$score` and `x[["score"]]` give the vector. `drop` is accepted and
ignored.

## Usage

``` r
# S3 method for class 'zutable'
x[i, j, ..., drop = FALSE]

# S3 method for class 'zutable'
x$name <- value

# S3 method for class 'zutable'
x[[i, j]] <- value

# S3 method for class 'zutable'
x[i, j] <- value
```

## Arguments

- x:

  A zutable.

- i:

  Rows: an integer or logical vector.

- j:

  Columns: a character, integer or logical vector.

- ...:

  Not used.

- drop:

  Ignored.

- name, value:

  The column and its new values.

## Value

A zutable.

## Details

Replacing values (`x$col <- v`, `x[["col"]] <- v`, `x[i, "col"] <- v`)
needs the column to exist and `v` to fit its type: exactly, or as a
literal that is exactly representable there, such as `1` in an `int32`
column. Renaming, and assigning `NULL`, are `zutable_schema_error`s.

## Examples

``` r
x <- zutable(id = 1:3, score = c(1.5, 2, 2.5))
x[2:3, ]
#> <zutable> 2 rows x 2 columns
#>   id      score
#>   <int32> <float64>
#> 1 2       2.0
#> 2 3       2.5
x[, "score"]
#> <zutable> 3 rows x 1 column
#>   score
#>   <float64>
#> 1 1.5
#> 2 2.0
#> 3 2.5
x$id <- 7
x
#> <zutable> 3 rows x 2 columns
#>   id      score
#>   <int32> <float64>
#> 1 7       1.5
#> 2 7       2.0
#> 3 7       2.5
```
