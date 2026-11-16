# A small table of every common type, and the same data as a plain frame.
sample_frame <- function() {
  data.frame(
    id = 1:6,
    g = c("a", "b", "a", "c", "b", "a"),
    px = c(10.5, 11, NA, 19.5, 7, 3.25),
    day = as.Date("2026-01-01") + 0:5,
    k = factor(c("lo", "hi", "lo", NA, "hi", "lo"), levels = c("lo", "hi")),
    stringsAsFactors = FALSE
  )
}

# Plain data frame from a result, row names reset: zutables keep none.
plain <- function(x) {
  x <- as.data.frame(x)
  rownames(x) <- NULL
  x
}
