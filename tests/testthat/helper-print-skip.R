# Helpers of test-print-skip.R, kept here so that test_check(shuffle = TRUE)
# defines them before any test runs.

headers_after_marks <- function(out) {
  marks <- grep("^@@", out)
  ends <- c(marks[-1L] - 1L, length(out))
  stats::setNames(vapply(seq_along(marks), function(k) {
    seg <- out[seq_len(ends[[k]] - marks[[k]]) + marks[[k]]]
    sum(grepl("^<zutable>", seg))
  }, 0L), sub("^@@ ?", "", out[marks]))
}
