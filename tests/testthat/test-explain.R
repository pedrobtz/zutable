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
  # By name, so that dplyr, a large package, need not be in Suggests.
  pkg <- "dplyr"
  skip_if_not_installed(pkg)
  dplyr_explain <- getExportedValue(pkg, "explain")
  z <- zutable(id = 1:3)
  out <- utils::capture.output(dplyr_explain(z[id > 1]))
  expect_identical(out, utils::capture.output(explain(z[id > 1])))
})
