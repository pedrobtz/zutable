.libPaths(c("/tmp/zutable-hunt/lib", .libPaths()))
library(zutable)
cat("long double:", capabilities("long.double"), R.version.string, "\n")
set.seed(1)
fails <- 0
chk <- function(label, a, b) { if (!identical(a, b)) { fails <<- fails + 1; cat("FAIL", label, "\n"); if (fails < 15) { print(head(a, 20)); print(head(b, 20)) } } }
gens <- list(
  int_small = function(n) sample(c(NA, -3:3), n, TRUE),
  int_ext = function(n) sample(c(NA, -.Machine$integer.max, .Machine$integer.max, 0L, 1L, -1L), n, TRUE),
  int_wide = function(n) as.integer(runif(n, -2^31 + 1, 2^31 - 1)),
  int_4095 = function(n) sample(0:4094, n, TRUE),
  int_4096 = function(n) sample(0:4095, n, TRUE),
  int_4097 = function(n) sample(c(NA, 0:4096), n, TRUE),
  lgl = function(n) sample(c(NA, TRUE, FALSE), n, TRUE),
  dbl = function(n) sample(c(NA, NaN, -0, 0, Inf, -Inf, 1, 1 + .Machine$double.eps, 1 - .Machine$double.eps/2, 4.9e-324, -4.9e-324, 2.2e-308, 1e308, -1e308), n, TRUE),
  dbl_r = function(n) rnorm(n),
  dbl_int = function(n) as.double(sample(c(NA, 1:50), n, TRUE)),
  sorted = function(n) sort(sample(1:20, n, TRUE)),
  rev = function(n) rev(sort(sample(1:20, n, TRUE))),
  revd = function(n) rev(sort(sample(c(-0, 0, 1, 2), n, TRUE))),
  const = function(n) rep(5L, n),
  allna = function(n) rep(NA_real_, n),
  runs = function(n) rep_len(c(1:200, 200:1, rep(7L, 150)), n),
  fct = function(n) factor(sample(c("b", "a", "zz", NA), n, TRUE), levels = c("zz", "unused", "b", "a"))
)
sizes <- c(0, 1, 2, 3, 23, 24, 25, 127, 128, 129, 999, 1000, 1001, 2999, 3000, 3001, 4095, 4096, 4097, 5000, 70000)
for (gn in names(gens)) for (n in sizes) {
  x <- gens[[gn]](n)
  for (dec in c(FALSE, TRUE)) for (nl in list(TRUE, FALSE, NA)) {
    lab <- paste(gn, n, dec, nl)
    chk(paste("order", lab), key_order(x, decreasing = dec, na.last = nl), order(x, decreasing = dec, na.last = nl, method = "radix"))
    s <- key_sort(x, decreasing = dec, na.last = nl)
    o <- order(x, decreasing = dec, na.last = nl, method = "radix")
    chk(paste("sort", lab), unclass(s[seq_along(s)]) + 0L * 0, unclass(x[o]) + 0L * 0)
    if (!identical(is.unsorted(s), is.unsorted(x[o]))) { fails <- fails + 1; cat("FAIL unsorted mark", lab, "\n") }
    if (!identical(anyNA(s), anyNA(x[o]))) { fails <- fails + 1; cat("FAIL anyNA mark", lab, "\n") }
  }
  if (!is.factor(x)) for (tm in c("min", "first")) for (nl in list(TRUE, FALSE, "keep", NA)) {
    b <- rank(x, ties.method = tm, na.last = nl)
    chk(paste("rank", gn, n, tm, nl), key_rank(x, ties = tm, na.last = nl), as.integer(b))
  }
  if (n > 0 && !is.factor(x)) chk(paste("dense", gn, n), key_rank(x, ties = "dense", na.last = "keep"), { u <- sort(unique(x[!is.na(x)])); r <- match(x, u); r[is.na(x)] <- NA; r })
}
# multi-key
for (it in 1:400) {
  n <- sample(sizes[-length(sizes)], 1); k <- sample(2:5, 1)
  cols <- lapply(seq_len(k), function(i) gens[[sample(names(gens), 1)]](n))
  dec <- sample(c(TRUE, FALSE), k, TRUE)
  for (nl in list(TRUE, FALSE, NA)) {
    a <- do.call(key_order, c(cols, list(decreasing = dec, na.last = nl)))
    b <- do.call(order, c(cols, list(decreasing = dec, na.last = nl, method = "radix")))
    chk(paste("multi", it, n, k, nl), a, b)
  }
}
cat("fails:", fails, "\n")
