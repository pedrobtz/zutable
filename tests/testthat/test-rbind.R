test_that("identical schemas bind, keeping types and attributes", {
  a <- zutable(id = 1:2, t = .POSIXct(c(0, 1), "Asia/Tokyo"),
               k = factor(c("lo", "hi"), levels = c("lo", "hi")),
               l = list(1:2, NULL), d = as.Date("2026-01-01") + 0:1)
  r <- rbind(a, a, a)
  expect_identical(nrow(r), 6L)
  expect_identical(schema(r), schema(a))
  expect_identical(attr(r$t, "tzone"), "Asia/Tokyo")
  expect_identical(levels(r$k), c("lo", "hi"))
  expect_identical(r$l, rep(list(1:2, NULL), 3L))
  expect_identical(plain(r)[1:2, ], plain(a))
})

test_that("any difference in schema is a schema error", {
  a <- zutable(id = 1:2, x = c(1.5, 2))
  expect_error(rbind(a, zutable(id = 1:2, x = 1:2)), class = "zutable_schema_error")
  expect_error(rbind(a, zutable(x = c(1.5, 2), id = 1:2)), class = "zutable_schema_error")
  expect_error(rbind(a, zutable(id = 1:2)), class = "zutable_schema_error")
  nn <- as_zutable(data.frame(id = 1:2, x = c(1, 2)), schema(id = not_null(int32), x = float64))
  expect_error(rbind(a, nn), class = "zutable_schema_error")
  expect_error(rbind(a, data.frame(id = 1:2, x = c(1, 2))), class = "zutable_schema_error")
})
