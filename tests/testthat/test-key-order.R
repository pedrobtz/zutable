# key_order() and key_rank() against base R's order(method = "radix") and
# rank() (design-kernel 6.3), at sizes either side of every threshold of
# the hybrid (zutable/sort.h): the leaf (24), Vergesort's minimum (128),
# pdqsort's limit (1000), and the MSD pass (1e6).

test_that("key_order() is order(method = 'radix') on every kind, direction and na.last", {
  withr::local_seed(111)
  for (n in sort_sizes) {
    for (kind in kinds) {
      x <- key_of(kind, n)
      for (d in c(FALSE, TRUE)) {
        for (nl in list(TRUE, FALSE, NA)) {
          expect_identical(
            key_order(x, decreasing = d, na.last = nl),
            order(x, decreasing = d, na.last = nl, method = "radix"),
            info = paste(kind, n, d, format(nl))
          )
        }
      }
    }
  }
})

test_that("several keys sort by the first, then the next, each in its direction", {
  withr::local_seed(112)
  for (n in c(0L, 30L, 1000L, 20000L)) {
    a <- key_of("int", n)
    b <- key_of("dbl", n)
    c <- key_of("lgl", n)
    w <- key_of("dbl_wide", n)
    for (d in list(
      c(FALSE, FALSE, FALSE),
      c(TRUE, FALSE, TRUE),
      c(FALSE, TRUE, FALSE)
    )) {
      for (nl in list(TRUE, FALSE, NA)) {
        expect_identical(
          key_order(a, b, c, decreasing = d, na.last = nl),
          order(a, b, c, decreasing = d, na.last = nl, method = "radix"),
          info = paste(n, format(d), format(nl))
        )
        # Wider than 64 bits together: sorted in chunks, last first.
        expect_identical(
          key_order(w, b, w, decreasing = d, na.last = nl),
          order(w, b, w, decreasing = d, na.last = nl, method = "radix"),
          info = paste("wide", n, format(d), format(nl))
        )
      }
    }
    df <- data.frame(a = a, b = b)
    expect_identical(key_order(df), order(a, b, method = "radix"))
  }
})

test_that("large inputs take the MSD and radix paths and agree", {
  skip_on_cran()
  skip_under_torture()
  withr::local_seed(113)
  n <- 1100000L
  for (kind in c("int_wide", "dbl_wide", "sorted", "int")) {
    x <- key_of(kind, n)
    expect_identical(key_order(x), order(x, method = "radix"), info = kind)
    expect_identical(
      key_order(x, decreasing = TRUE, na.last = FALSE),
      order(x, decreasing = TRUE, na.last = FALSE, method = "radix"),
      info = kind
    )
  }
})

test_that("the order is stable, and NA and NaN tie as base R has them", {
  expect_identical(key_order(rep(3L, 50)), 1:50)
  expect_identical(key_order(rep(3L, 50), decreasing = TRUE), 1:50)
  x <- c(NaN, NA, 1, NaN, NA, -0, 0)
  expect_identical(key_order(x), c(6L, 7L, 3L, 1L, 2L, 4L, 5L))
  expect_identical(key_order(x), order(x, method = "radix"))
})

test_that("integer64, strings and raw keys sort by value, text and bytes", {
  withr::local_seed(114)
  s <- sample(c("b", "a", "B", "", NA, "é", "ab"), 300, TRUE)
  for (d in c(FALSE, TRUE)) {
    for (nl in list(TRUE, FALSE, NA)) {
      expect_identical(
        key_order(s, decreasing = d, na.last = nl),
        order(enc2utf8(s), decreasing = d, na.last = nl, method = "radix")
      )
    }
  }
  i <- c(3, 1, 2)
  expect_identical(
    key_order(s[1:3], i),
    order(enc2utf8(s[1:3]), i, method = "radix")
  )
  r <- list(
    as.raw(c(1, 2)),
    NULL,
    as.raw(1),
    raw(),
    as.raw(255),
    as.raw(c(1, 2))
  )
  hex <- c("0102", NA, "01", "", "ff", "0102")
  expect_identical(key_order(r), order(hex, method = "radix"))
  skip_if_not_installed("bit64")
  v <- c(5, -3, NA, 2^40, -2^40, 0, 5)
  x <- bit64::as.integer64(v)
  for (d in c(FALSE, TRUE)) {
    for (nl in list(TRUE, FALSE, NA)) {
      expect_identical(
        key_order(x, decreasing = d, na.last = nl),
        order(v, decreasing = d, na.last = nl, method = "radix")
      )
    }
  }
})

test_that("key_rank() is rank() for ties min and first, for every na.last", {
  withr::local_seed(115)
  for (n in c(0L, 1L, 25L, 200L, 3000L)) {
    for (kind in c("int", "dbl", "lgl", "fct", "date")) {
      x <- key_of(kind, n)
      # unclass(): rank() on a Date dispatches per comparison, and is slow
      # under gctorture; the day numbers rank the same.
      xr <- if (is.factor(x)) as.integer(x) else unclass(x)
      for (ties in c("min", "first")) {
        for (nl in list(TRUE, FALSE, NA, "keep")) {
          expect_identical(
            key_rank(x, ties = ties, na.last = nl),
            as.integer(rank(xr, ties.method = ties, na.last = nl)),
            info = paste(kind, n, ties, format(nl))
          )
        }
      }
      if (n) {
        expect_identical(
          key_rank(x, ties = "min", decreasing = TRUE),
          as.integer(rank(-as.numeric(xr), ties.method = "min"))
        )
      }
    }
  }
})

test_that("ties = 'dense' numbers the distinct keys in order, missing last", {
  withr::local_seed(116)
  x <- sample(c(NA, NaN, -0, 0, 2.5, 1, 7), 500, TRUE)
  y <- x
  y[is.na(y)] <- NA
  want <- match(y, sort(unique(y), na.last = TRUE))
  expect_identical(key_rank(x, ties = "dense"), want)
  expect_identical(
    key_rank(x, ties = "dense", na.last = "keep"),
    match(y, sort(unique(y)))
  )
  a <- sample(1:3, 200, TRUE)
  b <- sample(c("x", "y"), 200, TRUE)
  o <- order(a, b)
  runs <- cumsum(c(TRUE, a[o][-1] != a[o][-200] | b[o][-1] != b[o][-200]))
  want2 <- integer(200)
  want2[o] <- runs
  expect_identical(key_rank(a, b, ties = "dense"), want2)
  want_min <- integer(200)
  want_min[o] <- match(runs, runs)
  expect_identical(key_rank(a, b), want_min)
})

test_that("refusals", {
  expect_error(key_order(1:3, 1:2), class = "zutable_length_error")
  expect_error(key_order(1i), class = "zutable_type_error")
  expect_error(
    key_order(1:3, 1:3, decreasing = c(TRUE, FALSE, TRUE)),
    class = "zutable_type_error"
  )
  expect_error(key_order(1:3, decreasing = NA), class = "zutable_type_error")
  expect_error(key_order(1:3, na.last = "keep"), class = "zutable_type_error")
  expect_error(
    key_order(1:3, na.last = c(TRUE, FALSE)),
    class = "zutable_type_error"
  )
  expect_error(key_rank(1:3, ties = "average"), class = "zutable_type_error")
  expect_error(
    key_rank(1:3, ties = NA_character_),
    class = "zutable_type_error"
  )
  expect_error(key_rank(1:3, na.last = "drop"), class = "zutable_type_error")
  expect_identical(key_order(), integer())
  expect_identical(key_rank(), integer())
})
