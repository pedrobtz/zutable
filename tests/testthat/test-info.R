test_that("zutable_info() reports the installed version", {
  info <- zutable_info()
  expect_type(info, "list")
  expect_identical(info$version, utils::packageVersion("zutable"))
})

test_that("zutable_info() reports the header and zufast it was built with", {
  info <- zutable_info()
  expect_identical(info$header, as.character(utils::packageVersion("zutable")))
  expect_match(info$zufast, "^[0-9]+[.][0-9]+[.][0-9]+")
  # zufast is LinkingTo only, so R CMD check --as-cran hides it at test
  # time; compare with it where it is installed.
  skip_if_not_installed("zufast")
  expect_identical(info$zufast, as.character(utils::packageVersion("zufast")))
})
