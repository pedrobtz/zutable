test_that("grp() identifiers follow first appearance, as match(x, unique(x))", {
  withr::local_seed(41)
  for (x in list(sample(c(3L, 1L, NA, 7L), 50, TRUE), sample(letters[1:5], 50, TRUE),
                 c(2.5, NaN, NA, -0, 0, NaN), c(TRUE, NA, TRUE, FALSE), integer())) {
    g <- grp(x)
    expect_identical(g$id, match(x, unique(x)))
    expect_identical(g$n, length(unique(x)))
    expect_identical(g$keys[[1L]], unique(x))
  }
})

test_that("several keys agree with interaction(drop = TRUE) in first appearance", {
  withr::local_seed(42)
  a <- sample(c("x", "y", NA), 200, TRUE)
  b <- sample(c(1L, 2L, 3L), 200, TRUE)
  d <- sample(c(0.5, NaN, NA), 200, TRUE)
  expect_identical(grp(a, b, d)$id, grp_ref(a, b, d))
  expect_identical(grp(data.frame(a, b))$id, grp_ref(a, b))
  expect_identical(grp(list(a, b))$id, grp_ref(a, b))
})

test_that("sizes, starts and order describe the groups", {
  x <- c("b", "a", "b", "c", "a", "b")
  g <- grp(x)
  expect_identical(g$sizes, c(3L, 2L, 1L))
  expect_identical(g$starts, c(1L, 4L, 6L))
  expect_identical(g$order, c(1L, 3L, 6L, 2L, 5L, 4L))
  expect_identical(x[g$order], c("b", "b", "b", "a", "a", "c"))
})

test_that("sort = TRUE numbers groups in key order, NA last, as collapse::GRP", {
  withr::local_seed(43)
  x <- sample(c(5L, -2L, NA, 9L, 0L), 300, TRUE)
  g <- grp(x, sort = TRUE)
  expect_identical(g$keys[[1L]], c(-2L, 0L, 5L, 9L, NA))
  expect_identical(x[g$order], x[order(x, method = "radix")])
  skip_if_not_installed("collapse")
  expect_identical(g$id, collapse::GRP(x, sort = TRUE, na.last = TRUE)$group.id)
  y <- sample(c("b", "A", "a"), 300, TRUE)
  expect_identical(grp(x, y, sort = TRUE)$id,
                   collapse::GRP(list(x, y), sort = TRUE)$group.id)
})

test_that("doubles: -0 is 0, NaN and NA are different keys, NaNs fold", {
  x <- c(0, -0, NaN, NA, -NaN, 0 / 0)
  expect_identical(grp(x)$id, c(1L, 1L, 2L, 3L, 2L, 2L))
})

test_that("strings are equal by text whatever their encoding", {
  u <- "café"
  l <- iconv(u, "UTF-8", "latin1")
  expect_identical(Encoding(l), "latin1")
  expect_identical(grp(c(u, l, "x", l))$id, c(1L, 1L, 2L, 1L))
})

test_that("factors group by code, integer64 by value, raw lists by bytes", {
  f <- factor(c("hi", "lo", "hi", NA), levels = c("lo", "hi"))
  expect_identical(grp(f)$id, c(1L, 2L, 1L, 3L))
  expect_identical(levels(grp(f)$keys[[1L]]), c("lo", "hi"))
  skip_if_not_installed("bit64")
  i <- bit64::as.integer64(c("9007199254740993", "9007199254740992", "9007199254740993"))
  expect_identical(grp(i)$id, c(1L, 2L, 1L))
  r <- list(as.raw(1:2), NULL, as.raw(1:2), raw())
  expect_identical(grp(r)$id, c(1L, 2L, 1L, 3L))
})

test_that("errors: lengths differ, too many rows, a kind that is not a key", {
  expect_error(grp(1:3, 1:2), class = "zutable_length_error")
  expect_error(grp(1:2^31), class = "zutable_length_error")
  expect_error(grp(1i), class = "zutable_type_error")
  expect_error(grp(1:3, sort = NA), class = "zutable_type_error")
  expect_identical(grp()$n, 0L)
  expect_identical(grp(integer())$n, 0L)
})
