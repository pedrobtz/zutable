.libPaths(c("/tmp/zutable-hunt/lib", .libPaths()))
library(zutable)
set.seed(2)
fails <- 0
chk <- function(label, a, b) { if (!identical(a, b)) { fails <<- fails + 1; cat("FAIL", label, "\n"); if (fails < 15) { print(head(a, 20)); print(head(b, 20)) } } }
# byte-order oracle: C locale order on UTF-8
hx <- function(u) { u <- enc2utf8(u); h <- vapply(u, function(s) if (is.na(s)) NA_character_ else paste(charToRaw(s), collapse = ""), "", USE.NAMES = FALSE); h }
corder <- function(x, dec = FALSE, nl = TRUE) { u <- hx(x); r <- match(u, sort(unique(u), method = "radix")); order(r, decreasing = dec, na.last = nl, method = "radix") }
pool <- c(NA, "", "a", "ab", "abcdefg", "abcdefgh", "abcdefghi", "abcdefghj", "abcdefgh\x01", "abcdefgi", "abcdefg\x7f", "abcdefghabcdefgh", "abcdefghabcdefgi",
          "é", "é", "ÿ", "z", "Z", "abcdefghé", "abcdefgé", "\U0001F600", "aaaaaaaaaaaaaaaaaaaaaaaaa", "aaaaaaaaaaaaaaaaaaaaaaaab")
for (n in c(0, 1, 2, 15, 16, 17, 100, 5000)) for (dec in c(FALSE, TRUE)) for (nl in list(TRUE, FALSE, NA)) {
  x <- sample(pool, n, TRUE)
  chk(paste("strorder", n, dec, nl), key_order(x, decreasing = dec, na.last = nl), corder(x, dec, nl))
}
# many distinct random strings with shared prefixes
rs <- function(n) vapply(seq_len(n), function(i) paste0(sample(c("abcdefgh", "abcdefg", "", "ab"), 1), paste(sample(c("a", "b", "é", "\x01"), sample(0:12, 1), TRUE), collapse = "")), "")
for (n in c(15, 16, 17, 31, 33, 300, 20000)) { x <- rs(n); chk(paste("rs", n), key_order(x), corder(x)); chk(paste("rs sort", n), as.vector(key_sort(x)), x[corder(x)]) }
# encodings
e_utf8 <- "café"; e_l1 <- iconv(e_utf8, "UTF-8", "latin1"); e_nat <- e_utf8; Encoding(e_nat) <- "unknown"; e_bytes <- e_utf8; Encoding(e_bytes) <- "bytes"
x <- c(e_utf8, e_l1, e_nat, "cafe", NA, "")
print(Encoding(x))
g <- grp(x); print(g$id); print(match(x, unique(x)))
print(key_order(x)); print(key_rank(x, ties = "dense"))
print(grp_match(x, c(e_l1, "", NA))); print(match(x, c(e_l1, "", NA)))
print(grp_join(x, x)$y)
r <- tryCatch(grp(c(e_bytes, e_utf8))$id, error = function(e) conditionMessage(e)); print(r)
r <- tryCatch(key_order(c(e_bytes, e_utf8, "a")), error = function(e) conditionMessage(e)); print(r)
r <- tryCatch(grp_match(c(e_bytes, e_utf8, "a"), e_utf8), error = function(e) conditionMessage(e)); print(r)
# latin1 high byte only string vs UTF-8
l1 <- c("\xe9", "\xff", "a"); Encoding(l1) <- "latin1"
chk("latin1 order", key_order(l1), corder(l1)); chk("latin1 grp", grp(c(l1, enc2utf8(l1)))$id, c(1:3, 1:3))
print(grp_reduce(c(l1, "b"), c(1, 1, 1, 1), "max")); print(Encoding(grp_reduce(c(l1, "b"), c(1, 1, 1, 1), "max")))
# grp vs base
gens <- list(
  int = function(n) sample(c(NA, -3:3, .Machine$integer.max, -.Machine$integer.max), n, TRUE),
  lgl = function(n) sample(c(NA, TRUE, FALSE), n, TRUE),
  dbl = function(n) sample(c(NA, NaN, -0, 0, Inf, -Inf, 1, 1 + .Machine$double.eps, 4.9e-324, -4.9e-324), n, TRUE),
  chr = function(n) sample(pool, n, TRUE),
  fct = function(n) factor(sample(c("b", "a", "zz", NA), n, TRUE), levels = c("zz", "unused", "b", "a")),
  wide = function(n) sample.int(max(1, n), n, TRUE),
  dblw = function(n) rnorm(n)
)
# key string distinguishing NA/NaN, merging -0/0
ks <- function(v) { if (is.double(v)) ifelse(is.na(v) & !is.nan(v), "NA", ifelse(is.nan(v), "NaN", ifelse(v == 0, "0", sprintf("%a", v)))) else if (is.character(v)) ifelse(is.na(v), "<NA>", paste0("s", enc2utf8(v))) else as.character(v) }
for (it in 1:600) {
  n <- sample(c(0, 1, 2, 10, 100, 1000, 5000, 70000), 1, prob = c(1, 1, 1, 3, 3, 3, 2, .3)); k <- sample(1:3, 1)
  cols <- lapply(seq_len(k), function(i) gens[[sample(names(gens), 1)]](n))
  key <- do.call(paste, c(lapply(cols, ks), sep = "\r")); if (n == 0) key <- character()
  g <- do.call(grp, cols)
  id0 <- match(key, unique(key))
  chk(paste("grp id", it, n), g$id, id0)
  chk(paste("grp n", it), g$n, length(unique(key)))
  chk(paste("grp sizes", it), g$sizes, as.integer(tabulate(id0, g$n)))
  chk(paste("grp order", it), g$order, order(id0, method = "radix"))
  chk(paste("grp starts", it), g$starts, as.integer(cumsum(c(1L, tabulate(id0, g$n)))[seq_len(g$n)]))
  f <- match(seq_len(g$n), id0)
  for (j in seq_len(k)) chk(paste("grp keys", it, j), ks(g$keys[[j]]), ks(cols[[j]][f]))
  # sorted
  gs <- do.call(grp, c(cols, list(sort = TRUE)))
  chk(paste("grps partition", it, n), match(gs$id, unique(gs$id)), id0)
  # keys in order: key_order on gs$keys must be identity up to NA/NaN ties
  if (gs$n > 1) {
    o <- do.call(key_order, lapply(gs$keys, function(v) v[seq_along(v)]))
    chk(paste("grps sorted keys", it, n), o, seq_len(gs$n))
  }
  chk(paste("grps sizes", it), gs$sizes, as.integer(tabulate(gs$id, gs$n)))
  chk(paste("grps order", it), gs$order, order(gs$id, method = "radix"))
  chk(paste("grps starts", it), gs$starts, as.integer(cumsum(c(1L, tabulate(gs$id, gs$n)))[seq_len(gs$n)]))
  f <- match(seq_len(gs$n), gs$id)
  for (j in seq_len(k)) chk(paste("grps keys", it, j), ks(gs$keys[[j]]), ks(cols[[j]][f]))
}
cat("fails:", fails, "\n")
