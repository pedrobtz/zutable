test_that("over() agrees with ave()", {
  withr::local_seed(13)
  df <- bracket_frame(80L)
  df$k[is.na(df$k)] <- 99L
  z <- as_zutable(df)
  r <- z[select = .(.all, s = over(sum(px), by = k), m = over(mean(px), by = .(k, flag)),
                    n = over(count(), by = k), tot = over(sum(px)))]
  expect_equal(r$s, ave(df$px, df$k, FUN = sum))
  key <- paste(df$k, df$flag)
  expect_equal(r$m, ave(df$px, key, FUN = mean))
  expect_identical(r$n, as.integer(ave(df$px, df$k, FUN = length)))
  expect_equal(r$tot, rep(sum(df$px), nrow(df)))
  expect_identical(r$id, df$id)
})

test_that("over() needs an aggregate and stays out of aggregate queries", {
  z <- zutable(g = c("a", "b"), x = c(1, 2))
  expect_error(z[, .(y = over(x, by = g))], class = "zutable_type_error")
  expect_error(z[, .(y = over(sum(x), by = g)), by = g], class = "zutable_syntax_error")
  expect_error(z[, .(y = over(sum(x), group = g))], class = "zutable_syntax_error")
})

test_that("over() partitions only by a key `by` takes, in both executors (#78)", {
  z <- zutable(id = 1:4, st = data.frame(a = c(1L, 1L, 2L, NA), b = c("u", "u", "w", "w")),
               px = c(1, 2, 3, 4))
  for (ex in c("kernel", "reference")) {
    withr::local_options(zutable.executor = ex)
    # As by = st is refused, so is over(by = st), before any row is read.
    expect_error(z[, .(n = count()), by = st], class = "zutable_type_error")
    expect_error(z[select = .(id, c = over(count(), by = st))], class = "zutable_type_error")
    expect_error(z[select = .(id, c = over(sum(px), by = .(id, st)))],
                 class = "zutable_type_error")
  }
})
