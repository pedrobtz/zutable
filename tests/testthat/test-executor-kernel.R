# The kernel against the reference executor it replaces (D29): every
# aggregate query gives the same result through grp() as through match().

test_that("aggregate queries agree, kernel and reference", {
  withr::local_seed(47)
  df <- bracket_frame(500L)
  z <- as_zutable(df)
  queries <- list(
    function() z[, .(n = count(), s = sum(px)), by = g],
    function() z[, .(m = mean(px), c = count(k)), by = .(g, flag)],
    function() z[px > 0, .(hi = max(px), lo = min(g)), by = k],
    function() z[, .(n = count()), by = k, having = n > 25],
    function() z[, .(n = count()), by = .(mon = date_trunc("month", day))],
    function() z[select = .(.all, s = over(sum(px), by = g))],
    function() z[by = .(g, k)],
    function() z[, .(d = count_distinct(g)), by = flag]
  )
  for (q in queries) {
    expect_identical(plain(with_executor("kernel", q())),
                     plain(with_executor("reference", q())))
  }
  u <- copy(as_zutable(cbind(df, s = NA_real_)))
  r <- copy(u)
  with_executor("kernel", u[, s := px - mean(px), by = g])
  with_executor("reference", r[, s := px - mean(px), by = g])
  expect_identical(u$s, r$s)
})

test_that("ordered queries agree, kernel and reference", {
  withr::local_seed(48)
  df <- bracket_frame(3000L)
  df$x <- sample(c(NaN, NA, -0, 0, Inf, -Inf, stats::rnorm(40)), 3000L, TRUE)
  df$f <- factor(sample(c("lo", "mid", "hi", NA), 3000L, TRUE), levels = c("lo", "mid", "hi"))
  z <- as_zutable(df)
  queries <- list(
    function() z[order = k],
    function() z[order = desc(k)],
    function() z[order = .(desc(k), px)],
    function() z[order = .(flag, desc(day), id)],
    function() z[order = x],
    function() z[order = desc(x)],
    function() z[order = .(f, desc(x))],
    function() z[order = px * k],
    function() z[px > 0, .(id, px, k), order = .(desc(k), px), limit = 50],
    function() z[, .(n = count(), s = sum(px)), by = k, order = desc(s)],
    function() z[order = .(g, k)],
    function() z[select = .(.all, s = over(sum(px), by = g)), order = .(desc(s), id)]
  )
  for (i in seq_along(queries)) {
    expect_identical(plain(with_executor("kernel", queries[[i]]())),
                     plain(with_executor("reference", queries[[i]]())), info = i)
  }
})

test_that("joins agree, kernel and reference, for every how, multiple and na_equal", {
  withr::local_seed(49)
  mk <- function(n, tag) {
    d <- data.frame(
      id = seq_len(n),
      k = sample(c(1:6, NA), n, TRUE),
      s = sample(c("a", "é", iconv("é", "UTF-8", "latin1"), "", NA), n, TRUE),
      x = sample(c(NA, NaN, -0, 0, 2.5), n, TRUE),
      b = sample(c(TRUE, FALSE, NA), n, TRUE),
      day = as.Date("2026-01-01") + sample(c(0:3, NA), n, TRUE),
      e = factor(sample(c("lo", "hi", NA), n, TRUE), levels = c("lo", "hi")),
      stringsAsFactors = FALSE
    )
    names(d)[-1L] <- paste0(names(d)[-1L], tag)
    as_zutable(d)
  }
  # Both sizes of x against y, so the table is built on either side.
  for (sz in list(c(60L, 25L), c(25L, 60L))) {
    x <- mk(sz[[1L]], "")
    y <- mk(sz[[2L]], "2")
    ons <- list(
      quote(.(k == k2)), quote(.(s == s2)), quote(.(x == x2)), quote(.(b == b2)),
      quote(.(day == day2)), quote(.(e == e2)), quote(.(k == k2, s == s2)),
      quote(.(x == x2, e == e2, b == b2))
    )
    # Step 20 keeps one key of each native kind and the three-column one,
    # which reach every C path; the rest repeat them (a Date is a double, a
    # factor a string). In full this test took 41 of the 240 minutes there
    # (2026-11-18).
    if (under_torture()) ons <- ons[c(1L, 2L, 3L, 8L)]
    for (on in ons) {
      for (how in c("inner", "left", "right", "full", "semi", "anti")) {
        for (multiple in c("all", "first", "last")) {
          for (na_equal in c(TRUE, FALSE)) {
            run <- function(which) with_executor(which, eval(bquote(
              join(x, y, on = .(on), how = .(how), multiple = .(multiple),
                   na_equal = .(na_equal), suffix = c(".x", ".y"))
            )))
            expect_identical(plain(run("kernel")), plain(run("reference")),
                             info = paste(deparse(on), how, multiple, na_equal, sz[[1L]]))
          }
        }
      }
      for (how in c("inner", "left", "right", "full")) {
        k <- tryCatch(with_executor("kernel", eval(bquote(join(x, y, on = .(on), how = .(how),
                        multiple = "error", suffix = c(".x", ".y"))))), error = identity)
        r <- tryCatch(with_executor("reference", eval(bquote(join(x, y, on = .(on), how = .(how),
                        multiple = "error", suffix = c(".x", ".y"))))), error = identity)
        expect_identical(class(k), class(r))
        expect_identical(conditionMessage(k), conditionMessage(r))
      }
    }
  }
})

test_that("every aggregate of the vocabulary agrees, kernel and reference (Stage 14)", {
  withr::local_seed(145)
  latin <- iconv("é", "UTF-8", "latin1")
  for (n in c(0L, 1L, 70L, 5000L)) {
    df <- bracket_frame(n)
    df$x <- sample(c(NaN, NA, -0, 0, Inf, -Inf, 1e300, stats::rnorm(30)), n, TRUE)
    df$s <- sample(c(NA, "a", "", "B", "é", latin, "中"), n, TRUE)
    df$f <- factor(sample(c("lo", "mid", "hi", NA), n, TRUE), levels = c("lo", "mid", "hi"))
    df$ts <- as.POSIXct("2026-01-01", tz = "UTC") + sample(c(NA, 0:9) * 3600, n, TRUE)
    z <- as_zutable(df)
    queries <- list(
      function() z[, .(n = count(), nk = count(k), nx = count(x), ns = count(s),
                       nf = count(f), nt = count(ts)), by = g],
      function() z[, .(dk = count_distinct(k), dx = count_distinct(x), ds = count_distinct(s),
                       df = count_distinct(f), dd = count_distinct(day),
                       db = count_distinct(flag)), by = flag],
      function() z[, .(sk = sum(k), sx = sum(x), mk = mean(k), mx = mean(x)), by = .(g, flag)],
      function() z[, .(a = min(k), b = max(k), c = min(x), d = max(x), e = min(s), f = max(s),
                       h = min(day), i = max(day), j = min(ts), l = max(ts),
                       m = min(flag), o = max(flag)), by = g],
      function() z[, .(a = first(x), b = last(x), c = first(s), d = last(f),
                       e = first(ts), h = last(day)), by = g],
      function() z[, .(a = any(flag), b = all(flag), c = any(px > 0)), by = g],
      function() z[select = .(n = count(), s = sum(x), lo = min(s), d = count_distinct(g),
                             hi = max(day), f = first(f))],
      function() z[px > 100, .(n = count(), s = sum(px), m = max(s))],
      function() z[, .(r = sum(px) / count(), w = max(px) - min(px), c = cast(count(), float64),
                       q = case(sum(px) > 0 ~ "up", .default = "down"),
                       t = coalesce(max(k), 0L) + 1L), by = .(g, k)],
      function() z[, .(n = count(), s = sum(px)), by = g, having = n > 2 & s > 0],
      function() z[, .(n = count()), by = .(g, flag), having = max(px) > 1 | count_distinct(k) == 1L],
      function() z[select = .(.all, a = over(sum(px) / count(), by = g),
                             b = over(max(s), by = .(flag, k)), c = over(count()))],
      function() z[px > 0, .(k, a = over(min(x), by = g)), order = id]
    )
    for (i in seq_along(queries)) {
      expect_identical(plain(with_executor("kernel", queries[[i]]())),
                       plain(with_executor("reference", queries[[i]]())), info = paste(n, i))
    }
    u <- copy(as_zutable(cbind(df, w = rep(NA_real_, n), v = rep(NA_integer_, n))))
    r <- copy(u)
    with_executor("kernel", u[px > -2, { w := px - mean(px); v := count() }, by = .(g, flag)])
    with_executor("reference", r[px > -2, { w := px - mean(px); v := count() }, by = .(g, flag)])
    expect_identical(plain(u), plain(r), info = n)
    with_executor("kernel", u[, w := sum(x) / max(px)])
    with_executor("reference", r[, w := sum(x) / max(px)])
    expect_identical(plain(u), plain(r), info = n)
  }
})
