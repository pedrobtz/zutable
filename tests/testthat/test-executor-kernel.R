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
