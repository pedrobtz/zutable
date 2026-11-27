test_that("inference gives each R vector its §4.1 type", {
  utc <- as.POSIXct("2026-01-01 09:00:00", tz = "UTC")
  lis <- as.POSIXct("2026-01-01 09:00:00", tz = "Europe/Lisbon")
  cases <- list(
    list(TRUE, "bool"),
    list(1L, "int32"),
    list(1.5, "float64"),
    list("a", "string"),
    list(as.Date("2026-01-01"), "date"),
    list(utc, 'timestamp("us", "UTC")'),
    list(lis, 'timestamp("us", "Europe/Lisbon")'),
    list(factor(c("b", "a")), 'enum(c("a", "b"))'),
    list(list(as.raw(1:2), NULL), "binary"),
    list(list(1:2, NULL, 3L), "list(int32)"),
    list(list(list("a"), list("b", "c")), "list(list(string))"),
    list(data.frame(a = 1L, b = "x"), "struct(a = int32, b = string)"),
    list(as.difftime(1, units = "secs"), 'r_class("difftime")')
  )
  for (case in cases) {
    expect_identical(format(infer_type(case[[1L]])), case[[2L]],
                     info = case[[2L]])
  }
})

test_that("a POSIXct with no time zone is typed UTC (D38)", {
  x <- as.POSIXct("2026-01-01 09:00:00", tz = "UTC")
  for (tz in list(NULL, "")) {
    attr(x, "tzone") <- tz
    expect_identical(infer_type(x), zt_timestamp("us", "UTC"))
  }
  withr::local_timezone("America/New_York")
  expect_identical(infer_type(Sys.time()), zt_timestamp("us", "UTC"))
})

test_that("vectors with no type are refused", {
  expect_error(infer_type(as.raw(1)), class = "zutable_type_error")
  expect_error(infer_type(1i), class = "zutable_type_error")
  expect_error(infer_type(list()), class = "zutable_type_error")
  expect_error(infer_type(list(NULL)), class = "zutable_type_error")
  expect_error(infer_type(list(1L, "a")), class = "zutable_type_error")
  expect_error(infer_type(list(as.raw(1), 1L)), class = "zutable_type_error")
})

test_that("POSIXct converts to exact microseconds", {
  x <- as.POSIXct("2026-01-01 00:00:00", tz = "UTC") + 0.123456
  # 2026-01-01 is 20454 days after 1970-01-01: 20454 * 86400 seconds.
  expect_identical(posixct_to_us(x), 20454 * 86400 * 1e6 + 123456)
  expect_identical(posixct_to_us(.POSIXct(-0.000001, "UTC")), -1)
  expect_identical(posixct_to_us(.POSIXct(-1.5, "UTC")), -1500000)
  expect_identical(posixct_to_us(.POSIXct(NA_real_, "UTC")), NA_real_)
})

test_that("microseconds survive the trip through double seconds", {
  withr::local_seed(20261117)
  lim <- 2^33 * 1e6
  us <- c(
    round(stats::runif(5000, -lim + 1, lim - 1)),
    lim - 1, -(lim - 1), lim - 1e6, 0, 1, -1
  )
  secs <- .POSIXct(us / 1e6, "UTC")
  expect_identical(posixct_to_us(secs), us)
})

test_that("the 2^33-second limit is straddled on both sides", {
  lim <- 2^33
  for (sgn in c(1, -1)) {
    expect_identical(posixct_to_us(.POSIXct(sgn * (lim - 1), "UTC")),
                     sgn * (lim - 1) * 1e6)
    expect_error(posixct_to_us(.POSIXct(sgn * lim, "UTC")),
                 class = "zutable_value_error")
    expect_error(posixct_to_us(.POSIXct(sgn * (lim + 1), "UTC")),
                 class = "zutable_value_error")
  }
  expect_error(posixct_to_us(.POSIXct(Inf, "UTC")),
               class = "zutable_value_error")
})

test_that("a missing sibling makes its type an error naming it", {
  local_packages(character())
  cases <- list(
    list(quote(schema(a = int64)), "zuint"),
    list(quote(schema(a = decimal(18, 4))), "decimal"),
    list(quote(schema(a = timestamp("ns", "UTC"))), "zutempo"),
    list(quote(schema(a = list(int64))), "zuint"),
    list(quote(na(int64)), "zuint")
  )
  for (case in cases) {
    cnd <- expect_error(eval(case[[1L]]), class = "zutable_type_error")
    expect_identical(cnd$package, case[[2L]])
  }
  cnd <- expect_error(infer_type(zu_int64_of(1:2)),
                      class = "zutable_type_error")
  expect_identical(cnd$package, "zuint")
  expect_identical(schema(a = timestamp("us", "UTC"))$fields$a$type$unit, "us")
})

test_that("with its sibling present, each sibling type resolves", {
  local_packages(c("zuint", "decimal", "zutempo"))
  expect_identical(schema(a = int64)$fields$a$type, zt_type("int64"))
  expect_identical(infer_type(zu_int64_of(c(1L, -2L))), zt_type("int64"))
  expect_identical(schema(a = timestamp("ns", "UTC"))$fields$a$type$unit, "ns")
  expect_identical(infer_type(structure(0, class = "zutempo_instant")),
                   zt_timestamp("ns", "UTC"))
})

test_that("int64's missing value is bit64's NA", {
  skip_if_not_installed("bit64")
  local_packages("zuint")
  x <- na(int64)
  expect_s3_class(x, c("zu_int64", "integer64"), exact = TRUE)
  # bit64 keeps the other classes on the result: zu_int64, whose methods
  # (once zuint is loaded) cannot format a logical.
  expect_identical(unclass(bit64::is.na.integer64(x)), TRUE)
  expect_identical(
    unclass(x),
    unclass(bit64::NA_integer64_)
  )
})

test_that("decimal inference takes the scale and the smallest width", {
  skip_if_not_installed("decimal")
  x <- decimal::decimal(c("1.50", "-0.05", NA))
  expect_identical(infer_type(x), zt_type("decimal", precision = 38L,
                                          scale = 2L))
  wide <- decimal::decimal(paste0(strrep("9", 40), ".5"))
  expect_identical(infer_type(wide)$precision, 76L)
  expect_error(infer_type(decimal::decimal("NaN")),
               class = "zutable_type_error")
  expect_null(vector_problem(x, zt_type("decimal", precision = 3L, scale = 2L)))
  expect_match(vector_problem(x, zt_type("decimal", precision = 2L,
                                         scale = 2L)), "digits")
  expect_match(vector_problem(x, zt_type("decimal", precision = 18L,
                                         scale = 4L)), "scale")
})

test_that("nested types are enforced element by element", {
  t_int <- schema(a = list(int32))$fields$a$type
  expect_null(vector_problem(list(1:2, NULL, 3L), t_int))
  expect_match(vector_problem(list(1:2, NULL, "x"), t_int), "element 3")
  expect_error(check_vector(list(1:2, NULL, "x"), t_int),
               class = "zutable_type_error")
  t_nest <- schema(a = list(list(string)))$fields$a$type
  expect_null(vector_problem(list(list("a", "b")), t_nest))
  expect_match(vector_problem(list(list("a", 1L)), t_nest), "element 1")
  t_struct <- schema(a = struct(x = int32, y = list(string)))$fields$a$type
  ok <- data.frame(x = 1:2)
  ok$y <- list("a", NULL)
  expect_null(vector_problem(ok, t_struct))
  bad <- ok
  bad$y <- list("a", 2L)
  expect_match(vector_problem(bad, t_struct), "field `y`")
  expect_match(vector_problem(data.frame(x = 1:2), t_struct), "columns")
  expect_match(vector_problem(list(as.raw(1), "x"), zt_type("binary")), "raw")
})

test_that("each type rejects the wrong vector", {
  wrong <- list(
    list(1L, zt_type("bool")),
    list(1.5, zt_type("int32")),
    list(factor("a"), zt_type("int32")),
    list(1L, zt_type("float64")),
    list(factor("a"), zt_type("string")),
    list(1, zt_type("date")),
    list(1, zt_timestamp("us", "UTC")),
    list(.POSIXct(0, "Europe/Lisbon"), zt_timestamp("us", "UTC")),
    list(.POSIXct(0, "Europe/Lisbon"), zt_timestamp("us", NULL)),
    list(factor("a", levels = c("a", "b")), zt_type("enum", levels = "a")),
    list("a", zt_type("enum", levels = "a")),
    list(1, zt_type("int64")),
    list(1L, zt_type("r_class", class = "difftime"))
  )
  for (case in wrong) {
    expect_false(is.null(vector_problem(case[[1L]], case[[2L]])),
                 info = format(case[[2L]]))
  }
  expect_null(vector_problem(.POSIXct(0, "UTC"), zt_timestamp("ms", "UTC")))
  expect_null(vector_problem(.POSIXct(0), zt_timestamp("us", NULL)))
})

test_that("na() gives each type's missing value", {
  expect_identical(na(bool), NA)
  expect_identical(na(int32), NA_integer_)
  expect_identical(na(float64), NA_real_)
  expect_identical(na(string), NA_character_)
  expect_identical(infer_type(na(date)), zt_type("date"))
  expect_identical(infer_type(na(timestamp("us", "Asia/Tokyo"))),
                   zt_timestamp("us", "Asia/Tokyo"))
  e <- na(enum(c("lo", "hi")))
  expect_true(is.na(e))
  expect_identical(levels(e), c("lo", "hi"))
  expect_identical(na(binary), list(NULL))
  s <- na(struct(a = int32, b = string))
  expect_identical(nrow(s), 1L)
  expect_null(vector_problem(s, schema(a = struct(a = int32, b = string))$fields$a$type))
  expect_error(na(r_class("difftime")), class = "zutable_type_error")
  for (t in list(quote(bool), quote(int32), quote(float64), quote(string),
                 quote(date), quote(enum("a")), quote(binary),
                 quote(list(int32)))) {
    type <- parse_type(t)
    expect_null(vector_problem(na_of(type), type), info = format(type))
  }
})

test_that("a formatted type reads back as the same type", {
  withr::defer(zt_registry$extensions[["test.rt"]] <- NULL)
  register_extension_type("test.rt", structure(double(), class = "rt"),
                          float64)
  types <- list(
    quote(bool), quote(int32), quote(float64), quote(string), quote(date),
    quote(binary), quote(timestamp("ms", "Europe/Lisbon")),
    quote(timestamp("s")),
    quote(enum(c("lo", "h\u00e9", "say \"hi\"", "a\\b", ""))),
    quote(list(list(string))),
    quote(struct(a = not_null(int32), b = list(enum(c("x", "y"))))),
    quote(r_class("difftime")), quote(extension("test.rt"))
  )
  check_round_trip <- function() {
    for (t in types) {
      type <- parse_type(t)
      expect_identical(parse_type(format(type)), type, info = format(type))
    }
  }
  check_round_trip()
  withr::local_options(OutDec = ",", scipen = -5, digits = 3)
  check_round_trip()
})

test_that("decimal types read back from their format", {
  skip_if_not_installed("decimal")
  type <- parse_type(quote(decimal(18, 4)))
  expect_identical(parse_type(format(type)), type)
  withr::local_options(OutDec = ",", scipen = -5, digits = 3)
  expect_identical(parse_type(format(type)), type)
})

test_that("a time zone R does not know is a type error (#90)", {
  # The oracle: R's own list of zones.
  expect_false("Not/AZone" %in% OlsonNames())
  expect_error(schema(t = timestamp("s", "Not/AZone")), class = "zutable_type_error")
  expect_error(zutable(t = .POSIXct(0, "Not/AZone")), class = "zutable_type_error")
  expect_error(as_zutable(data.frame(t = .POSIXct(0, "Not/AZone"))),
               class = "zutable_type_error")
  z <- zutable(t = .POSIXct(0, "UTC"))
  expect_error(z[select = .(u = cast(t, timestamp("us", "Not/AZone")))],
               class = "zutable_type_error")
  for (tz in c("UTC", "America/New_York", "Australia/Lord_Howe")) {
    expect_true(tz %in% OlsonNames())
    expect_identical(schema(zutable(t = .POSIXct(0, tz)))$fields[["t"]]$type,
                     zt_timestamp("us", tz))
  }
  # No zone is UTC (D38), not an unknown zone.
  expect_identical(schema(zutable(t = .POSIXct(0)))$fields[["t"]]$type,
                   zt_timestamp("us", "UTC"))
})

test_that("the 2^33-second limit holds by every route a timestamp enters (#69)", {
  lim <- 2^33
  iso <- function(v) format(.POSIXct(v, "UTC"), "%Y-%m-%dT%H:%M:%S")
  for (sgn in c(1, -1)) {
    inside <- sgn * (lim - 1)
    for (v in c(inside, sgn * lim, sgn * (lim + 1))) {
      ok <- abs(v) < lim
      t <- .POSIXct(v, "UTC")
      check <- function(code) {
        if (ok) expect_no_error(code) else expect_error(code, class = "zutable_value_error")
      }
      info <- format(v, digits = 15L)
      check(zutable(t = t))
      check(as_zutable(data.frame(t = t)))
      z <- zutable(t = .POSIXct(0, "UTC"), s = iso(v))
      check(z[, t := ..t])
      check({ u <- copy(z); u$t <- t })
      # A string cast, and a string literal read as a timestamp.
      check(z[select = .(c = cast(s, timestamp))])
      lit <- iso(v)
      check(z[select = .(c = coalesce(t, cast(..lit, timestamp)))])
      # A string compared with a timestamp is read as one when it names
      # one; past the limit it names none, as a malformed string does.
      if (ok) expect_no_error(z[t < ..lit]) else
        expect_error(z[t < ..lit], class = "zutable_type_error")
      if (ok) {
        expect_identical(as.double(z[select = .(c = cast(s, timestamp))]$c), v, info = info)
      }
    }
    # A date cast to a timestamp: the last and first whole days inside.
    day <- sgn * floor((lim - 1) / 86400)
    z <- zutable(d = structure(c(day, day + sgn), class = "Date"))
    expect_identical(as.double(z[1L][select = .(c = cast(d, timestamp))]$c), day * 86400)
    expect_error(z[select = .(c = cast(d, timestamp))], class = "zutable_value_error")
  }
})
