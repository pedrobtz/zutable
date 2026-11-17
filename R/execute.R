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
      aggregate = {
        res <- zt_run_aggregate(st, cols, n)
        cols <- res$cols
        n <- res$n
        input <- cols
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

# --- grouping ---------------------------------------------------------------

# Group identifiers in order of first appearance, NA a group of its own
# (design §5.3, D26). Keys are coded one by one with match(), which tells NA
# from NaN and -0 from nothing, and combined pairwise so the codes never
# exceed the row count.
zt_group_ids <- function(keys, n) {
  if (!length(keys)) {
    return(list(id = rep(1L, n), n_groups = 1L))
  }
  code <- NULL
  for (k in keys) {
    v <- if (is.factor(k)) as.character(k) else k
    if (inherits(v, "POSIXct") || inherits(v, "Date")) v <- zt_strip(unclass(v))
    ck <- match(v, unique(v))
    if (is.null(code)) {
      code <- ck
    } else {
      m <- max(ck, 1L)
      combined <- if (as.double(max(code, 1L)) * m < 2^52) {
        (as.double(code) - 1) * m + ck
      } else {
        paste(code, ck)
      }
      code <- match(combined, unique(combined))
    }
  }
  list(id = code, n_groups = if (n) max(code) else 0L)
}

# The rows of each group, in group order.
zt_group_rows <- function(g) {
  if (!g$n_groups) return(list())
  split(seq_along(g$id), factor(g$id, levels = seq_len(g$n_groups)))
}

# A vector of `type` of length n, all missing.
zt_empty <- function(type, n) {
  na <- na_of(type)
  if (is.data.frame(na)) na[rep(1L, n), , drop = FALSE] else rep(na, length.out = n)
}

zt_run_aggregate <- function(st, cols, n) {
  keys <- lapply(st$by, function(k) zt_recycle_n(zt_eval(k, cols, n), n))
  g <- zt_group_ids(keys, n)
  groups <- zt_group_rows(g)
  # With no keys there is one group, possibly of no rows (a summary).
  first <- if (length(keys)) vapply(groups, function(r) r[[1L]], 1L) else integer()
  out <- lapply(keys, zt_take, idx = first)
  # One value per group for each element, evaluated on the group's rows;
  # an expression of the keys takes its value from the group's first row.
  for (nm in names(st$exprs)) {
    node <- st$exprs[[nm]]
    res <- zt_empty(node$type, length(groups))
    for (i in seq_along(groups)) {
      rows <- groups[[i]]
      v <- zt_eval(node, zt_take_rows(cols, rows), length(rows))
      if (zt_nrow_of(v)) res[i] <- zt_take(v, 1L)
    }
    out[[nm]] <- res
  }
  m <- length(groups)
  if (!is.null(st$having)) {
    keep <- logical(m)
    for (i in seq_len(m)) {
      rows <- groups[[i]]
      scope <- c(lapply(out, zt_take, idx = i),
                 zt_take_rows(cols, rows)[setdiff(names(cols), names(out))])
      keep[[i]] <- isTRUE(zt_eval(st$having, scope, length(rows))[1L])
    }
    out <- zt_take_rows(out, which(keep))
    m <- sum(keep)
  }
  names(out) <- names(st$schema)
  list(cols = out, n = m)
}
