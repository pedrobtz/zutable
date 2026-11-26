.libPaths(c("/tmp/zutable-hunt/lib", .libPaths()))
library(zutable)
set.seed(7)
fails <- 0
plain <- function(s) { y <- s[seq_along(s)]; y <- c(y[0], y); attributes(y) <- attributes(s); y }  # materialised copy, no mark
ops <- list(
  sort = function(v) sort(v), sort_d = function(v) sort(v, decreasing = TRUE), sort_nl = function(v) sort(v, na.last = TRUE), sort_nf = function(v) sort(v, na.last = FALSE),
  sort_dnl = function(v) sort(v, decreasing = TRUE, na.last = TRUE), sort_dnf = function(v) sort(v, decreasing = TRUE, na.last = FALSE), sort_radix = function(v) sort(v, method = "radix", na.last = FALSE),
  sort_quick = function(v) tryCatch(sort(v, method = "quick"), error = function(e) "err"), sortint = function(v) sort.int(unclass(v), index.return = TRUE),
  order = function(v) order(v), order_d = function(v) order(v, decreasing = TRUE, na.last = FALSE), order_r = function(v) order(v, method = "radix", na.last = NA),
  unsorted = function(v) is.unsorted(v), unsorted_narm = function(v) is.unsorted(v, na.rm = TRUE), unsorted_strict = function(v) is.unsorted(v, strictly = TRUE), unsorted_strict_narm = function(v) is.unsorted(v, na.rm = TRUE, strictly = TRUE),
  unsorted_rev = function(v) is.unsorted(rev(v)), anyNA = function(v) anyNA(v), isna = function(v) which(is.na(v)), unique = function(v) unique(v), rank = function(v) rank(v), range = function(v) range(v), range_narm = function(v) range(v, na.rm = TRUE),
  min = function(v) suppressWarnings(min(v, na.rm = TRUE)), max = function(v) suppressWarnings(max(v)), whichmin = function(v) which.min(v), whichmax = function(v) which.max(v), sum = function(v) if (is.numeric(unclass(v)) || is.logical(v)) sum(unclass(v), na.rm = TRUE) else 0,
  match = function(v) match(v[length(v)], v), dup = function(v) duplicated(v), rev = function(v) rev(v), sub = function(v) v[-1], head = function(v) head(v, 3), tab = function(v) table(v, useNA = "always"),
  fi = function(v) if (is.numeric(unclass(v)) && !anyNA(v) && !is.unsorted(v)) findInterval(1, unclass(v)) else 0, median = function(v) if (is.numeric(unclass(v))) median(unclass(v), na.rm = TRUE) else 0, quant = function(v) if (is.double(unclass(v)) && !inherits(v, "Date")) quantile(v, .3, na.rm = TRUE, names = FALSE) else 0,
  cummax = function(v) if (is.numeric(unclass(v))) cummax(unclass(v)) else 0, diff = function(v) if (is.numeric(unclass(v))) diff(unclass(v)) else 0, ser = function(v) unserialize(serialize(v, NULL)), sersort = function(v) sort(unserialize(serialize(v, NULL)), na.last = FALSE),
  mod = function(v) { if (length(v) > 1) v[1] <- v[length(v)]; list(v, is.unsorted(v), anyNA(v), sort(v, na.last = TRUE)) },
  modna = function(v) { if (length(v) > 1) v[2] <- NA; list(v, anyNA(v), is.unsorted(v), sort(v, na.last = TRUE), sort(v)) },
  copymod = function(v) { w <- v; if (length(w)) w[length(w)] <- w[1]; list(v, w, is.unsorted(w), sort(w, decreasing = TRUE, na.last = TRUE)) },
  setlen = function(v) { length(v) <- length(v) + 1L; list(v, anyNA(v), sort(v, na.last = FALSE)) },
  cc = function(v) { w <- c(v, v); list(w, is.unsorted(w), anyNA(w)) }, asint = function(v) { w <- as.integer(unclass(v)); list(w, is.unsorted(w)) }, neg = function(v) if (is.numeric(unclass(v))) { w <- -unclass(v); list(w, is.unsorted(w), sort(w, na.last = TRUE)) } else 0
)
gens <- list(function(n) sample(c(NA, 1:5), n, TRUE), function(n) sample(c(NA, NaN, -0, 0, 1.5, Inf), n, TRUE), function(n) sample(c(TRUE, FALSE, NA), n, TRUE), function(n) sample(1:3, n, TRUE), function(n) rnorm(n),
  function(n) factor(sample(c("a", "b", NA), n, TRUE), levels = c("b", "a")), function(n) structure(sample(c(NA, 1:4), n, TRUE), class = "Date"), function(n) structure(sample(c(NA, 1, 2.5), n, TRUE), class = c("POSIXct", "POSIXt")), function(n) sample(c("b", "a", NA, "é"), n, TRUE))
for (gi in seq_along(gens)) for (n in c(0, 1, 2, 7, 300)) for (dec in c(FALSE, TRUE)) for (nl in list(TRUE, FALSE, NA)) {
  x <- gens[[gi]](n)
  for (on in names(ops)) {
    s <- key_sort(x, decreasing = dec, na.last = nl); p <- plain(s)
    a <- tryCatch(ops[[on]](s), error = function(e) paste("error", conditionMessage(e))); b <- tryCatch(ops[[on]](p), error = function(e) paste("error", conditionMessage(e)))
    if (!identical(a, b)) { fails <- fails + 1; cat("FAIL", on, "gen", gi, "n", n, "dec", dec, "nl", nl, "\n") }
  }
}
cat("fails:", fails, "\n")
