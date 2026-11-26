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

test_that("grp_reduce() checks a grp() object's shape before the kernel (#68)", {
  g <- grp(c("a", "b", "a"))
  x <- c(1, 2, 3)
  expect_identical(grp_reduce(x, g, "sum"), c(4, 2))
  bad <- function(field, value) {
    h <- g
    h[field] <- list(value)
    h
  }
  e <- "zutable_type_error"
  # The ids: integer, one per row, no NA, in 1 .. n.
  expect_error(grp_reduce(x, bad("id", c(1L, 5L, 1L)), "sum"), class = "zutable_value_error")
  expect_error(grp_reduce(x, bad("id", c(1L, 0L, 1L)), "sum"), class = "zutable_value_error")
  expect_error(grp_reduce(x, bad("id", c(1L, NA, 1L)), "sum"), class = "zutable_value_error")
  expect_error(grp_reduce(x, bad("id", c(1, 2, 1)), "sum"), class = e)
  expect_error(grp_reduce(x, bad("id", NULL), "sum"), class = e)
  # n: one integer, not NA, at least 0, never coerced.
  for (n in list(2.9, 2, "2", c(2L, 3L), NA_integer_, -1L, integer(), NULL)) {
    expect_error(grp_reduce(x, bad("n", n), "sum"), class = "zutable_error",
                 info = deparse(n))
  }
  one <- bad("n", 1L)
  one$sizes <- 3L
  one$starts <- 1L
  expect_error(grp_reduce(x, one, "sum"), class = "zutable_value_error")
  # The rest, by type and length.
  expect_error(grp_reduce(x, bad("sizes", c(2, 1)), "sum"), class = e)
  expect_error(grp_reduce(x, bad("starts", 1L), "sum"), class = e)
  expect_error(grp_reduce(x, bad("order", 1:2), "sum"), class = e)
  expect_error(grp_reduce(x, bad("keys", 1:2), "sum"), class = e)
  # A hand-built grp object of the right shape is taken as it is.
  h <- list(id = c(2L, 1L, 2L), n = 2L, sizes = c(1L, 2L), starts = c(1L, 2L),
            order = c(2L, 1L, 3L), keys = list(c("b", "a")))
  expect_identical(grp_reduce(x, h, "sum"), c(2, 4))
})

test_that("zt_grp(), zt_grp_sort() and zt_join() check every key column's length (#85)", {
  # The R layer checks lengths first (zt_key_columns()), so these call the
  # routines directly, with a second column shorter than the first.
  keys <- list(1:4, 1:2)
  i64 <- c(FALSE, FALSE)
  expect_error(.Call(zutable:::zt_grp, keys, i64, 4, NA_integer_), "length")
  expect_error(.Call(zutable:::zt_grp, list(1:2), FALSE, 4, NA_integer_), "length")
  expect_error(.Call(zutable:::zt_grp_sort, keys, i64, 4, TRUE), "length")
  expect_error(.Call(zutable:::zt_join, list(1:4, 1:4), list(1:3, 1:2), i64, 0L, 0L,
                     NULL, NULL), "length")
  expect_error(.Call(zutable:::zt_join, list(1:4, 1:2), list(1:3, 1:3), i64, 0L, 0L,
                     NULL, NULL), "length")
  # A mask of another length than its side.
  expect_error(.Call(zutable:::zt_join, list(1:4), list(1:3), FALSE, 0L, 0L,
                     c(TRUE, FALSE), NULL), "length")
})

test_that("zt_reduce refuses what grp_reduce() never sends it (#68)", {
  call <- function(id, ng, xs, fns = 0L) {
    .Call(zutable:::zt_reduce_routine(), id, ng, xs, fns, rep(TRUE, length(xs)),
          rep(TRUE, length(xs)))
  }
  expect_error(call(c(1, 2), 2L, list(c(1, 2))), "zt_reduce")
  expect_error(call(c(1L, 2L), NA_integer_, list(c(1, 2))), "zt_reduce")
  expect_error(call(c(1L, 5L), 2L, list(c(1, 2))), "out of")
  expect_error(call(c(1L, 2L), 2L, list(c(1, 2)), c(0L, 0L)), "zt_reduce")
  expect_error(call(c(1L, 2L), 2L, list(c(1, 2)), 99L), "zt_reduce")
  expect_error(call(c(1L, 2L), 2L, list("a")), "zt_reduce")
  expect_error(call(c(1L, 2L), 2L, list(1)), "zt_reduce")
})
