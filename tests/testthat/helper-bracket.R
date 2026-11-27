# A generated table for the bracket's tests: no NaN, so base R's own
# comparisons are an oracle (NaN's order is tested on its own, D47).
# `struct = TRUE` adds a struct column `st` for the executor differential.
bracket_frame <- function(n = 60L, struct = FALSE) {
  d <- data.frame(
    id = seq_len(n),
    g = sample(c("a", "B", "b", "A", "", NA), n, replace = TRUE),
    k = sample(c(-2L, 0L, 3L, 7L, NA), n, replace = TRUE),
    px = round(stats::runif(n, -5, 5), 1)[sample.int(n)],
    flag = sample(c(TRUE, FALSE, NA), n, replace = TRUE),
    day = as.Date("2026-01-01") + sample(c(0:30, NA), n, replace = TRUE),
    stringsAsFactors = FALSE
  )
  if (struct) {
    d$st <- data.frame(a = sample(c(1L, 5L, NA), n, replace = TRUE),
                       b = sample(c("u", "w", NA), n, replace = TRUE))
  }
  d
}

# Expressions the plan property test draws from.
plan_exprs <- list(
  quote(px * 2), quote(k + 1L), quote(k / 2L), quote(px > 0), quote(g == "a"),
  quote(coalesce(k, 0L)), quote(nchar(g)), quote(upper(g)), quote(is.na(px)),
  quote(day + 1L), quote(year(day)), quote(ifelse(flag, k, -k)),
  quote(case(px > 1 ~ "hi", .default = "lo")), quote(cast(k, string)),
  quote(round(px, 1L)), quote(abs(k)), quote(concat(g, "!")), quote(id),
  quote(!flag), quote(between(px, -1, 1)), quote(k %/% 2L), quote(1L),
  quote(date_trunc("month", day))
)

# A data frame sorted by every column, row names reset.
sorted_frame <- function(x) {
  x <- as.data.frame(x)
  rownames(x) <- NULL
  if (!nrow(x)) return(x)
  d <- x[do.call(order, c(unname(as.list(x)), list(method = "radix"))), , drop = FALSE]
  rownames(d) <- NULL
  d
}

# Two tables to join, with duplicated and missing keys on both sides.
join_frames <- function(nx = 40L, ny = 30L) {
  list(
    x = data.frame(xi = seq_len(nx), k = sample(c(1:8, NA), nx, replace = TRUE),
                   s = sample(c("a", "b", NA), nx, replace = TRUE),
                   stringsAsFactors = FALSE),
    y = data.frame(yi = seq_len(ny), k2 = sample(c(3:12, NA), ny, replace = TRUE),
                   s2 = sample(c("a", "b", NA), ny, replace = TRUE),
                   stringsAsFactors = FALSE)
  )
}

# merge() as index pairs (xi, yi), sorted.
merge_pairs <- function(x, y, by.x, by.y, all.x, all.y, na_equal) {
  m <- merge(x, y, by.x = by.x, by.y = by.y, all.x = all.x, all.y = all.y,
             sort = FALSE, incomparables = if (na_equal) NULL else NA)
  p <- data.frame(xi = m$xi, yi = m$yi)
  p[order(p$xi, p$yi, method = "radix", na.last = TRUE), , drop = FALSE] |>
    (function(d) { rownames(d) <- NULL; d })()
}

# The trades of the ergonomics computations.
ergo_trades <- function() {
  data.frame(
    id = c(1L, 2L, 1L, 3L, 2L, 1L, 3L, 2L),
    day = as.Date("2026-01-01") + c(0L, 1L, 1L, 2L, 3L, 30L, 31L, 40L),
    px = c(10, 20, 11, 5, 21, 12, 6, 19),
    qty = c(100L, 10L, 50L, 300L, 20L, 70L, 200L, 40L),
    stringsAsFactors = FALSE
  )
}

# grp() identifiers by the reference: first appearance, composite keys
# through interaction() recoded to first appearance.
grp_ref <- function(...) {
  keys <- list(...)
  if (length(keys) == 1L) return(match(keys[[1L]], unique(keys[[1L]])))
  f <- interaction(lapply(keys, function(k) factor(k, levels = unique(k), exclude = NULL)),
                   drop = TRUE, lex.order = TRUE)
  match(as.integer(f), unique(as.integer(f)))
}

# Sample key vectors of every kind for the property tests.
grp_sample <- function(kind, n) {
  pick <- function(pool) pool[sample.int(length(pool), n, replace = TRUE)]
  switch(kind,
    int = pick(c(-3L, 0L, 1L, 7L, .Machine$integer.max, NA)),
    dbl = pick(c(-0, 0, 1.5, -2, Inf, -Inf, NaN, NA, 1e300)),
    lgl = pick(c(TRUE, FALSE, NA)),
    chr = {
      x <- pick(c("a", "B", "", "café", NA, "x y"))
      lat <- x == "café" & !is.na(x)
      lat[seq_along(lat) %% 2 == 0] <- FALSE
      x[lat & !is.na(lat)] <- iconv(x[lat & !is.na(lat)], "UTF-8", "latin1")
      x
    },
    fct = factor(pick(c("lo", "hi", NA)), levels = c("lo", "hi")),
    raw = pick(list(as.raw(1:2), raw(), NULL, as.raw(255)))
  )
}

# Runs code under one executor, "kernel" or "reference" (D29).
with_executor <- function(which, code) {
  withr::local_options(zutable.executor = which)
  force(code)
}
