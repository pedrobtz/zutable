# grp_join() against merge(sort = FALSE) turned into index pairs, and
# grp_match() against match() (design-kernel 6.4, section 9).

test_that("grp_join() is merge()'s pairs for every type and kind, either side built", {
  withr::local_seed(131)
  latin <- iconv("é", "UTF-8", "latin1")
  kinds <- list(
    int = function(n) sample(c(NA, 1:6), n, TRUE),
    dbl = function(n) sample(c(NA, NaN, 0, -0, 1.5, -2, Inf), n, TRUE),
    lgl = function(n) sample(c(NA, TRUE, FALSE), n, TRUE),
    chr = function(n) sample(c(NA, "a", "", "é", latin, "中"), n, TRUE)
  )
  for (nm in names(kinds)) {
    for (sz in list(c(0L, 5L), c(5L, 0L), c(1L, 1L), c(8L, 300L), c(300L, 8L),
                    c(200L, 200L))) {
      xk <- data.frame(k = kinds[[nm]](sz[[1L]]))
      yk <- data.frame(k = kinds[[nm]](sz[[2L]]))
      expect_joins_merge(xk, yk, info = paste(nm, sz[[1L]], sz[[2L]]))
    }
  }
})

test_that("two and three keys of mixed kinds agree with merge()", {
  withr::local_seed(132)
  for (sz in list(c(40L, 400L), c(400L, 40L), c(250L, 250L))) {
    mk <- function(n) data.frame(
      a = sample(c(NA, 1:3), n, TRUE),
      b = sample(c(NA, "x", "y"), n, TRUE),
      c = sample(c(NA, NaN, 0, 2.5), n, TRUE)
    )
    xk <- mk(sz[[1L]])
    yk <- mk(sz[[2L]])
    expect_joins_merge(xk[c("a", "b")], yk[c("a", "b")], info = paste(sz, collapse = " "))
    expect_joins_merge(xk, yk, info = paste(sz, collapse = " "))
  }
})

test_that("pairs come in x order, then y order, and the table side does not matter", {
  x <- c(2L, 1L, 2L, 3L)
  y <- c(2L, 2L, 9L, 1L, 2L)
  j <- grp_join(x, y)
  expect_identical(j, list(x = c(1L, 1L, 1L, 2L, 3L, 3L, 3L),
                           y = c(1L, 2L, 5L, 4L, 1L, 2L, 5L)))
  # The same keys with x the larger side.
  xl <- rep(x, 3L)
  j2 <- grp_join(xl, y)
  expect_false(is.unsorted(j2$x))
  expect_identical(j2, merge_join_pairs(data.frame(k = xl), data.frame(k = y)))
  expect_identical(grp_join(x, y, type = "left"),
                   list(x = c(1L, 1L, 1L, 2L, 3L, 3L, 3L, 4L),
                        y = c(1L, 2L, 5L, 4L, 1L, 2L, 5L, NA)))
  expect_identical(grp_join(x, y, multiple = "last"),
                   list(x = 1:3, y = c(5L, 4L, 5L)))
  expect_identical(grp_join(x, y, type = "semi"), list(x = 1:3))
  expect_identical(grp_join(x, y, type = "anti"), list(x = 4L))
})

test_that("keys pair by kind: factors by label, numbers by value", {
  f <- factor(c("b", "a", NA, "c"), levels = c("c", "b", "a"))
  g <- factor(c("a", "b", "z"))
  expect_identical(grp_join(f, g), list(x = 1:2, y = 2:1))
  expect_identical(grp_join(f, c("c", NA)), list(x = 3:4, y = 2:1))
  expect_identical(grp_join(c(1L, 2L, NA), c(2, 1, NA, 1.5)),
                   list(x = c(1L, 2L, 3L), y = c(2L, 1L, 3L)))
  expect_identical(grp_join(c(TRUE, FALSE), c(0L, 1L)), list(x = 1:2, y = 2:1))
  d <- as.Date("2026-01-01") + 0:2
  expect_identical(grp_join(d, rev(d)), list(x = 1:3, y = 3:1))
  r <- list(as.raw(1:2), NULL, raw(0), as.raw(1))
  expect_identical(grp_join(r, list(raw(0), as.raw(1:2), NULL)),
                   list(x = 1:3, y = c(2L, 3L, 1L)))
})

test_that("integer64 keys match by their 64 bits", {
  skip_if_not_installed("bit64")
  x <- bit64::as.integer64(c("9007199254740993", "0", NA, "-1"))
  y <- bit64::as.integer64(c("-1", "9007199254740992", "9007199254740993", NA, "0"))
  expect_identical(grp_join(x, y), list(x = 1:4, y = c(3L, 5L, 4L, 1L)))
  expect_error(grp_join(x, c(1, 2)), class = "zutable_type_error")
})

test_that("by pairs named columns of data frames and named lists", {
  orders <- data.frame(day = 1:4, customer = c(10L, 20L, 10L, 30L))
  people <- data.frame(id = c(20L, 10L), customer = c(1L, 2L), name = c("L", "A"))
  expect_identical(grp_join(orders, people, by = c(customer = "id")),
                   list(x = 1:3, y = c(2L, 1L, 2L)))
  expect_identical(grp_join(orders, people, by = "customer"), list(x = integer(), y = integer()))
  expect_identical(
    grp_join(list(a = 1:2, b = c("x", "y")), list(b = c("y", "x"), a = 2:1), by = c("a", "b")),
    list(x = 1:2, y = 2:1)
  )
  expect_identical(grp_join(orders["customer"], people["id"]),
                   grp_join(orders, people, by = c(customer = "id")))
})

test_that("grp_match() is match(), for one key and several", {
  withr::local_seed(133)
  latin <- iconv("é", "UTF-8", "latin1")
  for (n in c(0L, 1L, 50L, 2000L)) {
    x <- sample(c(NA, "a", "b", "é", latin, "zz"), n, TRUE)
    y <- sample(c(NA, "a", "b", "é", "q"), 30, TRUE)
    expect_identical(grp_match(x, y), match(x, y))
    d <- sample(c(NA, NaN, -0, 0, 1, 2.5), n, TRUE)
    e <- sample(c(NA, NaN, 0, 2.5, 7), 40, TRUE)
    expect_identical(grp_match(d, e), match(d, e))
    i <- sample(c(NA, 1:20), n, TRUE)
    j <- sample(c(NA, 1:20), 400, TRUE)
    expect_identical(grp_match(i, j), match(i, j))
    a <- sample(1:4, n, TRUE)
    b <- sample(c("u", "v"), n, TRUE)
    ya <- sample(1:4, 30, TRUE)
    yb <- sample(c("u", "v", "w"), 30, TRUE)
    expect_identical(grp_match(list(a, b), list(ya, yb)),
                     match(paste(a, b), paste(ya, yb)))
  }
})

test_that("multiple = \"error\" is a zutable_multiple_error naming the key", {
  x <- data.frame(k = c(1L, 2L, 3L), s = c("a", "b", "b"))
  y <- data.frame(k = c(2L, 3L, 3L, 2L), s = c("b", "b", "b", "c"))
  expect_error(grp_join(x, y, multiple = "error"), class = "zutable_multiple_error")
  expect_snapshot(grp_join(x, y, multiple = "error"), error = TRUE)
  # One match per row is not a fan-out, whichever side is larger.
  expect_identical(grp_join(x, y[1:2, ], multiple = "error"),
                   list(x = 2:3, y = 1:2))
  expect_identical(grp_join(rep(2L, 5L), 2L, multiple = "error"),
                   list(x = 1:5, y = rep(1L, 5L)))
  # Semi and anti joins have no fan-out.
  expect_identical(grp_join(x, y, type = "semi", multiple = "error"), list(x = 2:3))
})

test_that("more than 2^31 - 1 pairs is a zutable_length_error, before any is made", {
  skip_under_torture()
  # 2^15 rows of x each match 2^16 rows of y: 2^31 pairs, one too many.
  x <- rep(1L, 2^15)
  y <- rep(1L, 2^16)
  expect_error(grp_join(x, y), class = "zutable_length_error")
  expect_error(grp_join(x, y, type = "left"), class = "zutable_length_error")
  # multiple = "first" leaves one pair per row.
  expect_identical(lengths(grp_join(x, y, multiple = "first")), c(x = 32768L, y = 32768L))
  expect_identical(grp_join(x, y, type = "semi")$x, seq_len(2^15))
})

test_that("refusals", {
  expect_error(grp_join(1:3, 1:3, type = "right"), class = "zutable_syntax_error")
  expect_error(grp_join(1:3, 1:3, multiple = "any"), class = "zutable_syntax_error")
  expect_error(grp_join(1:3, 1:3, type = NA), class = "zutable_syntax_error")
  expect_error(grp_join(1:3, c("1", "2")), class = "zutable_type_error")
  expect_error(grp_join(list(1:3, 1:3), 1:3), class = "zutable_type_error")
  expect_error(grp_join(data.frame(), data.frame()), class = "zutable_type_error")
  expect_error(grp_join(list(1:2, 1:3), 1:3), class = "zutable_length_error")
  expect_error(grp_join(1:3, list(as.raw(1))), class = "zutable_type_error")
  expect_error(grp_join(1:3, mean), class = "zutable_type_error")
  expect_error(grp_join(data.frame(a = 1), data.frame(b = 1), by = "a"),
               class = "zutable_schema_error")
  expect_error(grp_join(1:3, 1:3, by = "a"), class = "zutable_syntax_error")
  expect_error(grp_join(data.frame(a = 1), data.frame(a = 1), by = c("a", NA)),
               class = "zutable_syntax_error")
  expect_error(grp_join(data.frame(a = 1), data.frame(a = 1), by = 1),
               class = "zutable_syntax_error")
  expect_error(grp_match(1:3, letters), class = "zutable_type_error")
})
