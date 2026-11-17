test_that("a column wins over a caller variable", {
  z <- zutable(a = 1:3, cutoff = c(10L, 0L, 0L))
  cutoff <- 2L
  expect_identical(z[a > cutoff]$a, 2:3)
  expect_identical(z[a > ..cutoff]$a, 3L)
})

test_that("other names are caller variables, entering as constants", {
  z <- zutable(a = 1:5)
  lim <- 3L
  f <- function(k) z[a > k]
  expect_identical(z[a > lim]$a, 4:5)
  expect_identical(f(4L)$a, 5L)
  expect_identical(z[, .(b = a + lim)]$b, 4:8)
})

test_that("a sub-expression with no column is evaluated once", {
  z <- zutable(day = as.Date("2026-01-01") + 0:9)
  calls <- 0L
  base_day <- function() { calls <<- calls + 1L; as.Date("2026-01-05") }
  r <- z[day > base_day() - 1]
  expect_identical(calls, 1L)
  expect_identical(nrow(r), 6L)
  expect_identical(nrow(z[day >= Sys.Date() + 1e5]), 0L)
})

test_that("a name after $ is not a column", {
  z <- zutable(px = c(5, 15))
  other <- list(px = 10)
  expect_identical(z[px > other$px]$px, 15)
  df <- data.frame(px = c(20, 0))
  expect_identical(z[df$px > 10]$px, 5)
})

test_that(".col() is the column a variable names, in every clause", {
  z <- zutable(a = 1:4, b = c(4, 3, 2, 1))
  nm <- "b"
  expect_identical(z[.col(nm) > 2]$a, 1:2)
  expect_identical(z[, .(v = .col(nm) * 2)]$v, c(8, 6, 4, 2))
  expect_identical(z[order = .col(nm)]$a, 4:1)
  expect_identical(z[, .(s = sum(.col(nm))), by = .(k = .col("a"))]$s, c(4, 3, 2, 1))
  # The column's type is known at plan time.
  expect_identical(format(schema(z[, .(v = .col(nm))])), "v float64")
  # A column that shares the variable's name does not change what it holds.
  w <- zutable(nm = 1:2, b = c(5, 6))
  expect_identical(w[, .(v = .col(nm))]$v, c(5, 6))
})

test_that(".col() refuses anything but one existing column name", {
  z <- zutable(a = 1:2)
  expect_error(z[.col("nope") > 1], class = "zutable_schema_error")
  expect_error(z[.col(c("a", "a")) > 1], class = "zutable_syntax_error")
  expect_error(z[.col(NA_character_) > 1], class = "zutable_syntax_error")
  expect_error(z[.col(1L) > 1], class = "zutable_syntax_error")
  expect_error(z[.col() > 1], class = "zutable_syntax_error")
  expect_error(z[.col("a", "a") > 1], class = "zutable_syntax_error")
})
