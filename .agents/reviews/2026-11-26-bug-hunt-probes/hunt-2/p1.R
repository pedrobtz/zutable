source("pre.R")
# 1 aliases and shared vectors
v <- c(1L,2L,3L); w <- c(1.5,2.5,3.5)
x <- zutable(a = v, b = w, c = c("x","y","z"))
df <- as.data.frame(x); y <- x; z <- copy(x); e <- new.env(); e$v <- x$a; l <- list(x$a)
snap <- as.data.frame(z)
x[, a := a + 10L]
chk("alias sees", identical(y$a, c(11L,12L,13L)))
chk("copy doesn't", identical(as.data.frame(z), snap))
chk("df doesn't", identical(df, snap)); chk("v", identical(v, 1:3)); chk("env", identical(e$v, 1:3)); chk("list", identical(l[[1]],1:3))
# where update
x[a > 11L, a := 0L]; chk("where", identical(y$a, c(11L,0L,0L)))
chk("z still", identical(z$a, 1:3))
# base routes copy-on-modify
x <- zutable(a = 1:3, b = c(1,2,3)); y <- x
x$a <- 7; chk("$<- alias unchanged", identical(y$a, 1:3) && identical(x$a, c(7L,7L,7L)))
x <- zutable(a = 1:3, b = c(1,2,3)); y <- x
x[["a"]] <- 7L; chk("[[<- alias", identical(y$a, 1:3))
x[2, "a"] <- 9L; chk("[<- alias", identical(y$a, 1:3) && identical(x$a, c(7L,9L,7L)))
x$a[3] <- 1L; chk("x$a[i]<-", identical(x$a, c(7L,9L,1L)))
# after $<- the x is a new list: := on x must not touch y
x[, a := 100L]; chk("after $<- then :=, y untouched", identical(y$a, 1:3)); print(y$a)
# the reverse: := on y after x was split
y[, a := -1L]; chk("x untouched", identical(x$a, rep(100L,3)))
# equivalent inputs
mk <- function() zutable(a = 1:3, b = c(1,2,3), s = c("a","b",NA))
r1 <- mk(); r1[, a := 5L]
r2 <- mk(); r2$a <- 5L
r3 <- mk(); r3[["a"]] <- 5L
r4 <- mk(); r4[, "a"] <- 5L
r5 <- mk(); r5["a"] <- 5L
r6 <- mk(); r6[1:3, "a"] <- 5L
r7 <- mk(); r7[[1]] <- 5L
for (r in list(r2,r3,r4,r5,r6,r7)) { chk("equiv data", identical(as.data.frame(r), as.data.frame(r1))); chk("equiv schema", identical(schema(r), schema(r1))) }
str(attributes(r1)[c("properties","frozen")]); str(attributes(r2)[c("properties","frozen")])
# attributes compare
print(names(attributes(r1))); print(names(attributes(r2)))
# x[] <- 
r8 <- mk(); print(try_(r8[] <- list(5L, 1, "q"))); print(as.data.frame(r8))
r9 <- mk(); print(try_(r9[] <- 5L)); 
# schema changing routes
r <- mk()
print(try_(names(r) <- c("x","y","z"))); print(try_(r$a <- NULL)); print(try_(r[["a"]] <- NULL)); print(try_(r$new <- 1))
print(try_(r$a <- c(1.5,2,3))); print(try_(r$a <- "a")); print(try_(r[4, "a"] <- 1L)); print(try_(r[0, "a"] <- 1L)); print(try_(r[-1, "a"] <- 1L)); print(r$a)
print(try_(r[NA, "a"] <- 1L)); print(try_(r[.Machine$integer.max + 1, "a"] <- 1L)); print(try_(r[Inf, "a"] <- 1L)); print(try_(r[1.9, "a"] <- 3L)); print(r$a)
print(try_(r[c(1,1), "a"] <- c(8L, 9L))); print(r$a)
print(try_(r[c(TRUE,NA,FALSE), "a"] <- 50L)); print(r$a)
print(try_(colnames(r) <- c("x","y","z"))); print(try_(dimnames(r) <- list(NULL, c("x","y","z"))))
print(try_(levels(r$a) <- "a")); print(try_(attr(r$a, "foo") <- "bar")); print(attributes(r$a)); print(schema(r))
print(try_(class(r$a) <- "Date")); print(class(r$a))
print(try_(dim(r$a) <- c(3,1)));  print(attributes(r$a))
print(try_(names(r$a) <- c("p","q","r")));  print(attributes(r$a))
print(try_(is.na(r$a) <- 2)); print(r$a)
print(try_(length(r) <- 2)); print(class(r))
print(try_(r <- within(r, a <- a + 1L))); print(class(r)); print(r$a)
print(try_(r2 <- transform(r, a = a * 2L, q = 1))); print(class(r2)); print(names(r2))
print(try_(r[["a"]][2] <- NA)); print(schema(r))
print(try_(r[[2, "a"]] <- 77L)); print(r$a)
print(try_(r[cbind(1,1)] <- 5L)); print(r$a)
print(try_(r[r$a > 5, ] <- list(1L, 2, "k"))); print(as.data.frame(r))
