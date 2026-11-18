# The string order and the collated sort from R against their section 9.3
# oracles (Stage 12): key_order() of character keys against base radix
# order() and data.table's forderv() at one thread; key_sort(collate =
# TRUE) against stringi::stri_sort() and base sort(). Each result is
# checked against its oracle before it is timed.
#
# Run on an optimised install (R CMD INSTALL --preclean . first):
#   Rscript tools/bench/str-order.R
suppressPackageStartupMessages({library(zutable); library(data.table)})
setDTthreads(1L)
set.seed(20261118)
med <- function(f, reps = 5L) { gc(); t <- replicate(reps, system.time(f())[["elapsed"]]); median(t) }
words <- function(m) unique(stringi::stri_rand_strings(m * 1.1, sample(4:16, m * 1.1, TRUE)))[seq_len(m)]
row <- function(what, n, d, ours, base, dt = NA) cat(sprintf("| %s | %g | %g | %.3f | %.3f | %s | %.2fx |\n", what, n, d, ours, base, if (is.na(dt)) "" else sprintf("%.3f", dt), base / ours))
cat("| input | rows | distinct | key_order s | base radix s | forder s | speed-up |\n|---|---|---|---|---|---|---|\n")
for (spec in list(c(1e7, 1e5), c(1e6, 1e6), c(1e7, 1e7))) {
  n <- spec[[1]]; d <- spec[[2]]
  u <- words(d); x <- if (n == d) sample(u) else sample(u, n, TRUE)
  stopifnot(identical(key_order(x), order(x, method = "radix")))
  row("character", n, d, med(function() key_order(x), 3L), med(function() order(x, method = "radix"), 3L), med(function() data.table:::forderv(x), 3L))
}
cat("\n| collated sort | strings | distinct | key_sort s | stri_sort s | base sort() s | vs stri | vs base |\n|---|---|---|---|---|---|---|---|\n")
for (spec in list(c(1e5, 1e4), c(1e6, 1e5), c(1e6, 1e6))) {
  n <- spec[[1]]; d <- spec[[2]]
  u <- words(d); x <- if (n == d) sample(u) else sample(u, n, TRUE)
  stopifnot(identical(key_sort(x, collate = TRUE, na.last = NA), stringi::stri_sort(x)))
  a <- med(function() key_sort(x, collate = TRUE), 3L); b <- med(function() stringi::stri_sort(x), 3L)
  cc <- med(function() sort(x), 1L)
  cat(sprintf("| words | %g | %g | %.3f | %.3f | %.3f | %.2fx | %.1fx |\n", n, d, a, b, cc, b / a, cc / a))
}
