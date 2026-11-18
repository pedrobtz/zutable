# Axis F (design-kernel 4.2): string keys hashed as interned pointers, or
# dictionary-encoded to integers first and then hashed as integers. The
# encoding is grp()'s `id`, one grouping pass over the strings; it pays only
# when the same column is grouped or joined again, so the result is the
# number of reuses that repays it. Run on an installed build (R CMD
# INSTALL --preclean .), not under load_all().
#
#   Rscript tools/bench/str-keys.R [n]
library(zutable)
args <- commandArgs(TRUE)
n <- if (length(args)) as.numeric(args[[1L]]) else 1e6
med <- function(f, reps = 5L) {
  t <- vapply(seq_len(reps), function(i) system.time(f())[["elapsed"]], 0)
  stats::median(t)
}
set.seed(20261118)
cat("op\tn\tdistinct\tpointer_s\tencode_s\tinteger_s\treuses_to_repay\n")
for (d in c(1e2, 1e4, 1e6)) {
  if (d > n) next
  pool <- sprintf("key-%09d-%s", sample.int(1e9, d), "suffix")
  s <- sample(pool, n, TRUE)
  # grp(): pointer hashing against the integer codes it produces.
  codes <- grp(s)$id
  tp <- med(function() grp(s))
  ti <- med(function() grp(codes))
  te <- tp
  cat(sprintf("grp\t%.0f\t%.0f\t%.3f\t%.3f\t%.3f\t%s\n", n, d, tp, te, ti,
              if (tp > ti) sprintf("%.1f", te / (tp - ti)) else "never"))
  # grp_match(): n rows against the d distinct keys; the encoding covers
  # both sides in one pass.
  y <- sample(pool)
  both <- grp(c(y, s))$id
  yc <- both[seq_len(d)]
  xc <- both[d + seq_len(n)]
  tp <- med(function() grp_match(s, y))
  te <- med(function() grp(c(y, s)))
  ti <- med(function() grp_match(xc, yc))
  cat(sprintf("match\t%.0f\t%.0f\t%.3f\t%.3f\t%.3f\t%s\n", n, d, tp, te, ti,
              if (tp > ti) sprintf("%.1f", te / (tp - ti)) else "never"))
}
