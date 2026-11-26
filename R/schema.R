# Fields and schemas (design §4.2). A field is a name, a type, a nullable
# flag and key-value metadata; a schema is an ordered set of uniquely named
# fields plus table metadata. Both are plain lists with a class, so two
# schemas compare with identical().

new_field <- function(name, type, nullable = TRUE, metadata = character()) {
  structure(
    list(name = name, type = type, nullable = nullable, metadata = metadata),
    class = "zutable_field"
  )
}

new_schema <- function(fields = list(), metadata = character()) {
  names(fields) <- vapply(fields, function(f) f$name, "")
  structure(list(fields = fields, metadata = metadata),
            class = "zutable_schema")
}

check_metadata <- function(metadata, what, call = NULL) {
  if (is.null(metadata)) {
    return(character())
  }
  nms <- names(metadata)
  if (!is.character(metadata) || is.null(nms) || anyNA(metadata) ||
      anyNA(nms) || any(!nzchar(nms)) || anyDuplicated(nms)) {
    zutable_abort("schema", sprintf(
      "%s metadata must be a character vector with unique, non-empty names",
      what
    ), call = call)
  }
  # Stored without other attributes, so identical() compares content.
  out <- as.vector(metadata)
  names(out) <- nms
  out
}

# A captured field expression: `not_null(T)`, `field(T, ...)`, or a type.
parse_field <- function(expr, name, env, call = NULL) {
  if (is.call(expr) && is.symbol(expr[[1L]])) {
    fn <- as.character(expr[[1L]])
    if (fn == "not_null") {
      if (length(expr) != 2L) {
        zutable_abort("type", "not_null() takes one type", call = call)
      }
      f <- parse_field(expr[[2L]], name, env, call)
      f$nullable <- FALSE
      return(f)
    }
    if (fn == "field") {
      args <- as.list(match.call(field, expr))[-1L]
      if (is.null(args$type)) {
        zutable_abort("type", "field() needs a type", call = call)
      }
      f <- parse_field(args$type, name, env, call)
      if (!is.null(args$nullable)) {
        nullable <- eval(args$nullable, env)
        if (!is.logical(nullable) || length(nullable) != 1L ||
            is.na(nullable)) {
          zutable_abort("type", "field() nullable must be TRUE or FALSE",
                        call = call)
        }
        f$nullable <- f$nullable && nullable
      }
      if (!is.null(args$metadata)) {
        f$metadata <- check_metadata(eval(args$metadata, env), "field", call)
      }
      return(f)
    }
  }
  if (!is.call(expr) && !is.symbol(expr) && inherits(expr, "zutable_field")) {
    expr$name <- name
    return(expr)
  }
  if (is.symbol(expr)) {
    # A caller variable holding a field.
    value <- tryCatch(eval(expr, env), error = function(e) NULL)
    if (inherits(value, "zutable_field")) {
      value$name <- name
      return(value)
    }
  }
  new_field(name, parse_type(expr, env, call))
}

#' Fields and schemas
#'
#' `schema()` builds a schema from named fields, each a type such as `int32`,
#' `decimal(18, 4)` or `list(string)`, or the fields made by `field()` and
#' `not_null()`. Called with one unnamed argument it returns the schema of
#' that table instead: a data frame's is inferred from its columns.
#'
#' Type names are read only inside these functions (and [na()]); they are
#' not R objects. A string is accepted wherever a type is, as is a variable
#' holding a type or a string. The types are:
#'
#' * `bool`, `int32`, `int64`, `float64`, `string`, `date`, `binary`;
#' * `timestamp(unit, tz)`, with `unit` one of `"s"`, `"ms"`, `"us"` and
#'   `"ns"` and `tz` a zone name, or `NULL` for a time without a zone;
#'   bare `timestamp` is `timestamp("us", "UTC")`;
#' * `decimal(precision, scale)`, `enum(levels)`, `list(type)`,
#'   `struct(name = type, ...)`;
#' * `r_class("cls")`, any S3 vector held as it is, and `extension(name)`,
#'   a class registered with [register_extension_type()].
#'
#' `int8`, `int16` and `float32` read as `int32` and `float64`, which is
#' exact. `int64` needs the 'zuint' package, `decimal` the 'decimal'
#' package, and `timestamp("ns")` the 'zutempo' package; without them the
#' type is a `zutable_type_error`.
#'
#' A `POSIXct` with no time zone is an instant shown in local time, and is
#' typed `timestamp("us", "UTC")`, so the type of a vector never depends on
#' the session (design D38).
#'
#' @param ... Named fields, or one table.
#' @param .metadata Table metadata, a named character vector.
#' @param type A type, as in `schema()`.
#' @param nullable Whether the field may hold `NA`.
#' @param metadata Field metadata, a named character vector.
#' @return `schema()` a `zutable_schema`; `field()` and `not_null()` a
#'   `zutable_field`.
#' @export
#' @examples
#' s <- schema(
#'   id   = not_null(int32),
#'   px   = field(float64, metadata = c(unit = "USD")),
#'   day  = date,
#'   tags = list(string)
#' )
#' s
#' schema(data.frame(x = 1:3, y = c("a", "b", "c")))
schema <- function(..., .metadata = NULL) {
  exprs <- as.list(substitute(list(...)))[-1L]
  env <- parent.frame()
  call <- sys.call()
  nms <- zt_enter_strings(names(exprs) %||% rep("", length(exprs)), "the field names", call)

  if (length(exprs) == 1L && !nzchar(nms[[1L]]) && is.null(.metadata)) {
    return(schema_of(eval(exprs[[1L]], env), call))
  }
  if (any(!nzchar(nms))) {
    zutable_abort("schema", "every field of a schema needs a name",
                  call = call)
  }
  if (anyDuplicated(nms)) {
    zutable_abort("schema", sprintf(
      "field names must be unique; `%s` is repeated", nms[anyDuplicated(nms)]
    ), call = call)
  }
  fields <- lapply(seq_along(exprs), function(i) {
    parse_field(exprs[[i]], nms[[i]], env, call)
  })
  new_schema(fields, check_metadata(.metadata, "table", call))
}

#' @rdname schema
#' @export
field <- function(type, nullable = TRUE, metadata = NULL) {
  f <- parse_field(substitute(type), "", parent.frame(), sys.call())
  if (!is.logical(nullable) || length(nullable) != 1L || is.na(nullable)) {
    zutable_abort("type", "field() nullable must be TRUE or FALSE")
  }
  f$nullable <- f$nullable && nullable
  f$metadata <- check_metadata(metadata, "field")
  f
}

#' @rdname schema
#' @export
not_null <- function(type) {
  f <- parse_field(substitute(type), "", parent.frame(), sys.call())
  f$nullable <- FALSE
  f
}

# The schema of a table-like object.
schema_of <- function(x, call = NULL) {
  if (inherits(x, "zutable_schema")) {
    return(x)
  }
  if (is_zutable(x)) {
    zt_validate(x, call)
    return(attr(x, "schema", exact = TRUE))
  }
  if (is.data.frame(x)) {
    return(infer_schema(x, call))
  }
  zutable_abort("schema", "schema() of something that is not a table",
                call = call)
}

infer_schema <- function(df, call = NULL) {
  nms <- names(df)
  if (is.null(nms) || anyNA(nms) || any(!nzchar(nms)) || anyDuplicated(nms)) {
    zutable_abort("schema", "column names must be unique and non-empty",
                  call = call)
  }
  fields <- lapply(seq_along(df), function(i) {
    new_field(nms[[i]], infer_type(df[[i]], nms[[i]], call))
  })
  new_schema(fields)
}

# --- formatting ------------------------------------------------------------

format_field_type <- function(f) {
  out <- format(f$type)
  if (!f$nullable) out <- paste0("not_null(", out, ")")
  out
}

#' @export
format.zutable_field <- function(x, ...) {
  out <- format_field_type(x)
  if (nzchar(x$name)) out <- paste0(x$name, " ", out)
  out
}

#' @export
print.zutable_field <- function(x, ...) {
  cat("<zutable_field> ", format(x), "\n", sep = "")
  invisible(x)
}

#' @export
format.zutable_schema <- function(x, ...) {
  vapply(x$fields, format, "", USE.NAMES = FALSE)
}

#' @export
print.zutable_schema <- function(x, ...) {
  n <- length(x$fields)
  cat(sprintf("<zutable_schema> %d field%s\n", n, if (n == 1L) "" else "s"))
  for (f in x$fields) {
    cat("  ", format(f), "\n", sep = "")
    if (length(f$metadata)) {
      cat("    ", paste0(names(f$metadata), ": ", f$metadata,
                         collapse = ", "), "\n", sep = "")
    }
  }
  if (length(x$metadata)) {
    cat("metadata: ", paste0(names(x$metadata), ": ", x$metadata,
                             collapse = ", "), "\n", sep = "")
  }
  invisible(x)
}

#' @export
length.zutable_schema <- function(x) length(unclass(x)$fields)

#' @export
names.zutable_schema <- function(x) names(unclass(x)$fields)
