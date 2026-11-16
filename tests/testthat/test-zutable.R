test_that("zutable() infers the schema and recycles length one only", {
  z <- zutable(id = 1:3, name = c("Ada", "Linus", "Grace"), score = NA_real_)
  expect_identical(schema(z), schema(id = int32, name = string,
                                     score = float64))
  expect_identical(z$score, rep(NA_real_, 3L))
  expect_error(zutable(a = 1:3, b = 1:2), class = "zutable_schema_error")
  expect_error(zutable(1:3), class = "zutable_schema_error")
  expect_error(zutable(a = 1, a = 2), class = "zutable_schema_error")
  expect_identical(nrow(zutable()), 0L)
  expect_identical(nrow(zutable(a = integer())), 0L)
})

test_that("typed placeholders declare later columns", {
  skip_if_not_installed("decimal")
  z <- zutable(id = 1:3, total = na(decimal(18, 4)))
  expect_identical(format(schema(z)$fields$total$type), "decimal(38, 4)")
})

test_that("the representation is a plain data frame (§9.1)", {
  z <- zutable(a = 1:2, b = c("x", "y"))
  expect_identical(class(z), c("zutable", "data.frame"))
  expect_identical(typeof(z), "list")
  expect_identical(.row_names_info(z, 1L), -2L)
  expect_setequal(names(attributes(z)),
                  c("names", "class", "row.names", "schema", "properties"))
  expect_true(is.data.frame(z))
  expect_true(is_zutable(z))
  expect_false(is_zutable(data.frame()))
})

test_that("row names are not kept", {
  df <- data.frame(a = 1:2, row.names = c("r1", "r2"))
  expect_identical(.row_names_info(as_zutable(df), 1L), -2L)
})

test_that("a POSIXct with no zone enters as UTC (D38)", {
  z <- zutable(t = .POSIXct(0))
  expect_identical(attr(z$t, "tzone"), "UTC")
  expect_identical(schema(z)$fields$t$type, zt_timestamp("us", "UTC"))
  expect_error(zutable(t = .POSIXct(2^33, "UTC")), class = "zutable_value_error")
})

test_that("entry refuses values a type cannot hold", {
  expect_error(zutable(d = structure(1.5, class = "Date")),
               class = "zutable_value_error")
  expect_error(as_zutable(data.frame(a = c(1L, NA)), schema(a = not_null(int32))),
               class = "zutable_value_error")
  expect_error(as_zutable(list(t = .POSIXct(0.5, "UTC")),
                          schema(t = timestamp("s", "UTC"))),
               class = "zutable_value_error")
})

test_that("strings enter as UTF-8", {
  utf8 <- "caf\u00e9"
  x <- iconv(utf8, "UTF-8", "latin1")
  expect_identical(Encoding(x), "latin1")
  z <- zutable(s = x)
  expect_identical(Encoding(z$s), "UTF-8")
  expect_identical(z$s, utf8)
})

test_that("a stale schema is caught on entry", {
  z <- zutable(a = 1:3, b = c("x", "y", "z"))
  stale <- unclass(z)
  stale$a <- c("p", "q", "r")
  class(stale) <- c("zutable", "data.frame")
  expect_error(schema(stale), class = "zutable_schema_error")
  expect_error(print(stale), class = "zutable_schema_error")
  expect_error(stale[1, ], class = "zutable_schema_error")
  expect_error(stale$b <- "w", class = "zutable_schema_error")
  short <- unclass(z)
  short$a <- 1:2
  class(short) <- c("zutable", "data.frame")
  expect_error(schema(short), class = "zutable_schema_error")
  bare <- z
  attr(bare, "schema") <- NULL
  expect_error(schema(bare), class = "zutable_schema_error")
})

test_that("as_zutable() checks against a schema and keeps declared parts", {
  s <- schema(t = timestamp("ms", "UTC"), a = not_null(int32))
  z <- as_zutable(list(t = .POSIXct(1.5, "UTC"), a = 1L), s)
  expect_identical(schema(z), s)
  expect_identical(as_zutable(z), z)
  expect_error(as_zutable(1:3), class = "zutable_schema_error")
  expect_error(as_zutable(data.frame(a = 1L), "a"), class = "zutable_schema_error")
})

test_that("struct and list columns", {
  inner <- data.frame(x = 1:2, y = c("a", "b"))
  z <- zutable(id = 1:2, s = inner, l = list(1:3, NULL))
  expect_identical(format(schema(z)$fields$s$type),
                   "struct(x = int32, y = string)")
  expect_identical(format(schema(z)$fields$l$type), "list(int32)")
  expect_identical(plain(z[2, ])$id, 2L)
})

test_that("metadata() is the table's", {
  z <- as_zutable(data.frame(a = 1L), schema(a = int32, .metadata = c(k = "v")))
  expect_identical(metadata(z), c(k = "v"))
  expect_identical(metadata(data.frame(a = 1L)), character())
})

test_that("as.data.frame() leaves the class", {
  z <- zutable(a = 1:2)
  df <- as.data.frame(z)
  expect_identical(class(df), "data.frame")
  expect_null(attr(df, "schema"))
  df$b <- 1
  expect_identical(ncol(df), 2L)
})
