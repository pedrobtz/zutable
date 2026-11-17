
test_that("exact casts round-trip", {
  expect_identical(ec(c(1L, NA, -3L), quote(float64)), c(1, NA, -3))
  expect_identical(ec(c(1, NA, -3), quote(int32)), c(1L, NA, -3L))
  expect_identical(ec(c("12", " -7", NA), quote(int32)), c(12L, -7L, NA))
  expect_identical(ec(c(TRUE, FALSE, NA), quote(string)), c("true", "false", NA))
  expect_identical(ec(c("true", "F", NA), quote(bool)), c(TRUE, FALSE, NA))
  expect_identical(ec(c(0.1, 1/3, 1e20, NaN, -Inf), quote(string)),
                   c("0.1", "0.3333333333333333", "1e+20", "nan", "-inf"))
  for (v in c(0.1, 1/3, 2/3, 123.456, 1e-300, .Machine$double.xmax)) {
    expect_identical(as.double(ec(v, quote(string))), v)
  }
  expect_identical(ec(as.Date("2026-01-01"), quote(string)), "2026-01-01")
  expect_identical(ec("2026-01-01", quote(date)), as.Date("2026-01-01"))
  expect_identical(ec(as.Date("2026-01-01"), quote(timestamp("us", "UTC"))),
                   as.POSIXct("2026-01-01", tz = "UTC"))
  expect_identical(ec(.POSIXct(1767225600.5, "UTC"), quote(string)),
                   "2026-01-01 00:00:00.5")
  expect_identical(ec(factor("a"), quote(string)), "a")
  expect_identical(ec("hi", quote(enum(c("lo", "hi")))), factor("hi", levels = c("lo", "hi")))
})

test_that("a lossy cast errors on the first value it cannot represent", {
  expect_error(ec(c(1, 1.5), quote(int32)), class = "zutable_value_error")
  expect_error(ec(2^31, quote(int32)), class = "zutable_value_error")
  expect_identical(ec(2^31 - 1, quote(int32)), .Machine$integer.max)
  expect_error(ec(c(Inf), quote(int32)), class = "zutable_value_error")
  expect_error(ec(NaN, quote(int32)), class = "zutable_value_error")
  expect_error(ec("1.5", quote(int32)), class = "zutable_value_error")
  expect_error(ec("2147483648", quote(int32)), class = "zutable_value_error")
  expect_error(ec("x", quote(float64)), class = "zutable_value_error")
  expect_error(ec("maybe", quote(bool)), class = "zutable_value_error")
  expect_error(ec("2026-02-30", quote(date)), class = "zutable_value_error")
  expect_error(ec("medium", quote(enum(c("lo", "hi")))), class = "zutable_value_error")
})

test_that("unsupported casts are type errors", {
  expect_error(ec(as.Date("2026-01-01"), quote(int32)), class = "zutable_type_error")
  expect_error(ec(1, quote(date)), class = "zutable_type_error")
  expect_error(ec(list(1L), quote(string)), class = "zutable_type_error")
})
