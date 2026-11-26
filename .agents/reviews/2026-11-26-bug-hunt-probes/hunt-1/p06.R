source("pre.R")
cat("--- update / replace routes\n")
mk <- function() zutable(id = 1:4, f = c(1.5, 2, NA, 4), s = c("a","b","c",NA), e = factor(c("x","y","x",NA)), d = as.Date("2020-01-01") + 0:3, t = as.POSIXct("2020-01-01", tz = "UTC") + 0:3, b = c(TRUE, FALSE, NA, TRUE))
x <- mk()
vals <- list(int = 7L, dbl = 7, dblfrac = 7.5, big = 2^31, chr = "x", chr_z = "zzz", lgl = TRUE, na = NA, nan = NaN, date = as.Date("2021-05-05"), datechr = "2021-05-05", posix = as.POSIXct("2021-05-05 01:02:03", tz = "UTC"), posix_paris = as.POSIXct("2021-05-05 01:02:03", tz = "Europe/Paris"), posix_notz = as.POSIXct("2021-05-05 01:02:03"), tschr = "2021-05-05 01:02:03", fac = factor("x"), fac2 = factor("x", levels = c("x","y")), null = NULL, len2 = 1:2, len0 = integer(), list = list(1))
res <- matrix("", length(vals), 7 * 3, dimnames = list(names(vals), as.vector(outer(c(":=", "$<-", "[<-"), names(x), paste))))
get <- function(r, col) if (is.character(r)) r else paste(format(as.data.frame(r)[[col]][2]), typeof(r[[col]]))
for (vn in names(vals)) for (col in names(x)) {
  v <- vals[[vn]]
  a <- tryCatch({ y <- mk(); eval(bquote(y[id == 2L, .(as.name(col)) := v])); y }, error = function(e) "E")
  b <- tryCatch({ y <- mk(); y[[col]][2] <- v; y }, error = function(e) "E")
  c_ <- tryCatch({ y <- mk(); y[2, col] <- v; y }, error = function(e) "E")
  res[vn, paste(":=", col)] <- get(a, col); res[vn, paste("$<-", col)] <- get(b, col); res[vn, paste("[<-", col)] <- get(c_, col)
}
for (col in names(x)) { cat("\ncolumn", col, "\n"); print(noquote(res[, paste(c(":=", "$<-", "[<-"), col)])) }
