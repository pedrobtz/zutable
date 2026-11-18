# Exercised by alloc-failure.yaml: each allocation, R's included, is failed
# in turn while this runs, and every failure must surface as R's
# "cannot allocate" error, never a crash. It reaches each native routine.
library(zutable)
x <- c("0.1", "1e-300", "nan", NA, "x", "1.7976931348623157e+308")
d <- zutable:::zt_parse_double(x)
s <- zutable:::zt_format_double(c(0.1, 1 / 3, NaN, -Inf, NA, 1e21))
s1 <- schema(a = float64)
node <- zutable:::zt_translate(quote(cast(a, string)), s1, environment())
zutable:::zt_eval(node, list(a = c(1.5, 2)), 2L)
z <- zutable(a = c(1L, 2L), b = c(1.5, 2.5))
z[, { a := a + 1L; b := b * 2 }]
z2 <- copy(z)
freeze(z)
# The kernel: grp() by hashing (zt_grp) and by sorting (zt_grp_sort), and
# the sort (zt_key_order, zt_key_rank).
k <- c(3L, 1L, NA, 3L, 2L)
g1 <- grp(k, c("a", "b", "a", "a", NA))
g2 <- grp(k, sort = TRUE)
o <- key_order(k, c(2.5, NaN, 1, -0, 0), decreasing = c(FALSE, TRUE))
r <- key_rank(k, ties = "dense")
invisible(list(d, z2, g1, g2, o, r))
