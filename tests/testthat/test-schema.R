test_that("bare names and strings give identical schemas", {
  a <- schema(id = not_null(int32), px = float64, day = date,
              tags = list(string), t = timestamp("ms", "Europe/Lisbon"),
              k = enum(c("lo", "hi")), s = struct(a = int32, b = string))
  b <- schema(id = not_null("int32"), px = "float64", day = "date",
              tags = "list(string)", t = "timestamp('ms', 'Europe/Lisbon')",
              k = "enum(c('lo', 'hi'))", s = "struct(a = int32, b = string)")
  expect_identical(a, b)
})

test_that("a variable holding a type, field or string is accepted", {
  ty <- "float64"
  f <- field(int32, metadata = c(unit = "USD"))
  s <- schema(a = ty, b = f)
  expect_identical(s, schema(a = float64, b = field(int32, metadata = c(unit = "USD"))))
  expect_identical(s$fields$b$metadata, c(unit = "USD"))
})

test_that("not_null() and field(nullable = FALSE) agree", {
  expect_identical(schema(a = not_null(int32)),
                   schema(a = field(int32, nullable = FALSE)))
  expect_false(schema(a = not_null(int32))$fields$a$nullable)
  expect_true(schema(a = int32)$fields$a$nullable)
})

test_that("field names must be unique and non-empty", {
  expect_error(schema(a = int32, a = string), class = "zutable_schema_error")
  expect_error(schema(a = int32, string), class = "zutable_schema_error")
})

test_that("an empty schema is a schema", {
  expect_identical(length(schema()), 0L)
  expect_s3_class(schema(), "zutable_schema")
})

test_that("metadata is checked and carried", {
  s <- schema(a = int32, .metadata = c(source = "test"))
  expect_identical(s$metadata, c(source = "test"))
  expect_error(schema(a = int32, .metadata = c("x")),
               class = "zutable_schema_error")
  expect_error(schema(a = field(int32, metadata = c(k = NA_character_))),
               class = "zutable_schema_error")
  expect_error(schema(a = field(int32, metadata = c(k = "1", k = "2"))),
               class = "zutable_schema_error")
})

test_that("schemas differing in any part are not identical", {
  base <- schema(a = int32, b = string)
  expect_false(identical(base, schema(a = int32, b = not_null(string))))
  expect_false(identical(base, schema(b = string, a = int32)))
  expect_false(identical(base, schema(a = int32, b = string,
                                      .metadata = c(k = "v"))))
  expect_false(identical(schema(t = timestamp("us", "UTC")),
                         schema(t = timestamp("us"))))
})

test_that("schema() of a data frame or a schema", {
  s <- schema(a = int32)
  expect_identical(schema(s), s)
  expect_identical(schema(data.frame(a = 1:2)), s)
  expect_error(schema(1:3), class = "zutable_schema_error")
})

test_that("unknown and malformed types are refused", {
  expect_error(schema(a = int33), class = "zutable_type_error")
  expect_error(schema(a = "int33"), class = "zutable_type_error")
  expect_error(schema(a = "int32("), class = "zutable_type_error")
  expect_error(schema(a = foo(int32)), class = "zutable_type_error")
  expect_error(schema(a = timestamp("days")), class = "zutable_type_error")
  expect_error(schema(a = timestamp("us", "")), class = "zutable_type_error")
  expect_error(schema(a = enum(c("a", "a"))), class = "zutable_type_error")
  expect_error(schema(a = enum(c("a", NA))), class = "zutable_type_error")
  expect_error(schema(a = list(int32, string)), class = "zutable_type_error")
  expect_error(schema(a = struct(int32)), class = "zutable_type_error")
  expect_error(schema(a = struct(x = int32, x = string)),
               class = "zutable_type_error")
  expect_error(schema(a = r_class(1)), class = "zutable_type_error")
  expect_error(schema(a = extension("no.such")), class = "zutable_type_error")
  expect_error(schema(a = c("int32", "string")), class = "zutable_type_error")
})

test_that("unsigned types are refused until design Q2 is answered", {
  for (u in c("uint8", "uint16", "uint32", "uint64")) {
    expect_error(eval(bquote(schema(a = .(as.name(u))))),
                 class = "zutable_type_error")
  }
})

test_that("narrow Arrow types widen exactly", {
  expect_identical(schema(a = int8, b = int16, c = float32),
                   schema(a = int32, b = int32, c = float64))
})

test_that("bare timestamp is timestamp('us', 'UTC'); no tz is no zone", {
  expect_identical(schema(t = timestamp), schema(t = timestamp("us", "UTC")))
  expect_null(schema(t = timestamp("us"))$fields$t$type$tz)
  expect_identical(schema(t = timestamp(us)), schema(t = timestamp("us")))
})

test_that("type names are not objects of the package", {
  ns <- asNamespace("zutable")
  for (n in c("int32", "date", "list", "string", "float64", "timestamp")) {
    expect_false(exists(n, envir = ns, inherits = FALSE), info = n)
  }
})

test_that("extension types register by name and class", {
  withr::defer(zt_registry$extensions[["test.celsius"]] <- NULL)
  register_extension_type("test.celsius",
                          structure(double(), class = "celsius"), float64)
  s <- schema(t = extension("test.celsius"))
  expect_identical(s$fields$t$type$storage, zt_type("float64"))
  x <- structure(c(1, 2), class = "celsius")
  expect_identical(infer_type(x), s$fields$t$type)
  expect_null(vector_problem(x, s$fields$t$type))
  expect_identical(class(na_of(s$fields$t$type)), "celsius")
  expect_error(register_extension_type("", structure(double(), class = "c"),
                                       float64), class = "zutable_type_error")
  expect_error(register_extension_type("x", double(), float64),
               class = "zutable_type_error")
})

test_that("decimal types parse and are checked", {
  skip_if_not_installed("decimal")
  expect_identical(schema(a = decimal(18, 4)), schema(a = "decimal(18, 4)"))
  expect_identical(schema(a = decimal(18))$fields$a$type$scale, 0L)
  expect_error(schema(a = decimal(0, 0)), class = "zutable_type_error")
  expect_error(schema(a = decimal(77, 0)), class = "zutable_type_error")
  expect_error(schema(a = decimal(18, 19)), class = "zutable_type_error")
  expect_error(schema(a = decimal(18.5, 2)), class = "zutable_type_error")
})

test_that("schemas print with a type row per field", {
  s <- schema(id = not_null(int32), px = field(float64,
              metadata = c(unit = "USD")), tags = list(string),
              t = timestamp("us", "UTC"), .metadata = c(source = "x"))
  expect_snapshot(print(s))
  expect_snapshot(print(s$fields$tags$type))
})
