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
  # The kernel's sort, strings by the bytes of their UTF-8 text (Stage
  # 12); base radix order is the reference (D29).
  if (!identical(getOption("zutable.executor", "kernel"), "reference")) {
    k <- zt_string_codes(list(keys = unname(keys), strings = TRUE))
    return(.Call(zt_key_order, k$keys, rep(FALSE, length(keys)), dec, 1L))
  }
  do.call(order, c(unname(keys), list(decreasing = dec, method = "radix")))
}

# --- grouping ---------------------------------------------------------------

# Group identifiers in order of first appearance, NA a group of its own
# (design §5.3, D26), through the kernel's grp() (Stage 10). The reference
# version below codes keys one by one with match(), which tells NA from NaN
# and -0 from nothing, and combines them pairwise so the codes never exceed
# the row count.
zt_group_ids <- function(keys, n) {
  if (!length(keys)) {
    return(list(id = rep(1L, n), n_groups = 1L))
  }
  if (!identical(getOption("zutable.executor", "kernel"), "reference")) {
    g <- zt_grp_native(keys, n)
    return(list(id = g$id, n_groups = g$n))
  }
  zt_group_ids_ref(keys, n)
}

# The reference executor's grouping, over match(): it ran until the kernel
# landed and stays as its oracle (D29); option zutable.executor =
# "reference" selects it.
zt_group_ids_ref <- function(keys, n) {
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
  if (zt_kernel_executor() && zt_reducible(c(st$exprs, list(st$having)))) {
    return(zt_run_aggregate_kernel(st, cols, n, keys, g))
  }
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

# --- aggregates through the kernel's grp_reduce() (Stage 14) ------------------

zt_kernel_executor <- function() {
  !identical(getOption("zutable.executor", "kernel"), "reference")
}

# An aggregate step through the kernel: each aggregate call is reduced over
# all the rows at once, every column in one pass (design-kernel 6.5), and
# the expression around it is evaluated once over the groups. The loop
# above, one evaluation per group, is its reference (D29).
zt_run_aggregate_kernel <- function(st, cols, n, keys, g) {
  ng <- g$n_groups
  first <- if (length(keys)) zt_reduce_ids(g$id, ng, list(NULL), "first", FALSE)[[1L]]
  out <- lapply(keys, zt_take, idx = first)
  vals <- zt_eval_groups(st$exprs, cols, n, g, first)
  for (nm in names(st$exprs)) out[[nm]] <- vals[[nm]]
  m <- ng
  if (!is.null(st$having)) {
    keep <- zt_eval_groups(list(st$having), cols, n, g, first, out)[[1L]] %in% TRUE
    out <- zt_take_rows(out, which(keep))
    m <- sum(keep)
  }
  names(out) <- names(st$schema)
  list(cols = out, n = m)
}

# Whether the kernel can evaluate these nodes by groups: an r() node is
# opaque (it may reduce a group's rows itself), so it keeps the loop.
zt_reducible <- function(nodes) {
  for (nd in nodes) {
    if (is.null(nd)) next
    if (nd$kind %in% c("r", "window")) return(FALSE)
    if (!zt_reducible(nd$args)) return(FALSE)
  }
  TRUE
}

# Each node's value per group (a list, one per node). An aggregate call
# becomes a column of its per-group values, reduced over all n rows; a
# column outside an aggregate takes the group's first row, or, when
# `scope` names it (having), scope's value.
zt_eval_groups <- function(nodes, cols, n, g, first, scope = NULL) {
  ng <- g$n_groups
  aggs <- list()
  pending <- list()
  used <- character()
  rewrite <- function(nd) {
    if (identical(nd$kind, "call") && identical(zt_vocab[[nd$fn]]$kind, "aggregate")) {
      nm <- paste0(".zt_agg", length(pending) + 1L)
      pending[[nm]] <<- nd
      return(zt_node("col", name = nm, type = nd$type, nullable = TRUE, aggregate = FALSE))
    }
    if (identical(nd$kind, "col")) used <<- c(used, nd$name)
    if (!is.null(nd$args)) nd$args <- lapply(nd$args, rewrite)
    nd
  }
  nodes <- lapply(nodes, rewrite)
  aggs <- zt_reduce_aggregates(pending, cols, n, g)
  env <- aggs
  for (nm in setdiff(unique(used), names(env))) {
    env[[nm]] <- if (nm %in% names(scope)) scope[[nm]] else zt_take(cols[[nm]], first)
  }
  lapply(nodes, function(nd) zt_recycle_n(zt_eval(nd, env, ng), ng))
}

# The per-group values of aggregate calls (a named list of nodes), all
# reduced in one call of the kernel where they can be; vocabulary entries
# keep their SQL null rules (D46): NA is dropped, NaN is a value.
zt_reduce_aggregates <- function(nodes, cols, n, g) {
  ng <- g$n_groups
  plans <- lapply(nodes, function(nd) {
    vals <- lapply(nd$args, function(a) zt_recycle_n(zt_eval(a, cols, n), n))
    zt_aggregate_plan(nd, vals, g)
  })
  fused <- Filter(function(p) !is.null(p$fn), plans)
  res <- list()
  if (length(fused)) {
    res <- zt_reduce_ids(g$id, ng, lapply(fused, function(p) p$x),
                         vapply(fused, function(p) p$fn, ""),
                         vapply(fused, function(p) p$na_rm, NA))
    names(res) <- names(fused)
  }
  out <- list()
  for (nm in names(plans)) {
    p <- plans[[nm]]
    out[[nm]] <- if (is.null(p$fn)) p$value else p$post(res[[nm]])
  }
  out
}

# How the kernel computes one vocabulary aggregate over its argument values:
# list(fn, x, na_rm, post), or list(value) when it is computed some other
# way (count_distinct, through grp()).
zt_aggregate_plan <- function(nd, vals, g) {
  v <- if (length(vals)) vals[[1L]]
  t <- if (length(vals)) nd$args[[1L]]$type
  # Without a copy when there is nothing to strip.
  plain <- function(v) {
    if (!is.null(attributes(v))) attributes(v) <- NULL
    v
  }
  # Not missing, as zt_is_null() has it: an integer column, NA where null.
  present <- function(v) {
    if ((is.integer(v) || is.logical(v) || is.double(v)) && !inherits(v, "integer64") &&
        !is.object(v) || inherits(v, c("Date", "POSIXct"))) {
      return(plain(v))
    }
    s <- rep(1L, zt_nrow_of(v))
    s[zt_is_null(v)] <- NA_integer_
    s
  }
  fn <- nd$fn
  switch(fn,
    count = if (!length(vals)) {
      list(fn = "count", x = NULL, na_rm = FALSE, post = identity)
    } else {
      list(fn = "nobs", x = present(v), na_rm = FALSE, post = identity)
    },
    count_distinct = {
      keep <- which(!zt_is_null(v))
      ids <- g$id[keep]
      d <- zt_grp_native(list(ids, zt_take(v, keep)), length(keep))
      list(value = zt_reduce_ids(ids[d$first], g$n_groups, list(NULL), "count")[[1L]])
    },
    sum = , mean = list(fn = fn, x = as.double(plain(v)), na_rm = TRUE, post = identity),
    min = , max = {
      if (identical(t$id, "string")) {
        # Byte order, as zt_minmax() sorts: each string's rank among the
        # distinct ones, through the kernel's sorted groups.
        s <- zt_grp_build(list(v), TRUE)
        code <- s$id
        code[is.na(v)] <- NA_integer_
        list(fn = fn, x = code, na_rm = TRUE, post = function(r) {
          out <- s$keys[[1L]][r]
          attributes(out) <- NULL
          out
        })
      } else if (identical(t$id, "bool")) {
        list(fn = fn, x = as.integer(v), na_rm = TRUE, post = as.logical)
      } else if (identical(t$id, "int32")) {
        list(fn = fn, x = plain(v), na_rm = TRUE, post = identity)
      } else {
        list(fn = fn, x = as.double(zt_strip(unclass(v))), na_rm = TRUE,
             post = function(r) zt_restore(r, v, t))
      }
    },
    first = , last = list(fn = fn, x = NULL, na_rm = FALSE, post = function(r) {
      out <- zt_take(v, r)
      if (is.null(names(v))) names(out) <- NULL
      out
    }),
    any = list(fn = "max", x = as.integer(v), na_rm = TRUE, post = as.logical),
    all = list(fn = "min", x = as.integer(v), na_rm = TRUE, post = as.logical),
    stop(sprintf("zt_aggregate_plan: no kernel route for %s()", fn))
  )
}
