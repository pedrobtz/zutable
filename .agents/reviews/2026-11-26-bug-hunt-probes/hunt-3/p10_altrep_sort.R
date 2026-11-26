.libPaths(c("/tmp/zutable-hunt/lib", .libPaths()))
library(zutable)
x <- c(3, 1, NA, 2)
s <- key_sort(x)                       # na.last = TRUE, the default
print(s); print(sort(s)); print(sort(x[order(x)]))
cat("order(s, radix, na.last=NA):", order(s, method = "radix", na.last = NA), " plain:", order(c(1, 2, 3, NA), method = "radix", na.last = NA), "\n")
# base R's own radix-sorted, NA-last vector
b <- sort(x, na.last = TRUE, method = "radix"); .Internal(inspect(b)); print(sort(b))
b2 <- sort(c(3L, 1L, NA, 2L), na.last = TRUE); .Internal(inspect(b2)); print(sort(b2))
.Internal(inspect(s))
# integer, logical, factor, Date; decreasing; na.last = FALSE
print(sort(key_sort(c(3L, 1L, NA, 2L))))
print(sort(key_sort(c(TRUE, NA, FALSE))))
print(sort(key_sort(factor(c("b", NA, "a")))))
print(sort(key_sort(as.Date(c(3, NA, 1)))))
print(sort(key_sort(c(3, 1, NA, 2), decreasing = TRUE), decreasing = TRUE))
print(sort(key_sort(c(3, 1, NA, 2), na.last = FALSE)))
print(sort(key_sort(c(3, 1, NaN, 2))))
print(median(key_sort(c(3, 1, NA, 2)), na.rm = TRUE)); print(quantile(key_sort(c(3, 1, NA, 2, 7)), 0.5, na.rm = TRUE))
print(sort(grp(c(3, 1, NA, 2), sort = TRUE)$keys[[1]]))
# via the bracket? order result column
