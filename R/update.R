# Updates in place (design §6). `col := expression` writes values into a
# column that exists and keeps its type; several columns are a block,
# whose statements run in order, are typed as a whole before any data is
# touched, and are committed at once by zt_commit() (src/commit.c).

#' Update columns in place
#'
#' `x[, col := expression]` writes new values into an existing column,
#' keeping its type: SQL's `UPDATE`. Several columns are a block,
#' `x[, { a := ...; b := ... }]`, whose statements run in order: `name <-
#' value` binds a local, and each statement sees the columns and locals as
#' those above it left them. The block is typed as a whole before any data
#' is touched, every new column is computed before any is written, and the
#' commit replaces column pointers, so a failure leaves the table as it
#' was and a vector shared with another object is never changed.
#'
#' With `where`, only the matching rows are written, and aggregates are
#' computed over those rows. With `by`, an aggregate is computed per group
#' and written to the group's rows. Each value is one value, or one per row
#' written.
#'
#' The table is changed in place: every alias of it sees the update.
#' `copy()` returns an independent table for one allocation. `freeze()`
#' marks a table, in place and for good, so that every write route raises a
#' `zutable_frozen_error`; queries read it as before.
#'
#' @param x A zutable.
#' @return The bracket returns `x`, invisibly. `copy()` returns a new
#'   zutable; `freeze()` returns `x`, invisibly; `is_frozen()` `TRUE` or
#'   `FALSE`.
#' @name zutable-update
#' @examples
#' d <- zutable(id = c(1L, 1L, 2L), px = c(10, 20, 30), qty = c(1L, 2L, 3L),
#'              notional = NA_real_, share = NA_real_)
#' d[, {
#'   w <- px * qty
#'   notional := w
#'   share := w / sum(w)
#' }, by = id]
#' d
#' freeze(d)
#' is_frozen(d)
NULL

#' @rdname zutable-update
#' @export
copy <- function(x) {
  call <- sys.call()
  if (!is_zutable(x)) {
    zutable_abort("type", "copy() takes a zutable", call = call)
  }
  zt_validate(x, call)
  .Call(zt_copy, x)
}

#' @rdname zutable-update
#' @export
freeze <- function(x) {
  call <- sys.call()
  if (!is_zutable(x)) {
    zutable_abort("type", "freeze() takes a zutable", call = call)
  }
  zt_validate(x, call)
  .Call(zt_freeze, x)
  invisible(x)
}

#' @rdname zutable-update
#' @export
is_frozen <- function(x) {
  isTRUE(attr(x, "frozen", exact = TRUE))
}

zt_check_not_frozen <- function(x, call) {
  if (is_frozen(x)) {
    zutable_abort("frozen", paste(
      "this table is frozen: its values do not change. copy() gives an",
      "independent table that can be updated"
    ), call = call)
  }
}

# Whether a captured second position is an update: `col := v`, or a block
# holding one.
zt_is_update <- function(e) {
  if (!is.call(e)) return(FALSE)
  if (identical(e[[1L]], as.name(":="))) return(TRUE)
  if (identical(e[[1L]], as.name("{"))) {
    return(any(vapply(as.list(e)[-1L], function(s) {
      is.call(s) && identical(s[[1L]], as.name(":="))
    }, NA)))
  }
  FALSE
}

# The statements of a block: list(kind = "local"/"set", name, node).
zt_plan_update <- function(x, e, where, by, env, call) {
  schema <- attr(x, "schema", exact = TRUE)
  stmts <- if (identical(e[[1L]], as.name("{"))) as.list(e)[-1L] else list(e)
  scope <- schema
  locals <- character()
  out <- list()
  for (s in stmts) {
    if (!is.call(s) || !(as.character(s[[1L]]) %in% c(":=", "<-", "="))) {
      zutable_abort("syntax", paste(
        "a statement of an update block is `col := value` or",
        "`name <- value`"
      ), call = call)
    }
    op <- as.character(s[[1L]])
    lhs <- s[[2L]]
    if (!is.symbol(lhs)) {
      zutable_abort("syntax", paste(
        "the left side of := names one column; several columns are a block:",
        "{ a := 1; b := 2 }"
      ), call = call)
    }
    name <- as.character(lhs)
    rhs <- s[[3L]]
    if (op == ":=") {
      if (!name %in% names(schema)) {
        zutable_abort("schema", sprintf(paste(
          "column `%s` does not exist; := updates columns, and a new column",
          "is a new table: x[select = .(.all, %s = ...)]"
        ), name, name), call = call)
      }
      if (name %in% locals) {
        zutable_abort("syntax", sprintf("`%s` is a local of this block", name),
                      call = call)
      }
      if (is.null(rhs)) {
        zutable_abort("schema", sprintf(
          "column `%s` cannot be removed; a table's columns are fixed", name
        ), call = call)
      }
      field <- schema$fields[[name]]
      node <- zt_translate(rhs, scope, env, call)
      node <- zt_fit_node(node, field, call)
      out[[length(out) + 1L]] <- list(kind = "set", name = name, node = node)
    } else {
      if (name %in% names(schema)) {
        zutable_abort("syntax", sprintf(paste(
          "`%s` is a column; write `%s := value` to update it, or give the",
          "local another name"
        ), name, name), call = call)
      }
      node <- zt_translate(rhs, scope, env, call)
      if (zt_is_lit(node) && is.null(node$type)) {
        zutable_abort("type", sprintf("local `%s` is a bare NA, which has no type", name),
                      call = call)
      }
      locals <- union(locals, name)
      fields <- scope$fields
      fields[[name]] <- new_field(name, node$type, isTRUE(node$nullable))
      scope <- new_schema(unname(fields))
      out[[length(out) + 1L]] <- list(kind = "local", name = name, node = node)
    }
  }
  pred <- NULL
  if (!is.null(where)) {
    pred <- zt_translate(where, schema, env, call)
    if (!identical(pred$type$id, "bool") || isTRUE(pred$aggregate)) {
      zutable_abort("type", "`where` of an update is a condition on the rows",
                    call = call)
    }
  }
  keys <- if (is.null(by)) list() else zt_parse_by(by, schema, env, call)
  list(stmts = out, where = pred, by = keys)
}

# The value of `col := node` as the column's type: the same type, an exact
# widening (int32 into float64 or int64), or a literal that is exactly representable
# there (§4.3). Anything else is a schema error (§6.1).
zt_fit_node <- function(node, field, call) {
  type <- field$type
  if (zt_is_lit(node)) {
    if (identical(type$id, "int64") && is.integer(node$value)) zt_require_type_package(type, call)
    v <- zt_lit_adapt(node$value, type)
    if (!is.null(v)) return(zt_lit_node(v, type))
  } else if (identical(node$type, type)) {
    return(node)
  } else if (identical(node$type$id, "int32") && type$id %in% c("float64", "int64")) {
    zt_require_type_package(type, call)
    return(zt_node("call", fn = "cast", args = list(node), type = type,
                   nullable = node$nullable, aggregate = node$aggregate))
  }
  zutable_abort("schema", sprintf(
    "column `%s` is %s; the update would make it %s", field$name,
    format(type), zt_format_type(node)
  ), call = call)
}

zt_run_update <- function(x, up, call) {
  zt_with_eval_call(call, zt_run_update_plan(x, up, call))
}

zt_run_update_plan <- function(x, up, call) {
  zt_check_not_frozen(x, call)
  schema <- attr(x, "schema", exact = TRUE)
  cols <- unclass(x)
  attributes(cols) <- list(names = names(x))
  n <- .row_names_info(x, 2L)
  rows <- seq_len(n)
  if (!is.null(up$where)) {
    rows <- which(zt_eval(up$where, cols, n) %in% TRUE)
  }
  scoped <- zt_take_rows(cols, rows)
  keys <- lapply(up$by, function(k) zt_recycle_n(zt_eval(k, scoped, length(rows)), length(rows)))
  if (zt_kernel_executor() && zt_reducible(lapply(up$stmts, function(s) s$node))) {
    new <- zt_update_kernel(up, cols, rows, scoped, keys, call)
  } else {
    new <- zt_update_loop(up, cols, rows, scoped, keys, call)
  }
  targets <- zt_update_targets(up)
  # Every new column is checked before any is written (§6.2).
  for (nm in targets) {
    new[[nm]] <- zt_normalise(new[[nm]], schema$fields[[nm]], call)
  }
  rec <- attr(x, "plan", exact = TRUE)
  zt_state$update_seq <- (zt_state$update_seq %||% 0) + 1
  step <- zt_step("update", schema, stmts = up$stmts, where = up$where, by = up$by,
                  token = zt_state$update_seq)
  plan <- zt_plan_record(list(source = list(kind = "table", anonymous = TRUE,
                                            schema = schema, parent = rec),
                              steps = list(step), schema = schema,
                              unknown = rec$unknown))
  status <- .Call(zt_commit, x, match(targets, names(x)), unname(new), plan)
  if (identical(status, 1L)) zt_check_not_frozen(x, call)
  invisible(x)
}

# The primitive `[` makes its result visible, so `x[, a := 1]` at top level
# would print the table. As data.table does, an update arms a one-shot
# flag (D53, D57): only when its bracket is a top-level call (`frames`,
# the frame number of the call `x[...]`, is 1), and holding the token of the update
# step the table's plan record gained, never the table. The task callback
# registered in .onLoad clears it once the top-level expression ends,
# after autoprint, so an update that is not autoprinted leaves nothing
# armed.
zt_state <- new.env(parent = emptyenv())

zt_update_token <- function(x) {
  steps <- attr(x, "plan", exact = TRUE)$steps
  if (length(steps)) steps[[length(steps)]]$token
}

zt_arm_print_skip <- function(x, frames) {
  zt_state$skip_print <- if (identical(frames, 1L)) zt_update_token(x)
}

# Skipped for the table whose last plan step is the armed update, once;
# print() inside a function (frame 2 or more) always prints.
zt_take_print_skip <- function(x, frames) {
  skip <- zt_state$skip_print
  if (is.null(skip) || frames > 2L) return(FALSE)
  if (!identical(zt_update_token(x), skip)) return(FALSE)
  zt_state$skip_print <- NULL
  TRUE
}

zt_clear_print_skip <- function(...) {
  zt_state$skip_print <- NULL
  TRUE
}

# A block with no `:=` whose last statement is `.(...)` is a `select` with
# locals (§6.2): the locals are computed row by row, then the select reads
# them as columns.
zt_block_query <- function(x, block, q, env, call) {
  stmts <- as.list(block)[-1L]
  last <- if (length(stmts)) stmts[[length(stmts)]]
  if (is.null(last) || !is.call(last) || !identical(last[[1L]], as.name("."))) {
    zutable_abort("syntax", paste(
      "a block in the second position is an update, holding `col := value`,",
      "or a select whose last statement is .(...)"
    ), call = call)
  }
  schema <- attr(x, "schema", exact = TRUE)
  cols <- unclass(x)
  attributes(cols) <- list(names = names(x))
  n <- .row_names_info(x, 2L)
  fields <- schema$fields
  for (s in stmts[-length(stmts)]) {
    if (!is.call(s) || !(as.character(s[[1L]]) %in% c("<-", "=")) ||
        !is.symbol(s[[2L]])) {
      zutable_abort("syntax", "a statement of a select block is `name <- value`",
                    call = call)
    }
    name <- as.character(s[[2L]])
    if (name %in% names(schema)) {
      zutable_abort("syntax", sprintf("local `%s` has a column's name", name),
                    call = call)
    }
    cur <- new_schema(unname(fields))
    node <- zt_translate(s[[3L]], cur, env, call)
    if (isTRUE(node$aggregate)) {
      zutable_abort("syntax", "a local of a select block is computed row by row",
                    call = call)
    }
    if (zt_is_lit(node) && is.null(node$type)) {
      zutable_abort("type", sprintf("local `%s` is a bare NA, which has no type", name),
                    call = call)
    }
    cols[[name]] <- zt_recycle_n(zt_eval(node, cols, n), n)
    fields[[name]] <- new_field(name, node$type, isTRUE(node$nullable))
  }
  x2 <- new_zutable(cols, new_schema(unname(fields)), n)
  q$select <- last
  zt_execute(x2, zt_plan_query(x2, q, env, call), call)
}

zt_update_targets <- function(up) {
  unique(vapply(Filter(function(s) s$kind == "set", up$stmts), function(s) s$name, ""))
}

# The statements group by group, each over its group's rows: the reference
# (D29) for zt_update_kernel(), and the route for an r() node.
zt_update_loop <- function(up, cols, rows, scoped, keys, call) {
  groups <- zt_group_rows(zt_group_ids(keys, length(rows)))
  if (!length(keys) && length(rows)) groups <- list(seq_along(rows))
  targets <- zt_update_targets(up)
  new <- cols[targets]
  for (g in groups) {
    if (!length(g)) next
    work <- zt_take_rows(cols, rows[g])
    m <- length(g)
    for (s in up$stmts) {
      v <- zt_eval(s$node, work, m)
      if (zt_nrow_of(v) != 1L && zt_nrow_of(v) != m) {
        zutable_abort("value", sprintf(
          "`%s` gets %d values for %d rows; give one value or one per row written",
          s$name, zt_nrow_of(v), m
        ), call = call)
      }
      v <- zt_recycle_n(v, m)
      work[[s$name]] <- v
      if (s$kind == "set") {
        col <- new[[s$name]]
        if (is.data.frame(col)) col[rows[g], ] <- v else col[rows[g]] <- v
        new[[s$name]] <- col
      }
    }
  }
  new
}

# The statements over all the written rows at once, through the kernel:
# each aggregate is reduced per group (design-kernel 6.5) and gathered back
# to the rows, so a statement is evaluated once, not once per group.
zt_update_kernel <- function(up, cols, rows, scoped, keys, call) {
  m <- length(rows)
  g <- zt_group_ids(keys, m)
  if (!length(keys)) g <- list(id = rep(1L, m), n_groups = as.integer(m > 0L))
  targets <- zt_update_targets(up)
  new <- cols[targets]
  work <- scoped
  for (s in up$stmts) {
    node <- s$node
    if (isTRUE(node$aggregate) && m) {
      pending <- list()
      rewrite <- function(nd) {
        if (identical(nd$kind, "call") && identical(zt_vocab[[nd$fn]]$kind, "aggregate")) {
          nm <- paste0(".zt_agg", length(pending) + 1L)
          pending[[nm]] <<- nd
          return(zt_node("col", name = nm, type = nd$type, nullable = TRUE, aggregate = FALSE))
        }
        if (!is.null(nd$args)) nd$args <- lapply(nd$args, rewrite)
        nd
      }
      node <- rewrite(node)
      aggs <- zt_reduce_aggregates(pending, work, m, g)
      v <- zt_eval(node, c(work, lapply(aggs, zt_take, idx = g$id)), m)
    } else {
      v <- zt_eval(node, work, m)
    }
    if (zt_nrow_of(v) != 1L && zt_nrow_of(v) != m) {
      zutable_abort("value", sprintf(
        "`%s` gets %d values for %d rows; give one value or one per row written",
        s$name, zt_nrow_of(v), m
      ), call = call)
    }
    v <- zt_recycle_n(v, m)
    work[[s$name]] <- v
    if (s$kind == "set") {
      col <- new[[s$name]]
      new[[s$name]] <- zt_assign(col, rows, v)
    }
  }
  new
}
