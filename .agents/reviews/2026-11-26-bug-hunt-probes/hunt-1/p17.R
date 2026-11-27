source("pre.R")
cat("--- grp_reduce vs tapply\n")
set.seed(2); n <- 200; k <- sample(c("a", "b", "c", NA), n, TRUE); kk <- ifelse(is.na(k), "<NA>", k)
cols <- list(dbl = { v <- rnorm(n); v[sample(n, 20)] <- NA; v[sample(n, 5)] <- NaN; v }, int = sample(c(-5:5, NA), n, TRUE), lgl = sample(c(TRUE, FALSE, NA), n, TRUE), big = sample(c(.Machine$integer.max, -.Machine$integer.max, 1L), n, TRUE), date = as.Date("2020-01-01") + sample(c(1:10, NA), n, TRUE), chr = sample(c("x", "é", "Z", NA, ""), n, TRUE), posix = as.POSIXct("2020-01-01", tz = "Asia/Tokyo") + sample(c(1:10, NA), n, TRUE))
g <- grp(k); ukeys <- ifelse(is.na(g$keys[[1]]), "<NA>", g$keys[[1]])
orc <- function(v, f) { r <- lapply(split(v, factor(kk, levels = ukeys)), f); r }
for (cn in names(cols)) for (fn in c("sum", "prod", "mean", "min", "max", "count", "nobs", "first", "last")) for (narm in c(TRUE, FALSE)) {
  v <- cols[[cn]]
  a <- tryCatch(grp_reduce(v, g, fn, na.rm = narm), error = function(e) "ERR")
  f <- switch(fn, sum = function(z) if (narm && all(is.na(z))) NA_real_ else sum(z, na.rm = narm), prod = function(z) if (narm && all(is.na(z))) NA_real_ else prod(z, na.rm = narm), mean = function(z) if (narm && all(is.na(z))) NA_real_ else mean(z, na.rm = narm),
    min = function(z) if (narm) { z <- z[!is.na(z)]; if (!length(z)) z[NA_integer_] else if (is.character(z)) sort(z, method = "radix")[1] else min(z) } else if (anyNA(z)) z[NA_integer_][1] else if (is.character(z)) sort(z, method = "radix")[1] else min(z),
    max = function(z) if (narm) { z <- z[!is.na(z)]; if (!length(z)) z[NA_integer_] else if (is.character(z)) rev(sort(z, method = "radix"))[1] else max(z) } else if (anyNA(z)) z[NA_integer_][1] else if (is.character(z)) rev(sort(z, method = "radix"))[1] else max(z),
    count = length, nobs = function(z) sum(!is.na(z)), first = function(z) if (narm) { z <- z[!is.na(z)]; if (length(z)) z[1] else z[NA_integer_] } else z[1], last = function(z) if (narm) { z <- z[!is.na(z)]; if (length(z)) z[length(z)] else z[NA_integer_] } else z[length(z)])
  b <- tryCatch({ r <- orc(v, f); do.call(c, unname(r)) }, error = function(e) "ERR", warning = function(w) "ERRW")
  if (identical(a, "ERR") && (!is.numeric(v) && !is.logical(v)) && fn %in% c("sum", "prod", "mean")) next
  ok <- isTRUE(all.equal(a, b, check.attributes = FALSE)) && identical(is.na(a), is.na(b)) && (identical(class(a), class(b)) || fn %in% c("count", "nobs", "sum","prod","mean"))
  if (!ok) { cat("REDUCE DIFF", cn, fn, narm, "\n"); print(a); print(b) }
}
cat("--- broadcast & shapes\n")
v <- c(1, 2, 3, NA); gg <- grp(c("a", "b", "a", "b"))
print(grp_reduce(v, gg, "mean", broadcast = "subtract")); print(grp_reduce(c(a = 1, b = 2, c = 3, d = 4), gg, "sum", broadcast = "replace")); print(grp_reduce(1:4, gg, "sum", broadcast = "divide")); print(try_(grp_reduce(c("x", "y", "z", "w"), gg, "max", broadcast = "replace"))); print(try_(grp_reduce(factor(c("x", "y", "z", "w")), gg, "first", broadcast = "replace"))); print(try_(grp_reduce(factor(c("x", "y", "z", "w")), gg, "max")))
print(try_(grp_reduce(list(v = v, w = 4:1), gg, c("mean", "max")))); print(try_(grp_reduce(data.frame(v = v, w = 4:1), gg, "sum"))); print(try_(grp_reduce(list(v, 4:1), gg, c("mean", "max", "sum")))); print(try_(grp_reduce(v, gg, "median"))); print(try_(grp_reduce(v, gg, NA))); print(try_(grp_reduce(v, gg, "sum", na.rm = NA))); print(try_(grp_reduce(v, gg, "sum", broadcast = "x")))
print(try_(grp_reduce(v[1:3], gg, "sum"))); print(try_(grp_reduce(double(), grp(double()), "sum"))); print(try_(grp_reduce(list(), gg))); print(try_(grp_reduce(NULL, gg))); print(try_(grp_reduce(list(list(1, 2, 3, 4)), gg, "first"))); print(try_(grp_reduce(v, c("a", "b", "a", "b"), "sum"))); print(try_(grp_reduce(v, data.frame(a = c(1, 1, 2, 2), b = c("x", "x", "x", "y")), "count")))
print(try_(grp_reduce(matrix(1:4, 2), gg, "sum"))); print(try_(grp_reduce(zuint::int64(1:4), gg, "first"))); print(try_(grp_reduce(zuint::int64(1:4), gg, "sum"))); print(try_(grp_reduce(as.Date("2020-01-01") + 0:3, gg, "max", broadcast = "replace"))); print(try_(grp_reduce(c(TRUE, NA, FALSE, TRUE), gg, "max"))); print(try_(grp_reduce(c(TRUE, NA, FALSE, TRUE), gg, "sum")))
print(try_(grp_reduce(c(.Machine$integer.max, 1L, .Machine$integer.max, 1L), gg, "sum"))); print(try_(grp_reduce(1:4, gg, "mean", broadcast = "subtract")))
cat("--- grp shapes\n")
print(try_(grp())); print(try_(grp(NULL))); print(try_(grp(character()))); str(try_(grp(c(2, 1, 2), c("a", "a", "a"), sort = TRUE))); str(try_(grp(data.frame(a = c(2, 1, 2), b = factor(c("a", "a", "b")))))); print(try_(grp(1:3, sort = NA))); print(try_(grp(1:3, 1:2))); str(try_(grp(list(1:3, c("a", "b", "a"))))); str(try_(grp(factor(c("b", "a", NA, "b")), sort = TRUE))); str(try_(grp(c(0, -0, NaN, NA, NaN), sort = TRUE))); str(try_(grp(as.Date(c("2020-01-02", "2020-01-01")), sort = TRUE)$keys)); str(try_(grp(c(b = 2, a = 1, c = 2))$keys))
cat("--- grp_join / grp_match\n")
l1 <- "caf\xe9"; Encoding(l1) <- "latin1"
print(grp_match(c("café", "x", NA), c(NA, l1))); print(match(c("café", "x", NA), c(NA, l1)))
vals <- list(c(1, NA, NaN, 0, -0, 2), c(1L, NA, 3L), c(TRUE, NA, FALSE), c("a", NA, "b", ""), factor(c("a", NA, "b")), as.Date(c("2020-01-01", NA)), as.raw(1:3))
for (a in vals) for (b in vals) { r <- tryCatch(grp_match(a, b), error = function(e) "ERR"); m <- tryCatch(suppressWarnings(match(if (is.factor(a)) as.character(a) else if (is.raw(a)) as.integer(a) else unclass(a), if (is.factor(b)) as.character(b) else if (is.raw(b)) as.integer(b) else unclass(b))), error = function(e) "ERR"); if (!identical(r, m)) { cat("MATCH DIFF", class(a), class(b), ":", format(r), "| base:", format(m), "\n") } }
print(try_(grp_join(data.frame(customer = c(10L, 20L, 10L), day = 1:3), data.frame(id = c(10L, 20L), name = c("Ada", "Linus")), by = c(customer = "id"))))
print(try_(grp_join(data.frame(a = 1:2, b = 1:2), data.frame(a = 2:1, b = 1:2), by = c("a", x = "b")))); print(try_(grp_join(data.frame(a = 1:2, b = 1:2), data.frame(a = 2:1, b = 2:1), by = c("a", b = "b"))));  print(try_(grp_join(1:3, 1:3, by = "a"))); print(try_(grp_join(1:3, 3:1, type = "full"))); print(try_(grp_join(1:3, c(3, 3, 1), multiple = "error"))); print(try_(grp_join(1:3, c("1", "2")))); print(try_(grp_join(data.frame(a = 1:2, b = 1:2), 1:2))); print(try_(grp_join(integer(), integer(), type = "left"))); print(try_(grp_join(1:2, integer(), type = "left"))); print(try_(grp_join(c(a = 1, b = 2), c(z = 2), type = "anti"))); print(try_(grp_match(1:3, NULL))); print(try_(grp_match(NULL, 1:3))); print(try_(grp_match(list(1:2, c("a", "b")), list(c(2L, 1L), c("b", "b")))))
print(try_(grp_join(setNames(list(1:2, 3:4), c("a", "a")), data.frame(a = 4:3), by = "a")))
print(try_(grp_match(2^53 + 1, zuint::int64("9007199254740993")))); print(try_(grp_match(zuint::int64("9007199254740993"), zuint::int64(c("9007199254740992", "9007199254740993"))))); print(try_(grp_match(c(1.5, 2), c(2L, 1L)))); print(try_(grp_match(.Machine$integer.max, .Machine$integer.max + 0)))
