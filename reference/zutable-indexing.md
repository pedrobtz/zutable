# Replace values in a zutable

Replacing values (`x$col <- v`, `x[["col"]] <- v`, `x[i, "col"] <- v`)
needs the column to exist and `v` to fit its type: exactly, or as a
literal that is exactly representable there, such as `1` in an `int32`
column. Renaming, and assigning `NULL`, are `zutable_schema_error`s, so
no replacement changes a table's schema. Selecting rows and columns by
value is the bracket's: see
[zutable-bracket](https://pedrobtz.github.io/zutable/reference/zutable-bracket.md).

## Usage

``` r
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

- name, value:

  The column and its new values.

- i, j:

  Rows and columns, as for a data frame.

## Value

A zutable.

## Examples

``` r
x <- zutable(id = 1:3, score = c(1.5, 2, 2.5))
x$id <- 7
x[2, "score"] <- 0
x
#> <zutable> 3 rows x 2 columns
#>   id      score
#>   <int32> <float64>
#> 1 7       1.5
#> 2 7       0.0
#> 3 7       2.5
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
