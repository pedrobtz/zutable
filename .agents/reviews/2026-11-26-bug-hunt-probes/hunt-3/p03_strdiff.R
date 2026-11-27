.libPaths(c("/tmp/zutable-hunt/lib", .libPaths()))
library(zutable)
set.seed(2)
rs <- function(n) vapply(seq_len(n), function(i) paste0(sample(c("abcdefgh", "abcdefg", "", "ab"), 1), paste(sample(c("a", "b", "é", "\x01"), sample(0:12, 1), TRUE), collapse = "")), "")
# true byte order oracle: compare raw bytes
bytecmp <- function(a, b) { ra <- as.integer(charToRaw(a)); rb <- as.integer(charToRaw(b)); m <- min(length(ra), length(rb)); d <- which(ra[seq_len(m)] != rb[seq_len(m)]); if (length(d)) sign(ra[d[1]] - rb[d[1]]) else sign(length(ra) - length(rb)) }
for (n in c(300, 3000)) {
x <- rs(n)
o <- key_order(x)
s <- x[o]
bad <- which(vapply(seq_len(n - 1), function(i) bytecmp(s[i], s[i + 1]) > 0, NA))
cat("n", n, "kernel order violations vs bytes:", length(bad), "\n")
ob <- order(x, method = "radix"); sb <- x[ob]
badb <- which(vapply(seq_len(n - 1), function(i) bytecmp(sb[i], sb[i + 1]) > 0, NA))
cat("base radix violations vs bytes:", length(badb), "\n")
if (length(bad)) for (i in head(bad, 5)) { print(charToRaw(s[i])); print(charToRaw(s[i + 1])) }
if (length(badb)) for (i in head(badb, 3)) { print(charToRaw(sb[i])); print(charToRaw(sb[i + 1])) }
# stability: ties in row order
ties <- which(s[-n] == s[-1]); cat("stable:", all(o[ties] < o[ties + 1]), "\n")
}
