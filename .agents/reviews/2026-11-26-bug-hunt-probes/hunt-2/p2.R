source("pre.R")
mk <- function() zutable(a = 1:3, b = c(1,2,3), s = c("a","b",NA))
r <- mk()
print(try_(r[["a"]][2] <- NA)); print(schema(r)); print(r$a)
print(try_(r[[2, "a"]] <- 77L)); print(r$a)
print(try_(r[cbind(1,1)] <- 5L)); print(r$a)
print(try_(r[r$a > 5, ] <- list(1L, 2, "k"))); print(as.data.frame(r))
# not_null
n <- as_zutable(data.frame(a = 1:3, b = c(1,2,3)), schema(a = not_null(int32), b = float64))
print(try_(n$a[2] <- NA)); print(try_(n[, a := NA])); print(try_(n[2, "a"] <- NA)); print(try_(n[b > 1, a := if_else(b > 2, NA, 1L)])); print(n$a)
# matrix-ish columns then queries
m <- mk(); a <- m$a; dim(a) <- c(3,1); m$a <- a
print(try_(print(m[a > 1L]))); print(try_(print(m[, .(s = sum(a)), by = a])))
print(try_(m[, a := a + 1L])); print(attributes(m$a))
nm <- mk(); a <- nm$a; names(a) <- c("p","q","r"); nm$a <- a
print(try_(print(nm[a > 1L]))); str(nm[a > 1L]$a); nm[, b := a * 2]; str(nm$b)
# freeze
f <- mk(); g <- f; h <- copy(f); freeze(f)
chk("alias frozen", is_frozen(g)); chk("copy not", !is_frozen(h))
for (ex in list(quote(f[, a := 1L]), quote(g[, a := 1L]), quote(f$a <- 1L), quote(g[["a"]] <- 1L), quote(f[1,"a"] <- 1L), quote(f$a[1] <- 9L), quote(f[] <- list(1L,1,"a")), quote(f[a > 1, {a := 1L; b := 2}]), quote(f[a > 100, a := 1L]), quote(f[[1,1]] <- 5L)))
  print(try_(eval(ex)))
chk("unchanged", identical(as.data.frame(f), as.data.frame(mk())))
chk("query result not frozen", !is_frozen(f[a > 0L]) && !is_frozen(f[1:2, ]) && !is_frozen(f[]) && !is_frozen(f[, .(a)]) && !is_frozen(head(f)) )
cat("as_zutable frozen:", is_frozen(as_zutable(f)), " conform:", is_frozen(conform(f, schema(f))), " copy:", is_frozen(copy(f)), " copy of copy alias\n")
k <- copy(f); k[, a := 9L]; chk("copy updates, f not", identical(f$a, 1:3) && identical(k$a, rep(9L,3)))
# other "copy" routes that keep attributes
for (ex in list(quote(rbind(f, f)), quote(f[order(f$a), ]), quote(subset(f, a > 1)), quote(unique(f)), quote(rev(f)), quote(f[c("a","b","s")]), quote(merge(f, f)), quote(cbind(f)), quote(within(f, a <- 1L)), quote(transform(f, a = 1L)), quote(na.omit(f)), quote(droplevels(f)), quote(stack), quote(lapply(list(f), identity)[[1]]), quote(unserialize(serialize(f, NULL))), quote(rapply(f, identity, how="replace")), quote(`attr<-`(f, "frozen", NULL)), quote(`row.names<-`(f, 3:1)), quote(`dimnames<-`(f, list(NULL, names(f)))), quote(modifyList(f, list(a = 4:6))), quote(replace(f, "a", list(4:6))), quote(`levels<-`(f, "a")), quote(`comment<-`(f, "hi")), quote(`oldClass<-`(f, c("zutable","data.frame"))), quote(structure(f, frozen = NULL)), quote(head(f, 2)), quote(tail(f, 2)), quote(f[-1, ]), quote(t(f)), quote(f[TRUE, ]))) {
  o <- tryCatch(eval(ex), error = function(e) e)
  cat(deparse(ex), "->", if (inherits(o, "error")) paste("ERR", class(o)[1]) else paste(class(o)[1], "frozen:", isTRUE(attr(o, "frozen"))), "\n")
}
chk("f still frozen & same", is_frozen(f) && identical(as.data.frame(f), as.data.frame(mk())))
m2 <- modifyList(f, list(a = 4:6)); print(class(m2)); print(m2$a); print(f$a)
rp <- replace(f, "a", list(4:6)); print(class(rp));
# serialize
tf <- tempfile(); saveRDS(f, tf); f2 <- readRDS(tf); chk("rds frozen", is_frozen(f2)); print(try_(f2[, a := 1L]))
u <- mk(); u[, a := 5L]; saveRDS(u, tf); u2 <- readRDS(tf); u2[, a := 6L]; chk("rds independent", identical(u$a, rep(5L,3)) && identical(u2$a, rep(6L,3)) && identical(schema(u), schema(u2)))
# fork
if (.Platform$OS.type == "unix") {
  p <- mk(); q <- p
  res <- parallel::mclapply(1:2, function(i) { p[, a := a * 100L]; p$a }, mc.cores = 2)
  print(res); chk("parent untouched", identical(p$a, 1:3) && identical(q$a, 1:3))
}
# containers
L <- list(mk(), mk()); for (t in L) t[, a := 0L]; chk("list of tables updated via loop var", identical(L[[1]]$a, rep(0L,3)))
L2 <- lapply(L, function(t) t[, a := 1L]); chk("lapply updates originals", identical(L[[1]]$a, rep(1L,3)))
L[[1]][, a := 2L]; chk("L[[1]][...]", identical(L[[1]]$a, rep(2L,3)))
e <- new.env(); e$t <- mk(); local(t[, a := 3L], e); chk("env", identical(e$t$a, rep(3L,3)))
setClass("H", representation(t = "ANY")); s4 <- new("H", t = mk()); s4@t[, a := 4L]; chk("S4 slot", identical(s4@t$a, rep(4L,3)))
R5 <- setRefClass("R5", fields = list(t = "ANY"), methods = list(up = function() { t[, a := 5L]; invisible(NULL) })); o <- R5$new(t = mk()); o$up(); chk("R5", identical(o$t$a, rep(5L,3)))
cl <- (function() { t <- mk(); list(up = function() t[, a := 6L], get = function() t) })(); cl$up(); chk("closure", identical(cl$get()$a, rep(6L,3)))
# errors mid block
x <- mk(); y <- x; snap <- as.data.frame(x)
print(try_(x[, { a := 9L; b := r(function(b) stop("boom"), b) }]))
chk("block all-or-nothing", identical(as.data.frame(x), snap) && identical(as.data.frame(y), snap))
print(try_(x[, { a := 9L; b := c(1,2) }])); chk("unapplied2", identical(as.data.frame(x), snap))
print(try_(x[, { a := 9L; s := 1 }])); chk("unapplied3", identical(as.data.frame(x), snap))
x[, a := 2L]; chk("works after errors; alias", identical(y$a, rep(2L,3)))
# loop with error inside
x <- mk(); for (i in 1:3) tryCatch(x[, { a := a + 1L; b := if (i == 2) r(function(b) stop("no"), b) else b }], error = function(e) NULL)
print(x$a)
# time limit interrupt
x <- mk(); snap <- as.data.frame(x)
print(try_({setTimeLimit(elapsed = 0.2, transient = TRUE); x[, { a := 9L; b := r(function(b) { Sys.sleep(2); b }, b) }]})); setTimeLimit()
chk("after timeout untouched", identical(as.data.frame(x), snap)); x[, a := 1L]; chk("update after timeout", identical(x$a, rep(1L, 3)))
