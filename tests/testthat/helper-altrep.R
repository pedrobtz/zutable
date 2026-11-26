# Helpers of test-altrep.R, kept here so that test_check(shuffle = TRUE)
# defines them before any test runs.

# An ALTREP record of zutable's sorted class, as an earlier version wrote
# it (class, package, type, then the state, a list of the payload and the
# marks), in the ASCII serialization format, built by hand: since #80
# nothing writes one, and only such a stream reaches the unserialize
# method.
sorted_stream <- function(cls, type, payload, marks) {
  head <- strsplit(rawToChar(serialize(NULL, NULL, ascii = TRUE)), "\n")[[1L]]
  head <- head[seq_len(length(head) - 1L)]
  body <- function(x) {
    lines <- strsplit(rawToChar(serialize(x, NULL, ascii = TRUE)), "\n")[[1L]]
    lines[-seq_along(head)]
  }
  sym <- function(s) c("1", "262153", as.character(nchar(s)), s)
  lines <- c(head, "238",
             "2", sym(cls), "2", sym("zutable"), "2", "13", "1", as.character(type), "254",
             "19", "2", body(payload), body(marks), "254")
  charToRaw(paste0(paste(lines, collapse = "\n"), "\n"))
}
