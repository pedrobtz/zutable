source("pre.R")
vals <- list(dbl = c(3, 1, NA, 2, 1, NaN, -0, 0, Inf, -Inf), int = c(3L, 1L, NA, 2L, 1L), lgl = c(TRUE, NA, FALSE, TRUE), chr = c("b", "a", NA, "B", "é", "", "ab"), fac = factor(c("z", "a", NA, "z"), levels = c("z", "a")), date = as.Date("2020-01-01") + c(3, 1, NA, 2), posix = as.POSIXct("2020-01-01", tz = "UTC") + c(3, 1, NA, 2), named = c(b = 2, a = 1, c = NA), empty = double(), one = 5, ints = sample(c(1:50, NA), 300, TRUE))
plain <- function(v) { attributes(v) <- attributes(v)[intersect(names(attributes(v)), c("names", "class", "levels", "tzone"))]; v }
fns <- list(
  sort = function(v) sort(v), sortd = function(v) sort(v, decreasing = TRUE), sortna = function(v) sort(v, na.last = TRUE), sortnaf = function(v) sort(v, na.last = FALSE, decreasing = TRUE),
  order = function(v) order(v), orderd = function(v) order(v, decreasing = TRUE, na.last = FALSE), unsorted = function(v) is.unsorted(v), unsortedna = function(v) is.unsorted(v, na.rm = TRUE), unsorteds = function(v) is.unsorted(v, strictly = TRUE),
  anyNA = function(v) anyNA(v), rev = function(v) rev(v), unique = function(v) unique(v), range = function(v) if (is.factor(v) || !length(v)) NULL else range(v, na.rm = TRUE), mx = function(v) which.max(v), mn = function(v) which.min(v),
  match = function(v) match(v, rev(v)), dup = function(v) duplicated(v), sum = function(v) if (is.numeric(v)) sum(v, na.rm = TRUE), isna = function(v) is.na(v), rank = function(v) rank(v, ties.method = "min"),
  head = function(v) head(v, 2), neg = function(v) if (is.numeric(v) && !inherits(v, c("Date","POSIXct"))) sort(-v), mod1 = function(v) { if (length(v) > 1) v[1] <- v[length(v)]; list(v, is.unsorted(v), sort(v), anyNA(v), order(v)) }, mod2 = function(v) { if (length(v)) v[length(v)] <- NA; list(v, anyNA(v), sort(v, na.last = TRUE), is.unsorted(v)) },
  mod3 = function(v) { if (length(v) > 2) v[2:3] <- v[3:2]; list(v, is.unsorted(v), sort(v, na.last = TRUE)) }, sub = function(v) { w <- v[seq_along(v) %% 2 == 1]; list(w, is.unsorted(w), sort(w)) }, cc = function(v) { w <- c(v, v); list(is.unsorted(w), sort(w), anyNA(w)) },
  ser = function(v) unserialize(serialize(v, NULL)), dput = function(v) capture.output(dput(v)), ident = function(v) identical(v, plain(v))
)
bad <- 0
for (vn in names(vals)) for (dec in c(FALSE, TRUE)) for (nl in list(TRUE, FALSE, NA)) {
  v <- vals[[vn]]
  s <- tryCatch(key_sort(v, decreasing = dec, na.last = nl), error = function(e) { cat("ERR key_sort", vn, conditionMessage(e), "\n"); NULL }); if (is.null(s)) next
  o <- key_order(v, decreasing = dec, na.last = nl)
  # oracle
  vv <- if (is.character(v)) v else v
  oo <- if (is.character(v)) order(v, decreasing = dec, na.last = nl, method = "radix") else order(v, decreasing = dec, na.last = nl, method = "radix")
  if (!identical(o, oo)) {
    # NaN/NA tie rule differs: compare values instead
    if (!identical(plain(v[o]), plain(v[oo])) && !(is.double(v) && identical(is.na(v[o]), is.na(v[oo])) && isTRUE(all.equal(v[o][!is.na(v[o])], v[oo][!is.na(v[oo])])))) { bad <- bad + 1; cat("ORDER DIFF", vn, dec, format(nl), "\n"); print(o); print(oo) }
  }
  p <- v[o]
  for (fn in names(fns)) {
    a <- tryCatch(fns[[fn]](s), error = function(e) paste("ERR", conditionMessage(e))); b <- tryCatch(fns[[fn]](p), error = function(e) paste("ERR", conditionMessage(e)))
    if (!identical(a, b)) { bad <- bad + 1; cat("MARK DIFF", vn, "dec", dec, "na.last", format(nl), fn, "\n"); print(a); print(b) }
  }
}
cat("bad:", bad, "\n")
cat("--- key_rank vs rank\n")
for (vn in names(vals)) { v <- vals[[vn]]; if (is.factor(v)) next
  for (nl in list(TRUE, FALSE, "keep", NA)) for (ti in c("min", "first")) {
    a <- tryCatch(key_rank(v, ties = ti, na.last = nl), error = function(e) paste("ERR", conditionMessage(e)))
    vv <- v; if (is.double(vv)) vv[is.nan(vv)] <- NA
    b <- tryCatch(rank(vv, ties.method = ti, na.last = nl), error = function(e) paste("ERR", conditionMessage(e))); names(b) <- NULL
    if (is.character(v)) b <- tryCatch({ r <- rank(xtfrm(factor(v, levels = sort(unique(v), method = "radix"))), ties.method = ti, na.last = nl); r }, error = function(e) "ERR")
    if (!isTRUE(all.equal(as.integer(a), as.integer(b)))) { cat("RANK DIFF", vn, format(nl), ti, "\n"); print(a); print(b) } } }
cat("--- argument matrix\n")
x <- c(3, 1, NA, 2)
for (a in list(list(decreasing = NA), list(decreasing = c(TRUE, FALSE)), list(decreasing = "yes"), list(decreasing = 1), list(na.last = "keep"), list(na.last = c(TRUE, FALSE)), list(na.last = 1), list(collate = "x"), list(collate = NA), list(collate = TRUE))) { cat(deparse(a), ": "); print(try_(do.call(key_order, c(list(x), a)))); cat("   sort: "); print(try_(do.call(key_sort, c(list(x), a)))) ; cat("   rank: "); print(try_(do.call(key_rank, c(list(x), a))))}
print(try_(key_order())); print(try_(key_order(NULL))); print(try_(key_order(list()))); print(try_(key_order(1:3, 1:2))); print(try_(key_order(data.frame(a = c(2, 1), b = c("x", "y"))))); print(try_(key_order(list(c(2, 1), c("x", "y"))))); print(try_(key_order(1i))); print(try_(key_order(list(as.raw(2), as.raw(1), NULL)))); print(try_(key_sort(list(as.raw(2), as.raw(1), NULL)))); print(try_(key_order(matrix(4:1, 2)))); print(try_(key_sort(matrix(4:1, 2)))); print(try_(key_sort(data.frame(a = 2:1)))); print(try_(key_rank(x, ties = "average"))); print(try_(key_rank(x, ties = c("dense", "min")))); print(try_(key_rank(x, ties = NULL)))
print(try_(key_order(c("b", "a"), c(2, 1), decreasing = c(TRUE, FALSE)))); print(try_(key_order(zuint::int64(c("9007199254740993", "9007199254740992", NA, "-1"))))); print(try_(key_sort(zuint::int64(c("9007199254740993", "9007199254740992", NA, "-1")))))
l1 <- "\xe9"; Encoding(l1) <- "latin1"; print(key_order(c("z", l1, "é", "e"))); print(order(enc2utf8(c("z", l1, "é", "e")), method = "radix")); print(try_(key_order(c("b", "A", "a"), collate = TRUE)))
