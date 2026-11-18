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

test_that("strings sort by the bytes of their UTF-8 text, at every size", {
  # The kernel's string sort (zutable/strsort.h) on the distinct strings,
  # held to base radix order of enc2utf8() input (design-kernel 6.3, 8).
  withr::local_seed(117)
  latin <- iconv("caf\u00e9", "UTF-8", "latin1")
  pool <- c(
    "b", "a", "B", "", NA, "\u00e9", "ab", "a b", "abc", "abd", latin,
    "caf\u00e9", "\u4e2d\u6587", "zz", "https://example.org/a/1",
    "https://example.org/a/10", "https://example.org/a/2", "aaaaaaaab",
    "aaaaaaaa", "aaaaaaaaa"
  )
  for (n in c(sort_sizes, 20000L)) {
    if (under_torture() && n > 1001L) next
    # Few distinct strings, and nearly every string distinct.
    few <- sample(pool, n, TRUE)
    many <- paste0(sample(c("k", "K", "\u00e9"), n, TRUE), sample.int(n * 4L + 1L, n))
    for (x in list(few, many)) {
      u <- enc2utf8(x)
      for (d in c(FALSE, TRUE)) {
        for (nl in list(TRUE, FALSE, NA)) {
          expect_identical(
            key_order(x, decreasing = d, na.last = nl),
            order(u, decreasing = d, na.last = nl, method = "radix"),
            info = paste(n, d, format(nl))
          )
        }
      }
      expect_identical(
        key_rank(x, ties = "min"),
        as.integer(rank(match(u, sort(unique(u), method = "radix")),
                        ties.method = "min", na.last = TRUE))
      )
    }
  }
  # One text in two encodings is one key: equal, in row order.
  expect_identical(key_order(c(latin, "a", "caf\u00e9")), c(2L, 1L, 3L))
  # Ordered by the UTF-8 bytes, not the native ones: latin1 "\u00e9" is
  # E9, after the E4 that starts "\u4e2d"; in UTF-8 it is C3 A9, before.
  e <- iconv("\u00e9", "UTF-8", "latin1")
  expect_identical(key_order(c(e, "\u4e2d", e)), c(1L, 3L, 2L))
  expect_identical(key_order(c("\u4e2d", e)), c(2L, 1L))
  # Strings beside other keys.
  a <- sample(1:3, 500, TRUE)
  s <- sample(pool, 500, TRUE)
  expect_identical(
    key_order(a, s, decreasing = c(TRUE, FALSE)),
    order(a, enc2utf8(s), decreasing = c(TRUE, FALSE), method = "radix")
  )
})

test_that("raw vectors sort by bytes, a shorter prefix first", {
  withr::local_seed(118)
  bytes <- function() {
    if (stats::runif(1) < 0.1) return(NULL)
    as.raw(sample(c(0L, 0L, 1L, 2L, 255L), sample(0:11, 1), TRUE))
  }
  for (n in c(1L, 30L, 1001L)) {
    r <- replicate(n, bytes(), simplify = FALSE)
    # Hexadecimal text sorts as the bytes do: two digits a byte.
    hex <- vapply(r, function(e) {
      if (is.null(e)) NA_character_ else paste(sprintf("%02x", as.integer(e)), collapse = "")
    }, "")
    for (nl in list(TRUE, FALSE, NA)) {
      expect_identical(
        key_order(r, na.last = nl),
        order(hex, na.last = nl, method = "radix"),
        info = paste(n, format(nl))
      )
    }
  }
})

test_that("key_sort() is sort(method = 'radix') on every kind", {
  withr::local_seed(119)
  for (n in c(0L, 1L, 25L, 1001L)) {
    for (kind in kinds) {
      x <- key_of(kind, n)
      for (d in c(FALSE, TRUE)) {
        for (nl in list(TRUE, FALSE, NA)) {
          want <- x[order(x, decreasing = d, na.last = nl, method = "radix")]
          expect_identical(
            key_sort(x, decreasing = d, na.last = nl),
            want,
            info = paste(kind, n, d, format(nl))
          )
        }
      }
    }
  }
  s <- c("b", NA, "A", "a", "")
  expect_identical(key_sort(s), sort(enc2utf8(s), method = "radix", na.last = TRUE))
  expect_identical(key_sort(s, na.last = NA), sort(enc2utf8(s), method = "radix"))
  named <- c(b = 2L, a = 1L)
  expect_identical(key_sort(named), named[2:1])
  skip_if_not_installed("bit64")
  v <- c(5, -3, NA, 2^40)
  expect_identical(key_sort(bit64::as.integer64(v)), bit64::as.integer64(v)[c(2L, 1L, 4L, 3L)])
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
  expect_error(key_sort(1:3, decreasing = c(TRUE, FALSE)), class = "zutable_type_error")
  expect_error(key_sort(data.frame(a = 1, b = 2)), class = "zutable_type_error")
  expect_error(key_sort(1i), class = "zutable_type_error")
  expect_identical(key_order(), integer())
  expect_identical(key_rank(), integer())
})
