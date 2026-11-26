source("pre.R")
f <- zutable(a = 1:3, b = c(1,2,3)); g <- f; freeze(f)
is.na(f) <- 1
print(class(f)); print(f); print(class(g)); print(is_frozen(g))
