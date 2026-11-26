.libPaths(c("/tmp/zutable-hunt/lib", .libPaths()))
library(zutable)
set.seed(12); fails <- 0
fns <- c("sum", "prod", "mean", "min", "max", "count", "nobs", "first", "last")
dbl <- function(x, fn) .Call(zutable:::zt_reduce_r_double, rep(1L, length(x)), 1L, list(x), match(fn, fns) - 1L, TRUE, TRUE)[[1]]
ld <- function(x, fn) .Call(zutable:::zt_reduce_r, rep(1L, length(x)), 1L, list(x), match(fn, fns) - 1L, TRUE, TRUE)[[1]]
acc <- function(x, op) { s <- if (op == "*") 1 else 0; for (v in x) s <- if (op == "*") s * v else s + v; s }
rmean <- function(x) { n <- length(x); s <- acc(x, "+"); if (is.finite(s)) { s <- s / n; t <- 0; for (v in x) t <- t + (v - s); s + t / n } else { s <- 0; for (v in x) s <- s + v / n; if (is.finite(s)) { t <- 0; for (v in x) t <- t + (v - s) / n; s + t } else s } }
gens <- list(function(n) rnorm(n) * 10^sample(-8:8, n, TRUE), function(n) sample(c(1e16, -1e16, 1, 1e-16, 0.1), n, TRUE), function(n) sample(c(1e308, 1.7e308, -1e308, 1), n, TRUE), function(n) runif(n, 0.5, 2), function(n) as.double(sample(c(-5:5, .Machine$integer.max), n, TRUE)))
for (it in 1:400) { n <- sample(c(1, 2, 3, 10, 100, 5000), 1); x <- gens[[sample(length(gens), 1)]](n)
  a <- dbl(x, "sum"); b <- acc(x, "+"); if (!identical(a, b)) { fails <- fails + 1; if (fails < 10) cat("FAIL sum", it, n, sprintf("%a %a", a, b), "\n") }
  a <- dbl(x, "prod"); b <- acc(x, "*"); if (!identical(a, b)) { fails <- fails + 1; if (fails < 10) cat("FAIL prod", it, n, sprintf("%a %a", a, b), "\n") }
  a <- dbl(x, "mean"); b <- rmean(x); if (!identical(a, b)) { fails <- fails + 1; if (fails < 10) cat("FAIL mean", it, n, sprintf("%a %a", a, b), "\n") }
  xi <- as.integer(pmin(pmax(x, -2e9), 2e9)); a <- dbl(xi, "sum"); b <- acc(as.double(xi), "+"); if (!identical(a, b)) { fails <- fails + 1; if (fails < 10) cat("FAIL isum", it, n, sprintf("%a %a", a, b), "\n") }
  a <- dbl(xi, "mean"); b <- acc(as.double(xi), "+") / n; if (!identical(a, b)) { fails <- fails + 1; if (fails < 10) cat("FAIL imean", it, n, sprintf("%a %a", a, b), "\n") }
  # long double route vs base, for the record
  if (!identical(ld(x, "sum"), sum(x)) || !identical(ld(x, "mean"), mean(x)) || !identical(ld(x, "prod"), prod(x))) { fails <- fails + 1; cat("FAIL ld", it, n, "\n") }
}
cat("fails:", fails, "\n")
