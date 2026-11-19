# For tools/ci/consumer.sh: the fixture's tests, from its tests/testthat,
# failing when none ran or one skipped: the absence check skips outside CI,
# and a fixture that skipped it proved nothing.
cat("libraries:", .libPaths(), sep = "\n  ")
cat("\n")
library(zutabletest)
res <- as.data.frame(testthat::test_dir(".", package = "zutabletest",
  load_package = "installed", stop_on_failure = FALSE, reporter = "summary"))
n <- sum(res$nb)
skipped <- sum(res$skipped)
cat(sprintf("ran %d expectations in %d tests, %d skipped\n", n, nrow(res), skipped))
if (nrow(res) == 0L || n == 0L || skipped > 0L) stop("the consumer fixture proved nothing")
if (sum(res$failed) > 0L || any(res$error)) stop("the consumer fixture failed")
