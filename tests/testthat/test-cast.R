
test_that("exact casts round-trip", {
  expect_identical(ec(c(1L, NA, -3L), quote(float64)), c(1, NA, -3))
  expect_identical(ec(c(1, NA, -3), quote(int32)), c(1L, NA, -3L))
  expect_identical(ec(c("12", " -7", NA), quote(int32)), c(12L, -7L, NA))
  expect_identical(ec(c(TRUE, FALSE, NA), quote(string)), c("true", "false", NA))
  expect_identical(ec(c("true", "F", NA), quote(bool)), c(TRUE, FALSE, NA))
  # ECMAScript Number::toString notation, shortest digits (Ryu).
  expect_identical(ec(c(1 / 10, 1 / 3, 1e20, 1e21, 1e-7, -0, NaN, -Inf), quote(string)),
                   c("0.1", "0.3333333333333333", "100000000000000000000",
                     "1e+21", "1e-7", "-0", "nan", "-inf"))
  # Values built by arithmetic, so no parser is the oracle: R's own is not
  # correctly rounded on every platform.
  hard <- c(1 / 10, 1 / 3, 2 / 3, 2^-1074, 2^-1022, (2 - 2^-52) * 2^1023,
            -(1 + 2^-52), 9007199254740993 - 1)
  for (v in hard) {
    expect_identical(ec(ec(v, quote(string)), quote(float64)), v)
  }
  expect_identical(ec(c("1.7976931348623157e+308", "5e-324", "0.1", "+2.5", " 7 "),
                      quote(float64)),
                   c((2 - 2^-52) * 2^1023, 2^-1074, 1 / 10, 2.5, 7))
  expect_identical(ec(c("inf", "-Infinity", "nan"), quote(float64)), c(Inf, -Inf, NaN))
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
  expect_error(ec("1e400", quote(float64)), class = "zutable_value_error")
  expect_error(ec("1.5x", quote(float64)), class = "zutable_value_error")
  expect_error(ec("0x1A", quote(float64)), class = "zutable_value_error")
  expect_error(ec("", quote(float64)), class = "zutable_value_error")
  expect_error(ec("maybe", quote(bool)), class = "zutable_value_error")
  expect_error(ec("2026-02-30", quote(date)), class = "zutable_value_error")
  expect_error(ec("medium", quote(enum(c("lo", "hi")))), class = "zutable_value_error")
})

test_that("unsupported casts are type errors", {
  expect_error(ec(as.Date("2026-01-01"), quote(int32)), class = "zutable_type_error")
  expect_error(ec(1, quote(date)), class = "zutable_type_error")
  expect_error(ec(list(1L), quote(string)), class = "zutable_type_error")
})

test_that("int32 widens to int64 where implicit (#67)", {
  skip_if_not_installed("zuint")
  i64 <- zuint::int64
  base <- function() zutable(i = i64(c(1L, 2L)), j = c(5L, NA))
  # Oracle: the same route with an explicit int64 value.
  same <- function(got, want) expect_identical(as.character(got$i), as.character(want$i))
  for (ex in c("kernel", "reference")) {
    withr::local_options(zutable.executor = ex)
    a <- base(); b <- base()
    a[, i := j]
    b[, i := r(i64(j), int64)]
    same(a, b)
    a <- base(); b <- base()
    a[, i := 7L]
    b[, i := r(i64(7L), int64)]
    same(a, b)
    a <- base(); b <- base()
    a[j > 1L, i := j * 2L]
    b[j > 1L, i := r(i64(j * 2L), int64)]
    same(a, b)
    expect_identical(as.character(base()[select = .(c = cast(j, int64))]$c),
                     as.character(i64(c(5L, NA))))
    expect_identical(as.character(base()[select = .(c = cast(i, int64))]$c),
                     as.character(i64(c(1L, 2L))))
    expect_identical(schema(base()[select = .(c = cast(j, int64))])$fields$c$type$id, "int64")
  }
  a <- base(); b <- base()
  a$i <- 7L
  b$i <- i64(7L)
  same(a, b)
  a <- base(); b <- base()
  a[2, "i"] <- NA_integer_
  b[2, "i"] <- i64(NA)
  same(a, b)
  a <- base(); b <- base()
  a[["i"]] <- c(3L, 4L)
  b[["i"]] <- i64(c(3L, 4L))
  same(a, b)
  expect_no_error(conform(a, schema(a)))
  # Not the other way: int64 to int32 is a cast, never implicit.
  z <- base()
  expect_error(z[, j := i], class = "zutable_schema_error")
})

test_that("int32 to int64 without zuint is a type error naming it (#67)", {
  z <- zutable(j = 1:2)
  local_packages(character())
  x <- new_zutable(list(i = zu_int64_of(1:2), j = 1:2),
                   new_schema(list(new_field("i", zt_type("int64")), new_field("j", zt_type("int32")))),
                   2L)
  err <- expect_error(x[, i := j], class = "zutable_type_error")
  expect_identical(err$package, "zuint")
  err <- expect_error(x$i <- 7L, class = "zutable_type_error")
  expect_identical(err$package, "zuint")
  err <- expect_error(z[select = .(c = cast(j, int64))], class = "zutable_type_error")
  expect_identical(err$package, "zuint")
})

# The nearest whole microsecond of each double, from its exact decimal
# expansion (a double's expansion is finite and %.60f prints all of it), so
# no floating-point product decides the rounding. No double lies exactly
# halfway between two microseconds.
us_oracle <- function(x) {
  vapply(x, function(v) {
    s <- sprintf("%.60f", abs(v))
    whole <- as.double(sub("\\..*$", "", s))
    frac <- sub("^[^.]*\\.", "", s)
    us <- as.double(substr(frac, 1L, 6L)) + (substr(frac, 7L, 7L) >= "5")
    sign(v) * (whole * 1e6 + us)
  }, 0)
}

us_text <- function(us) {
  sec <- floor(us / 1e6)
  micro <- us - sec * 1e6
  frac <- ifelse(micro == 0, "", sub("0+$", "", sprintf(".%06d", as.integer(micro))))
  paste0(format(.POSIXct(sec, "UTC"), "%Y-%m-%d %H:%M:%S", tz = "UTC"), frac)
}

test_that("a timestamp's text carries the second its microseconds round to (#51)", {
  ks <- c(0, 1, 1700000001, -86400 * 400, -1)
  x <- as.vector(outer(c(-0.5e-6, -0.4e-6, 0.5e-6, -0.6e-6, 0.4e-6), ks, `+`))
  us <- us_oracle(x)
  want <- us_text(us)
  z <- zutable(t = .POSIXct(x, "UTC"))
  got <- z[select = .(a = cast(t, string))]$a
  expect_identical(got, want)
  # The text reads back as the same microsecond.
  back <- zutable(a = got)[select = .(t = cast(a, timestamp("us", "UTC")))]$t
  expect_identical(posixct_to_us(back), us)
  # explain() and the SQL literal write the same text.
  for (i in seq_along(x)) {
    lit <- .POSIXct(x[[i]], "UTC")
    out <- utils::capture.output(explain(z[t == lit]))
    expect_true(any(grepl(sprintf('timestamp "%s"', want[[i]]), out, fixed = TRUE)),
                info = want[[i]])
  }
  expect_identical(zt_sql_literal(.POSIXct(0.9999996, "UTC"), zt_timestamp("us", "UTC")),
                   "TIMESTAMP '1970-01-01 00:00:01'")
})
