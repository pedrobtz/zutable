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

test_that("each string of a vector is read by its own ISO form (#54)", {
  forms <- list(
    c("2020-01-01 10:00:30", "%Y-%m-%d %H:%M:%S"),
    c("2020-01-01 10:00", "%Y-%m-%d %H:%M"),
    c("2020-01-01", "%Y-%m-%d"),
    c("2020-01-01T10:00:30.25", "%Y-%m-%dT%H:%M:%OS")
  )
  perms <- function(v) {
    if (length(v) <= 1L) return(list(v))
    do.call(c, lapply(seq_along(v), function(i) {
      lapply(perms(v[-i]), function(p) c(v[[i]], p))
    }))
  }
  # Under gctorture, the four rotations put each form at each position.
  orders <- if (under_torture()) {
    lapply(0:3, function(k) (seq_along(forms) + k - 1L) %% 4L + 1L)
  } else {
    perms(seq_along(forms))
  }
  for (tz in c("UTC", "Asia/Tokyo")) {
    # One at a time, each with its own format: base R as the oracle.
    one <- vapply(forms, function(f) {
      posixct_to_us(as.POSIXct(f[[1L]], tz = tz, format = f[[2L]]))
    }, 0)
    for (p in orders) {
      s <- vapply(forms[p], `[[`, "", 1L)
      got <- ec(s, call("timestamp", "us", tz))
      expect_identical(posixct_to_us(got), one[p], info = paste(tz, s, collapse = ","))
      tt <- zutable(t = .POSIXct(one[p] / 1e6, tz))
      expect_identical(nrow(tt[t %in% s]), length(s))
      expect_identical(nrow(tt[t %in% s[1:2]]),
                       nrow(tt[t == s[[1L]] | t == s[[2L]]]))
      expect_identical(nrow(tt[t %in% s[1:2]]), 2L)
    }
    for (i in seq_along(forms)) {
      tt <- zutable(t = .POSIXct(one / 1e6, tz))
      expect_identical(tt[t == forms[[i]][[1L]]]$t, tt$t[i])
    }
  }
})

test_that("a string in no accepted ISO form is a value error in cast() (#54)", {
  bad <- c("2020-01-01 10", "2020-01-01 10:00:60", "2020-13-01",
           "2020-02-30 00:00", "2020-01-01 24:00", "2020-01-01T10:00:00Z",
           "2020-01-01 10:00:00.1234567", "2020-1-01", " 2020-01-01")
  for (b in bad) {
    z <- zutable(s = c("2020-01-01", b))
    expect_error(z[select = .(t = cast(s, timestamp("us", "UTC")))],
                 class = "zutable_value_error", info = b)
  }
})

test_that("cast(string, timestamp) agrees with DuckDB per string (#54)", {
  skip_if_not_installed("duckdb")
  con <- duck_connect()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  s <- c("2020-01-01 10:00:30", "2020-01-01", "1969-12-31T23:59:59.999999",
         "2020-01-01 10:00", "2000-02-29 00:00:00.5", NA)
  got <- zutable(s = s)[select = .(t = cast(s, timestamp("us", "UTC")))]$t
  sql <- sprintf("SELECT CAST(s AS TIMESTAMP) AS t FROM (VALUES %s) v(s)",
                 paste(sprintf("(%s)", ifelse(is.na(s), "NULL",
                                              sprintf("'%s'", s))), collapse = ", "))
  want <- DBI::dbGetQuery(con, sql)$t
  expect_identical(posixct_to_us(got), posixct_to_us(want))
})

test_that("cast() between timestamp units refuses a finer part (#59)", {
  units <- c("s", "ms", "us")
  # Microseconds from 1970: whole seconds, whole milliseconds, and finer.
  exact <- list(s = c(-2e6, 0, 3e6, NA), ms = c(-1000, 2500000, 3123000),
                us = c(-1, 2500001, 3123456))
  step <- c(s = 1e6, ms = 1e3, us = 1)
  for (from in units) {
    for (to in units) {
      for (vals in exact[seq_len(match(from, units))]) {
        x <- .POSIXct(vals / 1e6, "UTC")
        s <- new_schema(list(new_field("x", zt_timestamp(from, "UTC"))))
        z <- as_zutable(data.frame(x = x), s)
        q <- substitute(z[select = .(y = cast(x, timestamp(TO, "UTC")))],
                        list(TO = to))
        fits <- all(vals %% step[[to]] == 0, na.rm = TRUE)
        if (fits) {
          y <- eval(q)
          expect_identical(posixct_to_us(y$y), vals, info = paste(from, to))
          expect_identical(schema(y)$fields[["y"]]$type, zt_timestamp(to, "UTC"))
          expect_silent(conform(y, schema(y)))
        } else {
          expect_error(eval(q), class = "zutable_value_error", info = paste(from, to))
        }
      }
    }
  }
})

test_that("a POSIXct constant in another zone compares as an instant (#89)", {
  t <- as.POSIXct(c("2020-06-01 12:00:00", "2020-06-01 13:00:00"), tz = "Asia/Tokyo")
  z <- zutable(t = t)
  at <- as.POSIXct("2020-06-01 03:00:00", tz = "UTC")
  local <- .POSIXct(as.double(at))
  # Base R compares the stored instants: the oracle.
  for (ex in c("kernel", "reference")) {
    withr::local_options(zutable.executor = ex)
    expect_identical(z[t == at]$t, t[as.double(t) == as.double(at)])
    expect_identical(z[t > at]$t, t[as.double(t) > as.double(at)])
    expect_identical(z[t <= local]$t, t[as.double(t) <= as.double(local)])
    expect_identical(nrow(z[t < Sys.time()]), 2L)
    expect_identical(z[t %in% c(at, at + 3600)]$t, t)
  }
  # A zoneless column is wall-clock time, not an instant: still refused.
  s <- new_schema(list(new_field("w", zt_type("timestamp", unit = "us", tz = NULL))))
  w <- as_zutable(data.frame(w = .POSIXct(0, "UTC")), s)
  expect_error(w[w == t[[1L]]], class = "zutable_type_error")
  # Elsewhere a zone is still part of the type.
  expect_error(z[select = .(x = coalesce(t, at))], class = "zutable_type_error")
})

test_that("cast() to timestamp(\"ns\") is refused even with zutempo present (#77)", {
  # The cast rule refuses ns as a target outright; zutempo's absence is a
  # separate type error (with `package`), so the test makes zutempo look
  # installed to see the cast's own refusal.
  local_mocked_bindings(zt_has_package = function(pkg) TRUE)
  z <- zutable(d = as.Date("2026-01-01") + 0:1,
               t = .POSIXct(c(0, 1), "UTC"))
  for (q in list(quote(z[, .(x = cast(d, timestamp("ns")))]),
                 quote(z[, .(x = cast(t, timestamp("ns")))]),
                 quote(z[, .(x = cast("2026-01-01", timestamp("ns")))]))) {
    cnd <- expect_error(eval(q), class = "zutable_type_error")
    expect_null(cnd$package)
  }
})
