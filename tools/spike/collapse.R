# The spike's comparison (design-kernel section 11): collapse grouping and
# summing the same shape of input as tools/spike/spike.c (1e7 rows, G
# distinct keys spread over the integers, shuffled), one thread, median of
# five. Run: Rscript tools/spike/collapse.R
n <- 1e7
set.seed(20261117)
cat("groups,method,seconds,groups_found\n")
for (G in c(1e3, 1e5, 1e6, 1e7)) {
  ids <- sample.int(.Machine$integer.max, G)
  g <- ids[c(seq_len(G), sample.int(G, n - G, replace = TRUE))[sample.int(n)]]
  v <- (sample.int(1000L, n, replace = TRUE) - 1) / 8
  t <- numeric(5)
  for (r in 1:5) t[[r]] <- system.time(s <- collapse::fsum(v, g))[["elapsed"]]
  cat(sprintf("%d,collapse_fsum,%.4f,%d\n", as.integer(G), stats::median(t), length(s)))
  for (r in 1:5) t[[r]] <- system.time(gg <- collapse::GRP(g, sort = FALSE))[["elapsed"]]
  cat(sprintf("%d,collapse_GRP,%.4f,%d\n", as.integer(G), stats::median(t), gg$N.groups))
}
