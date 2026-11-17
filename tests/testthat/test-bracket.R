test_that("where keeps the rows whose condition is TRUE, in input order", {
  withr::local_seed(1)
  df <- bracket_frame()
  z <- as_zutable(df)
  expect_identical(plain(z[px > 0]), plain(df[which(df$px > 0), ]))
  expect_identical(plain(z[where = k >= 0 & flag]),
                   plain(df[which(df$k >= 0 & df$flag), ]))
  expect_identical(plain(z[is.na(g) | g == "a"]),
                   plain(df[which(is.na(df$g) | df$g == "a"), ]))
  expect_identical(plain(z[day >= "2026-01-15"]),
                   plain(df[which(df$day >= as.Date("2026-01-15")), ]))
  expect_identical(nrow(z[px > 100]), 0L)
})

test_that("select projects columns and computes named ones", {
  withr::local_seed(2)
  df <- bracket_frame()
  z <- as_zutable(df)
  r <- z[, .(id, twice = px * 2, kk = coalesce(k, 0L))]
  expect_identical(names(r), c("id", "twice", "kk"))
  expect_identical(r$twice, df$px * 2)
  expect_identical(r$kk, ifelse(is.na(df$k), 0L, df$k))
  expect_identical(plain(z[, px]), plain(df["px"]))
  expect_identical(plain(z[select = .(.all, -flag, -day)]),
                   plain(df[c("id", "g", "k", "px")]))
  expect_identical(z[, .(one = 1L)]$one, rep(1L, nrow(df)))
})

test_that("order is stable, NA last, strings in byte order", {
  withr::local_seed(3)
  df <- bracket_frame()
  z <- as_zutable(df)
  expect_identical(plain(z[order = g]),
                   plain(df[order(df$g, method = "radix", na.last = TRUE), ]))
  expect_identical(plain(z[order = .(desc(k), id)]),
                   plain(df[order(-df$k, df$id, method = "radix", na.last = TRUE), ]))
  expect_identical(plain(z[order = .(day, desc(px))]),
                   plain(df[order(df$day, -df$px, method = "radix", na.last = TRUE), ]))
  # Keys may name input columns that the result leaves out.
  expect_identical(z[select = .(id), order = desc(px)]$id,
                   df$id[order(-df$px, method = "radix")])
  # NA last in both directions.
  expect_identical(z[order = desc(k)]$k, df$k[order(-df$k, method = "radix", na.last = TRUE)])
})

test_that("NaN sorts above every number and before NA (D47)", {
  z <- zutable(x = c(1, NaN, NA, Inf, -1))
  expect_identical(z[order = x]$x, c(-1, 1, Inf, NaN, NA))
  expect_identical(z[order = desc(x)]$x, c(NaN, Inf, 1, -1, NA))
  expect_identical(z[x > 1e300]$x, c(NaN, Inf))
})

test_that("limit and distinct", {
  withr::local_seed(4)
  df <- bracket_frame()
  z <- as_zutable(df)
  expect_identical(plain(z[limit = 5]), plain(head(df, 5)))
  expect_identical(nrow(z[limit = 0]), 0L)
  expect_identical(nrow(z[limit = 1000]), nrow(df))
  expect_identical(plain(z[, .(g), distinct = TRUE]), plain(unique(df["g"])))
  expect_identical(plain(z[select = .(g, k), distinct = TRUE]),
                   plain(unique(df[c("g", "k")])))
  expect_identical(z[, .(g), distinct = TRUE, order = g, limit = 2]$g,
                   head(sort(unique(df$g), method = "radix", na.last = TRUE), 2))
})

test_that("clauses run in SQL's logical order whatever order they are written", {
  withr::local_seed(5)
  z <- as_zutable(bracket_frame())
  a <- z[limit = 3, order = desc(px), where = k > 0, select = .(id, px)]
  b <- z[k > 0, .(id, px), order = desc(px), limit = 3]
  expect_identical(plain(a), plain(b))
})

test_that("chained brackets are steps", {
  withr::local_seed(6)
  df <- bracket_frame()
  z <- as_zutable(df)
  r <- z[px > 0][, .(id, half = px / 2)][order = desc(half), limit = 3]
  sub <- df[which(df$px > 0), ]
  want <- head(sub$id[order(-(sub$px / 2), method = "radix")], 3)
  expect_identical(r$id, want)
})

test_that("a bracket always returns a table", {
  z <- zutable(a = 1:3, b = c("x", "y", "z"))
  expect_s3_class(z[, b], "zutable")
  expect_s3_class(z[a > 5], "zutable")
  expect_identical(z$b, c("x", "y", "z"))
})
