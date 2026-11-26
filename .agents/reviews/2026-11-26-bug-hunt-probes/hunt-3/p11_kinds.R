.libPaths(c("/tmp/zutable-hunt/lib", .libPaths()))
library(zutable)
set.seed(8)
fails <- 0
chk <- function(label, a, b) { if (!identical(a, b)) { fails <<- fails + 1; cat("FAIL", label, "\n"); if (fails < 15) { print(head(a, 30)); print(head(b, 30)) } } }
T <- function(e) tryCatch(e, error = function(e) paste("ERR", class(e)[1], conditionMessage(e)))
# raw lists with zero bytes, NULL
rpool <- list(NULL, raw(0), as.raw(0), as.raw(c(0, 0)), as.raw(1), as.raw(c(1, 0)), as.raw(c(97:104)), as.raw(c(97:104, 0)), as.raw(c(97:104, 0, 0)), as.raw(c(97:104, 1)), as.raw(c(97:103, 0)), as.raw(c(97:103)), as.raw(255), as.raw(c(255, 255, 255, 255, 255, 255, 255, 255, 255)), as.raw(rep(0, 8)), as.raw(rep(0, 9)), as.raw(rep(0, 7)))
hexk <- function(l) vapply(l, function(e) if (is.null(e)) NA_character_ else paste0("x", paste(e, collapse = "")), "")
for (n in c(0, 1, 5, 16, 17, 18, 40, 500, 3000)) {
  l <- sample(rpool, n, TRUE); h <- hexk(l)
  chk(paste("raw grp", n), T(grp(l)$id), match(h, unique(h)))
  for (dec in c(FALSE, TRUE)) for (nl in list(TRUE, FALSE, NA)) {
    r <- match(h, sort(unique(h), method = "radix"))
    chk(paste("raw order", n, dec, nl), T(key_order(l, decreasing = dec, na.last = nl)), order(r, decreasing = dec, na.last = nl, method = "radix"))
  }
  l2 <- sample(rpool, 7, TRUE); chk(paste("raw match", n), T(grp_match(l, l2)), match(h, hexk(l2)))
}
# long random raw: sharing long prefixes
mk <- function() as.raw(c(rep(7, sample(c(0, 7, 8, 9, 20), 1)), sample(c(0, 1, 255), sample(0:4, 1), TRUE)))
l <- replicate(4000, mk(), simplify = FALSE); h <- hexk(l); r <- match(h, sort(unique(h), method = "radix"))
chk("raw long", key_order(l), order(r, method = "radix")); chk("raw rank dense", key_rank(l, ties = "dense"), r)
# integer64
if (FALSE) {
  library(bit64)
  v <- c(as.integer64("9223372036854775807"), as.integer64("-9223372036854775807"), as.integer64(0), NA_integer64_, as.integer64(1), as.integer64(-1), as.integer64("4611686018427387904"), as.integer64(2)^53 + 1L, as.integer64(2)^53)
  for (n in c(9, 100, 3000)) { x <- v[sample.int(9, n, TRUE)]; if (n == 9) x <- v
    cx <- as.character(x)
    chk(paste("i64 grp", n), T(grp(x)$id), match(cx, unique(cx)))
    for (dec in c(FALSE, TRUE)) for (nl in list(TRUE, FALSE, NA)) chk(paste("i64 order", n, dec, nl), T(key_order(x, decreasing = dec, na.last = nl)), { o <- bit64::order(x, decreasing = dec, na.last = nl); r <- match(cx, as.character(sort(unique(x)))); order(r, decreasing = dec, na.last = nl, method = "radix") })
    chk(paste("i64 sort", n), as.character(T(key_sort(x))), as.character(x[order(match(cx, as.character(sort(unique(x)))), method = "radix")]))
    chk(paste("i64 match", n), T(grp_match(x, rev(v))), match(cx, as.character(rev(v))))
    chk(paste("i64 2col", n), T(key_order(x, seq_len(n) %% 2L, decreasing = c(TRUE, FALSE))), order(-match(cx, as.character(sort(unique(x)))), seq_len(n) %% 2L, method = "radix"))
    print(T(grp_reduce(x, rep(1L, n), "min"))); print(T(grp_reduce(x, rep(1L, n), "sum"))); print(T(grp_reduce(x, rep(1L, n), "first"))); print(T(grp_reduce(x, rep(1L, n), "nobs")))
  }
  print(T(grp_match(as.integer64(1:3), c(1, 2)))); print(T(grp_match(as.integer64(1:3), 1:2)))
} else cat("no bit64\n")
# equivalence: Date int vs double, int vs double, one col vs split
d_i <- structure(sample(c(NA, -3:3), 500, TRUE), class = "Date"); d_d <- structure(as.double(unclass(d_i)), class = "Date")
chk("date grp", grp(d_i)$id, grp(d_d)$id); chk("date order", key_order(d_i, decreasing = TRUE), key_order(d_d, decreasing = TRUE)); chk("date rank", key_rank(d_i), key_rank(d_d))
chk("date sort class", class(key_sort(d_i)), "Date"); chk("date sort", unclass(key_sort(d_d))[1:500], sort(unclass(d_d), na.last = TRUE))
chk("date match", grp_match(d_i, d_d[1:20]), match(d_i, d_d[1:20]))
p <- as.POSIXct(c(2, NA, 1, 1.5), origin = "1970-01-01", tz = "UTC"); chk("posix", key_order(p), order(p, na.last = TRUE, method = "radix")); print(attributes(key_sort(p)))
f <- factor(c("b", "a", NA, "c", "a"), levels = c("c", "zz", "b", "a")); print(key_sort(f)); print(grp(f)$keys); print(grp(f, sort = TRUE)$keys); print(grp_reduce(f, c(1, 1, 2, 2, 2), "first")); print(T(grp_reduce(f, c(1, 1, 2, 2, 2), "max")))
fNA <- addNA(factor(c("x", NA, "y"))); print(grp(fNA)$id); print(key_order(fNA)); print(order(fNA)); print(T(grp_match(fNA, c("x", NA))))
of <- factor(c("lo", "hi", "lo"), levels = c("lo", "hi"), ordered = TRUE); print(T(grp_reduce(of, c(1, 1, 1), "max")))
# names / matrix / attributes
m <- matrix(c(2, 1, 2, 1), 2); print(T(grp(m)$id)); print(T(key_order(m))); print(T(key_sort(c(b = 2, a = 1))))
# args
print(T(key_order(1:3, decreasing = NA))); print(T(key_order(1:3, na.last = "x"))); print(T(key_order(1:3, 1:2))); print(T(key_order())); print(T(grp())); print(T(key_order(NULL))); print(T(grp(NULL)$n)); print(T(key_rank(c(1, NA), na.last = NA)))
print(T(key_order(list(1:3, 3:1)))); print(T(key_order(data.frame(a = c(2, 1), b = c("x", "y"))))); print(T(grp(list())$n)); print(T(key_order(1i))); print(T(grp(quote(a))))
print(T(key_order(c(1, 2), decreasing = c(TRUE, FALSE)))); print(T(key_rank(c(2, 1, 2), ties = "max"))); print(T(key_rank(c("b", NA, "a", "b"), ties = "min", na.last = "keep")))
cat("fails:", fails, "\n")
