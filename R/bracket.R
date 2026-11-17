# The bracket (design §5). One bracket is one SQL statement. Its clauses
# are named arguments, captured unevaluated, translated into typed
# expressions (R/expr.R), planned (R/plan.R) and run by the reference
# executor (R/execute.R). The value forms of §5.5 keep base R's meaning.

#' Query a zutable with SQL's clauses
#'
#' The bracket takes SQL's clauses as named arguments over bare column
#' names: `where`, `select`, `by`, `having`, `order`, `limit` and
#' `distinct`, run in SQL's
#' logical order whatever order they are written in. The first two
#' positions are `where` and `select`, as in data.table:
#' `x[px > 0, .(id, notional = px * qty)]`. A bracket always returns a
#' table, and its schema is known, and every type error raised, before any
#' data is read.
#'
#' * `select` is `.(...)` of bare columns, `name = expression`, `.all` for
#'   every input column, and `-name` after `.all` to leave one out. A
#'   computed element needs a name.
#' * `order` is an expression or `.(...)` of them, `desc(x)` reversing one.
#'   It may name result columns and, unless `distinct`, input columns. It
#'   is stable, and `NA` sorts last.
#' * `limit` is a row count, applied after `order`.
#' * With `by`, or an aggregate in `select`, the query aggregates: each
#'   element of `select` is an aggregate or an expression of the `by`
#'   keys. Without `by` it is a one-row summary. `having` filters groups.
#' * `over(aggregate, by = keys)` computes an aggregate per partition
#'   without collapsing rows, for a `select` that keeps `.all`.
#' * A name that is not a column is a variable of the caller, and enters
#'   as a constant; `..name` forces the variable when a column has the same
#'   name. `.col(name)` is the column whose name a variable holds.
#'
#' A position that mentions no column is a value form instead: an integer
#' or logical vector selects rows and a character, integer or logical
#' vector selects columns, as for a data frame.
#'
#' @param x A zutable.
#' @param i,where Rows to keep: a condition (or, as a value form, an
#'   integer or logical vector).
#' @param j,select Columns of the result: `.(...)` (or, as a value form, a
#'   character, integer or logical vector).
#' @param by Groups: a column, `.(a, b)`, `.(name = expression)` or a
#'   character vector of column names. `NA` is a group, and groups come in
#'   order of first appearance, `by` columns first in the result.
#' @param having A condition on the groups, naming result columns or
#'   aggregating input ones.
#' @param update An update: `col := value` or a block of them; see
#'   [zutable-update].
#' @param order Sort keys.
#' @param limit A row count.
#' @param distinct `TRUE` to keep one of each distinct result row.
#' @param drop Ignored: a bracket always returns a table.
#' @param ... Not used.
#' @return A zutable.
#' @name zutable-bracket
#' @examples
#' x <- zutable(id = 1:4, px = c(10.5, 11, 20, 7), qty = c(100L, 50L, 10L, 200L))
#' x[px > 10, .(id, notional = px * qty)]
#' x[select = .(.all, -qty), order = desc(px), limit = 2]
NULL

zt_clause_names <- c("where", "select", "update", "by", "having", "order",
                     "limit", "distinct")

#' @rdname zutable-bracket
#' @export
`[.zutable` <- function(x, i, j, by, ..., where, select, update, having,
                        order, limit, distinct = FALSE, drop = FALSE) {
  call <- sys.call()
  env <- parent.frame()
  zt_state$skip_print <- NULL
  zt_validate(x, call)
  if (!zt_aware(env)) {
    # Base R's own code indexes a zutable as a data frame (D43).
    return(zt_value_bracket(x, i, j, nargs() - !missing(drop), call, aware = FALSE))
  }
  if (...length()) {
    zutable_abort("syntax", sprintf(
      "the bracket has no argument `%s`; its clauses are %s",
      names(list(...))[[1L]] %||% "", paste(zt_clause_names, collapse = ", ")
    ), call = call)
  }
  ex <- list(
    i = if (!missing(i)) substitute(i),
    j = if (!missing(j)) substitute(j),
    by = if (!missing(by)) substitute(by),
    where = if (!missing(where)) substitute(where),
    select = if (!missing(select)) substitute(select),
    update = if (!missing(update)) substitute(update),
    having = if (!missing(having)) substitute(having),
    order = if (!missing(order)) substitute(order),
    limit = if (!missing(limit)) substitute(limit)
  )
  cols <- names(x)
  clause <- function(e) !is.null(e) && zt_is_clause(e, cols)
  named <- !all(vapply(ex[c("where", "select", "update", "by", "having",
                            "order", "limit")], is.null, NA)) || !isFALSE(distinct)
  positional_clause <- clause(ex$i) || clause(ex$j) || !is.null(ex$by)
  if (!named && !positional_clause) {
    n_args <- nargs() - !missing(drop)
    return(zt_value_bracket(x, i, j, n_args, call, aware = TRUE))
  }
  # D28: a clause given both by position and by name is an error.
  if (!is.null(ex$i) && !is.null(ex$where)) {
    zutable_abort("syntax", paste(
      "`where` is given twice, by position and by name; write",
      "x[cond, ...] or x[where = cond, ...]"
    ), call = call)
  }
  if (!is.null(ex$j) && (!is.null(ex$select) || !is.null(ex$update))) {
    zutable_abort("syntax", paste(
      "the second position is `select` (or `update`); it is given twice.",
      "Write x[, .(...)] or x[select = .(...)]"
    ), call = call)
  }
  if (!is.null(ex$select) && !is.null(ex$update)) {
    zutable_abort("syntax", paste(
      "one bracket is a query or an update, not both; chain two brackets:",
      "x[...][...]"
    ), call = call)
  }
  # D28 (kept by D55): the first position is `where`; an update or a
  # block there is a syntax error that shows the supported spelling.
  if (!is.null(ex$i) && is.call(ex$i) &&
      (identical(ex$i[[1L]], as.name(":=")) || identical(ex$i[[1L]], as.name("{")))) {
    zutable_abort("syntax", paste(
      "an update goes in the second position: x[, col := value] or",
      "x[cond, { a := ...; b := ... }]"
    ), call = call)
  }
  where_e <- ex$where %||% ex$i
  if (!is.null(where_e) && !zt_is_clause(where_e, cols)) {
    # A value form in the first position beside clauses.
    zutable_abort("syntax", paste(
      "beside other clauses the first position is a condition on the",
      "columns; select rows by number in a bracket of their own"
    ), call = call)
  }
  select_e <- ex$select %||% ex$j
  q <- list(where = where_e, select = if (!zt_is_update(select_e %||% quote(x))) select_e,
            update = ex$update,
            by = ex$by, having = ex$having, order = ex$order,
            limit = ex$limit, distinct = distinct)
  upd <- q$update %||% (if (!is.null(select_e) && zt_is_update(select_e)) select_e)
  if (!is.null(upd)) {
    if (!is.null(q$having) || !is.null(q$order) || !is.null(q$limit) ||
        !isFALSE(q$distinct)) {
      zutable_abort("syntax", paste(
        "an update takes `where` and `by` only; query the result in a",
        "bracket of its own"
      ), call = call)
    }
    if (!zt_is_update(upd)) {
      zutable_abort("syntax", "`update` is `col := value` or a block of them",
                    call = call)
    }
    up <- zt_plan_update(x, upd, where_e, q$by, env, call)
    out <- zt_run_update(x, up, call)
    frames <- sys.nframe()
    zt_arm_print_skip(out, frames)
    return(invisible(out))
  }
  if (!is.null(select_e) && is.call(select_e) && identical(select_e[[1L]], as.name("{"))) {
    q$select <- NULL
    return(zt_block_query(x, select_e, q, env, call))
  }
  plan <- zt_plan_query(x, q, env, call)
  zt_execute(x, plan, call)
}

# Whether a captured position is a clause: it is `.()`, a `{` block, or
# mentions a column. Anything else is a value form.
zt_is_clause <- function(e, cols) {
  if (is.call(e) && (identical(e[[1L]], as.name(".")) ||
                     identical(e[[1L]], as.name("{")) ||
                     identical(e[[1L]], as.name(":=")))) {
    return(TRUE)
  }
  nms <- all.names(e)
  zt_mentions_column(e, cols) ||
    any(startsWith(nms, "..") & nchar(nms) > 2L) ||
    any(c(".N", ".all", ".col") %in% nms)
}

# The value forms of §5.5, as Stage 2 gave them. `aware` is FALSE inside
# base R, where one position selects columns.
zt_value_bracket <- function(x, i, j, n_args, call, aware) {
  rows <- NULL
  cols <- NULL
  if (n_args <= 2L) {
    if (!missing(i)) {
      if (aware) {
        rows <- zt_row_index(i, .row_names_info(x, 2L), call)
      } else {
        cols <- zt_col_index(i, names(x), call)
      }
    }
  } else {
    if (!missing(i)) rows <- zt_row_index(i, .row_names_info(x, 2L), call)
    if (!missing(j)) cols <- zt_col_index(j, names(x), call)
  }
  zt_subset(x, rows, cols, call)
}
