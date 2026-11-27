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

test_that("argument checks raise the package's conditions (#68)", {
  x <- zutable(k = 1:3, a = c("p", "q", "r"))
  y <- zutable(k = 2:3, b = c(1, 2))
  expect_error(join(x, y), class = "zutable_syntax_error")
  expect_error(schema(int32), class = "zutable_schema_error")
  expect_error(schema(not_a_variable_anywhere), class = "zutable_schema_error")
  for (n in list(2.5, -1, NA, "2", c(1, 2), NA_integer_)) {
    expect_error(print(x, n = n), class = "zutable_syntax_error")
    # Nothing printed before the check.
    expect_output(try(print(x, n = n), silent = TRUE), NA)
  }
  expect_output(print(x, n = 2), "1 more row")
  expect_output(print(x, n = Inf), "zutable")
  expect_output(print(x, n = 0L), "zutable")
  for (v in list("ref", "Kernel", NA_character_, c("kernel", "reference"), 1L, TRUE)) {
    withr::local_options(zutable.executor = v)
    expect_error(x[k > 1], class = "zutable_value_error")
    expect_error(x[, a := "z"], class = "zutable_value_error")
    expect_error(join(x, y, on = k), class = "zutable_value_error")
    expect_error(x[by = k, select = .(n = count())], class = "zutable_value_error")
  }
  for (v in c("kernel", "reference")) {
    withr::local_options(zutable.executor = v)
    expect_identical(nrow(x[k > 1]), 2L)
  }
})

test_that("an error evaluating limit, by or .col() keeps its message (#82)", {
  x <- zutable(a = 1:3, g = c("p", "q", "p"))
  marker <- "zz-a-user-message-zz"
  fails <- function() stop(marker)
  for (e in list(quote(x[limit = fails()]), quote(x[by = fails(), select = .(n = count())]),
                 quote(x[select = .(v = .col(fails()))]))) {
    err <- expect_error(eval(e), class = "zutable_syntax_error")
    # D62's rule: the user's message is inside the package's.
    expect_true(grepl(marker, conditionMessage(err), fixed = TRUE), info = deparse(e))
  }
})

test_that("conditions name the exported function's call, never a helper's (#84)", {
  head_of <- function(e) {
    cl <- conditionCall(e)
    if (is.null(cl)) NULL else as.character(cl[[1L]])
  }
  z <- zutable(s = c("1", "x"), i = c(1L, 50000L), d = as.Date("2026-01-01") + 0:1)
  bracket <- c("[", "[.zutable")
  for (ex in c("kernel", "reference")) {
    withr::local_options(zutable.executor = ex)
    sites <- list(
      cast = quote(z[select = .(c = cast(s, int32))]),
      overflow = quote(z[select = .(v = i * i)]),
      r_type = quote(z[select = .(v = r("a", int32))]),
      r_nan_date = quote(z[select = .(v = r(structure(c(NaN, 1), class = "Date"), date))]),
      date_trunc = quote(z[select = .(v = date_trunc("hour", d))]),
      update = quote(copy(z)[, i := i * i]),
      grouped = quote(z[by = s, select = .(v = sum(cast(s, int32)))])
    )
    for (nm in names(sites)) {
      err <- expect_error(eval(sites[[nm]]), class = "zutable_error")
      expect_true(head_of(err) %in% bracket, info = paste(ex, nm, head_of(err)))
    }
  }
  expect_identical(head_of(expect_error(copy(1), class = "zutable_type_error")), "copy")
  expect_identical(head_of(expect_error(freeze(1), class = "zutable_type_error")), "freeze")
  expect_identical(head_of(expect_error(field(int32, nullable = NA), class = "zutable_type_error")),
                   "field")
  expect_identical(head_of(expect_error(register_extension_type("", structure(double(), class = "c"),
                                                                float64),
                                        class = "zutable_type_error")),
                   "register_extension_type")
  if (!isNamespaceLoaded("dplyr")) {
    expect_true(head_of(expect_error(explain(1), class = "zutable_type_error")) %in%
                  c("explain", "explain.default"))
  }
  expect_identical(head_of(expect_error(grp(1:2, sort = NA), class = "zutable_type_error")), "grp")
  # The SQL emitter has no exported entry yet: it names no call (D62).
  node <- zt_translate(quote(r(1, int32)), schema(a = int32), environment(), NULL)
  expect_null(conditionCall(expect_error(zt_sql_expr(node), class = "zutable_engine_error")))
})
