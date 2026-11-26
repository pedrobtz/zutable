source("pre.R")
x <- zutable(a = 1:2)
cat("# 1 top-level update: (nothing expected)\n")
x[, a := 5L]
cat("# 2 then x: (table expected)\n")
x
cat("# 3 assign result then autoprint x: (table expected)\n")
y <- x[, a := 6L]
x
cat("# 4 update in for loop then x\n")
for (i in 1) x[, a := 7L]
x
cat("# 5 update in function (invisible) then print(x)\n")
f <- function(t) { t[, a := 8L]; invisible(NULL) }
f(x)
print(x)
cat("# 6 update then equal-valued other table\n")
z <- zutable(a = c(9L, 9L))
invisible(x[, a := 9L])
z
cat("# 7 update that errors after a prior armed flag\n")
invisible(x[, a := 1L])
try(x[, a := "q"], silent = TRUE)
x
cat("# 8 update inside tryCatch then x\n")
tryCatch(x[, a := 2L], error = identity)
cat("# 8b now x\n")
x
cat("# 9 suppressWarnings(update) ; x\n")
suppressWarnings(x[, a := 3L])
cat("# 9b\n")
x
cat("# 10 (x[, a := 4L]) parenthesised: data.table prints\n")
(x[, a := 4L])
cat("# 11 print(x[, a := 4L])\n")
print(x[, a := 4L])
cat("# 12 update; then print(x, n = 1)\n")
invisible(x[, a := 4L])
print(x, n = 1)
cat("# 13 update in if\n")
if (TRUE) x[, a := 4L]
x
cat("# 14 freeze after update\n")
invisible(x[, a := 4L]); freeze(x)
x
cat("# 15 $<- after update\n")
w <- zutable(a = 1:2); invisible(w[, a := 4L]); w$a <- 1L
w
cat("# 16 update then query result equal to x\n")
w <- zutable(a = 1:2); for (i in 1) w[, a := 4L]
copy(w)
cat("# 17 update then lapply print\n")
w <- zutable(a = 1:2); for (i in 1) w[, a := 4L]
invisible(lapply(list(w), print))
cat("# 18 update then format/toString/capture.output(print)\n")
for (i in 1) w[, a := 4L]
length(capture.output(print(w)))
cat("# 19 knitr-like: withVisible + print\n")
for (i in 1) w[, a := 4L]
r <- withVisible(w); if (r$visible) print(r$value)
cat("# 20 sink\n")
