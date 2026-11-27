# The fixed computations of .agents/ergonomics.md, in the spellings kept by
# D55, each against base R.

test_that("1. VWAP and count per instrument, top five", {
  df <- ergo_trades()
  t <- as_zutable(df)
  r <- t[where  = day >= "2026-01-02",
         select = .(vwap = sum(px * qty) / sum(qty), n = count()),
         by     = id,
         order  = desc(vwap),
         limit  = 5]
  s <- df[df$day >= as.Date("2026-01-02"), ]
  vwap <- tapply(s$px * s$qty, s$id, sum) / tapply(s$qty, s$id, sum)
  o <- order(-vwap)
  expect_identical(r$id, as.integer(names(vwap))[o])
  expect_equal(r$vwap, as.vector(vwap)[o])
  expect_identical(r$n, as.integer(table(s$id))[o])
})

test_that("2. each trade's share of its instrument's notional", {
  df <- ergo_trades()
  t <- as_zutable(df)
  r <- t[select = .(.all, share = px * qty / over(sum(px * qty), by = id))]
  expect_equal(r$share, df$px * df$qty / ave(df$px * df$qty, df$id, FUN = sum))
})

test_that("3. two placeholders filled in one pass, per group", {
  df <- ergo_trades()
  t <- as_zutable(cbind(df, notional = NA_real_, share = NA_real_))
  t[, {
    w <- px * qty
    notional := w
    share    := w / sum(w)
  }, by = id]
  w <- df$px * df$qty
  expect_equal(t$notional, w)
  expect_equal(t$share, w / ave(w, df$id, FUN = sum))
})

test_that("4. monthly totals by a named key expression", {
  df <- ergo_trades()
  t <- as_zutable(df)
  r <- t[, .(total = sum(px * qty)), by = .(month = date_trunc("month", day))]
  m <- as.Date(format(df$day, "%Y-%m-01"))
  expect_identical(r$month, unique(m))
  # Keyed by text: before R 4.3 factor() of a Date matches no Date levels.
  key <- format(m)
  expect_equal(r$total, as.vector(tapply(df$px * df$qty, factor(key, levels = unique(key)), sum)))
})

test_that("5. a join, then an aggregate", {
  t <- as_zutable(ergo_trades())
  instruments <- zutable(id = 1:3, sector = c("x", "y", "x"))
  r <- join(t, instruments, on = id)[, .(n = count()), by = sector]
  m <- merge(ergo_trades(), data.frame(id = 1:3, sector = c("x", "y", "x")))
  expect_identical(r$sector, c("x", "y"))
  expect_identical(r$n, as.integer(table(m$sector)[c("x", "y")]))
})

test_that("6. a column chosen by a variable", {
  t <- as_zutable(ergo_trades())
  top_by <- function(t, col, n) t[order = desc(.col(col)), limit = n]
  expect_identical(top_by(t, "px", 2)$px, c(21, 20))
  expect_identical(top_by(t, "qty", 1)$qty, 300L)
  expect_error(top_by(t, "nope", 1), class = "zutable_schema_error")
  expect_error(t[order = .col(c("px", "qty"))], class = "zutable_syntax_error")
})

test_that("7. chained steps", {
  df <- ergo_trades()
  t <- as_zutable(df)
  r <- t[qty > 0][, .(id, notional = px * qty)][notional > 1000]
  n <- df$px * df$qty
  expect_identical(r$id, df$id[n > 1000])
  expect_identical(r$notional, n[n > 1000])
})

test_that("8. distinct keys, ordered", {
  t <- as_zutable(ergo_trades())
  expect_identical(t[, .(id), distinct = TRUE, order = id]$id, 1:3)
})

test_that("D28 is kept: an update in the first position is a syntax error", {
  t <- as_zutable(ergo_trades())
  expect_error(t[{ px := 1 }], class = "zutable_syntax_error")
  # The message shows the supported spelling.
  expect_snapshot(t[{ px := 1 }], error = TRUE)
  expect_error(t[px := 1], class = "zutable_syntax_error")
})
