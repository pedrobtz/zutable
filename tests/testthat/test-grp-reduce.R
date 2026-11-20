# grp_reduce() against base R per group (design-kernel 6.5, section 8):
# every statistic, kind and missing rule, broadcast, and fusion.

test_that("every statistic is base R's over each group, for every kind", {
  withr::local_seed(141)
  latin <- iconv("é", "UTF-8", "latin1")
  kinds <- list(
    int = function(n) sample(c(NA, -3L, 0L, 5L, 1000000L, -.Machine$integer.max), n, TRUE),
    dbl = function(n) sample(c(NA, NaN, -0, 0, 0.1, 1.5, -2.25, Inf, -Inf, 1e300, 1e-300,
                               stats::rnorm(20) * 1e6), n, TRUE),
    lgl = function(n) sample(c(NA, TRUE, FALSE), n, TRUE),
    chr = function(n) sample(c(NA, "a", "", "B", "é", latin, "中", "ab"), n, TRUE),
    date = function(n) as.Date("2026-01-01") + sample(c(NA, 0:40), n, TRUE)
  )
  numeric_fns <- c("sum", "prod", "mean")
  for (nm in names(kinds)) {
    for (sz in list(c(0L, 3L), c(1L, 1L), c(60L, 4L), c(5000L, 70L), c(4500L, 1L))) {
      x <- kinds[[nm]](sz[[1L]])
      keys <- sample(seq_len(sz[[2L]]), sz[[1L]], TRUE)
      g <- grp(keys)
      fns <- c("min", "max", "count", "nobs", "first", "last")
      if (nm %in% c("int", "dbl", "lgl")) fns <- c(numeric_fns, fns)
      for (fn in fns) {
        for (na.rm in c(TRUE, FALSE)) {
          expect_reduce_equal(grp_reduce(x, g, fn, na.rm = na.rm),
                              reduce_oracle(x, g$id, g$n, fn, na.rm), fn, na.rm,
                              info = paste(nm, sz[[1L]], fn, na.rm))
        }
      }
    }
  }
})

test_that("sums and means are base R's bit for bit, overflow included", {
  withr::local_seed(142)
  x <- c(stats::rnorm(3000) * 10^sample(-8:12, 3000, TRUE), 1e308, 1e308, -1e308)
  id <- sample(1:7, length(x), TRUE)
  id[3001:3003] <- 8L
  g <- grp(id)
  expect_identical(grp_reduce(x, g, "sum"), reduce_oracle(x, g$id, g$n, "sum", TRUE))
  expect_identical(grp_reduce(x, g, "mean"), reduce_oracle(x, g$id, g$n, "mean", TRUE))
  # Many groups, some where base mean()'s correction pass changes the bits
  # (checked, so the test cannot pass without that pass).
  y <- stats::rnorm(20000) * 10^sample(-8:12, 20000, TRUE)
  h <- grp(sample(1:400, 20000, TRUE))
  naive <- vapply(split(y, factor(h$id)), function(v) sum(v) / length(v), 0, USE.NAMES = FALSE)
  want <- reduce_oracle(y, h$id, h$n, "mean", TRUE)
  expect_true(any(naive != want))
  expect_identical(grp_reduce(y, h, "mean"), want)
  # Past DBL_MAX is Inf, as base sum() clamps its long double.
  one <- function(n) grp(rep(1L, n))
  expect_identical(grp_reduce(c(1e308, 1e308), one(2), "sum"), sum(c(1e308, 1e308)))
  expect_identical(grp_reduce(c(1e308, 10), one(2), "prod"), prod(c(1e308, 10)))
  i <- c(.Machine$integer.max, .Machine$integer.max, 1L)
  expect_identical(grp_reduce(i, one(3), "sum"), sum(as.double(i)))
  expect_identical(grp_reduce(i, one(3), "mean"), mean(i))
})

test_that("a mean whose sum overflows takes base R's second route", {
  # Base mean() (R >= 4.2) re-sums x / n when the sum is not finite, then
  # corrects by (x - s) / n; a long double sum past DBL_MAX takes it too.
  x <- c(1e308, 1e308, 1e308, -1e308, 1e308, 1e308, -1e308, 5, 1e308, 1e308, Inf, 1)
  id <- c(1L, 1L, 1L, 1L, 2L, 2L, 2L, 2L, 3L, 3L, 3L, 3L)
  g <- grp(id)
  expect_identical(grp_reduce(x, g, "mean"), reduce_oracle(x, g$id, g$n, "mean", TRUE))
  expect_identical(grp_reduce(x, g, "mean")[[3L]], Inf)
  withr::local_seed(147)
  m <- if (under_torture()) 150L else 600L
  y <- c(stats::runif(m, 0.5, 1.8) * 1e308, stats::rnorm(m))
  h <- grp(sample(1:40, length(y), TRUE))
  expect_identical(grp_reduce(y, h, "mean"), reduce_oracle(y, h$id, h$n, "mean", TRUE))
})

test_that("an R without long double gets sums and means in double, as base R's", {
  local_mocked_bindings(zt_long_double = function() FALSE)
  withr::local_seed(148)
  m <- if (under_torture()) 400L else 4000L
  x <- c(stats::rnorm(m) * 10^sample(-8:12, m, TRUE), 1e308, 1e308, -1e308, 7)
  id <- sample(1:30, length(x), TRUE)
  id[m + 1:4] <- 31L
  i <- sample(c(NA, -50:50, .Machine$integer.max), m + 4L, TRUE)
  g <- grp(id)
  for (fn in c("sum", "mean", "prod")) {
    v <- if (fn == "prod") x / 1e3 else x
    want <- reduce_oracle_double(v, g$id, g$n, fn)
    expect_identical(grp_reduce(v, g, fn), want, info = fn)
    expect_identical(grp_reduce(i, g, fn), reduce_oracle_double(i, g$id, g$n, fn), info = fn)
    # The executor's route (NaN a value) sums the same way.
    expect_identical(zt_reduce_ids(g$id, g$n, list(v), fn)[[1L]], want, info = fn)
  }
  # Where R has a wider long double the double sums differ from it, so the
  # test cannot pass by summing in long double. The probe is base R's own
  # long double sum, not sizeof: valgrind runs x87 long double at double's
  # 53 bits, so there the two agree.
  if (isTRUE(capabilities("long.double")) && sum(c(1, 2^-60, -1)) != 0) {
    expect_true(any(grp_reduce(x, g, "sum") != reduce_oracle(x, g$id, g$n, "sum", TRUE)))
  }
})

test_that("a group with no values left is NA, not base's 0 or Inf", {
  x <- c(NA, NA, 1)
  g <- grp(c(1L, 1L, 2L))
  expect_identical(grp_reduce(x, g, "sum"), c(NA, 1))
  expect_identical(grp_reduce(x, g, "min"), c(NA, 1))
  expect_identical(grp_reduce(c(NaN, 2), grp(1:2), "mean"), c(NA, 2))
  expect_identical(grp_reduce(x, g, "nobs"), c(0L, 1L))
  expect_identical(grp_reduce(x, g, "first"), c(NA, 1))
  expect_identical(grp_reduce(x, g, "first", na.rm = FALSE), c(NA, 1))
  expect_identical(grp_reduce(c("a", NA), grp(1:2), "max"), c("a", NA))
})

test_that("min and max keep the type and class, and compare strings by bytes", {
  one <- function(x) grp(rep(1L, length(x)))
  d <- as.Date("2026-03-01") + c(3, 1, 2)
  expect_identical(grp_reduce(d, grp(c(1, 1, 2)), "min"), as.Date("2026-03-01") + c(1, 2))
  t <- as.POSIXct("2026-01-01 10:00:00", tz = "UTC") + c(10, 5)
  expect_identical(grp_reduce(t, one(t), "max"), t[1L])
  lg <- c(TRUE, FALSE, NA)
  expect_identical(grp_reduce(lg, one(lg), "max"), 1L)
  expect_identical(grp_reduce(c(3L, 1L), one(1:2), "min"), 1L)
  # "B" < "a" < "é" in bytes; a locale's collation says otherwise.
  s <- c("a", "é", "B")
  expect_identical(grp_reduce(s, one(s), "min"), "B")
  expect_identical(grp_reduce(s, one(s), "max"), "é")
  # Ties keep the first value: -0 and 0 in row order.
  expect_identical(1 / grp_reduce(c(-0, 0), one(1:2), "min"), -Inf)
  expect_identical(1 / grp_reduce(c(0, -0), one(1:2), "max"), Inf)
})

test_that("first and last take any vector, factors and lists included", {
  f <- factor(c("u", NA, "w", "v"), levels = c("w", "v", "u"))
  g <- grp(c(1, 1, 2, 2))
  expect_identical(grp_reduce(f, g, "last"), factor(c("u", "v"), levels = levels(f)))
  expect_identical(grp_reduce(f, g, "last", na.rm = FALSE),
                   factor(c(NA, "v"), levels = levels(f)))
  # A list column goes inside a list: a bare list is several columns.
  l <- list(1:2, NULL, "a", 3)
  expect_identical(grp_reduce(list(l), g, "first"), list(list(1:2, "a")))
  expect_identical(grp_reduce(list(l), g, "count"), list(c(2L, 2L)))
  skip_if_not_installed("bit64")
  b <- bit64::as.integer64(c("9007199254740993", NA, "1", "2"))
  expect_identical(grp_reduce(b, g, "first"), b[c(1L, 3L)])
  expect_identical(grp_reduce(b, g, "nobs"), c(1L, 2L))
  expect_error(grp_reduce(b, g, "sum"), class = "zutable_fn_error")
})

test_that("broadcast gathers the group value to the rows", {
  withr::local_seed(143)
  x <- sample(c(NA, stats::rnorm(30)), 200, TRUE)
  g <- grp(sample(letters[1:6], 200, TRUE))
  for (fn in c("sum", "mean", "max", "count", "first")) {
    v <- reduce_oracle(x, g$id, g$n, fn, TRUE)
    expect_identical(grp_reduce(x, g, fn, broadcast = "replace"), v[g$id])
    expect_identical(grp_reduce(x, g, fn, broadcast = "subtract"), x - v[g$id])
    expect_identical(grp_reduce(x, g, fn, broadcast = "divide"), x / v[g$id])
  }
  s <- sample(c("p", "q", NA), 200, TRUE)
  expect_identical(grp_reduce(s, g, "min", broadcast = "replace"),
                   reduce_oracle(s, g$id, g$n, "min", TRUE)[g$id])
  expect_error(grp_reduce(s, g, "first", broadcast = "subtract"), class = "zutable_fn_error")
})

test_that("several columns reduced together are each reduced alone, bit for bit", {
  withr::local_seed(144)
  n <- 9000L
  cols <- list(a = stats::rnorm(n), b = sample(c(NA, 1:50), n, TRUE),
               c = sample(c(NA, NaN, stats::runif(10)), n, TRUE),
               d = sample(c(TRUE, FALSE, NA), n, TRUE), e = sample(c(NA, letters), n, TRUE))
  fns <- c("mean", "sum", "max", "nobs", "min")
  g <- grp(sample(1:300, n, TRUE))
  for (na.rm in c(TRUE, FALSE)) {
    fused <- grp_reduce(cols, g, fns, na.rm = na.rm)
    alone <- Map(function(v, f) grp_reduce(v, g, f, na.rm = na.rm), cols, fns)
    expect_identical(fused, alone)
  }
  expect_identical(names(grp_reduce(as.data.frame(cols), g, fns)), names(cols))
  expect_identical(grp_reduce(cols[c("a", "b")], g, "sum"),
                   Map(function(v) grp_reduce(v, g, "sum"), cols[c("a", "b")]))
})

test_that("keys in by are grouped once, and the groups come back", {
  k <- c("b", "a", "b", NA)
  x <- c(1, 2, 3, 4)
  s <- grp_reduce(x, k, "sum")
  expect_identical(attr(s, "groups"), grp(k))
  expect_identical(as.vector(s), c(4, 2, 4))
  expect_identical(grp_reduce(x, grp(k), "sum"), c(4, 2, 4))
  two <- grp_reduce(list(x, x), data.frame(k, j = c(1, 1, 1, 2)), c("count", "mean"))
  expect_identical(attr(two, "groups"), grp(data.frame(k, j = c(1, 1, 1, 2))))
  expect_identical(two[[1L]], c(2L, 1L, 1L))
})

test_that("refusals", {
  g <- grp(1:3)
  expect_error(grp_reduce(1:3, g, "median"), class = "zutable_fn_error")
  expect_error(grp_reduce(1:3, g, NA_character_), class = "zutable_fn_error")
  expect_error(grp_reduce(1:3, g, character()), class = "zutable_fn_error")
  expect_error(grp_reduce(list(1:3, 1:3), g, c("sum", "sum", "sum")), class = "zutable_fn_error")
  expect_error(grp_reduce(letters[1:3], g, "sum"), class = "zutable_fn_error")
  expect_error(grp_reduce(factor(letters[1:3]), g, "min"), class = "zutable_fn_error")
  expect_error(grp_reduce(as.Date("2026-01-01") + 1:3, g, "mean"), class = "zutable_fn_error")
  expect_error(grp_reduce(1:4, g, "sum"), class = "zutable_length_error")
  expect_error(grp_reduce(1:3, 1:4, "sum"), class = "zutable_length_error")
  expect_error(grp_reduce(list(), g, "sum"), class = "zutable_type_error")
  expect_error(grp_reduce(list(1:3, mean), g, "count"), class = "zutable_type_error")
  expect_error(grp_reduce(1:3, g, na.rm = NA), class = "zutable_type_error")
  expect_error(grp_reduce(1:3, g, na.rm = c(TRUE, FALSE)), class = "zutable_type_error")
  expect_error(grp_reduce(1:3, g, broadcast = "scale"), class = "zutable_syntax_error")
  expect_error(grp_reduce(1:3, mean, "sum"), class = "zutable_type_error")
})

test_that("the kernel's entry point refuses what R never sends it, without a crash", {
  for (entry in c("zt_reduce_r", "zt_reduce_r_double")) {
    r <- function(...) .Call(get(entry, asNamespace("zutable")), ...)
    ok <- list(1:3, 3L, list(c(1, 2, 3)), 0L, TRUE, TRUE)
    expect_identical(do.call(r, ok), list(c(1, 2, 3)))
    bad <- list(
      list(c(1, 2, 3), 3L, list(1:3), 0L, TRUE, TRUE),      # ids not integer
      list(1:3, NA_integer_, list(1:3), 0L, TRUE, TRUE),    # group count NA
      list(1:3, 3L, list(1:3), c(0L, 1L), TRUE, TRUE),      # two statistics, one column
      list(c(1L, 4L, 2L), 3L, list(1:3), 0L, TRUE, TRUE),   # id past the group count
      list(1:3, 3L, list(1:3), 9L, TRUE, TRUE),             # unknown statistic
      list(1:3, 3L, list(letters[1:3]), 0L, TRUE, TRUE),    # a character column
      list(1:3, 3L, list(1:2), 0L, TRUE, TRUE)              # a column of the wrong length
    )
    for (b in bad) expect_error(do.call(r, b), "zt_reduce", info = entry)
  }
})
