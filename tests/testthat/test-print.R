test_that("a zutable prints its schema under the names", {
  z <- zutable(
    id = 1:3, name = c("Ada", "Linus", NA), score = c(1.5, NA, 3),
    day = as.Date("2026-01-01") + 0:2, tags = list(1:2, NULL, 3L)
  )
  expect_snapshot(print(z))
  expect_snapshot(print(zutable(a = 1:12), n = 3))
  expect_snapshot(print(zutable()))
  expect_snapshot(print(as_zutable(data.frame(a = 1L), schema(a = not_null(int32)))))
})
