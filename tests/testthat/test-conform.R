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
