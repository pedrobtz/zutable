source("pre.R")
R.version.string
y <- sort(c(3, NA, 1), na.last = TRUE, method = "radix"); .Internal(inspect(y)); print(sort(y)); print(order(y, na.last = NA))
yi <- sort(c(3L, NA, 1L), na.last = TRUE, method = "radix"); .Internal(inspect(yi)); print(sort(yi)); print(order(yi, na.last = NA))
w <- key_sort(c(3, NA, 1)); .Internal(inspect(w)); print(sort(w)); print(sort(c(3, NA, 1))); print(order(w, na.last = NA))
wi <- key_sort(c(3L, NA, 1L)); print(sort(wi)); print(order(wi, na.last = NA))
f <- key_sort(factor(c("b", NA, "a"))); print(sort(f)); print(sort(factor(c("b", NA, "a")))); print(order(f, na.last = NA)); print(order(factor(c("b",NA,"a")), na.last=NA))
d <- key_sort(as.Date(c("2020-01-02", NA, "2020-01-01"))); print(sort(d)); print(order(d, na.last = NA)); print(length(sort(d)))
# the documented example
s <- key_sort(c(3, 1, NA, 2)); print(sort(s)); print(median(s, na.rm = TRUE)); print(quantile(s, na.rm = TRUE)); print(sort(s, decreasing = TRUE))
sd <- key_sort(c(3, 1, NA, 2), decreasing = TRUE); print(sd); print(sort(sd, decreasing = TRUE)); print(rev(sort(c(3,1,NA,2))))
# via grp
g <- grp(c(3, 1, NA, 2, 1), sort = TRUE); k <- g$keys[[1]]; .Internal(inspect(k)); print(sort(k)); print(table(k)); print(summary(k)); print(unique(sort(k)))
# as a zutable column
x <- zutable(k = key_sort(c(3, 1, NA, 2))); print(sort(x$k)); print(x[order = k]$k)
