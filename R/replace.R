# The value forms of the bracket (design §5.5) and the base replacement
# functions (§6.5). Base functions index a data frame with values, and
# those forms keep their base meaning, so head(), subset(), split(),
# unique() and friends work. No route changes a table's schema.

#' Replace values in a zutable
#'
#' Replacing values (`x$col <- v`, `x[["col"]] <- v`, `x[i, "col"] <- v`)
#' needs the column to exist and `v` to fit its type: exactly, or as a
#' literal that is exactly representable there, such as `1` in an `int32`
#' column. Renaming, and assigning `NULL`, are `zutable_schema_error`s, so
#' no replacement changes a table's schema. Selecting rows and columns by
#' value is the bracket's: see [zutable-bracket].
#'
#' @param x A zutable.
#' @param i,j Rows and columns, as for a data frame.
#' @param name,value The column and its new values.
#' @return A zutable.
#' @examples
#' x <- zutable(id = 1:3, score = c(1.5, 2, 2.5))
#' x$id <- 7
#' x[2, "score"] <- 0
#' x
#' @name zutable-indexing
#' @examples
#' x <- zutable(id = 1:3, score = c(1.5, 2, 2.5))
#' x[2:3, ]
#' x[, "score"]
#' x$id <- 7
#' x
NULL

# Whether code running in `env` knows zutable's bracket (D43, after
# data.table's cedta()): the global environment, zutable itself, and
# namespaces that import zutable. Base R's own namespaces do not, and index
# a zutable as the data frame it is: one position is columns, and a
# replacement acts on a plain data frame copy.
zt_aware <- function(env) {
  top <- topenv(env)
  if (identical(top, globalenv()) || !isNamespace(top)) {
    return(TRUE)
  }
  name <- getNamespaceName(top)
  name == "zutable" || "zutable" %in% names(getNamespaceImports(top))
}

zt_plain <- function(x) {
  attr(x, "schema") <- NULL
  attr(x, "properties") <- NULL
  class(x) <- "data.frame"
  x
}

zt_row_index <- function(i, n, call) {
  if (is.character(i) || is.factor(i)) {
    zutable_abort("syntax", paste(
      "a character vector cannot select rows; write a condition such as",
      "`x[name == \"a\"]`, or select columns with `x[, \"a\"]`"
    ), call = call)
  }
  if (is.logical(i) && !is.object(i)) {
    # Recycled, as base R does; longer than the table is refused.
    if (length(i) > n) {
      zutable_abort("syntax", sprintf(
        "a logical row selection has length %d, more than the %d rows",
        length(i), n
      ), call = call)
    }
    return(which(rep_len(i, n) %in% TRUE))
  }
  if (is.numeric(i) && !is.object(i)) {
    idx <- seq_len(n)[i]
    return(idx)
  }
  zutable_abort("syntax", "rows are selected by an integer or logical vector",
                call = call)
}

zt_col_index <- function(j, nms, call) {
  if (is.character(j) && !is.object(j)) {
    missing_cols <- setdiff(j, nms)
    if (length(missing_cols) || anyNA(j)) {
      zutable_abort("schema", sprintf("column `%s` does not exist",
                                      c(missing_cols, NA)[[1L]]), call = call)
    }
    idx <- match(j, nms)
  } else if (is.logical(j) && !is.object(j)) {
    if (length(j) > length(nms)) {
      zutable_abort("syntax", "a logical column selection is longer than the columns",
                    call = call)
    }
    idx <- which(rep_len(j, length(nms)) %in% TRUE)
  } else if (is.numeric(j) && !is.object(j)) {
    idx <- seq_along(nms)[j]
    if (anyNA(idx)) {
      zutable_abort("schema", "a column index is out of range", call = call)
    }
  } else {
    zutable_abort("syntax",
                  "columns are selected by a character, integer or logical vector",
                  call = call)
  }
  if (anyDuplicated(idx)) {
    zutable_abort("schema", "a column is selected twice", call = call)
  }
  idx
}

zt_subset <- function(x, rows, cols, call) {
  s <- attr(x, "schema")
  data <- unclass(x)
  attributes(data) <- list(names = names(x))
  if (!is.null(cols)) {
    data <- data[cols]
    s <- new_schema(s$fields[cols], s$metadata)
  }
  n <- .row_names_info(x, 2L)
  if (!is.null(rows)) {
    data <- lapply(data, zt_take, idx = rows)
    n <- length(rows)
    # Rows past the end, or NA, are missing rows, which a not_null column
    # cannot hold.
    if (anyNA(rows)) {
      for (k in seq_along(data)) {
        f <- s$fields[[k]]
        if (!f$nullable) {
          zutable_abort("value", sprintf(
            "column `%s` is not_null; a missing row index would put NA in it",
            f$name
          ), call = call)
        }
      }
    }
  }
  new_zutable(data, s, n)
}

# --- replacement -------------------------------------------------------------

# `value` as a vector of `field`'s type, of length `n`, or an error. A
# value already of the type is kept; a literal is converted only when it is
# exactly representable (§4.3): integers into float64, whole doubles into
# int32, all-NA logicals into any type, strings into an enum's levels.
zt_fit <- function(value, field, n, call) {
  type <- field$type
  what <- field$name
  if (is.null(value)) {
    zutable_abort("schema", sprintf(
      "column `%s` cannot be removed; a table's columns are fixed", what
    ), call = call)
  }
  len <- zt_nrow_of(value)
  if (len != n && len != 1L) {
    zutable_abort("value", sprintf(
      "column `%s`: %d values for %d rows; give one value or one per row",
      what, len, n
    ), call = call)
  }
  value <- zt_entry_column(value, sprintf("column `%s`", what), call)
  fitted <- zt_fit_literal(value, type, call)
  if (is.null(fitted) || !is.null(vector_problem(fitted, type))) {
    zutable_abort("schema", sprintf(
      "column `%s` is %s; the value would make it %s", what, format(type),
      zt_describe_value(value)
    ), call = call)
  }
  if (len == 1L && n != 1L) fitted <- zt_take(fitted, rep(1L, n))
  zt_normalise(fitted, field, call)
}

zt_describe_value <- function(value) {
  t <- tryCatch(format(infer_type_raw(value, "value", NULL)),
                error = function(e) class(value)[[1L]])
  t
}

zt_fit_literal <- function(value, type, call = NULL) {
  value <- zt_entry_column(value)
  if (is.null(vector_problem(value, type))) {
    return(value)
  }
  if (is.logical(value) && !is.object(value) && all(is.na(value))) {
    na <- tryCatch(na_of(type), error = function(e) NULL)
    if (is.null(na)) return(NULL)
    return(zt_take(na, rep(1L, length(value))))
  }
  switch(type$id,
    float64 = if (is.integer(value) && !is.object(value)) as.double(value),
    int32 = if (is.double(value) && !is.object(value)) {
      ok <- is.na(value) | (is.finite(value) & value == trunc(value) &
                              abs(value) <= .Machine$integer.max)
      if (all(ok) && !any(is.nan(value))) as.integer(value)
    },
    # int32 widens to int64 (§4.3); its vector lives in zuint.
    int64 = if (is.integer(value) && !is.object(value)) {
      zt_require_type_package(type, call)
      zt_int32_to_int64(value)
    },
    enum = if (is.character(value) && !is.object(value) &&
               all(is.na(value) | value %in% type$levels)) {
      factor(value, levels = type$levels)
    },
    NULL
  )
}

zt_column_position <- function(x, name, call) {
  nms <- names(x)
  if (is.character(name) && length(name) == 1L && !is.na(name)) {
    pos <- match(name, nms)
  } else if (is.numeric(name) && length(name) == 1L && !is.na(name)) {
    pos <- if (name >= 1 && name <= length(nms)) as.integer(name) else NA
  } else {
    zutable_abort("syntax", "one column is replaced at a time", call = call)
  }
  if (is.na(pos)) {
    zutable_abort("schema", sprintf(
      "column `%s` does not exist; a table's columns are fixed",
      as.character(name)
    ), call = call)
  }
  pos
}

zt_set_column <- function(x, pos, value) {
  attrs <- attributes(x)
  data <- unclass(x)
  data[[pos]] <- value
  attributes(data) <- attrs
  attr(data, "properties") <- list()
  # A value written outside the plan: its lineage is unknown, not stale
  # (§8.5 rule 6).
  rec <- attr(data, "plan", exact = TRUE)
  if (!is.null(rec)) {
    rec$unknown <- union(rec$unknown, names(x)[[pos]])
    attr(data, "plan") <- rec
  }
  data
}

#' @rdname zutable-indexing
#' @export
`$<-.zutable` <- function(x, name, value) {
  call <- sys.call()
  if (!zt_aware(parent.frame())) {
    x <- zt_plain(x)
    return(NextMethod())
  }
  zt_check_not_frozen(x, call)
  zt_validate(x, call)
  pos <- zt_column_position(x, name, call)
  f <- attr(x, "schema")$fields[[pos]]
  zt_set_column(x, pos, zt_fit(value, f, .row_names_info(x, 2L), call))
}

#' @rdname zutable-indexing
#' @export
`[[<-.zutable` <- function(x, i, j, value) {
  call <- sys.call()
  if (!zt_aware(parent.frame())) {
    x <- zt_plain(x)
    return(NextMethod())
  }
  zt_check_not_frozen(x, call)
  zt_validate(x, call)
  if (!missing(j)) {
    # x[[i, j]] <- v: one cell.
    x[i, j] <- value
    return(x)
  }
  pos <- zt_column_position(x, i, call)
  f <- attr(x, "schema")$fields[[pos]]
  zt_set_column(x, pos, zt_fit(value, f, .row_names_info(x, 2L), call))
}

#' @rdname zutable-indexing
#' @export
`[<-.zutable` <- function(x, i, j, value) {
  call <- sys.call()
  if (!zt_aware(parent.frame())) {
    x <- zt_plain(x)
    return(NextMethod())
  }
  zt_check_not_frozen(x, call)
  zt_validate(x, call)
  n <- .row_names_info(x, 2L)
  if (nargs() < 4L) {
    # x[j] <- value: columns, as base R reads it.
    cols <- if (missing(i)) seq_along(x) else zt_col_index(i, names(x), call)
    rows <- NULL
  } else {
    rows <- if (missing(i)) NULL else zt_row_index(i, n, call)
    cols <- if (missing(j)) seq_along(x) else zt_col_index(j, names(x), call)
  }
  if (!is.null(rows) && anyNA(rows)) {
    zutable_abort("value", "a row index is out of range", call = call)
  }
  values <- if (is.list(value) && !is.object(value) || is.data.frame(value)) {
    if (length(value) == length(cols)) as.list(value) else
      if (length(value) == 1L) rep(as.list(value), length(cols)) else
        zutable_abort("value", "one value per column replaced, or one for all",
                      call = call)
  } else {
    rep(list(value), length(cols))
  }
  s <- attr(x, "schema")
  for (k in seq_along(cols)) {
    pos <- cols[[k]]
    f <- s$fields[[pos]]
    if (is.null(rows)) {
      new <- zt_fit(values[[k]], f, n, call)
    } else {
      part <- zt_fit(values[[k]], f, length(rows), call)
      new <- zt_normalise(zt_assign(x[[pos]], rows, part), f, call)
    }
    x <- zt_set_column(x, pos, new)
  }
  x
}

#' @export
`names<-.zutable` <- function(x, value) {
  # Refused in every context, base R's included: a rename changes the
  # schema whoever asks for it (colnames<- reaches here from base).
  zutable_abort("schema", paste(
    "a table's column names are part of its schema and cannot change;",
    "select into a new table instead"
  ), call = sys.call())
}

#' @export
`dimnames<-.zutable` <- function(x, value) {
  # Column names unchanged: only row names, which a zutable does not keep.
  if (is.list(value) && length(value) == 2L &&
      identical(as.character(value[[2L]]), names(x))) {
    return(x)
  }
  zutable_abort("schema", paste(
    "a table's column names are part of its schema and cannot change;",
    "select into a new table instead"
  ), call = sys.call())
}

#' @export
`row.names<-.zutable` <- function(x, value) {
  # Row names are not kept (§4.4): the compact form stays.
  x
}
