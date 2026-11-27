.libPaths(c("/tmp/zutable-hunt/lib", .libPaths()))
library(zutable)
set.seed(5)
fails <- 0
chk <- function(label, a, b) { if (!identical(a, b)) { fails <<- fails + 1; cat("FAIL", label, "\n") } }
icol <- function(n, w, na) { # integer column whose range is exactly 2^w - 1 (+/- d)
  d <- sample(c(-1, 0, 1), 1); r <- min(2^w - 1 + d, 2^32 - 2); r <- max(r, 0)
  lo <- if (r >= 2^31 - 1) -(2^31 - 1) else sample(c(0, -5, floor(-(2^31 - 1) + runif(1) * (2^32 - 2 - r))), 1)
  lo <- max(lo, -(2^31 - 1)); hi <- min(lo + r, 2^31 - 1)
  v <- as.integer(c(lo, hi, floor(runif(n, lo, hi + 1))))[sample.int(n + 2, n, n > 2 && FALSE)]
  v <- sample(as.integer(pmin(hi, c(lo, hi, floor(runif(max(n - 2, 0), lo, hi + 1))))), n, TRUE)
  if (na && n) v[sample.int(n, max(1, n %/% 10))] <- NA
  v
}
dcol <- function(n, w, na) { # doubles with ordinal range ~2^w
  if (w <= 52) { j <- floor(runif(n) * 2^w); j[sample.int(max(n, 1), min(n, 2))] <- c(0, 2^w - 1)[seq_len(min(n, 2))]; v <- 1 + j * 2^-52 }
  else v <- sample(c(-Inf, Inf, -1e300, 1e300, 0, -0, 4.9e-324, -4.9e-324, rnorm(5)), n, TRUE)
  if (na && n) v[sample.int(n, max(1, n %/% 10))] <- sample(c(NA, NaN), max(1, n %/% 10), TRUE)
  v
}
sizes <- c(2, 23, 24, 25, 127, 128, 129, 999, 1000, 1001, 5000)
for (it in 1:3000) {
  n <- sample(sizes, 1); k <- sample(1:4, 1)
  cols <- lapply(seq_len(k), function(i) { w <- sample(c(0, 1, 2, 7, 8, 9, 15, 16, 17, 30, 31, 32, 33, 51, 52, 60), 1); na <- runif(1) < .5
    if (w <= 32 && runif(1) < .6) icol(n, w, na) else dcol(n, w, na) })
  # duplicate rows to create ties
  if (runif(1) < .5) { idx <- sample.int(n, n, TRUE); cols <- lapply(cols, `[`, idx) }
  dec <- sample(c(TRUE, FALSE), k, TRUE)
  for (nl in list(TRUE, FALSE, NA)) {
    a <- do.call(key_order, c(cols, list(decreasing = dec, na.last = nl)))
    b <- do.call(order, c(cols, list(decreasing = dec, na.last = nl, method = "radix")))
    chk(paste("multi", it, n, k, nl), a, b)
  }
  g <- do.call(grp, c(cols, list(sort = TRUE)))
  b <- do.call(order, c(cols, list(method = "radix")))
  chk(paste("grps order", it, n, k), g$order, b)
}
cat("fails:", fails, "\n")
# large: MSD threshold
for (n in c(999999, 1000000, 1000001)) {
  for (mk in 1:5) {
    x <- switch(mk, sample.int(.Machine$integer.max, n, TRUE), rnorm(n), sample(c(NA, 1:5000), n, TRUE), sample(c(NA, NaN, rnorm(1000)), n, TRUE), as.integer(runif(n, -2^31 + 1, 2^31 - 1)))
    for (dec in c(FALSE, TRUE)) chk(paste("big", n, mk, dec), key_order(x, decreasing = dec), order(x, decreasing = dec, method = "radix"))
    chk(paste("big na first", n, mk), key_order(x, na.last = FALSE), order(x, na.last = FALSE, method = "radix"))
  }
  x <- sample.int(3, n, TRUE); y <- rnorm(n); y[sample.int(n, 10)] <- NA
  chk(paste("big2", n), key_order(x, y, decreasing = c(TRUE, FALSE)), order(x, y, decreasing = c(TRUE, FALSE), method = "radix"))
}
cat("fails:", fails, "\n")
