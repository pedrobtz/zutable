# grp(sort = TRUE) by sorting every row (design-kernel 4.2, axis O; D44),
# held to the hash route, which test-grp-property.R holds to base R.

test_that("sorting every row gives the hash route's sorted groups", {
  withr::local_seed(49)
  int64 <- function(n) {
    skip_if_not_installed("bit64")
    bit64::as.integer64(sample(c(-2^40, 0, 3, 2^52, NA), n, TRUE))
  }
  for (n in c(2L, 23L, 1000L, 5000L)) {
    # Doubles with NaN but no NA, and NA but no NaN: no tie to split.
    nan <- sample(c(-0, 0, 1.5, -2, Inf, -Inf, NaN, 1e300), n, TRUE)
    na <- sample(c(-0, 0, 1.5, -2, Inf, -Inf, NA), n, TRUE)
    cases <- list(
      int = list(grp_sample("int", n)),
      wide_int = list(sample.int(.Machine$integer.max, n, TRUE)),
      nan = list(nan),
      na = list(na),
      lgl = list(grp_sample("lgl", n)),
      fct = list(grp_sample("fct", n)),
      raw = list(as.raw(sample.int(256L, n, TRUE) - 1L)),
      two = list(grp_sample("int", n), na),
      three = list(grp_sample("lgl", n), sample.int(3L, n, TRUE), nan),
      i64 = list(int64(n))
    )
    for (nm in names(cases)) {
      keys <- cases[[nm]]
      got <- zt_grp_sort_route(keys, n, force = TRUE)
      expect_false(is.null(got), info = paste(nm, n))
      expect_identical(got, grp_hash_sorted(keys), info = paste(nm, n))
    }
  }
})

test_that("NA beside NaN in a tied run falls back to hashing", {
  withr::local_seed(50)
  x <- sample(c(1, NA, NaN), 200, TRUE)
  expect_null(zt_grp_sort_route(list(x), 200L, force = TRUE))
  # In a second key, under a tie in the first.
  y <- sample(c(2, NA, NaN), 200, TRUE)
  expect_null(zt_grp_sort_route(list(rep(1L, 200), y), 200L, force = TRUE))
  # grp() still gives the sorted groups, on keys distinct enough that it
  # would sort them, with hundreds of each missing value.
  x <- sample(c(seq_len(3000), rep(c(NA, NaN), 500)), 5000, TRUE)
  expect_gt(sum(is.na(x) & !is.nan(x)), 100)
  expect_gt(sum(is.nan(x)), 100)
  expect_identical(grp(x, sort = TRUE), grp_hash_sorted(list(x)))
  expect_identical(
    grp(x, sort = TRUE)$id,
    match(x, sort(unique(x), na.last = TRUE))
  )
  # NA and NaN in different rows of a key that is not tied there: the
  # first key differs, so the order never puts them side by side.
  a <- rep(c(1L, 2L), 100)
  b <- ifelse(a == 1L, NA, NaN)
  expect_identical(
    zt_grp_sort_route(list(a, b), 200L, force = TRUE),
    grp_hash_sorted(list(a, b))
  )
})

test_that("strings and raw lists are never sorted by this route", {
  expect_null(zt_grp_sort_route(list(c("b", "a")), 2L, force = TRUE))
  expect_null(zt_grp_sort_route(list(list(as.raw(1), NULL)), 2L, force = TRUE))
  expect_null(zt_grp_sort_route(list(1:3, c("a", "b", "c")), 3L, force = TRUE))
})

test_that("the route is chosen by rows and estimated distinct keys", {
  # The thresholds themselves are straddled in tests/c/test-sort.c; here
  # the route as R reaches it, on either side of each.
  skip_under_torture()
  withr::local_seed(52)
  route <- function(x) !is.null(zt_grp_sort_route(list(x), length(x)))
  big <- 1e6L
  # Below a million rows the sort wins at any share (benchmarks.md).
  expect_true(route(rep_len(1:2, big - 1L)))
  expect_false(route(rep_len(1:2, big)))
  expect_false(route(rep_len(1:2, big + 1L)))
  # From a million: 0.3% distinct hashes, 3% and every row distinct sort.
  expect_false(route(sample.int(3000L, big, TRUE)))
  expect_true(route(sample.int(30000L, big, TRUE)))
  expect_true(route(sample.int(1e9, big)))
})

test_that("grp(sort = TRUE) takes the route and agrees with base R", {
  withr::local_seed(51)
  x <- sample.int(1e6, 2e5, TRUE)
  expect_false(is.null(zt_grp_sort_route(list(x), length(x))))
  g <- grp(x, sort = TRUE)
  expect_identical(g, grp_hash_sorted(list(x)))
  u <- sort(unique(x))
  expect_identical(g$id, match(x, u))
  expect_identical(g$keys[[1L]], u)
  expect_identical(g$order, order(x, method = "radix"))
})
