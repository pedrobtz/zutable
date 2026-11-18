# collate = TRUE: the locale's order through stringi's collation keys,
# computed once per distinct string (design-kernel 6.3), held to
# stringi::stri_order() and stri_sort().

test_that("collated order is stringi::stri_order()", {
  skip_if_not_installed("stringi")
  withr::local_seed(121)
  for (n in c(1L, 2L, 30L, 1001L, 5000L)) {
    x <- sample(collate_pool(), n, TRUE)
    for (d in c(FALSE, TRUE)) {
      for (nl in list(TRUE, FALSE, NA)) {
        expect_identical(
          key_order(x, decreasing = d, na.last = nl, collate = TRUE),
          stringi::stri_order(x, decreasing = d, na_last = nl),
          info = paste(n, d, format(nl))
        )
      }
    }
    expect_identical(
      key_sort(x, collate = TRUE, na.last = NA),
      stringi::stri_sort(x)
    )
  }
  # Byte order differs, so collate = TRUE is not ignored.
  x <- c("b", "A", "a", "B")
  expect_false(identical(key_order(x), key_order(x, collate = TRUE)))
})

test_that("collated keys beside other keys, and dense ranks", {
  skip_if_not_installed("stringi")
  withr::local_seed(122)
  s <- sample(collate_pool(), 400, TRUE)
  a <- sample(1:3, 400, TRUE)
  cs <- match(stringi::stri_sort_key(s), sort(unique(stringi::stri_sort_key(s)), method = "radix"))
  expect_identical(
    key_order(a, s, collate = TRUE),
    order(a, cs, method = "radix")
  )
  r <- key_rank(s, ties = "dense", collate = TRUE, na.last = "keep")
  expect_identical(r, match(cs, sort(unique(cs))))
  # Non-character keys are not changed by it.
  expect_identical(key_order(c(3, 1, 2), collate = TRUE), c(2L, 3L, 1L))
})

test_that("collate = TRUE without stringi is a zutable_collate_error", {
  local_mocked_bindings(zt_has_stringi = function() FALSE)
  expect_error(key_order(c("b", "a"), collate = TRUE), class = "zutable_collate_error")
  expect_error(key_sort(c("b", "a"), collate = TRUE), class = "zutable_collate_error")
  expect_error(key_rank(c("b", "a"), collate = TRUE), class = "zutable_collate_error")
  # Byte order needs nothing.
  expect_identical(key_order(c("b", "a")), 2:1)
})

test_that("collate is TRUE or FALSE", {
  expect_error(key_order("a", collate = NA), class = "zutable_type_error")
  expect_error(key_order("a", collate = c(TRUE, FALSE)), class = "zutable_type_error")
  expect_error(key_sort("a", collate = "yes"), class = "zutable_type_error")
  expect_error(key_rank("a", collate = 1), class = "zutable_type_error")
})
