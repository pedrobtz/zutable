# The bracket (design §5). One bracket is one SQL statement. Its clauses
# are named arguments, captured unevaluated, translated into typed
# expressions (R/expr.R), planned (R/plan.R) and run by the reference
# executor (R/execute.R). The value forms of §5.5 keep base R's meaning.

#' Query a zutable with SQL's clauses
#'
#' The bracket takes SQL's clauses as named arguments over bare column
#' names: `where`, `select`, `order`, `limit` and `distinct`, run in SQL's
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
#' * A name that is not a column is a variable of the caller, and enters
#'   as a constant; `..name` forces the variable when a column has the same
#'   name.
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
#' @param by,update,having Clauses that later stages of the package add.
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
  where_e <- ex$where %||% ex$i
  if (!is.null(where_e) && !zt_is_clause(where_e, cols)) {
    # A value form in the first position beside clauses.
    zutable_abort("syntax", paste(
      "beside other clauses the first position is a condition on the",
      "columns; select rows by number in a bracket of their own"
    ), call = call)
  }
  select_e <- ex$select %||% ex$j
  q <- list(where = where_e, select = select_e, update = ex$update,
            by = ex$by, having = ex$having, order = ex$order,
            limit = ex$limit, distinct = distinct)
  for (k in c("update", "by", "having")) {
    if (!is.null(q[[k]])) {
      zutable_abort("syntax", sprintf(
        "the `%s` clause is not implemented yet", k
      ), call = call)
    }
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
    any(c(".N", ".all") %in% nms)
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
