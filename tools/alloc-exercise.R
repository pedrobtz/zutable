# Exercised by alloc-failure.yaml: each allocation, R's included, is failed
# in turn while this runs, and every failure must surface as R's
# "cannot allocate" error, never a crash. It reaches each native routine.
library(zutable)
x <- c("0.1", "1e-300", "nan", NA, "x", "1.7976931348623157e+308")
d <- zutable:::zt_parse_double(x)
s <- zutable:::zt_format_double(c(0.1, 1 / 3, NaN, -Inf, NA, 1e21))
dt <- zutable:::zt_format_date(as.Date(c("2026-01-01", NA)) - c(0, 800000))
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
# Strings (zt_strings_rank) and sorted values (zt_sorted_wrap, the ALTREP
# class's methods: a write, a copy and a serialize round trip).
os <- key_order(c("b", "a", NA, "ab"), list(as.raw(1), NULL, raw(), as.raw(0)))
v <- key_sort(c(3, 1, NA))
v2 <- v
v2[1L] <- 5
vs <- key_sort(c("b", "a"))
vs[1L] <- "c"
u <- unserialize(serialize(v, NULL))
m <- .Call(zutable:::zt_sorted_meta, u)
# Joins (zt_join): pairs, a left join with an unmatched row, semi, the
# fan-out error, and join() on tables with na_equal = FALSE.
j1 <- grp_join(c("a", "b", "a"), c("b", "a", "a", NA), type = "left")
j2 <- grp_join(list(k, c(1, 2, 3, 4, 5)), list(c(3L, NA), c(1, 3)), type = "semi")
j3 <- tryCatch(grp_join(1:2, c(1L, 1L), multiple = "error"), error = identity)
jm <- grp_match(c(2L, 9L), 1:3)
jt <- join(zutable(a = c(1L, NA)), zutable(a = c(NA, 1L), b = 1:2), on = a,
           how = "full", na_equal = FALSE)
# Reductions (zt_reduce_r): every statistic over the three kinds, fused,
# broadcast, and the executor's aggregates, over() and := with by.
rd <- grp_reduce(list(c(1.5, NA, 3), c(2L, NA, 4L), c(TRUE, NA, FALSE)), c("a", "b", "a"),
                 c("mean", "sum", "max"))
rd2 <- lapply(c("prod", "min", "count", "nobs", "first", "last"),
              function(f) grp_reduce(c(1, 2, NaN), c(1L, 1L, 2L), f, na.rm = FALSE))
rd3 <- grp_reduce(c("b", "a", NA), c(1L, 1L, 2L), "min", broadcast = "replace")
# The double-accumulator build (zt_reduce_r_double), for an R without long
# double; a group whose sum overflows takes mean's later sweeps.
rd4 <- .Call(zutable:::zt_reduce_r_double, c(1L, 1L, 1L, 2L), 2L,
             list(c(1e308, 1e308, -1e308, 2)), 2L, TRUE, TRUE)
za <- zutable(g = c("x", "y", "x"), v = c(1, 2, 3), w = c(0, 0, 0))
ra <- za[, .(s = sum(v), d = count_distinct(v), hi = max(g)), by = g, having = s > 0]
ro <- za[select = .(v, m = over(mean(v), by = g))]
za[, w := v - mean(v), by = g]
invisible(list(d, z2, g1, g2, o, r, os, v2, vs, u, m, j1, j2, j3, jm, jt, rd, rd2, rd3, rd4,
               ra, ro, za))
