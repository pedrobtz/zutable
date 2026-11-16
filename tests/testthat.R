# This file is part of the standard setup for testthat.
# Learn more about the roles of various files in:
# * https://r-pkgs.org/testing-design.html#sec-tests-files-overview
# * https://testthat.r-lib.org/articles/special-files.html

# testthat is in Suggests: CRAN's noSuggests check runs without it.
if (requireNamespace("testthat", quietly = TRUE)) {
  library(testthat)
  library(zutable)

  # Shuffled within each file, as tools/ci-run-tests.R runs them, so an
  # order dependence shows on every R CMD check leg. The seed is printed in
  # testthat.Rout; ZUTABLE_TEST_SEED replays an order.
  seed <- suppressWarnings(as.integer(Sys.getenv("ZUTABLE_TEST_SEED")))
  if (is.na(seed)) {
    seed <- as.integer(Sys.time()) %% 100000L
  }
  cat("test order seed:", seed, "(ZUTABLE_TEST_SEED to replay)\n")
  set.seed(seed)
  test_check("zutable", shuffle = TRUE)
}
