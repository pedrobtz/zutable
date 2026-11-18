# Sorted values (design-kernel 4.1, 6.3; D22): key_sort()'s result and
# g$keys[[1]] under sort = TRUE carry sortedness and no-NA metadata in a
# zutable ALTREP class (src/altrep.c), which base R reads.

test_that("key_sort() marks what it knows, in base R's codes", {
  expect_identical(sorted_meta(key_sort(c(3L, 1L, 2L))), c(1L, 1L))
  expect_identical(sorted_meta(key_sort(c(3, NA, 1))), c(1L, 0L))
  expect_identical(sorted_meta(key_sort(c(3, NA, 1), na.last = FALSE)), c(2L, 0L))
  expect_identical(sorted_meta(key_sort(c(3, NA, 1), na.last = NA)), c(1L, 1L))
  expect_identical(sorted_meta(key_sort(c(3, NA, 1), decreasing = TRUE)), c(-1L, 0L))
  expect_identical(
    sorted_meta(key_sort(c(3, NA, 1), decreasing = TRUE, na.last = FALSE)),
    c(-2L, 0L)
  )
  expect_identical(sorted_meta(key_sort(c(TRUE, FALSE))), c(1L, 1L))
  expect_identical(sorted_meta(key_sort(factor(c("b", "a")))), c(1L, 1L))
  expect_identical(sorted_meta(key_sort(as.Date("2026-01-02") - 0:1)), c(1L, 1L))
  # Strings: no-NA only; R's sortedness of strings is its collation.
  expect_identical(sorted_meta(key_sort(c("b", "a"))), c(NA_integer_, 1L))
  # Plain integers and lists are not wrapped.
  expect_null(sorted_meta(key_sort(list(as.raw(2), as.raw(1)))))
  expect_null(sorted_meta(c(1L, 2L)))
  skip_if_not_installed("bit64")
  expect_null(sorted_meta(key_sort(bit64::as.integer64(c(2, 1)))))
})

test_that("is.unsorted(), anyNA() and sort() answer from the metadata", {
  # A wrapper whose metadata is false: base R believes it, so the answer
  # came from the metadata and not from a pass.
  lie <- sorted_wrap(c(3L, 1L, 2L), 1L, TRUE)
  expect_false(is.unsorted(lie))
  expect_identical(sort(lie), c(3L, 1L, 2L))
  expect_false(anyNA(sorted_wrap(c(NA, 1L), 1L, TRUE)))
  expect_false(anyNA(sorted_wrap(c(NA, 1), 1L, TRUE)))
  # Base R reads no metadata for anyNA() of strings: the pass is done.
  expect_true(anyNA(sorted_wrap(c(NA, "a"), NA_integer_, TRUE)))
  # Unknown sortedness and possible NA: base R does the pass.
  expect_true(is.unsorted(sorted_wrap(c(3L, 1L, 2L), NA_integer_, FALSE)))
  expect_true(anyNA(sorted_wrap(c(NA, 1L), 1L, FALSE)))
  # On the real thing the answers are right.
  s <- key_sort(c(5, 2, 9, 1))
  expect_false(is.unsorted(s))
  expect_false(anyNA(s))
  expect_identical(sort(s), c(1, 2, 5, 9))
})

test_that("a write through a writable DATAPTR drops the metadata", {
  # In place: the wrapper is not shared, so `[<-` writes through it.
  y <- key_sort(c(1L, 2L, 3L))
  y[2L] <- 9L
  expect_identical(sorted_meta(y), c(NA_integer_, 0L))
  expect_true(is.unsorted(y))
  expect_identical(y, c(1L, 9L, 3L))
  for (case in list(list(c(3, 1, 2), 9), list(c(TRUE, FALSE, TRUE), TRUE))) {
    y <- key_sort(case[[1L]])
    plain <- sort(case[[1L]])
    y[1L] <- case[[2L]]
    plain[1L] <- case[[2L]]
    expect_identical(sorted_meta(y)[[1L]], NA_integer_)
    expect_identical(is.unsorted(y), is.unsorted(plain))
  }
  # Strings through Set_elt.
  s <- key_sort(c("b", "a"))
  s[1L] <- NA
  expect_true(anyNA(s))
  # The write that read first: a read keeps it, the write then drops it.
  y <- key_sort(c(3L, 1L, 2L))
  expect_false(is.unsorted(y))
  expect_identical(sorted_meta(y), c(1L, 1L))
  y[3L] <- 0L
  expect_true(is.unsorted(y))
})

test_that("a shared payload is copied before a write, never changed", {
  x <- c(1L, 2L, 3L)
  w <- sorted_wrap(x, 1L, TRUE)
  w[1L] <- 7L
  expect_identical(x, c(1L, 2L, 3L))
  expect_identical(w, c(7L, 2L, 3L))
  # A copy writes on its own; the original keeps its values and metadata.
  # The metadata is read first: before R 4.6, identical() reads through
  # INTEGER(), a writable pointer, which drops it.
  y <- key_sort(c(3L, 1L, 2L))
  z <- y
  z[1L] <- 9L
  expect_identical(sorted_meta(y), c(1L, 1L))
  expect_identical(sorted_meta(z)[[1L]], NA_integer_)
  expect_identical(y, 1:3)
  expect_identical(z, c(9L, 2L, 3L))
})

test_that("serialize() round trip keeps the values, attributes and metadata", {
  for (x in list(
    key_sort(c(3L, NA, 1L)),
    key_sort(c(2.5, -1, NaN), decreasing = TRUE, na.last = FALSE),
    key_sort(c(TRUE, NA, FALSE)),
    key_sort(c("b", "\u00e9", "a")),
    key_sort(factor(c("y", "x", "y"))),
    key_sort(c(b = 2, a = 1)),
    key_sort(as.POSIXct("2026-01-01", tz = "UTC") + c(10, 0))
  )) {
    y <- unserialize(serialize(x, NULL))
    expect_identical(y, x)
    expect_identical(attributes(y), attributes(x))
    expect_identical(sorted_meta(y), sorted_meta(x))
  }
  # Metadata a write dropped stays dropped.
  x <- key_sort(c(2L, 1L))
  x[1L] <- 5L
  expect_identical(sorted_meta(unserialize(serialize(x, NULL))), sorted_meta(x))
  # Through a file, as saveRDS() does.
  f <- withr::local_tempfile(fileext = ".rds")
  s <- key_sort(c(9, 3, 4))
  saveRDS(s, f)
  expect_identical(readRDS(f), s)
  expect_identical(sorted_meta(readRDS(f)), c(1L, 1L))
})

test_that("grp(sort = TRUE) marks its first key column sorted", {
  g <- grp(c(3, 1, 2, 1), sort = TRUE)
  expect_identical(sorted_meta(g$keys[[1L]]), c(1L, 1L))
  g <- grp(c("b", NA, "a"), c(1L, 2L, 3L), sort = TRUE)
  expect_identical(sorted_meta(g$keys[[1L]]), c(NA_integer_, 0L))
  expect_null(sorted_meta(g$keys[[2L]]))
  expect_null(sorted_meta(grp(c(3, 1))$keys[[1L]]))
})

test_that("the wrapping hook takes only a plain vector and a sortedness code", {
  expect_error(sorted_wrap(c(a = 1L), 1L, TRUE))
  expect_error(sorted_wrap(list(1), 1L, TRUE))
  expect_error(sorted_wrap(1:3, 3L, TRUE))
  expect_error(sorted_wrap(1:3, -3L, TRUE))
  for (code in c(-2L, -1L, 0L, 1L, 2L, NA_integer_)) {
    expect_identical(sorted_meta(sorted_wrap(c(1L, 2L), code, FALSE)), c(code, 0L))
  }
})
