test_that(":= writes an existing column and keeps its type", {
  z <- zutable(id = 1:3, px = c(1.5, 2, 2.5), qty = c(1L, 2L, 3L))
  z[, qty := qty * 2L]
  expect_identical(z$qty, c(2L, 4L, 6L))
  z[, px := 1]
  expect_identical(z$px, c(1, 1, 1))
  z[, qty := 5]
  expect_identical(z$qty, c(5L, 5L, 5L))
  z[, px := qty]
  expect_identical(z$px, c(5, 5, 5))
  expect_identical(schema(z), schema(id = int32, px = float64, qty = int32))
})

test_that("blocks agree with the same computation in plain R", {
  withr::local_seed(21)
  df <- bracket_frame(50L)
  df$notional <- NA_real_
  df$share <- NA_real_
  z <- as_zutable(df)
  z[, {
    w <- abs(px) * 2
    notional := w + 1
    share := notional / w
  }]
  w <- abs(df$px) * 2
  expect_identical(z$notional, w + 1)
  expect_identical(z$share, (w + 1) / w)
})

test_that("statements run in order and a local binds a value", {
  z <- zutable(a = c(1L, 2L), b = c(0L, 0L))
  z[, {
    tmp <- a
    a := a + 10L
    b := tmp
  }]
  expect_identical(z$a, c(11L, 12L))
  expect_identical(z$b, c(1L, 2L))
  z[, { a := a * 2L; b := a }]
  expect_identical(z$b, c(22L, 24L))
})

test_that("a failing third statement leaves the first two unapplied", {
  z <- zutable(a = c(1L, 2L), b = c(1.5, 2), c = c("x", "y"))
  before <- copy(z)
  # A value error found only while running (int32 overflow).
  expect_error(z[, {
    a := a + 1L
    b := b * 2
    a := a * .Machine$integer.max
  }], class = "zutable_value_error")
  expect_identical(plain(z), plain(before))
  # A type error found before any data is touched.
  expect_error(z[, { a := 0L; b := 0; c := 1L }], class = "zutable_schema_error")
  expect_identical(plain(z), plain(before))
})

test_that("a column refused by the final check leaves the earlier ones unapplied", {
  # The not_null check runs on every new column after all statements and
  # before the commit, so `a` must not be written when `b` is refused.
  z <- as_zutable(data.frame(a = 1:3, b = 1:3),
                  schema(a = int32, b = not_null(int32)))
  before <- copy(z)
  expect_error(z[, { a := a + 1L; b := NA_integer_ }],
               class = "zutable_value_error")
  expect_identical(plain(z), plain(before))
})

test_that("where writes only the matching rows; aggregates see those rows", {
  z <- zutable(g = c("a", "b", "a", "b"), x = c(1, 2, 3, 4), y = NA_real_)
  z[g == "a", y := x / sum(x)]
  expect_identical(z$y, c(0.25, NA, 0.75, NA))
  z[x > 100, y := 0]
  expect_identical(z$y, c(0.25, NA, 0.75, NA))
})

test_that("by computes an aggregate per group and writes the group's rows", {
  withr::local_seed(22)
  df <- bracket_frame(60L)
  df$k[is.na(df$k)] <- 0L
  df$s <- NA_real_
  z <- as_zutable(df)
  z[, s := px - mean(px), by = k]
  expect_equal(z$s, df$px - ave(df$px, df$k, FUN = mean))
  z[flag %in% TRUE, s := sum(px), by = k]
  want <- df$px - ave(df$px, df$k, FUN = mean)
  sel <- df$flag %in% TRUE
  want[sel] <- ave(df$px[sel], df$k[sel], FUN = sum)
  expect_equal(z$s, want)
})

test_that("each value is one value or one per row written", {
  z <- zutable(a = 1:4)
  expect_error(z[, a := r(1:2, int32)], class = "zutable_type_error")
  expect_identical(z$a, 1:4)
})

test_that("the type rule: a value of another type, a missing target, NULL", {
  z <- zutable(a = 1:3, s = c("x", "y", "z"), d = as.Date("2026-01-01") + 0:2)
  expect_error(z[, a := 1.5], class = "zutable_schema_error")
  expect_error(z[, a := s], class = "zutable_schema_error")
  expect_error(z[, s := a], class = "zutable_schema_error")
  expect_error(z[, nope := 1L], class = "zutable_schema_error")
  expect_error(z[, a := NULL], class = "zutable_schema_error")
  expect_error(z[, c("a", "s") := list(1L, "q")], class = "zutable_syntax_error")
  expect_error(z[, a <- 1L], class = "zutable_syntax_error")
  expect_error(z[, { a <- 1L; a := 2L }], class = "zutable_syntax_error")
  z[, d := "2026-06-01"]
  expect_identical(z$d, rep(as.Date("2026-06-01"), 3L))
  expect_error(z[, a := 1L, order = a], class = "zutable_syntax_error")
  expect_error(z[, a := 1L, select = .(a)], class = "zutable_syntax_error")
})

test_that("NA into a not_null column is refused, leaving the table", {
  z <- as_zutable(data.frame(a = 1:3), schema(a = not_null(int32)))
  expect_error(z[a == 2L, a := NA], class = "zutable_value_error")
  expect_identical(z$a, 1:3)
})

test_that("update = is the named form", {
  z <- zutable(a = 1:3)
  z[update = a := a + 1L]
  expect_identical(z$a, 2:4)
  z[a > 3L, update = { a := 0L }]
  expect_identical(z$a, c(2L, 3L, 0L))
})

test_that("a select block computes locals row by row", {
  z <- zutable(px = c(1, 2), qty = c(3L, 4L))
  r <- z[, { w <- px * qty; .(w, double = w * 2) }]
  expect_identical(plain(r), data.frame(w = c(3, 8), double = c(6, 16)))
  expect_error(z[, { w <- sum(px); .(w) }], class = "zutable_syntax_error")
  expect_error(z[, { px <- 1; .(px) }], class = "zutable_syntax_error")
  expect_error(z[, { w <- 1 }], class = "zutable_syntax_error")
})

test_that("an update records itself in the plan (rule 6: blocks are expressions)", {
  z <- zutable(a = 1:3, b = 0L)
  z[a > 1L, b := a * 2L]
  expect_match(zt_explain_lines(z), "update  b := (a * 2L)", fixed = TRUE, all = FALSE)
  expect_match(zt_explain_lines(z), "where (a > 1L)", fixed = TRUE, all = FALSE)
})

test_that("an update at top level does not print; an explicit print does", {
  # The flag holds the update's token (D57); test-print-skip.R runs the
  # sequences at top level.
  z <- zutable(a = 1:2)
  z[, a := 3L]
  zt_arm_print_skip(z, 1L)
  expect_true(zt_take_print_skip(z, 2L))
  expect_false(zt_take_print_skip(z, 2L))
  zt_arm_print_skip(z, 2L)
  expect_false(zt_take_print_skip(z, 2L))
  zt_arm_print_skip(z, 1L)
  expect_false(zt_take_print_skip(z, 3L))
  expect_false(zt_take_print_skip(zutable(a = 3:3), 2L))
  w <- zutable(a = 1:2)
  w[, a := 3L]
  zt_arm_print_skip(z, 1L)
  expect_false(zt_take_print_skip(w, 2L))
  expect_true(zt_take_print_skip(z, 2L))
  zt_arm_print_skip(z, 1L)
  zt_clear_print_skip()
  expect_null(zt_state$skip_print)
  expect_output(print(z), "zutable")
})

test_that("both update routes check a value's length per group (#77)", {
  # No statement a user can write reaches this check with the wrong length
  # (a constant is length one; r() checks its own), so the routes are
  # called with a statement built by hand: a constant of two values.
  z <- zutable(a = 1:4, g = c(1L, 1L, 2L, 2L))
  cols <- list(a = 1:4, g = c(1L, 1L, 2L, 2L))
  node <- zt_lit_node(c(5L, 6L, 7L), zt_type("int32"))
  up <- list(stmts = list(list(kind = "set", name = "a", node = node)), by = list())
  rows <- 1:4
  for (keys in list(list(), list(cols$g))) {
    expect_error(zt_update_loop(up, cols, rows, cols, keys, NULL),
                 class = "zutable_value_error")
    expect_error(zt_update_kernel(up, cols, rows, cols, keys, NULL),
                 class = "zutable_value_error")
  }
  # One per row, or one, is taken by both.
  for (v in list(9L, 5:8)) {
    up$stmts[[1L]]$node <- zt_lit_node(v, zt_type("int32"))
    want <- rep_len(v, 4L)
    expect_identical(zt_update_loop(up, cols, rows, cols, list(), NULL)$a, want)
    expect_identical(zt_update_kernel(up, cols, rows, cols, list(), NULL)$a, want)
  }
})
