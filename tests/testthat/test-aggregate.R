test_that("aggregates by a key agree with base R", {
  withr::local_seed(11)
  df <- bracket_frame(200L)
  z <- as_zutable(df)
  r <- z[, .(s = sum(px), m = mean(px), n = count(), hi = max(px), lo = min(px)),
         by = k]
  ok <- !is.na(df$k)
  # Base R drops NA keys, so they are compared apart.
  keys <- unique(df$k[ok])
  expect_identical(r$k[!is.na(r$k)], keys)
  rr <- r[!is.na(k)]
  expect_equal(rr$s, as.vector(tapply(df$px, df$k, sum)[as.character(keys)]))
  expect_equal(rr$m, as.vector(tapply(df$px, df$k, mean)[as.character(keys)]))
  expect_identical(rr$n, as.integer(table(df$k)[as.character(keys)]))
  expect_identical(rr$hi, as.vector(tapply(df$px, df$k, max)[as.character(keys)]))
  expect_identical(rr$lo, as.vector(tapply(df$px, df$k, min)[as.character(keys)]))
  agg <- stats::aggregate(px ~ k, data = df, FUN = sum)
  expect_equal(rr$s[order(rr$k)], agg$px[order(agg$k)])
  rs <- rowsum(df$px[ok], df$k[ok], reorder = FALSE)
  expect_equal(rr$s, unname(rs[as.character(keys), 1L]))
})

test_that("NA is a group, and groups come in order of first appearance", {
  z <- zutable(g = c("b", NA, "a", "b", NA, "c"), x = 1:6)
  r <- z[, .(n = count(), s = sum(x)), by = g]
  expect_identical(r$g, c("b", NA, "a", "c"))
  expect_identical(r$n, c(2L, 2L, 1L, 1L))
  expect_identical(r$s, c(5, 7, 3, 6))
  # NaN and NA are different groups; 0 and -0 are one.
  w <- zutable(v = c(NaN, NA, 0, -0, NaN), x = 1:5)
  expect_identical(w[, .(n = count()), by = v]$n, c(2L, 1L, 2L))
})

test_that("several keys, named key expressions, and a character vector", {
  withr::local_seed(12)
  df <- bracket_frame(120L)
  z <- as_zutable(df)
  r <- z[, .(n = count()), by = .(g, f = flag)]
  key <- paste(df$g, df$flag)
  expect_identical(r$n, as.integer(table(factor(key, levels = unique(key)))))
  expect_identical(names(r), c("g", "f", "n"))
  m <- z[, .(n = count()), by = .(mon = date_trunc("month", day))]
  expect_identical(m$mon, unique(as.Date(format(df$day, "%Y-%m-01"))))
  keys <- c("g", "k")
  expect_identical(plain(z[, .(n = count()), by = keys]),
                   plain(z[, .(n = count()), by = .(g, k)]))
})

test_that("a summary without by is one row, also over no rows", {
  z <- zutable(x = c(1, 2, NA))
  r <- z[select = .(n = count(), s = sum(x), m = mean(x))]
  expect_identical(plain(r), data.frame(n = 3L, s = 3, m = 1.5))
  e <- z[x > 10, .(n = count(), s = sum(x))]
  expect_identical(plain(e), data.frame(n = 0L, s = NA_real_))
  expect_identical(nrow(z[x > 10, .(n = count()), by = x]), 0L)
})

test_that("having filters groups and may name results or aggregate inputs", {
  z <- zutable(g = c("a", "a", "b", "c", "c", "c"), x = c(1, 2, 3, 4, 5, 6))
  expect_identical(z[, .(n = count()), by = g, having = n > 1]$g, c("a", "c"))
  expect_identical(z[, .(n = count()), by = g, having = sum(x) == 3]$g, c("a", "b"))
  expect_identical(z[, .(n = count()), by = g, having = sum(x) > 3]$g, "c")
  expect_identical(z[by = g, having = max(x) < 4]$g, c("a", "b"))
  expect_identical(z[, .(n = count()), by = g, having = n > 1, order = desc(n)]$g,
                   c("c", "a"))
})

test_that("key expressions in select; keys come first", {
  z <- zutable(id = c(2L, 1L, 2L), x = c(1, 2, 3))
  r <- z[, .(s = sum(x), twice = id * 2L), by = id]
  expect_identical(names(r), c("id", "s", "twice"))
  expect_identical(r$twice, c(4L, 2L))
  expect_identical(names(z[, .(id, s = sum(x)), by = id]), c("id", "s"))
})

test_that("refusals in aggregate queries", {
  z <- zutable(g = c("a", "b"), x = c(1, 2), l = list(1L, 2L))
  expect_error(z[, .(x), by = g], class = "zutable_type_error")
  expect_error(z[, .(y = x + sum(x)), by = g], class = "zutable_type_error")
  expect_error(z[, .(n = count()), by = g, having = x > 1], class = "zutable_type_error")
  expect_error(z[, .(n = count()), by = g, having = count()], class = "zutable_type_error")
  expect_error(z[, .(g = count()), by = g], class = "zutable_schema_error")
  expect_error(z[, .(n = count()), by = .(g, g)], class = "zutable_schema_error")
  expect_error(z[, .(n = count()), by = nope], class = "zutable_syntax_error")
  expect_error(z[, .(n = count()), by = .(x + 1)], class = "zutable_syntax_error")
  expect_error(z[, .(n = count()), by = .(s = sum(x))], class = "zutable_type_error")
  expect_error(z[, .(n = count()), by = l], class = "zutable_type_error")
  expect_error(z[, .(n = count()), by = 3], class = "zutable_syntax_error")
  expect_error(z[, .(n = count()), by = g, order = x], class = "zutable_syntax_error")
  expect_error(z[sum(x) > 1, .(n = count()), by = g], class = "zutable_type_error")
})

test_that("the aggregate plan's schema describes the result", {
  z <- as_zutable(data.frame(g = c("a", "b"), x = c(1L, 2L)),
                  schema(g = not_null(string), x = int32))
  r <- z[, .(n = count(), s = sum(x), f = first(x)), by = g]
  s <- schema(r)
  expect_identical(format(s), c("g not_null(string)", "n not_null(int32)",
                                "s float64", "f int32"))
  for (f in s$fields) expect_null(vector_problem(r[[f$name]], f$type))
})
