source("pre.R")
set.seed(1)
mk <- function() zutable(g = sample(c(1L,2L,NA,3L), 200, TRUE), v = round(rnorm(200), 2), w = sample(c(1:5, NA), 200, TRUE), s = sample(c("a","b",NA), 200, TRUE), t = NA_real_, u = NA_integer_)
seqs <- list(
  quote(x[, t := sum(v), by = g]), quote(x[w > 2L, u := max(w), by = s]), quote(x[, { m <- mean(v); t := v - m; u := n() }, by = .(g, s)]),
  quote(x[v > 0, t := t * 2]), quote(x[, u := w]), quote(x[is.na(g), { t := min(v); u := 0L }]), quote(x[, t := v / sum(v), by = s]), quote(x[s == "a", t := first(v), by = g])
)
run <- function(pattern) { set.seed(2); x <- mk(); for (i in seq_along(seqs)) { options(zutable.executor = pattern[(i - 1) %% length(pattern) + 1]); r <- tryCatch(eval(seqs[[i]]), error = function(e) cat("E", i, conditionMessage(e), "\n")) }; options(zutable.executor = NULL); as.data.frame(x) }
a <- run("kernel"); b <- run("reference"); c <- run(c("kernel", "reference")); d <- run(c("reference", "kernel"))
chk("kernel == reference", identical(a, b)); chk("mixed1", identical(a, c)); chk("mixed2", identical(a, d))
if (!identical(a, b)) print(all.equal(a, b))
print(head(a, 4))
for (bad in list("Kernel", "", NA, 1, c("kernel","reference"), "ref", TRUE)) { options(zutable.executor = bad); x <- mk(); cat(deparse(bad), ":", try_(x[, t := sum(v), by = g]), "| query:", try_(x[, .(s = sum(v)), by = g]), "\n") }
options(zutable.executor = NULL)
# switch between a query and update on the result; within a function with on.exit
x <- mk(); options(zutable.executor = "reference"); q <- x[, .(sv = sum(v)), by = g, order = g]; options(zutable.executor = "kernel"); q2 <- x[, .(sv = sum(v)), by = g, order = g]; chk("query equal", identical(as.data.frame(q), as.data.frame(q2))); if (!identical(as.data.frame(q), as.data.frame(q2))) print(all.equal(as.data.frame(q), as.data.frame(q2)))
