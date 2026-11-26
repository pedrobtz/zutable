.libPaths(c("/tmp/zutable-hunt/lib", .libPaths()))
library(zutable)
set.seed(6)
fails <- 0
chk <- function(label, a, b) { if (!identical(a, b)) { fails <<- fails + 1; cat("FAIL", label, "\n") } else cat("ok", label, "\n") }
full <- function(lab, x, g = grp(x)) {
  id0 <- match(x, unique(x))
  chk(paste(lab, "id"), g$id, id0); chk(paste(lab, "n"), g$n, max(id0))
  chk(paste(lab, "sizes"), g$sizes, tabulate(id0, g$n)); chk(paste(lab, "order"), g$order, order(id0, method = "radix"))
}
# forced partition bits at small sizes
for (b in c(0, 1, 5, 16)) for (n in c(1, 100, 5000)) { x <- sample.int(n %/% 3 + 1, n, TRUE); g <- zutable:::zt_grp_native(list(x), n, b); id0 <- match(x, unique(x)); if (!identical(g$id, id0) || !identical(g$first, match(seq_len(g$n), id0))) { fails <- fails + 1; cat("FAIL forced", b, n, "\n") } }
# adversarial estimate: sampled rows all equal, rest distinct
n <- 3000000L
x <- seq_len(n); s <- as.integer((0:1023) * as.double(n) %/% 1024) + 1L; x[s] <- 0L
full("sample-says-1-truth-distinct", x)
# sampled rows all distinct, rest equal
x <- rep(7L, n); x[s] <- -(1:1024)
full("sample-says-distinct-truth-few", x)
# all distinct doubles (partitioned)
x <- runif(n); full("distinct dbl 3e6", x)
# strings 2e6 distinct
x <- as.character(sample.int(2000000L)); full("distinct chr 2e6", x)
# sort route threshold
for (n in c(999999L, 1000000L, 1000001L)) for (nd in c(9999L, 10000L, 10001L, 10011L, 50L)) {
  x <- sample(c(NA, sample.int(1e9, nd - 1)), n, TRUE); x[seq_len(nd)] <- unique(x)[seq_len(min(nd, length(unique(x))))]
  g <- grp(x, sort = TRUE); u <- sort(unique(x), na.last = TRUE); id0 <- match(x, u)
  ok <- identical(g$id, id0) && identical(g$keys[[1]][seq_len(g$n)], u) && identical(g$sizes, tabulate(id0, g$n)) && identical(g$order, order(id0, method = "radix")) && identical(g$starts, as.integer(cumsum(c(1L, g$sizes))[seq_len(g$n)]))
  if (!ok) { fails <- fails + 1; cat("FAIL sortroute", n, nd, "\n") }
  # doubles with NA and NaN
  y <- as.double(x); y[sample.int(n, 5)] <- NaN
  g <- grp(y, sort = TRUE); ky <- ifelse(is.nan(y), "NaN", as.character(y)); 
  if (!identical(match(g$id, unique(g$id)), match(ky, unique(ky))) || is.unsorted(g$keys[[1]][seq_len(g$n - 2)]) || !all(is.na(tail(g$keys[[1]], 2)))) { fails <- fails + 1; cat("FAIL sortroute dbl", n, nd, "\n") }
}
cat("fails:", fails, "\n")
