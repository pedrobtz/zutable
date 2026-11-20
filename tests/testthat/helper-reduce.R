# The oracle for grp_reduce() (design-kernel 6.5): base R's statistic over
# each group's rows, split() as tapply() would split them, with the rule
# that a group with no values left gives NA.
reduce_oracle <- function(x, id, ng, fn, na.rm) {
  rows <- split(seq_along(id), factor(id, levels = seq_len(ng)))
  one <- function(r) {
    v <- x[r]
    if (fn == "count") return(length(r))
    if (fn == "nobs") return(sum(!is.na(v)))
    if (na.rm) v <- v[!is.na(v)]
    if (fn %in% c("first", "last")) {
      if (!length(v)) return(x[NA_integer_])
      return(if (fn == "first") v[1L] else v[length(v)])
    }
    if (!length(v)) {
      return(if (fn %in% c("sum", "prod", "mean")) NA_real_ else x[NA_integer_])
    }
    switch(fn,
      sum = sum(as.double(v)),
      prod = prod(as.double(v)),
      # Base mean() of an integer vector divides its long double sum, with
      # no correction pass; of a logical one, mean() of its integers.
      mean = mean(if (is.logical(v)) as.integer(v) else v),
      min = , max = {
        if (is.character(v)) {
          if (anyNA(v)) return(NA_character_)
          s <- sort(unique(enc2utf8(v)), method = "radix")
          if (fn == "min") s[[1L]] else s[[length(s)]]
        } else if (is.logical(v)) {
          if (fn == "min") min(as.integer(v)) else max(as.integer(v))
        } else {
          r <- if (fn == "min") min(v) else max(v)
          if (is.integer(v)) as.integer(r) else r
        }
      }
    )
  }
  out <- lapply(rows, one)
  res <- if (length(out)) do.call(c, unname(out)) else x[0L]
  if (fn %in% c("count", "nobs")) res <- as.integer(res)
  if (fn %in% c("sum", "prod", "mean")) res <- as.double(res)
  if (fn %in% c("min", "max") && is.logical(x)) res <- as.integer(res)
  if (fn %in% c("min", "max", "first", "last")) names(res) <- NULL
  res
}

# The same, NA or NaN where base arithmetic mixes them: sum, prod and mean
# without na.rm, over a group holding both, give either (IEEE takes the
# payload from the operand order, which the compiler may commute).
expect_reduce_equal <- function(got, want, fn, na.rm, info = NULL) {
  if (!na.rm && fn %in% c("sum", "prod", "mean") && is.double(got) && length(got) == length(want)) {
    both <- is.na(got) & is.na(want)
    got[both] <- NA_real_
    want[both] <- NA_real_
  }
  testthat::expect_identical(got, want, info = info)
}

# Base R's rsum(), rprod() and real_mean() as an R built without long
# double runs them (R CMD check's nold leg): every sum in double, in row
# order. R's own arithmetic is double, so a loop is the oracle.
sum_double <- function(v) {
  s <- 0
  for (e in as.double(v)) s <- s + e
  s
}
prod_double <- function(v) {
  s <- 1
  for (e in as.double(v)) s <- s * e
  s
}
mean_double <- function(v) {
  if (!is.double(v)) return(sum_double(v) / length(v))
  n <- length(v)
  s <- sum_double(v)
  if (is.finite(s)) {
    s <- s / n
    t <- 0
    for (e in v) t <- t + (e - s)
    return(s + t / n)
  }
  # R >= 4.2: an infinite sum may have overflowed; sum the smaller terms.
  s <- 0
  for (e in v) s <- s + e / n
  if (is.finite(s)) {
    t <- 0
    for (e in v) t <- t + (e - s) / n
    s <- s + t
  }
  s
}

# reduce_oracle() for sum, prod and mean in double, groups 1 .. ng, na.rm.
reduce_oracle_double <- function(x, id, ng, fn) {
  f <- switch(fn, sum = sum_double, prod = prod_double, mean = mean_double)
  rows <- split(seq_along(id), factor(id, levels = seq_len(ng)))
  vapply(rows, function(r) {
    v <- x[r]
    v <- v[!is.na(v)]
    if (!length(v)) NA_real_ else f(if (is.logical(v)) as.integer(v) else v)
  }, 0, USE.NAMES = FALSE)
}
