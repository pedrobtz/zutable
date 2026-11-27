# D53 and D57 (#61): only the autoprint of an update at top level is
# skipped. Each sequence runs at top level in its own Rscript, and the
# oracle is what it prints: the number of table headers after each mark.

test_that("only the autoprint of a top-level update is skipped (#61)", {
  skip_on_cran()
  out <- run_script(c(
    "x <- zutable(a = 1:2)",
    "cat('@@ autoprint\\n')",
    "x[, a := 4L]",
    "cat('@@ later autoprint\\n')",
    "x",
    "cat('@@ explicit print\\n')",
    "print(x[, a := 5L])",
    "cat('@@ after explicit\\n')",
    "x",
    "f <- function(t) { t[, a := 8L]; invisible(NULL) }",
    "cat('@@ in a function\\n')",
    "f(x)",
    "print(x)",
    "cat('@@ function then autoprint\\n')",
    "f(x)",
    "x",
    "cat('@@ assigned\\n')",
    "y <- x[, a := 6L]",
    "x",
    "cat('@@ assigned then y\\n')",
    "y <- x[, a := 6L]",
    "y",
    "cat('@@ loop then copy\\n')",
    "for (i in 1) x[, a := 4L]",
    "copy(x)",
    "cat('@@ loop then x\\n')",
    "for (i in 1) x[, a := 4L]",
    "x",
    "cat('@@ lapply\\n')",
    "invisible(lapply(1, function(i) x[, a := 9L]))",
    "x",
    "cat('@@ invisible\\n')",
    "invisible(x[, a := 3L])",
    "x",
    "cat('@@ another table\\n')",
    "z <- zutable(b = 1L)",
    "x[, a := 2L]; z",
    "cat('@@ end\\n')"
  ))
  got <- headers_after_marks(out)
  want <- c(autoprint = 0L, "later autoprint" = 1L, "explicit print" = 1L,
            "after explicit" = 1L, "in a function" = 1L,
            "function then autoprint" = 1L, assigned = 1L, "assigned then y" = 1L,
            "loop then copy" = 1L, "loop then x" = 1L, lapply = 1L, invisible = 1L,
            "another table" = 1L, end = 0L)
  expect_identical(got, want, info = paste(out, collapse = "\n"))
})

test_that("the print-skip callback is registered once and removed on unload (#61)", {
  expect_identical(sum(getTaskCallbackNames() == "zutable_print_skip"), 1L)
  skip_on_cran()
  out <- run_script(c(
    "cat(sum(getTaskCallbackNames() == 'zutable_print_skip'), '\\n')",
    "unloadNamespace('zutable')",
    "cat(sum(getTaskCallbackNames() == 'zutable_print_skip'), '\\n')"
  ))
  expect_identical(trimws(out), c("1", "0"))
})
