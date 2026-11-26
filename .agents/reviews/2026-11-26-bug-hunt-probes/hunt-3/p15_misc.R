.libPaths(c("/tmp/zutable-hunt/lib", .libPaths()))
library(zutable)
set.seed(11); fails <- 0
chk <- function(label, a, b) { if (!identical(a, b)) { fails <<- fails + 1; cat("FAIL", label, "\n"); if (fails < 12) { print(head(a, 20)); print(head(b, 20)) } } }
T <- function(e) tryCatch(e, error = function(e) paste("ERR", class(e)[1], conditionMessage(e)))
if (requireNamespace("stringi", quietly = TRUE)) {
  pool <- c(NA, "", "a", "A", "b", "B", "é", "e", "f", "Z", "z", "abcdefgh", "ABCDEFGH", "abcdefghi", "ß", "ss", "10", "9", "é", "é")
  for (n in c(0, 1, 16, 17, 500, 5000)) for (dec in c(FALSE, TRUE)) for (nl in list(TRUE, FALSE, NA)) {
    x <- sample(pool, n, TRUE)
    chk(paste("collate", n, dec, nl), T(key_order(x, decreasing = dec, na.last = nl, collate = TRUE)), stringi::stri_order(x, decreasing = dec, na_last = nl))
  }
  x <- sample(pool, 300, TRUE); y <- sample(1:3, 300, TRUE)
  chk("collate 2 col", key_order(y, x, collate = TRUE), order(y, stringi::stri_rank(x), method = "radix"))
} else cat("no stringi\n")
# fast path skips argument checks?
print(T(key_order(1:3, collate = "junk"))); print(T(key_order(c("a", "b"), collate = "junk"))); print(T(key_order(1:3, na.last = c(TRUE, FALSE))))
# long vectors / zero-length / odd
print(T(key_order(integer()))); print(T(key_rank(integer()))); print(T(key_sort(integer()))); print(T(grp(integer(), sort = TRUE)$n)); print(T(grp_join(integer(), integer()))); print(T(grp_match(1:3, integer()))); print(T(grp_join(1:3, integer(), type = "left")))
print(T(grp_join(1:2, 1:2, by = "a"))); print(T(grp_join(data.frame(a = 1:2, b = 3:4), data.frame(a = 2:1, b = 4:3)))); print(T(grp_join(data.frame(a = 1:2, b = 3:4), data.frame(z = 9, a = 2:1), by = "a")))
print(T(grp_join(list(a = 1:2), list(b = c(2, 1)), by = c(a = "b")))); print(T(grp_join(1:2, c("1", "2")))); print(T(grp_join(c(TRUE, FALSE, NA), c(1L, 0L, NA)))); print(T(grp_join(factor(c("1", "2")), 1:2)))
print(T(grp_match(as.Date(1:3), c(2, 3.0, 2.5)))); print(T(grp_match(c(1, 2^53, 2^53 + 2), c(2L, 1L)))); print(T(grp_match(2147483647, .Machine$integer.max))); print(T(grp_match(as.raw(1:3), 2:3))); print(T(grp_match(as.raw(1:3), as.raw(3))))
print(T(grp_match(c(0.1 + 0.2, 0.3), 0.3))); print(match(c(0.1 + 0.2, 0.3), 0.3)); print(T(grp_match(c(-0, 0, NaN, NA), c(0, NA, NaN)))); print(T(grp_match(-NA_real_, NA_real_))); print(T(grp_match(NA_real_ + 1, NA_real_)))
nan2 <- readBin(as.raw(c(1, 0, 0, 0, 0, 0, 0xf8, 0xff)), "double"); print(T(grp(c(NaN, nan2, -NaN, 0/0, NA, NA_real_ * 2))$id)); print(match(c(NaN, nan2, -NaN, 0/0, NA), c(NaN, NA)))
na2 <- readBin(as.raw(c(0xa2, 0x07, 0, 0, 1, 0, 0xf8, 0x7f)), "double"); print(is.na(na2)); print(is.nan(na2)); print(T(grp(c(NA, na2, NaN))$id)); print(T(grp_reduce(c(1, na2), c(1, 1), "sum", na.rm = FALSE))); print(T(grp_reduce(c(1, na2), c(1, 1), "max", na.rm = FALSE)))
# multiple = error message
print(T(grp_join(c(5, 1, 1), c(1, 1, 5), multiple = "error"))); print(T(grp_join(c(1/3, 1), c(1/3, 1/3), multiple = "error")))
# grp of a grp from one vector applied to another: reduce with order/starts consistent
g <- grp(c("b", "a", "b")); print(T(grp_reduce(1:4, g, "sum")))
# key_sort attributes, data frames
print(T(key_sort(data.frame(a = 2:1)))); print(T(key_sort(list(as.raw(2), as.raw(1), NULL)))); print(T(key_order(data.frame(a = c(2, 1, 2), b = c("x", "y", "a")), decreasing = c(FALSE, TRUE))))
print(T(key_rank(data.frame(a = c(2, 1, 2, NA), b = c("x", "y", "x", "x"))))); print(T(key_rank(c(2, 1, 2, NA), c("x", "y", "x", "x"), ties = "dense", na.last = "keep"))); print(T(key_rank(c(1, 1, NA, NA, NaN), ties = "dense"))); print(T(key_rank(c(1, 1, NA, NA, NaN), ties = "min", na.last = FALSE)))
print(rank(c(1, 1, NA, NA, NaN), ties.method = "min", na.last = FALSE))
cat("fails:", fails, "\n")
