source("pre.R")
x <- zutable(a = 1:3)
for (n in list(0, 1, 2.9, -1, NA, Inf, .Machine$integer.max + 1, NULL, "2", c(1,2), TRUE, NaN, -Inf, 0.5)) { cat("n =", deparse(n), ":\n"); r <- try_(print(x, n = n)); if (r != "no error") print(r) }
# retention
y <- zutable(a = 1:3); for (i in 1) y[, a := 1L]; rm(y); invisible(gc()); cat("held after rm:", !is.null(zutable:::zt_state$skip_print), "\n")
# explicit print at top level after a top-level update that DID autoprint-skip: prints
z <- zutable(a = 1:2)
z[, a := 3L]
print(z)
# two tables
p <- zutable(a = 1:2); q <- zutable(a = 1:2)
for (i in 1) { p[, a := 0L]; q[, a := 0L] }
cat("p:\n")
p
cat("q:\n")
q
cat("q again:\n")
q
