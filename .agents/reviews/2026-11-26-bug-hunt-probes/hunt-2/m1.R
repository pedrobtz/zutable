source("pre.R")
meta <- function(x) paste(.Call(zutable:::zt_sorted_meta, x), collapse = ",")
# grp keys
v <- c(3L, 1L, NA, 2L, 1L); g <- grp(v, sort = TRUE); k <- g$keys[[1]]; snap <- k[seq_along(k)]
k[1] <- 99L; chk("g$keys intact after write to k", identical(g$keys[[1]][seq_along(snap)], snap) && meta(g$keys[[1]]) != "NA,0"); cat(meta(g$keys[[1]]), meta(k), "\n")
g$keys[[1]][2] <- 50L; cat("after write in g:", meta(g$keys[[1]]), is.unsorted(g$keys[[1]]), format(g$keys[[1]]), "\n")
g2 <- grp(v, sort = TRUE); g3 <- g2; g3$keys[[1]][1] <- 77L; chk("g2 intact", identical(g2$keys[[1]][1:3], snap[1:3])); cat(meta(g2$keys[[1]]), "\n")
gs <- unserialize(serialize(g2, NULL)); chk("grp roundtrip", identical(gs$keys[[1]][seq_along(snap)], snap) && meta(gs$keys[[1]]) == meta(g2$keys[[1]]))
# strings with encodings
l1 <- iconv("é", "UTF-8", "latin1"); b <- "\xff"; Encoding(b) <- "bytes"
s <- c("b", NA, l1, "é", "a", "")
w <- key_sort(s); print(w); print(Encoding(w)); print(meta(w)); print(anyNA(w)); print(identical(sort(unique(w[!is.na(w)]), method = "radix"), sort(unique(enc2utf8(s[!is.na(s)])), method = "radix")))
w2 <- w; w2[2] <- NA; print(anyNA(w2)); print(meta(w2)); print(meta(w)); print(w)
wn <- key_sort(c("b", "a")); cat("no-NA str meta", meta(wn), "\n"); wn[1] <- NA; cat("after NA write: anyNA", anyNA(wn), "is.na", is.na(wn), "meta", meta(wn), "\n")
wn <- key_sort(c("b", "a")); is.na(wn) <- 2; cat("is.na<-: anyNA", anyNA(wn), meta(wn), "\n")
wn <- key_sort(c("b", "a")); wn[[2]] <- NA_character_; cat("[[<-: anyNA", anyNA(wn), meta(wn), "\n")
wn <- key_sort(c("b", "a")); wn2 <- wn; substr(wn, 1, 1) <- "z"; cat("substr<-:", wn, "| copy", wn2, "\n")
wn <- key_sort(c("b", "a")); x <- zutable(s = wn); x[, s := NA]; cat("table col anyNA", anyNA(x$s), "orig", anyNA(wn), meta(wn), "\n")
wn <- key_sort(c("b", "a")); Encoding(wn) <- "latin1"; print(wn)
print(try_(key_sort(c("a", b))))
# metadata through lifecycle
sc <- schema(a = int32, b = not_null(float64)); 
x <- as_zutable(data.frame(a = 1:3, b = c(1,2,3)), sc); print(metadata(x))
m <- tryCatch({ s2 <- sc; s2$metadata <- c(k = "v"); as_zutable(data.frame(a = 1:3, b = c(1,2,3)), s2) }, error = function(e) { print(conditionMessage(e)); NULL })
if (!is.null(m)) { m0 <- metadata(m); sch0 <- schema(m)
  m[, a := 5L]; chk("meta after :=", identical(metadata(m), m0) && identical(schema(m), sch0)); m$a <- 1L; chk("meta after $<-", identical(metadata(m), m0)); m[2, "a"] <- 3L; chk("meta after [<-", identical(metadata(m), m0))
  chk("meta copy", identical(metadata(copy(m)), m0)); chk("meta rds", identical(metadata(unserialize(serialize(m, NULL))), m0)); freeze(m); chk("meta frozen", identical(metadata(m), m0) && identical(schema(m), sch0))
  cat("meta after query:", deparse(metadata(m[a > 0L])), deparse(metadata(m[1:2, ])), deparse(metadata(m[, .(a)])), "\n") }
