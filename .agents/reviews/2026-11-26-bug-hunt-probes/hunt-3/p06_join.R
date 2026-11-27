.libPaths(c("/tmp/zutable-hunt/lib", .libPaths()))
library(zutable)
set.seed(4)
fails <- 0
chk <- function(label, a, b) { if (!identical(a, b)) { fails <<- fails + 1; cat("FAIL", label, "\n"); if (fails < 12) { str(a); str(b) } } }
pool <- c(NA, "", "a", "abcdefgh", "abcdefghi", "é")
gens <- list(
  int = function(n) sample(c(NA, -2:2, .Machine$integer.max), n, TRUE),
  lgl = function(n) sample(c(NA, TRUE, FALSE), n, TRUE),
  dbl = function(n) sample(c(NA, NaN, -0, 0, Inf, 1, 2, 0.5, 2147483647), n, TRUE),
  chr = function(n) sample(pool, n, TRUE),
  fct = function(n) factor(sample(c("a", "é", "", NA, "q"), n, TRUE), levels = sample(c("q", "unused", "a", "é", ""))),
  date_i = function(n) structure(sample(c(NA, 0:2), n, TRUE), class = "Date"),
  date_d = function(n) structure(sample(c(NA, 0, 1, 2, 0.5), n, TRUE), class = "Date")
)
compat <- list(int = c("int", "lgl", "dbl", "date_i", "date_d"), lgl = c("int", "lgl", "dbl"), dbl = c("int", "lgl", "dbl", "date_d"), chr = c("chr", "fct"), fct = c("chr", "fct"), date_i = c("date_i", "date_d", "int"), date_d = c("date_i", "date_d", "dbl"))
ks <- function(v) { if (is.factor(v)) v <- as.character(v); if (is.character(v)) return(ifelse(is.na(v), "<NA>", paste0("s", enc2utf8(v)))); v <- as.double(unclass(v)); ifelse(is.na(v) & !is.nan(v), "NA", ifelse(is.nan(v), "NaN", ifelse(v == 0, "0", sprintf("%a", v)))) }
for (it in 1:1500) {
  nx <- sample(c(0, 1, 2, 5, 30, 300), 1); ny <- sample(c(0, 1, 2, 5, 30, 300), 1); k <- sample(1:3, 1)
  tx <- sample(names(gens), k, TRUE); ty <- vapply(tx, function(t) sample(compat[[t]], 1), "")
  xc <- lapply(tx, function(t) gens[[t]](nx)); yc <- lapply(ty, function(t) gens[[t]](ny))
  kx <- do.call(paste, c(lapply(xc, ks), sep = "\r")); ky <- do.call(paste, c(lapply(yc, ks), sep = "\r"))
  if (nx == 0) kx <- character(); if (ny == 0) ky <- character()
  m <- lapply(kx, function(s) which(ky == s))
  lab <- paste(it, paste(tx, collapse = "/"), paste(ty, collapse = "/"), nx, ny)
  X <- if (k == 1) xc[[1]] else xc; Y <- if (k == 1) yc[[1]] else yc
  for (type in c("inner", "left")) for (mult in c("all", "first", "last")) {
    mm <- switch(mult, all = m, first = lapply(m, head, 1), last = lapply(m, tail, 1))
    if (type == "left") mm <- lapply(mm, function(e) if (length(e)) e else NA_integer_)
    exp <- list(x = rep(seq_along(mm), lengths(mm)), y = as.integer(unlist(mm)))
    r <- tryCatch(grp_join(X, Y, type = type, multiple = mult), error = function(e) conditionMessage(e))
    chk(paste("join", type, mult, lab), r, exp)
  }
  has <- lengths(m) > 0
  chk(paste("semi", lab), tryCatch(grp_join(X, Y, type = "semi"), error = function(e) conditionMessage(e)), list(x = which(has)))
  chk(paste("anti", lab), tryCatch(grp_join(X, Y, type = "anti"), error = function(e) conditionMessage(e)), list(x = which(!has)))
  chk(paste("match", lab), tryCatch(grp_match(X, Y), error = function(e) conditionMessage(e)), match(kx, ky))
  r <- tryCatch(grp_join(X, Y, multiple = "error"), error = function(e) class(e)[1])
  if (any(lengths(m) > 1)) chk(paste("err", lab), r, "zutable_multiple_error") else chk(paste("noerr", lab), r, list(x = which(has), y = as.integer(unlist(m))))
}
cat("fails:", fails, "\n")
