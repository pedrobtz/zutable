# Materialised tables (design §4.4, §9.1). A zutable is a list of column
# vectors with class c("zutable", "data.frame"), compact row names, and the
# attributes `schema` (whose metadata is the table's, D42) and `properties`
# (§9.2, empty until column properties exist). No external pointer, no
# self-reference, no over-allocation.

zt_class <- c("zutable", "data.frame")

# Build a table from columns already normalised to `schema`. No checks.
new_zutable <- function(cols, schema, n = NULL) {
  if (is.null(n)) {
    n <- if (length(cols)) zt_nrow_of(cols[[1L]]) else 0L
  }
  names(cols) <- names(schema)
  structure(cols, class = zt_class, row.names = c(NA_integer_, -n),
            schema = schema, properties = list())
}

zt_nrow_of <- function(x) {
  if (is.data.frame(x)) .row_names_info(x, 2L) else length(x)
}

#' Create a typed table
#'
#' `zutable()` builds a table from named vectors, recycling only those of
#' length one. Each column's type is inferred from its vector (see
#' [schema()]); [na()] declares a column to be filled later with a typed
#' missing value. `as_zutable()` converts a data frame or a list, inferring
#' the types or checking the columns against `schema`. Row names are not
#' kept.
#'
#' Values enter exactly or not at all: strings are converted to UTF-8, a
#' `POSIXct` with no time zone is given `"UTC"` (it already counts from
#' 1970 in UTC), and a value a type cannot hold, such as a date with a
#' fraction of a day or `NA` in a `not_null()` field, is a
#' `zutable_value_error`.
#'
#' @param ... Named column vectors.
#' @param x A data frame, a list of columns, or a zutable.
#' @param schema A schema from [schema()] to check `x` against, or `NULL`
#'   to infer one.
#' @return A zutable. `is_zutable()` returns `TRUE` or `FALSE`.
#' @export
#' @examples
#' zutable(id = 1:3, name = c("Ada", "Linus", "Grace"), score = NA_real_)
#' as_zutable(data.frame(x = 1:2), schema(x = not_null(int32)))
zutable <- function(...) {
  cols <- list(...)
  call <- sys.call()
  nms <- names(cols) %||% rep("", length(cols))
  if (any(!nzchar(nms))) {
    zutable_abort("schema", "every column needs a name", call = call)
  }
  zt_from_columns(zt_recycle(cols, call), NULL, call)
}

#' @rdname zutable
#' @export
as_zutable <- function(x, schema = NULL) {
  call <- sys.call()
  if (!is.null(schema) && !inherits(schema, "zutable_schema")) {
    zutable_abort("schema", "`schema` must be a schema from schema()",
                  call = call)
  }
  if (is_zutable(x)) {
    zt_validate(x, call)
    if (is.null(schema)) return(x)
    return(conform(x, schema))
  }
  if (is.data.frame(x)) {
    cols <- unclass(x)
    attributes(cols) <- list(names = names(x))
    n <- .row_names_info(x, 2L)
  } else if (is.list(x) && !is.object(x)) {
    cols <- zt_recycle(x, call)
    n <- NULL
  } else {
    zutable_abort("schema", "as_zutable() takes a data frame or a list",
                  call = call)
  }
  zt_from_columns(cols, schema, call, n = n)
}

#' @rdname zutable
#' @export
is_zutable <- function(x) inherits(x, "zutable")

# Recycle length-one columns to the common length; any other mismatch is
# an error.
zt_recycle <- function(cols, call) {
  if (!length(cols)) return(cols)
  lens <- vapply(cols, zt_nrow_of, 0L)
  long <- unique(lens[lens != 1L])
  if (length(long) > 1L) {
    zutable_abort("schema", sprintf(
      "columns have lengths %s; only length-one columns are recycled",
      paste(sort(unique(lens)), collapse = ", ")
    ), call = call)
  }
  n <- if (length(long)) long else 1L
  for (i in which(lens == 1L & n != 1L)) {
    x <- cols[[i]]
    cols[[i]] <- if (is.data.frame(x)) x[rep(1L, n), , drop = FALSE] else
      rep(x, length.out = n)
  }
  cols
}

zt_from_columns <- function(cols, schema, call, n = NULL) {
  nms <- names(cols) %||% rep("", length(cols))
  if (anyNA(nms) || any(!nzchar(nms)) || anyDuplicated(nms)) {
    zutable_abort("schema", "column names must be unique and non-empty",
                  call = call)
  }
  if (is.null(schema)) {
    fields <- lapply(seq_along(cols), function(i) {
      new_field(nms[[i]], infer_type(cols[[i]], nms[[i]], call))
    })
    schema <- new_schema(fields)
  } else {
    zt_check_columns(cols, schema, call)
  }
  for (i in seq_along(cols)) {
    cols[[i]] <- zt_normalise(cols[[i]], schema$fields[[i]], call)
  }
  if (is.null(n)) {
    n <- if (length(cols)) zt_nrow_of(cols[[1L]]) else 0L
  }
  new_zutable(cols, schema, n)
}

# Columns against a schema: the same names in the same order, and each
# vector valid for its type. Every mismatch is listed.
zt_check_columns <- function(cols, schema, call) {
  problems <- zt_schema_problems(names(cols), cols, schema)
  if (length(problems)) {
    zutable_abort("schema", paste0(
      "the columns do not match the schema:\n",
      paste0("* ", problems, collapse = "\n")
    ), problems = problems, call = call)
  }
}

zt_schema_problems <- function(nms, cols, schema) {
  want <- names(schema)
  problems <- character()
  for (n in setdiff(want, nms)) {
    problems <- c(problems, sprintf("column `%s` is missing", n))
  }
  for (n in setdiff(nms, want)) {
    problems <- c(problems, sprintf("column `%s` is not in the schema", n))
  }
  common <- intersect(want, nms)
  if (!identical(nms[nms %in% common], want[want %in% common])) {
    problems <- c(problems, "the columns are in another order")
  }
  for (n in common) {
    p <- vector_problem(cols[[n]], schema$fields[[n]]$type)
    if (!is.null(p)) {
      problems <- c(problems, sprintf(
        "column `%s` is not %s: %s", n, format(schema$fields[[n]]$type), p
      ))
    }
  }
  problems
}

# Bring a valid vector to its stored form, and refuse values its type
# cannot hold exactly.
zt_normalise <- function(x, field, call) {
  type <- field$type
  what <- field$name
  if (is.character(x) && !is.object(x)) {
    x <- enc2utf8(x)
  }
  if (identical(type$id, "timestamp") && !identical(type$unit, "ns")) {
    attr(x, "tzone") <- type$tz %||% "UTC"
    us <- posixct_to_us(x, what, call)
    step <- switch(type$unit, s = 1e6, ms = 1e3, us = 1)
    if (step > 1 && any(us %% step != 0, na.rm = TRUE)) {
      zutable_abort("value", sprintf(
        "column `%s` is timestamp(\"%s\"): a value has a finer part",
        what, type$unit
      ), call = call)
    }
  }
  if (identical(type$id, "date") &&
      any(unclass(x) != trunc(unclass(x)), na.rm = TRUE)) {
    zutable_abort("value", sprintf(
      "column `%s` is date: a value has a fraction of a day", what
    ), call = call)
  }
  if (identical(type$id, "struct")) {
    for (n in names(type$fields)) {
      x[[n]] <- zt_normalise(x[[n]], type$fields[[n]], call)
    }
  }
  if (!field$nullable && zt_any_missing(x)) {
    zutable_abort("value", sprintf(
      "column `%s` is not_null but holds a missing value", what
    ), call = call)
  }
  x
}

zt_any_missing <- function(x) {
  if (is.data.frame(x)) {
    return(any(zt_struct_missing(x)))
  }
  any(zt_is_missing(x))
}

# Missing elements: NA for atomic vectors, NULL for list elements.
zt_is_missing <- function(x) {
  if (is.list(x) && !is.data.frame(x) && !is.object(x)) {
    return(vapply(x, is.null, NA))
  }
  is.na(x)
}

# A struct row is missing when every field of it is.
zt_struct_missing <- function(x) {
  if (!length(x)) return(logical(zt_nrow_of(x)))
  Reduce(`&`, lapply(x, zt_is_missing))
}

# The schema check on entry (§9.1): one pass over the columns, so a stale
# schema is never believed.
zt_validate <- function(x, call = NULL) {
  s <- attr(x, "schema", exact = TRUE)
  if (!inherits(s, "zutable_schema")) {
    zutable_abort("schema", "this zutable has no schema", call = call)
  }
  cols <- unclass(x)
  problems <- zt_schema_problems(names(x), cols, s)
  n <- .row_names_info(x, 2L)
  lens <- vapply(cols, zt_nrow_of, 0L)
  if (any(lens != n)) {
    problems <- c(problems, "a column's length differs from the row count")
  }
  if (length(problems)) {
    zutable_abort("schema", paste0(
      "this zutable's columns no longer match its schema:\n",
      paste0("* ", problems, collapse = "\n")
    ), problems = problems, call = call)
  }
  invisible(x)
}

#' Check a table against a schema
#'
#' `conform()` returns `x` as a zutable of schema `s` when its columns match
#' it, and otherwise raises a `zutable_schema_error` that lists every
#' mismatch: a missing column, an extra one, another order, a column of the
#' wrong type. `NA` in a `not_null()` field is a `zutable_value_error`.
#' `metadata()` returns a table's own key-value pairs.
#'
#' @param x A zutable or a data frame.
#' @param s A schema from [schema()].
#' @return `conform()` a zutable; `metadata()` a named character vector.
#' @export
#' @examples
#' conform(data.frame(id = 1:2), schema(id = not_null(int32)))
conform <- function(x, s) {
  call <- sys.call()
  if (!inherits(s, "zutable_schema")) {
    zutable_abort("schema", "`s` must be a schema from schema()", call = call)
  }
  if (is_zutable(x)) {
    zt_validate(x, call)
  } else if (!is.data.frame(x)) {
    zutable_abort("schema", "conform() takes a table", call = call)
  }
  cols <- unclass(x)
  attributes(cols) <- list(names = names(x))
  zt_from_columns(cols, s, call, n = .row_names_info(x, 2L))
}

#' @rdname conform
#' @export
metadata <- function(x) {
  schema_of(x)$metadata
}

#' @export
as.data.frame.zutable <- function(x, ...) {
  cols <- unclass(x)
  n <- .row_names_info(x, 2L)
  attributes(cols) <- list(names = names(x))
  structure(cols, class = "data.frame", row.names = c(NA_integer_, -n))
}

# --- printing ----------------------------------------------------------------

#' @export
print.zutable <- function(x, n = 10L, ...) {
  zt_validate(x)
  s <- attr(x, "schema")
  rows <- .row_names_info(x, 2L)
  cat(sprintf("<zutable> %d row%s x %d column%s\n", rows,
              if (rows == 1L) "" else "s", length(s),
              if (length(s) == 1L) "" else "s"))
  if (!length(s)) return(invisible(x))
  show <- min(rows, n)
  idx <- seq_len(show)
  cells <- lapply(seq_along(s$fields), function(i) {
    col <- x[[i]]
    c(names(s)[[i]], paste0("<", format_field_type(s$fields[[i]]), ">"),
      zt_format_cells(zt_take(col, idx)))
  })
  rn <- c("", "", as.character(idx))
  table <- c(list(rn), cells)
  widths <- vapply(table, function(c) max(nchar(c, type = "width")), 0L)
  for (r in seq_along(rn)) {
    line <- vapply(seq_along(table), function(j) {
      formatC(table[[j]][[r]], width = widths[[j]],
              flag = if (j == 1L) "" else "-")
    }, "")
    cat(sub(" +$", "", paste(line, collapse = " ")), "\n", sep = "")
  }
  if (rows > show) {
    cat(sprintf("# ... %d more row%s\n", rows - show,
                if (rows - show == 1L) "" else "s"))
  }
  invisible(x)
}

zt_take <- function(col, idx) {
  if (is.data.frame(col)) col[idx, , drop = FALSE] else col[idx]
}

zt_format_cells <- function(col) {
  if (is.data.frame(col)) {
    return(rep("<struct>", zt_nrow_of(col)))
  }
  if (is.list(col) && !is.object(col)) {
    return(vapply(col, function(e) {
      if (is.null(e)) "NULL" else sprintf("<%s[%d]>", class(e)[[1L]],
                                          length(e))
    }, ""))
  }
  out <- format(col, trim = TRUE)
  out[is.na(col)] <- "NA"
  as.character(out)
}
