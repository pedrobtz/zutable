# Each kernel operation through the header, against base R; and that the
# run is the one it claims to be, with zutable absent.

test_that("zutable is not installed when the CI says so", {
  skip_if_not(identical(Sys.getenv("ZUTABLETEST_ZUTABLE_ABSENT"), "true"))
  expect_false(requireNamespace("zutable", quietly = TRUE))
  expect_false("zutable" %in% loadedNamespaces())
})

test_that("groups follow first appearance, as match(x, unique(x))", {
  x <- c(3L, NA, 1L, 3L, NA, 2L, 1L)
  g <- zt_consume_groups(x)
  expect_identical(g[[1L]], match(x, unique(x)))
  expect_identical(g[[2L]], 4L)
  # -0 is 0; NA and NaN are two groups, as match() has them.
  d <- c(0, -0, NA, NaN, 1.5, NA, NaN, 1.5)
  g <- zt_consume_groups(d)
  expect_identical(g[[1L]], match(d, unique(d)))
  expect_identical(g[[2L]], length(unique(d)))
  set.seed(1)
  big <- sample(c(NA, seq_len(300L)), 10000L, replace = TRUE)
  expect_identical(zt_consume_groups(big)[[1L]], match(big, unique(big)))
  expect_identical(zt_consume_groups(integer())[[2L]], 0L)
})

test_that("the order is base radix order, stable, with na.last", {
  x <- c(2.5, NA, -1, 0, -0, 2.5, -Inf, Inf, NA, 7)
  for (dec in c(FALSE, TRUE)) {
    for (na in list(TRUE, FALSE, NA)) {
      expect_identical(zt_consume_order(x, dec, na),
                       order(x, decreasing = dec, na.last = na, method = "radix"),
                       info = paste(dec, na))
    }
  }
  set.seed(2)
  big <- sample(c(NA, round(rnorm(50), 1)), 5000L, replace = TRUE)
  expect_identical(zt_consume_order(big), order(big, method = "radix"))
})

test_that("the inner join is every equal pair, x order then y order", {
  x <- c(1L, 2L, NA, 2L, 5L)
  y <- c(2L, 1L, 2L, NA, 7L)
  j <- zt_consume_join(x, y)
  want <- which(outer(x, y, function(a, b) a == b | (is.na(a) & is.na(b))), arr.ind = TRUE)
  want <- want[order(want[, 1L], want[, 2L]), , drop = FALSE]
  expect_identical(j[[1L]], unname(want[, 1L]))
  expect_identical(j[[2L]], unname(want[, 2L]))
  expect_length(zt_consume_join(integer(), y)[[1L]], 0L)
})

test_that("group sums are base sum(na.rm = TRUE), NA where a group has none", {
  id <- c(1L, 2L, 1L, 3L, 2L, 1L)
  x <- c(0.1, NA, 0.2, NA, 5, 0.3)
  want <- vapply(1:3, function(g) {
    v <- x[id == g & !is.na(x)]
    if (length(v)) sum(v) else NA_real_
  }, double(1))
  expect_identical(zt_consume_sum(id, 3L, x), want)
  set.seed(3)
  id <- sample(1:40, 20000L, replace = TRUE)
  x <- runif(20000L)
  expect_identical(zt_consume_sum(id, 40L, x), as.vector(tapply(x, id, sum)))
})

test_that("the header's version is the zutable it was built against", {
  v <- zt_consume_version()
  expect_match(v[[1L]], "^[0-9]+\\.[0-9]+\\.[0-9]+(\\.[0-9]+)?$")
  parts <- v[[2L]]
  want <- paste(parts[parts > 0L | seq_along(parts) < 4L], collapse = ".")
  expect_identical(v[[1L]], want)
  built <- Sys.getenv("ZUTABLETEST_ZUTABLE_VERSION")
  skip_if(built == "")
  expect_identical(v[[1L]], built)
})
