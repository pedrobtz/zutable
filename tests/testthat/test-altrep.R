# Sorted values (design-kernel 4.1, 6.3; D22): key_sort()'s result and
# g$keys[[1]] under sort = TRUE carry sortedness and no-NA metadata in a
# zutable ALTREP class (src/altrep.c), which base R reads.

test_that("key_sort() marks what it knows, in base R's codes", {
  expect_identical(sorted_meta(key_sort(c(3L, 1L, 2L))), c(1L, 1L))
  expect_identical(sorted_meta(key_sort(c(3L, 1L, 2L), decreasing = TRUE)), c(-1L, 1L))
  # A direction only without NA (#56, design-kernel D46 amended): base R's
  # sort() and order(na.last = NA) trust a direction without reading the
  # NA mark, so a vector with an NA is marked NA-holding only.
  expect_identical(sorted_meta(key_sort(c(3, NA, 1))), c(NA_integer_, 0L))
  expect_identical(sorted_meta(key_sort(c(3, NA, 1), na.last = FALSE)), c(NA_integer_, 0L))
  expect_identical(sorted_meta(key_sort(c(3, NA, 1), na.last = NA)), c(1L, 1L))
  expect_identical(sorted_meta(key_sort(c(3, NA, 1), decreasing = TRUE)), c(NA_integer_, 0L))
  expect_identical(
    sorted_meta(key_sort(c(3, NA, 1), decreasing = TRUE, na.last = FALSE)),
    c(NA_integer_, 0L)
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

test_that("sorted values serialize as their plain payload (#80)", {
  # design-kernel D46, amended: the marks are not written, so a saved
  # object reads back without zutable and no mark is trusted from a file.
  for (x in list(
    key_sort(c(3L, NA, 1L)),
    key_sort(c(2.5, -1, NaN), decreasing = TRUE, na.last = FALSE),
    key_sort(c(TRUE, NA, FALSE)),
    key_sort(c("b", "\u00e9", "a")),
    key_sort(factor(c("y", "x", "y"))),
    key_sort(c(b = 2, a = 1)),
    key_sort(as.POSIXct("2026-01-01", tz = "UTC") + c(10, 0))
  )) {
    plain_x <- x[seq_along(x)]
    names(plain_x) <- names(x)
    bytes <- serialize(x, NULL, ascii = TRUE)
    expect_identical(bytes, serialize(plain_x, NULL, ascii = TRUE))
    expect_false(grepl("zutable|zt_sorted", rawToChar(bytes)))
    y <- unserialize(bytes)
    expect_identical(y, x)
    expect_identical(attributes(y), attributes(x))
    expect_null(sorted_meta(y))
  }
  # Through a file, as saveRDS() does.
  f <- withr::local_tempfile(fileext = ".rds")
  s <- key_sort(c(9, 3, 4))
  saveRDS(s, f)
  expect_identical(readRDS(f), c(3, 4, 9))
  expect_null(sorted_meta(readRDS(f)))
})

test_that("a saved key_sort() result reads back where zutable is not installed (#80)", {
  skip_on_cran()
  base_libs <- c(.Library, .Library.site)
  skip_if(any(file.exists(file.path(base_libs, "zutable"))),
          "zutable is in the base library")
  f <- withr::local_tempfile(fileext = ".rds")
  saveRDS(list(i = key_sort(c(3L, 1L, 2L)), s = key_sort(c("b", "a")),
               f = key_sort(factor(c("y", "x")))), f)
  empty <- withr::local_tempfile()
  dir.create(empty)
  script <- withr::local_tempfile(fileext = ".R")
  writeLines(c(
    sprintf(".libPaths(%s)", deparse(empty)),
    "stopifnot(!requireNamespace('zutable', quietly = TRUE))",
    sprintf("x <- readRDS(%s)", deparse(f)),
    "dput(x)"
  ), script)
  out <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"),
                                  c("--vanilla", shQuote(script)), stdout = TRUE, stderr = TRUE))
  expect_null(attr(out, "status"))
  got <- eval(parse(text = out))
  expect_identical(got, list(i = 1:3, s = c("a", "b"), f = factor(c("x", "y"))))
})

# An ALTREP record of zutable's sorted class, as an earlier version wrote
# it (class, package, type, then the state, a list of the payload and the
# marks), in the ASCII serialization format, built by hand: since #80
# nothing writes one, and only such a stream reaches the unserialize
# method.
sorted_stream <- function(cls, type, payload, marks) {
  head <- strsplit(rawToChar(serialize(NULL, NULL, ascii = TRUE)), "\n")[[1L]]
  head <- head[seq_len(length(head) - 1L)]
  body <- function(x) {
    lines <- strsplit(rawToChar(serialize(x, NULL, ascii = TRUE)), "\n")[[1L]]
    lines[-seq_along(head)]
  }
  sym <- function(s) c("1", "262153", as.character(nchar(s)), s)
  lines <- c(head, "238",
             "2", sym(cls), "2", sym("zutable"), "2", "13", "1", as.character(type), "254",
             "19", "2", body(payload), body(marks), "254")
  charToRaw(paste0(paste(lines, collapse = "\n"), "\n"))
}

test_that("the unserialize method trusts no mark from a stream (#52)", {
  # A well-formed stream gives the payload, unmarked.
  ok <- unserialize(sorted_stream("zt_sorted_int", 13L, c(1L, 2L, 3L), c(1L, 1L)))
  expect_identical(ok, 1:3)
  expect_null(sorted_meta(ok))
  # Marks that lie, or are malformed: the payload, never a believed mark.
  for (marks in list(integer(), 1L, c(1, 1), c(7L, 5L), NULL, c(1L, 1L))) {
    y <- unserialize(sorted_stream("zt_sorted_int", 13L, c(3L, 1L, 2L), marks))
    expect_identical(y, c(3L, 1L, 2L))
    expect_null(sorted_meta(y))
    expect_true(is.unsorted(y))
    expect_identical(sort(y), 1:3)
    print(y)
  }
  y <- unserialize(sorted_stream("zt_sorted_real", 14L, c(1, NA, 2), c(1L, 1L)))
  expect_true(anyNA(y))
  expect_identical(sort(y), c(1, 2))
  # A payload that is not the class's type, or not a list of two: a
  # zutable_value_error, not a crash.
  expect_error(unserialize(sorted_stream("zt_sorted_int", 13L, c(1, 2), c(1L, 1L))),
               class = "zutable_value_error")
  expect_error(unserialize(sorted_stream("zt_sorted_str", 16L, 1:2, c(1L, 1L))),
               class = "zutable_value_error")
  expect_error(unserialize(sorted_stream("zt_sorted_lgl", 10L, structure(TRUE, foo = 1), 1:2)),
               class = "zutable_value_error")
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

test_that("element access, inspect() and order() read through the wrapper", {
  # x[[i]] goes through the Elt method of each type, NA included.
  for (v in list(c(NA, 1L, 3L), c(NA, -0.5, 2), c(NA, FALSE, TRUE), c(NA, "a", "b"))) {
    s <- key_sort(v, na.last = FALSE)
    for (i in seq_along(v)) {
      expect_identical(s[[i]], sort(v, na.last = FALSE, method = "radix")[[i]])
    }
  }
  # inspect() shows the class's own line, then the payload.
  out <- utils::capture.output(.Internal(inspect(key_sort(c(2L, 1L)))))
  expect_match(out[[1L]], "zutable sorted values (sorted 1, no_na 1)", fixed = TRUE)
  out <- utils::capture.output(.Internal(inspect(key_sort(c("b", NA)))))
  expect_match(out[[1L]], "sortedness unknown, no_na 0", fixed = TRUE)
  # order() and radix sort() of strings read the payload's pointers.
  v <- c("b", NA, "a", "c", "a")
  s <- key_sort(v)
  plain <- c("a", "a", "b", "c", NA)
  expect_identical(order(s), order(plain))
  expect_identical(order(s, decreasing = TRUE), order(plain, decreasing = TRUE))
  expect_identical(sort(s, method = "radix"), sort(plain, method = "radix"))
})

test_that("base R reads marked values as it reads an unmarked copy (#56)", {
  vals <- list(
    integer = c(3L, NA, 1L, 2L, 1L),
    double = c(3, NA, 1, 2.5, -0, NaN),
    factor = factor(c("b", NA, "a", "c", "a")),
    Date = as.Date("2026-01-01") + c(3, NA, 1, 2),
    POSIXct = as.POSIXct("2026-01-01", tz = "UTC") + c(3, NA, 1, 2)
  )
  reads <- function(y) {
    out <- list(
      sort(y), sort(y, decreasing = TRUE), sort(y, na.last = TRUE),
      sort(y, na.last = FALSE), sort(y, method = "radix"),
      sort(y, decreasing = TRUE, na.last = TRUE),
      order(y), order(y, na.last = FALSE), order(y, na.last = NA),
      order(y, decreasing = TRUE), order(y, decreasing = TRUE, na.last = NA),
      order(y, method = "radix", na.last = NA),
      is.unsorted(y), is.unsorted(y, na.rm = TRUE), is.unsorted(y, strictly = TRUE),
      anyNA(y), unique(y), rev(y), y[!is.na(y)], which(is.na(y)),
      sort(unique(y)), length(sort(y))
    )
    if (!is.factor(y)) out <- c(out, list(range(y, na.rm = TRUE), min(y, na.rm = TRUE)))
    out
  }
  for (type in names(vals)) {
    x <- vals[[type]]
    for (dec in c(FALSE, TRUE)) {
      for (na in list(TRUE, FALSE, NA)) {
        y <- key_sort(x, decreasing = dec, na.last = na)
        u <- y[seq_along(y)]
        expect_null(sorted_meta(u))
        expect_identical(reads(y), reads(u),
                         info = sprintf("%s, decreasing %s, na.last %s", type, dec, na))
      }
    }
    k <- grp(x, sort = TRUE)$keys[[1L]]
    expect_identical(reads(k), reads(k[seq_along(k)]), info = paste(type, "grp(sort = TRUE)"))
  }
})
