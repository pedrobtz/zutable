# Random keys of every kind, with NA, NaN, -0, Inf, duplicated and
# mixed-encoding strings, sorted, reversed and constant, at lengths 0, 1, 2
# and 1e5, through the one-pass and the partitioned paths, against base R.

test_that("grp() agrees with the reference on random keys of every kind", {
  withr::local_seed(44)
  kinds <- c("int", "dbl", "lgl", "chr", "fct", "raw")
  for (n in c(0L, 1L, 2L, 1000L)) {
    for (kind in kinds) {
      x <- grp_sample(kind, n)
      for (shape in c("random", "sorted", "reversed", "constant")) {
        y <- switch(shape, random = x,
          sorted = if (is.list(x)) x else x[order(x, method = "radix")],
          reversed = if (is.list(x)) rev(x) else rev(x[order(x, method = "radix")]),
          constant = if (n) rep(x[1L], n) else x)
        want <- if (kind == "chr") match(enc2utf8(y), unique(enc2utf8(y))) else
          if (kind == "raw") match(lapply(y, function(e) e), unique(y)) else
            match(y, unique(y))
        expect_identical(grp(y)$id, want, info = paste(kind, shape, n))
      }
    }
  }
})

test_that("the partitioned path gives the one-pass path's result", {
  withr::local_seed(45)
  n <- 1e5L
  keys <- list(sample.int(5e4, n, TRUE), sample(c(letters, NA), n, TRUE),
               sample(c(0.5, NaN, NA, -0, 0), n, TRUE))
  one <- zt_grp_native(keys, n, force_bits = 0L)
  for (bits in c(1L, 4L, 9L)) {
    part <- zt_grp_native(keys, n, force_bits = bits)
    expect_identical(part$bits, bits)
    expect_identical(part$id, one$id)
    expect_identical(part$first, one$first)
    expect_identical(part$sizes, one$sizes)
    expect_identical(part$order, one$order)
  }
  expect_identical(one$id, grp_ref(keys[[1L]], keys[[2L]], keys[[3L]]))
})

test_that("large inputs choose partitions on their own and agree", {
  withr::local_seed(46)
  x <- sample.int(.Machine$integer.max, 3e6, TRUE)
  g <- zt_grp_native(list(x), length(x))
  expect_gt(g$bits, 0L)
  expect_identical(g$id, match(x, unique(x)))
})

test_that("a table that starts small and grows gives the same groups", {
  withr::local_seed(48)
  # Distinct keys all over a small sample's view: the estimate is low, so
  # the table must double many times.
  x <- c(rep(1L, 5e4), sample.int(1e9, 5e4))
  g <- zt_grp_native(list(x), length(x), force_bits = 0L)
  expect_identical(g$id, match(x, unique(x)))
})
