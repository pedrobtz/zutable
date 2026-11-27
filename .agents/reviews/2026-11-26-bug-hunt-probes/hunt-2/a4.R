source("pre.R")
meta <- function(x) .Call(zutable:::zt_sorted_meta, x)
show <- function(l, x) cat(sprintf("%-28s meta=%-6s unsorted=%-5s anyNA=%-5s vals=%s\n", l, paste(meta(x), collapse=","), tryCatch(is.unsorted(x), error=function(e) "E"), anyNA(x), paste(format(x), collapse=" ")))
for (mkv in list(function() c(3L,1L,2L,5L), function() c(3,1,2,5), function() c(TRUE,FALSE,TRUE,TRUE), function() c("c","a","b","e"))) {
  cat("---", typeof(mkv()), "\n")
  src <- mkv(); srcsnap <- mkv()
  w <- key_sort(src); wsnap <- w[seq_along(w)]; cp <- w; 
  v0 <- if (is.character(src)) "0" else if (is.logical(src)) FALSE else 0
  routes <- list(
    `[<-` = function(w) { w[4] <- v0; w }, `[[<-` = function(w) { w[[4]] <- v0; w }, na = function(w) { w[2] <- NA; w }, `length<-` = function(w) { length(w) <- 2; w },
    lengthup = function(w) { length(w) <- 6; w }, attr = function(w) { attr(w, "foo") <- 1; w }, names = function(w) { names(w) <- letters[1:4]; w }, sm = function(w) { storage.mode(w) <- "character"; w },
    isna = function(w) { is.na(w) <- 1; w }, rev = function(w) rev(w), revassign = function(w) { w[] <- rev(w); w }, empty = function(w) { w[integer()] <- v0; w }, same = function(w) { w[1] <- w[1]; w },
    logicalidx = function(w) { w[c(FALSE,FALSE,FALSE,TRUE)] <- v0; w }, append = function(w) { w[5] <- v0; w }, dim = function(w) { dim(w) <- c(2,2); w }, cls = function(w) { class(w) <- "foo"; unclass(w) },
    sortself = function(w) { w[] <- sort(w, decreasing = TRUE); w }, replace = function(w) replace(w, 4, v0), vap = function(w) vapply(w, identity, w[1]), mostattr = function(w) { mostattributes(w) <- list(foo = 1); w }
  )
  for (nm in names(routes)) {
    w <- key_sort(src); cp <- w; ww <- routes[[nm]](w)
    p <- wsnap; pp <- routes[[nm]](p)
    ok <- identical(ww[seq_along(ww)], pp[seq_along(pp)]) && identical(is.unsorted(ww), is.unsorted(pp)) && identical(anyNA(ww), anyNA(pp)) && identical(sort(ww), sort(pp)) && identical(order(ww), order(pp)) && identical(range(ww), range(pp)) && identical(unique(ww), unique(pp))
    ok2 <- identical(cp[seq_along(cp)], wsnap) && identical(src, srcsnap) && identical(meta(cp), meta(key_sort(src)))
    if (!ok || !ok2) { cat("FAIL", nm, ok, ok2, "\n"); show("  after", ww); show("  plain", pp); show("  copy", cp) }
  }
  # already-sorted input: payload shared with caller's vector?
  s <- sort(mkv()); ss <- s[seq_along(s)]; w <- key_sort(s); w[1] <- v0; chk("sorted source untouched", identical(s, ss))
  # function-local write, C-level via Reduce
  w <- key_sort(src); f <- function(v) { v[1] <- v0; v }; r <- f(w); chk("fn arg write: original intact", identical(w[seq_along(w)], wsnap) && !is.null(meta(w)) && identical(meta(w), meta(key_sort(src))))
  # serialize before/after write
  w <- key_sort(src); u <- unserialize(serialize(w, NULL)); chk("ser meta kept", identical(meta(u), meta(w)) && identical(u[1:4], w[1:4]))
  u[4] <- v0; chk("ser copy write indep", identical(w[seq_along(w)], wsnap)); show("  u after write", u)
  w[4] <- v0; u2 <- unserialize(serialize(w, NULL)); show("  ser after write", u2)
  # in a zutable column
  w <- key_sort(src); x <- zutable(k = w, o = seq_along(w)); cat("  col meta:", paste(meta(x$k), collapse=","), "\n")
  y <- x; x[o == 4L, k := NA]; cat("  after := col meta:", paste(meta(x$k), collapse=","), "is.unsorted:", is.unsorted(x$k), "anyNA:", anyNA(x$k), format(x$k), "| w intact:", identical(w[seq_along(w)], wsnap), paste(meta(w), collapse=","), "\n")
  x2 <- zutable(k = key_sort(src), o = 4:1); x2$k[1] <- x2$k[4]; cat("  after $<-[1]:", paste(meta(x2$k), collapse=","), is.unsorted(x2$k), format(x2$k), "\n")
  x3 <- zutable(k = key_sort(src), o = 4:1); q <- x3[order = o]; cat("  after order query:", paste(meta(q$k), collapse=","), is.unsorted(q$k), format(q$k), "\n")
  q <- x3[o > 0L]; cat("  after where-all query:", paste(meta(q$k), collapse=","), is.unsorted(q$k), "\n"); q <- x3[, .(k)]; cat("  after select:", paste(meta(q$k), collapse=","), "\n"); q[, k := k[1]] ; cat("  select then := :", paste(meta(q$k), collapse=","), format(q$k), "orig:", format(x3$k), "\n")
  x4 <- zutable(k = key_sort(src), o = 4:1); x4[, o := 1L]; cat("  := other col:", paste(meta(x4$k), collapse=","), "\n")
}
