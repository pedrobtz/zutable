.libPaths(c("/tmp/zutable-hunt/lib", .libPaths()))
library(zutable)
set.seed(10); fails <- 0
chk <- function(label, a, b) { if (!identical(a, b)) { fails <<- fails + 1; cat("FAIL", label, "\n"); if (fails < 12) { print(head(a, 20)); print(head(b, 20)) } } }
T <- function(e) tryCatch(e, error = function(e) paste("ERR", class(e)[1], conditionMessage(e)))
hx <- function(u) vapply(enc2utf8(u), function(s) if (is.na(s)) NA_character_ else paste(charToRaw(s), collapse = ""), "", USE.NAMES = FALSE)
pool <- c(NA, "", "a", "Z", "abcdefgh", "abcdefghi", "abcdefgh\x01", "é", "zz", "\U0001F600")
for (it in 1:300) {
  n <- sample(c(1, 2, 50, 4096, 4097, 9000), 1); ng <- sample(c(1, 3, 40, n), 1)
  key <- sample.int(ng, n, TRUE); g <- grp(key); f <- factor(g$id, levels = seq_len(g$n))
  s <- sample(pool, n, TRUE); if (it %% 4 == 0) s[!is.na(s) & s == "é"] <- iconv("é", "UTF-8", "latin1")
  sp <- split(s, f)
  for (narm in c(TRUE, FALSE)) {
    for (fn in c("min", "max")) {
      b <- unname(vapply(sp, function(w) { if (narm) w <- w[!is.na(w)]; if (!length(w) || anyNA(w)) return(NA_character_); h <- hx(w); w[if (fn == "min") which(h == sort(h, method = "radix")[1])[1] else which(h == sort(h, method = "radix", decreasing = TRUE)[1])[1]] }, ""))
      r <- grp_reduce(s, g, fn, na.rm = narm)
      chk(paste(it, "chr", fn, narm), enc2utf8(r), enc2utf8(b))
    }
    chk(paste(it, "chr first", narm), enc2utf8(grp_reduce(s, g, "first", na.rm = narm)), enc2utf8(unname(vapply(sp, function(w) { if (narm) w <- w[!is.na(w)]; if (length(w)) w[1] else NA_character_ }, ""))))
    chk(paste(it, "chr last", narm), enc2utf8(grp_reduce(s, g, "last", na.rm = narm)), enc2utf8(unname(vapply(sp, function(w) { if (narm) w <- w[!is.na(w)]; if (length(w)) w[length(w)] else NA_character_ }, ""))))
    chk(paste(it, "chr nobs", narm), grp_reduce(s, g, "nobs", na.rm = narm), unname(vapply(sp, function(w) sum(!is.na(w)), 1L)))
  }
  # Date and POSIXct min/max, first/last on doubles with NaN
  d <- structure(sample(c(NA, -5:5), n, TRUE), class = "Date")
  chk(paste(it, "date max"), grp_reduce(d, g, "max"), structure(unname(vapply(split(unclass(d), f), function(w) { w <- w[!is.na(w)]; if (length(w)) max(w) else NA_integer_ }, 1L)), class = "Date"))
  x <- sample(c(NA, NaN, 1, 2), n, TRUE)
  chk(paste(it, "dbl first narm"), grp_reduce(x, g, "first"), unname(vapply(split(x, f), function(w) { w <- w[!is.na(w)]; if (length(w)) w[1] else NA_real_ }, 1)))
  chk(paste(it, "dbl last"), grp_reduce(x, g, "last", na.rm = FALSE), unname(vapply(split(x, f), function(w) w[length(w)], 1)))
  chk(paste(it, "dbl nobs"), grp_reduce(x, g, "nobs"), unname(vapply(split(x, f), function(w) sum(!is.na(w)), 1L)))
  # broadcast
  y <- rnorm(n); m <- unname(vapply(split(y, f), mean, 1))
  chk(paste(it, "bc replace"), grp_reduce(y, g, "mean", broadcast = "replace"), m[g$id])
  chk(paste(it, "bc sub"), grp_reduce(y, g, "mean", broadcast = "subtract"), y - m[g$id])
  chk(paste(it, "bc div"), grp_reduce(y, g, "mean", broadcast = "divide"), y / m[g$id])
  # keyed == grp
  r1 <- grp_reduce(y, key, "sum"); attr(r1, "groups") <- NULL; chk(paste(it, "keyed"), r1, grp_reduce(y, g, "sum"))
  # sorted grp lines up with keys
  gs <- grp(key, sort = TRUE); chk(paste(it, "sorted grp"), grp_reduce(y, gs, "sum"), unname(vapply(split(y, key), sum, 1))); chk(paste(it, "sorted keys"), gs$keys[[1]][seq_len(gs$n)], sort(unique(key)))
}
# hand-made grp: empty group, wrong fields
g <- grp(c(1, 2, 1)); g2 <- g; g2$n <- 4L
for (fn in c("sum", "prod", "mean", "min", "max", "count", "nobs", "first", "last")) { cat(fn, ": "); print(T(grp_reduce(c(1, 2, 3), g2, fn))) }
g3 <- g; g3$id <- c(1L, 5L, 1L); print(T(grp_reduce(c(1, 2, 3), g3, "sum")))
g3$id <- c(1L, NA, 1L); print(T(grp_reduce(c(1, 2, 3), g3, "sum"))); g3$id <- c(1, 2, 1); print(T(grp_reduce(c(1, 2, 3), g3, "sum"))); g3$id <- c(0L, 1L, 1L); print(T(grp_reduce(c(1, 2, 3), g3, "sum")))
g3 <- g; g3$n <- NA_integer_; print(T(grp_reduce(c(1, 2, 3), g3, "sum"))); g3$n <- 2.9; print(T(grp_reduce(c(1, 2, 3), g3, "sum"))); g3$n <- 1e10; print(T(grp_reduce(c(1, 2, 3), g3, "sum"))); g3$n <- c(2L, 3L); print(T(grp_reduce(c(1, 2, 3), g3, "sum"))); g3$n <- "2"; print(T(grp_reduce(c(1, 2, 3), g3, "sum")))
print(T(grp_reduce(c(1, 2), g, "sum"))); print(T(grp_reduce(numeric(), grp(numeric()), "sum"))); print(T(grp_reduce(numeric(), numeric(), "count")))
print(T(grp_reduce(list(), g, "sum"))); print(T(grp_reduce(c(1, 2, 3), g, c("sum", "mean")))); print(T(grp_reduce(1:3, g, "sum"))); print(T(grp_reduce(c(TRUE, NA, TRUE), g, "mean")))
print(T(grp_reduce(c(.Machine$integer.max, .Machine$integer.max, 1L), c(1, 1, 1), "sum")[1])); print(T(grp_reduce(c(.Machine$integer.max, 2L, 3L), c(1, 1, 1), "prod")[1])); print(T(typeof(grp_reduce(1:3, g, "min"))))
print(T(grp_reduce(c(a = 1, b = 2, c = 3), g, "first"))); print(T(grp_reduce(factor(c("u", "v", "u")), g, "last"))); print(T(grp_reduce(list(a = 1:3, b = c("x", NA, "z")), g, c("sum", "first"))))
print(T(grp_reduce(I(list(1, "a", NULL)), g, "last"))); print(T(grp_reduce(list(list(1, "a", NULL)), g, "last", na.rm = FALSE)));print(T(grp_reduce(list(list(1, "a", NULL)), g, "count")))
print(T(grp_reduce(c(1, 2, 3), g, "sum", broadcast = "replace"))); print(T(grp_reduce(c("a", "b", "c"), g, "max", broadcast = "subtract")))
print(T(grp_reduce(1:3, g, "max", broadcast = "divide"))); print(T(grp_reduce(c(2147483647L, 1L, -2147483647L), g, "max", broadcast = "subtract")))
cat("fails:", fails, "\n")
