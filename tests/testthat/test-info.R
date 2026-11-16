test_that("zutable_info() reports the installed version", {
  info <- zutable_info()
  expect_type(info, "list")
  expect_identical(info$version, utils::packageVersion("zutable"))
})
