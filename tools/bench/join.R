# Joins and matches against design-kernel 9.3's targets: data.table's
# x[y, on =] index pairs (which = TRUE), collapse::fmatch(), match() and
# bit64's match. Run on an installed build (R CMD INSTALL --preclean .).
#
#   Rscript tools/bench/join.R [n]
library(zutable)
args <- commandArgs(TRUE)
n <- if (length(args)) as.numeric(args[[1L]]) else 1e6
med <- function(f, reps = 5L) {
  stats::median(vapply(seq_len(reps), function(i) system.time(f())[["elapsed"]], 0))
}
has <- function(p) requireNamespace(p, quietly = TRUE)
if (has("data.table")) data.table::setDTthreads(1L)
if (has("collapse")) collapse::set_collapse(nthreads = 1L)
set.seed(20261118)
cat("case\tn\tdistinct\tzutable\tother\tother_s\tratio\n")
row <- function(case, d, tz, other, to) {
  cat(sprintf("%s\t%.0f\t%.0f\t%.3f\t%s\t%.3f\t%.2fx\n", case, n, d, tz, other, to, to / tz))
}
for (d in c(1e3, n / 10)) {
  xk <- sample.int(d, n, TRUE)
  yk <- sample.int(d)
  tz <- med(function() grp_join(xk, yk))
  if (has("data.table")) {
    X <- data.table::data.table(k = xk)
    Y <- data.table::data.table(k = yk)
    row("inner, one key", d, tz, "data.table", med(function() X[Y, on = "k", which = TRUE, nomatch = NULL]))
  }
  xa <- xk %% 97L; xb <- xk %/% 97L
  ya <- yk %% 97L; yb <- yk %/% 97L
  tz2 <- med(function() grp_join(list(xa, xb), list(ya, yb)))
  if (has("data.table")) {
    X2 <- data.table::data.table(a = xa, b = xb)
    Y2 <- data.table::data.table(a = ya, b = yb)
    row("inner, two keys", d, tz2, "data.table",
        med(function() X2[Y2, on = c("a", "b"), which = TRUE, nomatch = NULL]))
  }
  tm <- med(function() grp_match(xk, yk))
  row("match, one key", d, tm, "match()", med(function() match(xk, yk)))
  if (has("collapse")) row("match, one key", d, tm, "fmatch()", med(function() collapse::fmatch(xk, yk)))
  if (has("bit64")) {
    x64 <- bit64::as.integer64(xk) * 1000003L
    y64 <- bit64::as.integer64(yk) * 1000003L
    row("match, integer64", d, med(function() grp_match(x64, y64)), "bit64",
        med(function() bit64::match(x64, y64)))
  }
}
