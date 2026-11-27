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

test_that("a table that starts small and grows gives the same groups (#70)", {
  withr::local_seed(48)
  # The estimator samples rows i * n / m (zt_estimate_distinct()): one key
  # at every sampled row and a distinct key everywhere else, so the
  # estimate is 1 where the truth is n - m + 1 groups, and the table
  # starting at 16 slots must double many times, one-pass and partitioned.
  n <- 1e5L
  m <- 1024L
  seen <- floor(seq.int(0, m - 1) * n / m) + 1
  x <- sample.int(1e9, n) + 1L
  x[seen] <- 1L
  want <- match(x, unique(x))
  for (bits in c(0L, 1L, 4L)) {
    g <- zt_grp_native(list(x), n, force_bits = bits)
    expect_identical(g$bits, bits)
    expect_identical(g$id, want, info = bits)
    expect_identical(g$n, max(want), info = bits)
  }
  # And through grp() on its own estimate.
  expect_identical(grp(x)$id, want)
})
