test_that("conform() returns a table of the schema", {
  s <- schema(id = not_null(int32), name = string)
  z <- conform(data.frame(id = 1:2, name = c("a", "b")), s)
  expect_s3_class(z, "zutable")
  expect_identical(schema(z), s)
})

test_that("conform() lists every mismatch", {
  s <- schema(id = int32, name = string, px = float64)
  df <- data.frame(name = 1:2, id = 1:2, extra = TRUE)
  cnd <- expect_error(conform(df, s), class = "zutable_schema_error")
  expect_length(cnd$problems, 4L)
  expect_match(cnd$problems, "`px` is missing", all = FALSE, fixed = TRUE)
  expect_match(cnd$problems, "`extra` is not in the schema", all = FALSE,
               fixed = TRUE)
  expect_match(cnd$problems, "another order", all = FALSE)
  expect_match(cnd$problems, "`name` is not string", all = FALSE,
               fixed = TRUE)
})

test_that("conform() raises a value error for NA in not_null", {
  expect_error(conform(data.frame(a = NA_integer_), schema(a = not_null(int32))),
               class = "zutable_value_error")
})

test_that("conform() refuses what is not a table or a schema", {
  expect_error(conform(1:3, schema(a = int32)), class = "zutable_schema_error")
  expect_error(conform(data.frame(a = 1L), "a"), class = "zutable_schema_error")
})

test_that("NaN is a value in a not_null float64 by every route (#63)", {
  s <- schema(a = not_null(float64), b = not_null(float64))
  # D47's rule, as the queries have it: is.na() is FALSE for NaN.
  nn <- as_zutable(data.frame(a = c(0, 1, NaN), b = c(0, 1, 2)), s)
  expect_identical(nn$a, c(0, 1, NaN))
  expect_identical(nn[select = .(m = is.na(a))]$m, c(FALSE, FALSE, FALSE))
  expect_no_error(zutable(a = NaN)[, "a"])
  for (ex in c("kernel", "reference")) {
    withr::local_options(zutable.executor = ex)
    r <- nn[select = .(q = a / b)]
    expect_identical(r$q, c(NaN, 1, NaN), info = ex)
    expect_no_error(conform(r, schema(r)))
    expect_no_error(conform(nn, s))
    u <- copy(nn)
    u[, a := a / b]
    expect_identical(u$a, c(NaN, 1, NaN), info = ex)
    expect_no_error(conform(u, schema(u)))
  }
  u <- copy(nn)
  u[2, "a"] <- NaN
  u$b <- c(NaN, NaN, NaN)
  expect_identical(u$a, c(0, NaN, NaN))
  expect_no_error(conform(u, s))
  expect_error(u$b <- c(1, NA, 1), class = "zutable_value_error")
  expect_error(u[1, "a"] <- NA_real_, class = "zutable_value_error")
  # NaN in a struct field is a value too: the row is not missing.
  st <- zutable(s = data.frame(x = c(NaN, 1)))
  expect_identical(st[select = .(m = is.na(s))]$m, c(FALSE, FALSE))
  expect_no_error(as_zutable(st, schema(s = not_null(struct(x = float64)))))
})

test_that("NaN behind a date or timestamp is refused on entry (#63)", {
  d <- structure(c(1, NaN), class = "Date")
  ts <- structure(c(0, NaN), class = c("POSIXct", "POSIXt"), tzone = "UTC")
  expect_error(zutable(d = d), class = "zutable_value_error")
  expect_error(zutable(t = ts), class = "zutable_value_error")
  expect_error(as_zutable(data.frame(d = d)), class = "zutable_value_error")
  expect_error(as_zutable(list(d = d), schema(d = date)), class = "zutable_value_error")
  expect_error(conform(data.frame(t = ts), schema(t = timestamp("us", "UTC"))),
               class = "zutable_value_error")
  z <- zutable(d = as.Date("2026-01-01") + 0:1, t = ts[c(1L, 1L)])
  expect_error(z$d <- d, class = "zutable_value_error")
  expect_error(z[2, "t"] <- ts[[2L]], class = "zutable_value_error")
  expect_error(z[, d := r(structure(c(NaN, 1), class = "Date"), date)],
               class = "zutable_value_error")
  expect_error(z[select = .(e = r(structure(c(NaN, 1), class = "Date"), date))],
               class = "zutable_value_error")
  expect_identical(z$d, as.Date("2026-01-01") + 0:1)
})
