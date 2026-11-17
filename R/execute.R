# The reference executor (design §11.1, D29): every operator in R over base
# functions. It runs until a kernel piece lands and stays as that piece's
# oracle.

zt_recycle_n <- function(v, n) {
  if (zt_nrow_of(v) == 1L && n != 1L) {
    if (is.data.frame(v)) v[rep(1L, n), , drop = FALSE] else rep(v, length.out = n)
  } else {
    v
  }
}

zt_take_rows <- function(cols, idx) lapply(cols, zt_take, idx = idx)

zt_execute <- function(x, plan, call) {
  cols <- unclass(x)
  attributes(cols) <- list(names = names(x))
  n <- .row_names_info(x, 2L)
  input <- cols
  for (st in plan$steps) {
    switch(st$op,
      filter = {
        keep <- which(zt_eval(st$predicate, cols, n) %in% TRUE)
        cols <- zt_take_rows(cols, keep)
        input <- cols
        n <- length(keep)
      },
      project = {
        input <- cols
        cols <- lapply(st$exprs, function(e) zt_recycle_n(zt_eval(e, input, n), n))
      },
      distinct = {
        keep <- which(!zt_duplicated_rows(cols, n))
        cols <- zt_take_rows(cols, keep)
        input <- zt_take_rows(input, keep)
        n <- length(keep)
      },
      sort = {
        scope <- c(cols, input[setdiff(names(input), names(cols))])
        vals <- lapply(st$keys, function(k) zt_recycle_n(zt_eval(k$node, scope, n), n))
        types <- lapply(st$keys, function(k) k$node$type)
        ord <- zt_order_index(vals, types, vapply(st$keys, function(k) k$desc, NA))
        cols <- zt_take_rows(cols, ord)
        input <- zt_take_rows(input, ord)
      },
      limit = {
        keep <- seq_len(min(n, st$n))
        cols <- zt_take_rows(cols, keep)
        input <- zt_take_rows(input, keep)
        n <- length(keep)
      }
    )
  }
  out <- new_zutable(cols, plan$schema, n)
  attr(out, "plan") <- zt_plan_record(plan)
  out
}

# Duplicated rows, comparing values exactly (NA and NaN differ).
zt_duplicated_rows <- function(cols, n) {
  if (!length(cols) || !n) return(logical(n))
  duplicated(structure(lapply(cols, function(c) {
    if (is.data.frame(c)) do.call(paste, c(unname(as.list(c)), sep = "\r")) else c
  }), names = names(cols), class = "data.frame", row.names = c(NA_integer_, -n)))
}

# A stable permutation for sort keys: missing values last in either
# direction, NaN above every number (D47), strings in byte order.
zt_order_index <- function(vals, types, desc) {
  keys <- list()
  dec <- logical()
  for (k in seq_along(vals)) {
    v <- vals[[k]]
    t <- types[[k]]
    null <- zt_is_null(v)
    keys <- c(keys, list(null))
    dec <- c(dec, FALSE)
    if (identical(t$id, "string")) {
      s <- v
      s[null] <- ""
      keys <- c(keys, list(s))
      dec <- c(dec, desc[[k]])
      next
    }
    num <- if (is.factor(v)) as.integer(v) else zt_strip(unclass(v))
    num <- as.double(num)
    nan <- is.nan(num) & !null
    num[null | nan] <- 0
    keys <- c(keys, list(nan, num))
    dec <- c(dec, desc[[k]], desc[[k]])
  }
  if (!length(vals[[1L]])) return(integer())
  do.call(order, c(unname(keys), list(decreasing = dec, method = "radix")))
}
