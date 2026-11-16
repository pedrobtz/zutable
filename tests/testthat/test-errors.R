test_that("each condition kind inherits from zutable_error", {
  for (kind in zutable_error_kinds) {
    cls <- paste0("zutable_", kind, "_error")
    expect_error(zutable_abort(kind, "boom"), class = cls)
    expect_error(zutable_abort(kind, "boom"), class = "zutable_error")
    cnd <- zutable_condition(kind, "boom")
    expect_identical(
      class(cnd),
      c(cls, "zutable_error", "error", "condition")
    )
    expect_identical(conditionMessage(cnd), "boom")
  }
})

test_that("extra fields are carried on the condition", {
  cnd <- tryCatch(
    zutable_abort("schema", "boom", column = "score"),
    zutable_error = function(e) e
  )
  expect_identical(cnd$column, "score")
})

test_that("the kinds are the design's", {
  expect_setequal(
    zutable_error_kinds,
    c("syntax", "type", "schema", "value", "frozen", "engine",
      "length", "multiple", "levels", "fn", "collate")
  )
})

test_that("an unknown kind is refused", {
  expect_error(zutable_condition("nope", "boom"), "unknown")
  expect_error(zutable_condition(c("type", "value"), "boom"), "unknown")
  expect_error(zutable_condition(NA_character_, "boom"), "unknown")
})
