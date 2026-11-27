.libPaths(c("/tmp/zutable-hunt/lib", .libPaths()))
library(zutable)
set.seed(3)
fails <- 0
bits <- function(v) if (is.double(v)) { b <- vapply(v, function(e) paste(rev(as.character(writeBin(e, raw()))), collapse = ""), ""); if (LOOSE) b[is.na(v)] <- "missing"; b } else v
LOOSE <- FALSE
chk <- function(label, a, b) { if (!identical(bits(a), bits(b))) { fails <<- fails + 1; if (fails < 25) { cat("FAIL", label, "\n"); d <- which(bits(a) != bits(b) | is.na(bits(a)) != is.na(bits(b))); print(head(d)); print(head(a[d], 8)); print(head(b[d], 8)) } } }
gens <- list(
  dbl = function(n) rnorm(n) * 10^sample(-5:5, n, TRUE),
  dbl_na = function(n) sample(c(NA, NaN, 1, 2.5, -1e10, 1e10, 0.1), n, TRUE),
  dbl_big = function(n) sample(c(1e308, -1e308, 1.7e308, 1, Inf, -Inf), n, TRUE, prob = c(3, 3, 3, 3, .1, .1)),
  dbl_cancel = function(n) sample(c(1e16, -1e16, 1, 1e-16, 2^53, 1 + 2^-52, 2^-1074, 2^64, -2^64, 2^63), n, TRUE),
  dbl_zero = function(n) sample(c(-0, 0, NA), n, TRUE),
  int = function(n) sample(c(NA, -5:5), n, TRUE),
  int_big = function(n) sample(c(.Machine$integer.max, -.Machine$integer.max, 1L, NA), n, TRUE, prob = c(5, 3, 1, .2)),
  lgl = function(n) sample(c(NA, TRUE, FALSE), n, TRUE)
)
base_fn <- function(fn, v, narm) {
  if (narm) { w <- v[!is.na(v)] } else w <- v
  switch(fn,
    sum = if (narm && !length(w)) NA_real_ else as.double(if (is.double(w)) sum(w) else sum(as.double(w))),
    prod = if (narm && !length(w)) NA_real_ else prod(w),
    mean = if (narm && !length(w)) NA_real_ else mean(w),
    min = if (narm && !length(w)) v[NA_integer_][1] else if (anyNA(w)) { if (is.double(w)) min(w) else w[NA_integer_][1] } else min(w),
    max = if (narm && !length(w)) v[NA_integer_][1] else if (anyNA(w)) { if (is.double(w)) max(w) else w[NA_integer_][1] } else max(w),
    count = length(v), nobs = sum(!is.na(v)),
    first = if (length(w)) w[1] else v[NA_integer_][1], last = if (length(w)) w[length(w)] else v[NA_integer_][1])
}
fns <- c("sum", "prod", "mean", "min", "max", "count", "nobs", "first", "last")
for (it in 1:500) {
  n <- sample(c(1, 2, 3, 50, 4095, 4096, 4097, 8191, 8192, 8193, 10000, 30000), 1)
  ng <- sample(c(1, 2, 3, 50, n), 1)
  key <- sample.int(ng, n, TRUE)
  if (runif(1) < .3) key <- sort(key)
  gn <- sample(names(gens), 1); v <- gens[[gn]](n)
  g <- grp(key)
  sp <- split(v, factor(g$id, levels = seq_len(g$n)))
  for (narm in c(TRUE, FALSE)) for (fn in fns) {
    LOOSE <- !narm
    r <- grp_reduce(v, g, fn, na.rm = narm)
    b <- unname(vapply(sp, function(w) base_fn(fn, w, narm), if (fn %in% c("count", "nobs")) 1L else if (fn %in% c("sum", "prod", "mean")) 1 else if (is.logical(v) && fn %in% c("min", "max")) 1L else v[1]))
    chk(paste(it, gn, n, ng, fn, narm), r, b)
  }
  # fused all at once must equal alone
  LOOSE <- FALSE
  r_all <- grp_reduce(rep(list(v), length(fns)), g, fns)
  for (j in seq_along(fns)) chk(paste("fused", it, gn, fns[j]), r_all[[j]], grp_reduce(v, g, fns[j]))
}
cat("fails:", fails, "\n")
