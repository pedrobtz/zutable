# Local semantics against base R, where they are the vocabulary's own and
# not simply R's defaults: the overflow rule, NaN as a value, byte order,
# SQL's null rules for aggregates, and NA propagation.


test_that("int32 arithmetic is straddled at the overflow limit", {
  big <- .Machine$integer.max
  expect_identical(ev(quote(a + b), a = big - 1L, b = 1L), big)
  expect_error(ev(quote(a + b), a = big, b = 1L), class = "zutable_value_error")
  expect_error(ev(quote(a + b), a = big, b = 2L), class = "zutable_value_error")
  expect_identical(ev(quote(a - b), a = -big + 1L, b = 1L), -big)
  expect_error(ev(quote(a - b), a = -big, b = 1L), class = "zutable_value_error")
  expect_error(ev(quote(a * b), a = 46341L, b = 46341L), class = "zutable_value_error")
  expect_identical(ev(quote(a * b), a = 46340L, b = 46340L), 46340L * 46340L)
  expect_identical(ev(quote(-a), a = big), -big)
  expect_identical(ev(quote(d - e), d = as.Date("2026-01-02"),
                      e = as.Date("2026-01-01")), 1L)
})

test_that("NaN is a value: equal to itself, above every number (D47)", {
  x <- c(NaN, NaN, 1, Inf, NA)
  y <- c(NaN, 1, NaN, NaN, 1)
  expect_identical(ev(quote(a == b), a = x, b = y), c(TRUE, FALSE, FALSE, FALSE, NA))
  expect_identical(ev(quote(a > b), a = x, b = y), c(FALSE, TRUE, FALSE, FALSE, NA))
  expect_identical(ev(quote(is.na(a)), a = x), c(FALSE, FALSE, FALSE, FALSE, TRUE))
  expect_identical(ev(quote(max(a)), a = c(1, NaN)), NaN)
  expect_identical(ev(quote(min(a)), a = c(1, NaN)), 1)
  expect_identical(ev(quote(count(a)), a = x), 4L)
  expect_true(is.nan(ev(quote(sum(a)), a = c(1, NaN, NA))))
})

test_that("NA wins over NaN in arithmetic", {
  expect_identical(ev(quote(a * b), a = c(NA, NaN), b = c(NaN, NA)), c(NA_real_, NA_real_))
  expect_identical(ev(quote(a ^ b), a = c(NA, 1), b = c(0, NA)), c(NA_real_, NA_real_))
})

test_that("strings compare by bytes under a collation that does not", {
  # testthat runs tests under LC_COLLATE=C, where base R compares bytes too;
  # a real collation shows the difference.
  ok <- suppressWarnings(Sys.setlocale("LC_COLLATE", "en_US.UTF-8"))
  skip_if(!nzchar(ok), "no en_US.UTF-8 locale")
  withr::defer(Sys.setlocale("LC_COLLATE", "C"))
  skip_if(!("a" < "B"), "the locale's collation is byte order")
  expect_identical(ev(quote(a < b), a = "a", b = "B"), FALSE)
  expect_identical(ev(quote(max(a)), a = c("a", "B")), "a")
  expect_identical(ev(quote(min(a)), a = c("a", "B")), "B")
})

test_that("strings compare by bytes, whatever the collation", {
  a <- c("B", "a", "Z", "é", "e")
  b <- c("a", "B", "a", "f", "é")
  want <- vapply(seq_along(a), function(i) {
    x <- as.integer(charToRaw(enc2utf8(a[[i]])))
    y <- as.integer(charToRaw(enc2utf8(b[[i]])))
    k <- min(length(x), length(y))
    d <- which(x[seq_len(k)] != y[seq_len(k)])
    if (length(d)) x[[d[[1L]]]] < y[[d[[1L]]]] else length(x) < length(y)
  }, NA)
  expect_identical(ev(quote(a < b), a = a, b = b), want)
  expect_identical(ev(quote(max(a)), a = a), "é")
  expect_identical(ev(quote(min(a)), a = a), "B")
})

test_that("aggregates follow SQL's null rules (D46)", {
  expect_identical(ev(quote(sum(a)), a = c(1L, NA, 2L)), 3)
  expect_identical(ev(quote(sum(a)), a = c(NA_integer_, NA)), NA_real_)
  expect_identical(ev(quote(sum(a)), a = integer()), NA_real_)
  expect_identical(ev(quote(mean(a)), a = c(1, NA, 4)), 2.5)
  expect_identical(ev(quote(count()), a = c(1, NA)), 2L)
  expect_identical(ev(quote(count(a)), a = c(1, NA)), 1L)
  expect_identical(ev(quote(count_distinct(a)), a = c("x", "y", "x", NA)), 2L)
  expect_identical(ev(quote(any(a)), a = c(NA, FALSE)), FALSE)
  expect_identical(ev(quote(all(a)), a = logical()), NA)
  expect_identical(ev(quote(first(a)), a = c(NA, 2L)), NA_integer_)
  expect_identical(ev(quote(last(a)), a = c(1L, 2L)), 2L)
  expect_identical(ev(quote(min(a)), a = as.Date(c("2026-02-01", NA, "2026-01-01"))),
                   as.Date("2026-01-01"))
})

test_that("R's own behaviour where the vocabulary keeps it", {
  expect_identical(ev(quote(a %/% b), a = c(7L, -7L, 7L), b = c(2L, 2L, 0L)),
                   c(3L, -4L, NA))
  expect_identical(ev(quote(a %% b), a = c(7L, -7L), b = c(-2L, 2L)), c(-1L, 1L))
  expect_identical(ev(quote(substr(a, 2L, 3L)), a = c("abcd", "a", NA)),
                   substr(c("abcd", "a", NA), 2L, 3L))
  expect_identical(ev(quote(round(a)), a = c(0.5, 1.5, 2.5, -0.5)),
                   round(c(0.5, 1.5, 2.5, -0.5)))
  expect_identical(ev(quote(ifelse(c, 1L, 2L)), c = c(TRUE, NA, FALSE)), c(1L, NA, 2L))
  expect_identical(ev(quote(a ^ b), a = c(-1, 0, -8), b = c(Inf, -1, 1/3)),
                   c(-1, 0, -8)^c(Inf, -1, 1/3))
  expect_identical(ev(quote(nchar(a)), a = c("café", "", NA)), c(4L, 0L, NA))
  expect_identical(ev(quote(trim(a)), a = c(" \tx \n", "y")), c("x", "y"))
})

test_that("D48: float %/% and %% are floor(x / y) and x - y * floor(x / y)", {
  x <- c(-3, 5, 7.5, 1)
  y <- c(Inf, Inf, 2, 0)
  expect_identical(ev(quote(a %/% b), a = x, b = y), floor(x / y))
  expect_identical(ev(quote(a %% b), a = x, b = y), x - y * floor(x / y))
})

test_that("NA propagates through concat, like and %in%", {
  expect_identical(ev(quote(paste0(a, b)), a = c("x", NA), b = c("y", "z")),
                   c("xy", NA))
  expect_identical(ev(quote(like(a, "a%")), a = c("ab", "ba", NA)), c(TRUE, FALSE, NA))
  expect_identical(ev(quote(like(a, "a_c")), a = c("abc", "a.c", "ac", "a\nc")),
                   c(TRUE, TRUE, FALSE, TRUE))
  expect_identical(ev(quote(like(a, "50%")), a = c("50%", "500", "5")),
                   c(TRUE, TRUE, FALSE))
  expect_identical(ev(quote(a %in% c(1L, 3L)), a = c(1L, 2L, NA)), c(TRUE, FALSE, NA))
  expect_error(ev(quote(a %in% c(1L, NA)), a = 1:2), class = "zutable_value_error")
})

test_that("case() takes the first TRUE condition; NA conditions are skipped", {
  out <- ev(quote(case(a > 2 ~ "big", a > 0 ~ "small", .default = "none")),
            a = c(3L, 1L, NA, -1L))
  expect_identical(out, c("big", "small", "none", "none"))
  expect_identical(ev(quote(case(a > 2 ~ a)), a = c(3L, 1L)), c(3L, NA))
  expect_error(ev(quote(case(a ~ 1L)), a = 1:2), class = "zutable_type_error")
  expect_error(ev(quote(case(a > 1 ~ 1L, .default = "x")), a = 1:2),
               class = "zutable_type_error")
})

test_that("dates: parts and date_trunc", {
  d <- as.Date(c("2026-03-15", "2025-12-31", NA))
  expect_identical(ev(quote(year(a)), a = d), c(2026L, 2025L, NA))
  expect_identical(ev(quote(month(a)), a = d), c(3L, 12L, NA))
  expect_identical(ev(quote(date_trunc("month", a)), a = d),
                   as.Date(c("2026-03-01", "2025-12-01", NA)))
  expect_identical(ev(quote(date_trunc("week", a)), a = as.Date("2026-11-19")),
                   as.Date("2026-11-16"))
  expect_error(ev(quote(date_trunc("hour", a)), a = d), class = "zutable_value_error")
  t <- as.POSIXct("2026-03-15 13:45:10", tz = "Asia/Tokyo")
  expect_identical(ev(quote(day(a)), a = t), 15L)
  expect_identical(format(ev(quote(date_trunc("hour", a)), a = t), tz = "Asia/Tokyo"),
                   "2026-03-15 13:00:00")
})

test_that("r() runs arbitrary R and checks its declared type", {
  s <- schema(px = float64, qty = int32)
  cols <- list(px = c(1, 2), qty = c(3L, 4L))
  my_model <- function(a, b) a * b
  node <- zt_translate(quote(r(my_model(px, qty), float64)), s, environment())
  expect_true(node$opaque)
  expect_setequal(node$columns, c("px", "qty"))
  expect_identical(zt_eval(node, cols, 2L), c(3, 8))
  bad <- zt_translate(quote(r(as.character(px), float64)), s, environment())
  expect_error(zt_eval(bad, cols, 2L), class = "zutable_type_error")
  short <- zt_translate(quote(r(px[1:3], float64)), s, environment())
  expect_error(zt_eval(short, cols, 2L), class = "zutable_type_error")
  expect_error(zt_sql_expr(node), class = "zutable_engine_error")
})

test_that("SQL literals do not change under a hostile session", {
  s <- schema(f = float64, i = int32)
  node <- zt_translate(quote(f * 0.1 + i + 12345678.9), s, environment())
  plain_sql <- zt_sql_expr(node)
  withr::local_options(OutDec = ",", scipen = -5, digits = 3)
  expect_identical(zt_sql_expr(node), plain_sql)
  expect_match(plain_sql, "CAST(12345678.9 AS DOUBLE)", fixed = TRUE)
  expect_match(plain_sql, "CAST(0.10000000000000001 AS DOUBLE)", fixed = TRUE)
})
