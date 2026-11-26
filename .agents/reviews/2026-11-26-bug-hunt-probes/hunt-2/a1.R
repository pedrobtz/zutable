source("pre.R")
meta <- function(x) .Call(zutable:::zt_sorted_meta, x)
plain <- function(x) { a <- attributes(x); y <- unserialize(serialize(x, NULL)); y <- y[seq_along(y)]; attributes(y) <- a; y }  # materialise
reads <- list(
  unsorted = function(v) is.unsorted(v), unsorted_rm = function(v) is.unsorted(v, na.rm = TRUE), unsorted_strict = function(v) is.unsorted(v, strictly = TRUE),
  sort = function(v) sort(v), sortd = function(v) sort(v, decreasing = TRUE), sortna = function(v) sort(v, na.last = TRUE), sortnaf = function(v) sort(v, na.last = FALSE), sortdna = function(v) sort(v, decreasing = TRUE, na.last = TRUE), sortdnaf = function(v) sort(v, decreasing = TRUE, na.last = FALSE),
  sortint = function(v) sort.int(v, method = "radix"), order = function(v) order(v), orderd = function(v) order(v, decreasing = TRUE), ordernaf = function(v) order(v, na.last = FALSE), ordernaNA = function(v) order(v, na.last = NA),
  anyNA = function(v) anyNA(v), min = function(v) min(v), max = function(v) max(v), minrm = function(v) min(v, na.rm = TRUE), maxrm = function(v) max(v, na.rm = TRUE), range = function(v) range(v), rangerm = function(v) range(v, na.rm = TRUE),
  unique = function(v) unique(v), rev = function(v) rev(v), match = function(v) match(c(v[1], 2, NA, 7), v), fi = function(v) tryCatch(findInterval(c(0, 2, 2.5, 10), v), error = function(e) "err"), inn = function(v) c(2, NA, 99) %in% v,
  sum = function(v) sum(v), mean = function(v) mean(v), which = function(v) which(v > 1), dup = function(v) duplicated(v), tab = function(v) table(v, useNA = "always"), isna = function(v) is.na(v), whichmin = function(v) which.min(v), whichmax = function(v) which.max(v),
  rank = function(v) rank(v), cummax = function(v) tryCatch(cummax(v), error = function(e) "err"), diff = function(v) tryCatch(diff(v), error=function(e) "err"), median = function(v) tryCatch(median(v, na.rm = TRUE), error = function(e) "err"), quant = function(v) tryCatch(quantile(v, na.rm = TRUE, type = 1), error = function(e) "err"),
  as.char = function(v) as.character(v), fct = function(v) factor(v), head = function(v) head(v, 2), sub = function(v) v[c(3, 1)], subneg = function(v) v[-1], xtfrm = function(v) xtfrm(v), sortlist = function(v) sort(c(v, v)), seqa = function(v) v + 0L, rle = function(v) unclass(rle(as.vector(v)))
)
cmp <- function(label, w) {
  p <- plain(w)
  if (!is.null(meta(p))) cat("   (plain still altrep!)\n")
  for (nm in names(reads)) {
    a <- tryCatch(reads[[nm]](w), error = function(e) paste("E", conditionMessage(e))); b <- tryCatch(reads[[nm]](p), error = function(e) paste("E", conditionMessage(e)))
    if (!identical(a, b)) { cat("DIFF", label, nm, "\n  wrapped:", deparse(a)[1], "\n  plain:  ", deparse(b)[1], "\n") }
  }
}
inputs <- list(int = c(3L, 1L, NA, 2L, 2L), intnona = c(3L,1L,2L), dbl = c(3, NaN, 1, NA, -Inf, Inf, 0, -0, 2), dblnona = c(2.5, 1, 3), lgl = c(TRUE, NA, FALSE, TRUE), fct = factor(c("b","a",NA,"c")), date = as.Date("2020-01-01") + c(3, NA, 1), posix = as.POSIXct("2020-01-01", tz = "UTC") + c(3, NA, 1), chr = c("b", NA, "a", "B", "é"),
  empty = integer(), one = 1L, onena = NA_integer_, allna = c(NA_real_, NA), nan = c(NaN, NA, 1, NaN), neg0 = c(0, -0, 0, -0))
for (nm in names(inputs)) for (dec in c(FALSE, TRUE)) for (nl in list(TRUE, FALSE, NA)) {
  w <- tryCatch(key_sort(inputs[[nm]], decreasing = dec, na.last = nl), error = function(e) { cat("ERR key_sort", nm, conditionMessage(e), "\n"); NULL })
  if (is.null(w)) next
  lab <- sprintf("%s dec=%s na.last=%s meta=%s", nm, dec, nl, paste(meta(w), collapse = ","))
  # vs base sort
  b <- sort(inputs[[nm]], decreasing = dec, na.last = nl, method = "radix")
  if (!identical(plain(w), b) && !is.character(inputs[[nm]])) { cat("SORTDIFF", lab, "\n"); print(plain(w)); print(b) }
  cmp(lab, w)
}
