.libPaths(c("/tmp/zutable-hunt/lib", .libPaths()))
library(zutable)
set.seed(13); fails <- 0
chk <- function(label, a, b) { if (!identical(a, b)) { fails <<- fails + 1; cat("FAIL", label, "\n") } else { cat("ok", label, "\n"); flush(stdout()) } }
n <- 1200000L
# ASCII digits/letters only, so base radix (C-locale) is a sound oracle
x <- paste0(sample(c("", "abcdefg", "abcdefgh", "abcdefghijk"), n, TRUE), sample.int(400000L, n, TRUE)); x[sample.int(n, 100)] <- NA
chk("big str order", key_order(x), order(x, method = "radix", na.last = TRUE))
chk("big str order dec", key_order(x, decreasing = TRUE, na.last = FALSE), order(x, method = "radix", decreasing = TRUE, na.last = FALSE))
chk("big str dense", key_rank(x, ties = "dense", na.last = "keep"), match(x, sort(unique(x), method = "radix")))
g <- grp(x, sort = TRUE); chk("big str grp sorted", g$id, match(x, sort(unique(x), method = "radix", na.last = TRUE)))
y <- sample(c(NA, 1:3), n, TRUE); z <- rnorm(n); z[sample.int(n, 1000)] <- NA
chk("big 3 col", key_order(y, x, z, decreasing = c(FALSE, TRUE, FALSE)), order(y, x, z, decreasing = c(FALSE, TRUE, FALSE), method = "radix"))
chk("big wide 2 dbl", key_order(z, rev(z), na.last = FALSE), order(z, rev(z), na.last = FALSE, method = "radix"))
chk("big rank", key_rank(z, na.last = "keep"), as.integer(rank(z, ties.method = "min", na.last = "keep")))
j <- grp_join(x[1:300000], x[600001:1200000]); xx <- x[1:300000]; yy <- x[600001:1200000]
u <- unique(yy); sp <- split(seq_along(yy), match(yy, u)); e <- unname(sp[as.character(match(xx, u))]); e <- lapply(e, function(v) if (is.null(v)) integer() else v)
chk("big join", j, list(x = rep(seq_along(e), lengths(e)), y = as.integer(unlist(e))))
cat("fails:", fails, "\n")
