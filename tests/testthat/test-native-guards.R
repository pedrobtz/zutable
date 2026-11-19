# The native entry points' own argument checks (src/commit.c, numbers.c,
# join.c). The R layer never sends them these arguments, so these tests
# call the routines directly: each refuses with an R error, not a crash,
# and a refused commit writes nothing (native coverage, Stage 17).

test_that("zt_commit() validates every target before writing one", {
  call <- function(...) .Call(zutable:::zt_commit, ...)
  x <- list(a = 1:3, b = c(1, 2, 3))
  # Built apart: the commit writes into x itself, so a copy of x would
  # change with it.
  before <- list(a = 1:3, b = c(1, 2, 3))
  expect_error(call(1:3, 1L, list(4:6), NULL), "zt_commit")
  expect_error(call(x, 1, list(4:6), NULL), "zt_commit")
  expect_error(call(x, 1L, 4:6, NULL), "zt_commit")
  expect_error(call(x, c(1L, 2L), list(4:6), NULL), "zt_commit")
  for (bad in list(c(1L, 3L), c(1L, 0L), c(1L, NA))) {
    expect_error(call(x, bad, list(4:6, c(4, 5, 6)), NULL), "out of range")
    # The first target was valid, and is not written either.
    expect_identical(x, before)
  }
})

test_that("zt_commit() sets the plan only when given one, and reads only TRUE as frozen", {
  call <- function(...) .Call(zutable:::zt_commit, ...)
  x <- structure(list(a = 1:3), plan = "old")
  expect_identical(call(x, 1L, list(4:6), NULL), 0L)
  expect_identical(attr(x, "plan"), "old")
  expect_identical(x$a, 4:6)
  expect_identical(call(x, 1L, list(7:9), "new"), 0L)
  expect_identical(attr(x, "plan"), "new")
  for (mark in list(FALSE, NA, c(TRUE, TRUE), "TRUE", 1L)) {
    y <- structure(list(a = 1:3), frozen = mark)
    expect_identical(call(y, 1L, list(4:6), NULL), 0L, info = format(mark))
  }
  y <- structure(list(a = 1:3), frozen = TRUE)
  expect_identical(call(y, 1L, list(4:6), NULL), 1L)
  expect_identical(y$a, 1:3)
})

test_that("zt_freeze() and zt_copy() take only a table", {
  expect_error(.Call(zutable:::zt_freeze, 1:3), "zt_freeze")
  expect_error(.Call(zutable:::zt_copy, 1:3), "zt_copy")
})

test_that("the number routines take only their own type", {
  expect_error(.Call(zutable:::zt_parse_f64, 1), "zt_parse_f64")
  expect_error(.Call(zutable:::zt_format_f64, "1"), "zt_format_f64")
  expect_identical(.Call(zutable:::zt_parse_f64, c(NA, "", "1.5", "1.5x")), c(NA, NA, 1.5, NA))
})

test_that("zt_join() refuses keys of unequal width", {
  call <- function(x, y) {
    .Call(zutable:::zt_join, x, y, rep(FALSE, max(length(x), 1L)), 0L, 0L, NULL, NULL)
  }
  expect_error(call(list(), list()), "unequal width")
  expect_error(call(list(1:3), list(1:3, 1:3)), "unequal width")
})
