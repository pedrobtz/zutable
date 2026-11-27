.libPaths(c("/tmp/zutable-hunt/lib", .libPaths()))
library(zutable)
set.seed(9); fails <- 0
bits <- function(d) lapply(d, function(v) if (is.double(v)) { b <- vapply(unclass(v), function(e) paste(rev(as.character(writeBin(e, raw()))), collapse = ""), ""); list(b, attributes(v)) } else v)
both <- function(label, expr) {
  e <- substitute(expr); env <- parent.frame()
  r <- lapply(c("kernel", "reference"), function(ex) { options(zutable.executor = ex); tryCatch(bits(as.data.frame(eval(e, env))), error = function(err) paste("ERR", class(err)[1])) })
  options(zutable.executor = "kernel")
  if (!identical(r[[1]], r[[2]])) { fails <<- fails + 1; cat("FAIL", label, "\n"); if (fails < 8) { options(zutable.executor = "kernel"); print(tryCatch(eval(e, env), error = function(x) conditionMessage(x)), n = 30); options(zutable.executor = "reference"); print(tryCatch(eval(e, env), error = function(x) conditionMessage(x)), n = 30); options(zutable.executor = "kernel") } }
}
gens <- list(
  int = function(n) sample(c(NA, -2:2, .Machine$integer.max), n, TRUE),
  dbl = function(n) sample(c(NA, NaN, -0, 0, Inf, -Inf, 1, 2.5, 1e308, 1e16, -1e16, 0.1), n, TRUE),
  chr = function(n) sample(c(NA, "", "a", "abcdefgh", "abcdefghi", "é", "Z"), n, TRUE),
  lgl = function(n) sample(c(NA, TRUE, FALSE), n, TRUE),
  date = function(n) as.Date(sample(c(NA, 0:3), n, TRUE), origin = "1970-01-01")
)
for (it in 1:120) {
  n <- sample(c(0, 1, 2, 10, 200, 4200), 1, prob = c(1, 1, 1, 3, 3, .4))
  kt <- sample(names(gens), 1); k2 <- sample(names(gens), 1)
  t <- zutable(k = gens[[kt]](n), k2 = gens[[k2]](n), i = gens$int(n), d = gens$dbl(n), s = gens$chr(n), b = gens$lgl(n), dt = gens$date(n))
  lab <- paste(it, n, kt, k2)
  both(paste("agg", lab), t[select = .(n = count(), ni = count(i), si = sum(i), sd = sum(d), mi = mean(i), md = mean(d), mni = min(i), mxi = max(i), mnd = min(d), mxd = max(d), mns = min(s), mxs = max(s), fs = first(s), ls = last(d), cd = count_distinct(d), cs = count_distinct(s), a = any(b), al = all(b), mdt = max(dt), mb = min(b)), by = k])
  both(paste("agg2", lab), t[select = .(sd = sum(d), mxs = max(s), n = count()), by = .(k, k2)])
  both(paste("agg0", lab), t[select = .(sd = sum(d), md = mean(d), mxs = max(s), mnd = min(d), n = count(), cd = count_distinct(k))])
  both(paste("order", lab), t[order = .(k, -d)])
  both(paste("order2", lab), t[order = .(-k2, s, i)])
  both(paste("distinct", lab), t[select = .(k, k2), distinct = TRUE])
  both(paste("having", lab), t[select = .(sd = sum(d)), by = k, having = count() > 1L, order = k])
  m <- sample(c(0, 1, 5, 100), 1)
  u <- zutable(k = gens[[kt]](m), k2 = gens[[k2]](m), v = seq_len(m))
  for (how in c("inner", "left", "right", "full", "semi", "anti")) for (mult in c("all", "first", "last", "error")) for (ne in c(TRUE, FALSE)) {
    both(paste("join", how, mult, ne, lab, m), join(t, u, on = k, how = how, multiple = mult, na_equal = ne, suffix = c(".x", ".y")))
    if (it %% 3 == 0) both(paste("join2", how, mult, ne, lab, m), join(t, u, on = .(k, k2), how = how, multiple = mult, na_equal = ne))
  }
}
cat("fails:", fails, "\n")
