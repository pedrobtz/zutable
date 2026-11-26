test_that("explain() prints one step per line", {
  z <- zutable(id = 1:3, px = c(1.5, 2, 2.5), qty = c(1L, 2L, 3L),
               g = c("a", "b", "a"))
  expect_snapshot(explain(z))
  expect_snapshot(explain(z[px > 1.6 & g == "a", .(id, notional = px * qty),
                            order = .(desc(notional), id), limit = 2]))
  expect_snapshot(explain(z[, .(g), distinct = TRUE][order = g]))
  expect_snapshot(explain(z[, .(day = cast("2026-01-01", date), s = case(px > 2 ~ "hi"))]))
})

test_that("dplyr::explain() reaches the same method (D50)", {
  # dplyr is in Suggests so that the full legs install it and run this
  # (#75); explain.zutable is registered on dplyr's generic when it loads.
  skip_if_not_installed("dplyr")
  dplyr_explain <- dplyr::explain
  z <- zutable(id = 1:3)
  out <- utils::capture.output(dplyr_explain(z[id > 1]))
  expect_identical(out, utils::capture.output(explain(z[id > 1])))
  # Dispatched from where zutable's functions are out of sight, so only the
  # method registered on dplyr's generic can answer (#75).
  methods <- asNamespace("dplyr")[[".__S3MethodsTable__."]]
  expect_true(is.function(get0("explain.zutable", envir = methods, inherits = FALSE)))
  bare <- list2env(list(f = dplyr_explain, q = z[id > 1]), parent = baseenv())
  out2 <- utils::capture.output(eval(quote(f(q)), bare))
  expect_identical(out2, out)
})
