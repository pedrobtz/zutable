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
