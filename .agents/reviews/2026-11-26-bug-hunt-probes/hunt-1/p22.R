source("pre.R")
set.seed(3); n <- 60
BASE <- zutable(g = sample(c("a", "b", NA), n, TRUE), h = sample(c(1L, 2L, NA), n, TRUE), v = { v <- round(rnorm(n), 2); v[sample(n, 8)] <- NA; v[sample(n, 3)] <- NaN; v }, i = sample(c(-3:3, NA), n, TRUE), out = NA_real_, oi = NA_integer_, os = NA_character_)
mk <- function() copy(BASE)
df <- as.data.frame(mk())
cat("--- := by vs over vs grouped join\n")
a <- mk(); a[, out := sum(v), by = .(g, h)]
b <- mk()[select = .(g, h, v, i, out = over(sum(v), by = .(g, h)), oi, os)]
print(identical(as.data.frame(a)$out, as.data.frame(b)$out))
ar <- mk(); ref(ar[, out := sum(v), by = .(g, h)]); print(identical(a$out, ar$out))
gr <- mk()[by = .(g, h), select = .(s = sum(v))]; j <- join(mk(), gr, on = .(g, h), how = "left"); print(identical(j$s, a$out))
upd <- function(expr) { e <- substitute(expr); x <- mk(); r1 <- tryCatch({ eval(e); as.data.frame(x) }, error = function(err) conditionMessage(err)); x <- mk(); r2 <- ref(tryCatch({ eval(e); as.data.frame(x) }, error = function(err) conditionMessage(err))); cat(if (identical(r1, r2)) "same" else "DIFF", "|", substr(paste(deparse(e), collapse = " "), 1, 90), if (is.character(r1)) paste("\n    ->", r1), "\n"); invisible(r1) }
upd(x[, out := v * 2]); upd(x[i > 0, out := mean(v)]); upd(x[i > 0, out := v - mean(v), by = g]); upd(x[, { w <- v * i; out := w; oi := count(w) }, by = h]); upd(x[, { out := max(v); oi := i %/% 2L; os := first(g) }, by = .(g, h)])
upd(x[, oi := .N, by = g]); upd(x[, oi := count_distinct(i), by = g]); upd(x[, os := max(g)]); upd(x[, os := concat(g, "-", cast(h, string))]); upd(x[is.na(g), os := "none"]); upd(x[, { out := 1; out := out + 1; v := out }]); upd(x[, { v := 0; out := sum(v) }, by = g])
upd(x[g == "a", { v := 0; out := sum(v) }, by = h]); upd(x[, g := NA]); upd(x[, v := NaN]); upd(x[, i := 2^31]); upd(x[, i := i * 1000000000L]); upd(x[, i := 1.0]); upd(x[, oi := v]); upd(x[, out := i]); upd(x[, out := i, by = g]); upd(x[, out := sum(i) / .N, by = g]); upd(x[, os := r(paste0(g, h), string)]); upd(x[, out := r(mean(v, na.rm = TRUE), float64), by = g]); upd(x[, out := c(1, 2)]); upd(x[, zz := 1]); upd(x[, c("out", "v") := 1]); upd(x[, out := NULL]); upd(x[, `:=`(out, 1)]); upd(x[, out := (w <- 1)]); upd(x[v > 0 & i > 0, out := first(v), by = g]); upd(x[v > 100, out := first(v), by = g]); upd(x[, out := last(v) - first(v), by = .(k = i %% 2L)]); upd(x[, out := mean(v), by = "g"]); upd(x[, out := ifelse(v > mean(v), 1, 0), by = g]); upd(x[, out := case(v > 0 ~ sum(v), .default = min(v)), by = g]); upd(x[, oi := cast(sum(i), int32), by = g]); upd(x[, out := sum(v), by = v]); upd(x[update = out := 1, where = i > 0]); upd(x[i > 0, update = { out := 2 }])
x <- mk(); r <- x[, out := 1]; print(identical(r, x)); y <- x[i > 0, out := 5][, .(out)]; print(table(y$out, useNA = "a"))
