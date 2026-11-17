# The materialised table as a long-lived object updated in place: its
# out-of-order sequences (design §6.4, §14).

test_that("aliases see an update (D14)", {
  a <- zutable(x = 1:3)
  b <- a
  a[, x := x * 10L]
  expect_identical(b$x, c(10L, 20L, 30L))
  f <- function(t) { t[, x := 0L]; invisible() }
  f(a)
  expect_identical(a$x, c(0L, 0L, 0L))
  expect_identical(b$x, c(0L, 0L, 0L))
})

test_that("a vector shared with a plain data frame is never changed (D27)", {
  df <- data.frame(x = c(1L, 2L, 3L), y = c(1.5, 2.5, 3.5))
  snapshot <- unserialize(serialize(df, NULL))
  z <- as_zutable(df)
  z[, { x := x + 1L; y := 0 }]
  expect_identical(df, snapshot)
  v <- c(5L, 6L, 7L)
  z2 <- zutable(v = v)
  z2[, v := 0L]
  expect_identical(v, c(5L, 6L, 7L))
})

test_that("copy() is independent and costs one list", {
  a <- zutable(x = 1:3, y = c("p", "q", "r"))
  b <- copy(a)
  b[, x := 0L]
  expect_identical(a$x, 1:3)
  expect_identical(b$x, c(0L, 0L, 0L))
  expect_identical(attributes(copy(a)), attributes(a))
})

test_that("a base replacement is copy-on-modify, not in place", {
  a <- zutable(x = 1:3)
  b <- a
  b$x <- 0L
  expect_identical(a$x, 1:3)
  expect_identical(b$x, c(0L, 0L, 0L))
})

test_that("updates after queries, chains and copies stay consistent", {
  a <- zutable(g = c("a", "b", "a"), x = c(1, 2, 3), s = NA_real_)
  r <- a[x > 1]
  r[, s := 1]
  expect_identical(a$s, rep(NA_real_, 3L))
  a[, s := sum(x), by = g]
  expect_identical(a$s, c(4, 2, 4))
  expect_identical(a[, .(s), distinct = TRUE]$s, c(4, 2))
  schema_before <- schema(a)
  a[, s := s / 2]
  expect_identical(schema(a), schema_before)
})

test_that("an error mid-block, then more updates, then a query", {
  a <- zutable(x = c(1L, 2L))
  expect_error(a[, { x := x + 1L; x := x * .Machine$integer.max }],
               class = "zutable_value_error")
  a[, x := x + 1L]
  expect_identical(a$x, c(2L, 3L))
  expect_identical(a[x > 2L]$x, 3L)
})
