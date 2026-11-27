source("pre.R")
mk <- function() zutable(a = 1:3, b = c(1,2,3), s = c("a","b",NA))
for (exec in c("kernel", "reference")) { options(zutable.executor = exec); cat("== ", exec, "\n")
x <- mk(); y <- x; snap <- as.data.frame(x)
print(try_(x[, { a := 9L; b := r(stop("boom"), float64) }]))
chk("block all-or-nothing", identical(as.data.frame(x), snap) && identical(as.data.frame(y), snap))
print(try_(x[, { a := 9L; b := r(c(1,2), float64) }])); chk("unapplied2", identical(as.data.frame(x), snap))
print(try_(x[, { a := 9L; b := r(c("a","b","c"), float64) }])); chk("unapplied wrong r type", identical(as.data.frame(x), snap)); 
n <- as_zutable(data.frame(a = 1:3, b = c(1,2,3)), schema(a = int32, b = not_null(float64))); sn <- as.data.frame(n)
print(try_(n[, { a := 9L; b := b / (b - 2) * 0 + r(c(1,NA,3), float64) }])); chk("not_null late fail unapplied", identical(as.data.frame(n), sn))
print(try_(n[, { a := 9L; b := sum(b) }, by = a])); print(as.data.frame(n))
x <- mk(); for (i in 1:3) tryCatch(x[, { a := a + 1L; b := r(if (i == 2) stop("no") else b, float64) }], error = function(e) NULL)
print(x$a)
x <- mk(); snap <- as.data.frame(x)
print(try_({setTimeLimit(elapsed = 0.2, transient = TRUE); x[, { a := 9L; b := r({ Sys.sleep(2); b }, float64) }]})); setTimeLimit()
x <- mk()
# second case: column shared twice
x <- mk(); x2 <- zutable(a = x$a, a2 = x$a, l = list(1, 2, NULL), f = factor(c("u","v","u")), st = data.frame(p = 1:3, q = c("a","b","c")), d = as.Date("2020-01-01") + 0:2)
before <- as.data.frame(copy(x2)); xa <- x$a
x2[, a := a + 1L]; chk("a2 untouched", identical(x2$a2, 1:3) && identical(x$a, 1:3))
x2[a > 2L, f := "v"]; print(x2$f); chk("orig factor", identical(before$f, factor(c("u","v","u"))))
print(try_(x2[, f := "zzz"])); print(try_(x2$f <- "zzz")); print(try_(x2$f <- factor(c("u","v","u"), levels = c("v","u")))); print(x2$f)
print(try_(levels(x2$f) <- c("U","V"))); print(x2$f); print(schema(x2))
st <- x2$st; x2[a == 3L, st := st]; chk("struct self", identical(x2$st, st))
print(try_(x2$st$p[2] <- 99L)); print(x2$st); chk("before struct untouched", identical(before$st$p, 1:3))
print(try_(x2[2, "st"] <- data.frame(p = 5L, q = "z"))); print(x2$st)
print(try_(x2[2, "l"] <- list(NULL))); str(x2$l)
print(try_(x2$l[[1]] <- 1:5)); str(x2$l)
print(try_(x2[, d := d + 1L])); print(x2$d); 
print(try_(x2$d[1] <- as.Date("1999-01-01") + 0.5))
print(try_(x2$d <- as.POSIXct("2020-01-01", tz = "UTC")))
print(schema(x2))
# zero-row table
z <- mk()[0, ]; print(try_(z[, a := 1L])); print(try_(z$a <- 5L)); print(try_(z[, a := sum(a)])); print(dim(z)); print(try_(z[a > 0L, { a := max(a) }, by = s])); 
# where matches nothing
x <- mk(); y <- x; x[a > 100L, a := 0L]; chk("no rows", identical(x$a, 1:3))
# where NA
x <- zutable(a = c(1L, NA, 3L), b = c(1,2,3)); x[a > 1L, b := 0]; print(x$b)
# update after query chain
x <- mk(); q <- x[a > 1L]; q[, a := 0L]; chk("query result independent", identical(x$a, 1:3)); 
q2 <- x[]; q2[, a := 0L]; cat("x[] then := leaks to x? ", identical(x$a, rep(0L,3)), "\n")
x <- mk(); q3 <- x[, .(a, b)]; q3[, a := 0L]; chk("select indep", identical(x$a, 1:3))
x <- mk(); q4 <- as_zutable(x); q4[, a := 0L]; cat("as_zutable(x) is x (alias):", identical(x$a, rep(0L,3)), "\n")
x <- mk(); q5 <- x[1:3, ]; q5[, a := 0L]; chk("rows indep", identical(x$a, 1:3))
x <- mk(); x[, a := 5L][, b := 7]; chk("chain", identical(x$a, rep(5L,3)) && identical(x$b, rep(7,3)))
x <- mk(); x[a > 1L][, a := 0L]; chk("chain on query doesn't touch", identical(x$a, 1:3))
x <- mk(); df <- as.data.frame(x); df$a[1] <- 100L; chk("df write doesn't leak", identical(x$a, 1:3))
x <- mk(); h <- head(x, 3); h[, a := 0L]; chk("head indep", identical(x$a, 1:3))
x <- mk(); j <- conform(x, schema(x)); j[, a := 0L]; chk("conform indep", identical(x$a, 1:3))
}
