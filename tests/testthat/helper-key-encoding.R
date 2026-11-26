# Helpers of test-key-encoding.R, kept here so that test_check(shuffle = TRUE)
# defines them before any test runs.

native_jose <- function() {
  x <- rawToChar(as.raw(c(0x4a, 0x6f, 0x73, 0xc3, 0xa9)))
  Encoding(x) <- "unknown"
  x
}

skip_unless_utf8_locale <- function() {
  skip_if_not(isTRUE(l10n_info()[["UTF-8"]]), "not a UTF-8 locale")
}
