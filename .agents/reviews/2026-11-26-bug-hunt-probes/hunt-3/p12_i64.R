.libPaths(c("/tmp/zutable-hunt/lib", .libPaths()))
library(zutable)
set.seed(8); fails <- 0
chk <- function(label, a, b) { if (!identical(a, b)) { fails <<- fails + 1; cat("FAIL", label, "\n"); if (fails < 15) { print(head(a, 30)); print(head(b, 30)) } } }
i64 <- bit64::as.integer64
v <- c(i64("9223372036854775807"), i64("-9223372036854775807"), i64(0), bit64::NA_integer64_, i64(1), i64(-1), i64("4611686018427387904"), i64("9007199254740993"), i64("9007199254740992"), i64("-4611686018427387905"))
ord_true <- c(2, 10, 6, 3, 5, 9, 8, 7, 1)  # ascending order of v's non-NA indices
rk <- integer(10); rk[ord_true] <- 1:9; rk[4] <- NA
for (n in c(10, 100, 3000, 70000)) { idx <- if (n == 10) 1:10 else sample.int(10, n, TRUE); x <- v[idx]; r <- rk[idx]
  chk(paste("i64 grp", n), grp(x)$id, base::match(idx, unique(idx)))
  for (dec in c(FALSE, TRUE)) for (nl in list(TRUE, FALSE, NA)) {
    chk(paste("i64 order", n, dec, nl), key_order(x, decreasing = dec, na.last = nl), base::order(r, decreasing = dec, na.last = nl, method = "radix"))
    chk(paste("i64 sort", n, dec, nl), as.character(key_sort(x, decreasing = dec, na.last = nl)), as.character(x[base::order(r, decreasing = dec, na.last = nl, method = "radix")]))
  }
  for (tm in c("min", "first")) chk(paste("i64 rank", n, tm), key_rank(x, ties = tm, na.last = "keep"), as.integer(base::rank(r, ties.method = tm, na.last = "keep")))
  chk(paste("i64 match", n), grp_match(x, rev(v)), base::match(idx, 10:1))
  y <- seq_len(n) %% 3L
  chk(paste("i64 2col", n), key_order(y, x, decreasing = c(TRUE, FALSE)), base::order(y, r, decreasing = c(TRUE, FALSE), method = "radix"))
  gs <- grp(x, sort = TRUE); chk(paste("i64 grps", n), gs$id, { u <- sort(unique(r), na.last = TRUE); base::match(r, u) }); chk(paste("i64 grps cls", n), class(gs$keys[[1]]), "integer64")
  j <- grp_join(x, v[c(1, 1, 4, 8)]); e <- lapply(idx, function(i) which(c(1, 1, 4, 8) == i)); chk(paste("i64 join", n), j, list(x = rep(seq_along(e), lengths(e)), y = as.integer(unlist(e))))
  chk(paste("i64 first", n), as.character(grp_reduce(x, y, "first", na.rm = TRUE)), as.character(x[sapply(split(seq_len(n), base::match(y, unique(y))), function(ii) { w <- ii[!is.na(r[ii])]; if (length(w)) w[1] else NA })]))
  chk(paste("i64 nobs", n), as.vector(grp_reduce(x, y, "nobs")), as.integer(tapply(!is.na(r), base::match(y, unique(y)), sum)))
}
cat("fails:", fails, "\n")
