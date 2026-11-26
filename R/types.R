# Types (design §4.1). A type is a list with class `zutable_type`: an `id`
# naming its kind and the parameters that kind takes. Type names are
# resolved by parse_type() inside the capturing functions (schema(),
# field(), not_null(), na(), and later cast()); they are never exported
# objects, so `date` and `list` mask nothing (D24).

zt_type <- function(id, ...) {
  structure(list(id = id, ...), class = "zutable_type")
}

# The simple types, by name. Narrow Arrow types widen exactly (§4.1).
zt_simple_types <- c(
  bool = "bool", int32 = "int32", int64 = "int64", float64 = "float64",
  string = "string", date = "date", binary = "binary",
  int8 = "int32", int16 = "int32", float32 = "float64",
  # Synonyms in Arrow's spelling.
  boolean = "bool", double = "float64", utf8 = "string"
)

zt_unsigned_types <- c("uint8", "uint16", "uint32", "uint64")

zt_timestamp_units <- c("s", "ms", "us", "ns")

# Types whose R vector lives in a sibling package (§4.1, "Exact or
# error"). The package name is held in a variable, not a literal, because
# these siblings are not on CRAN yet and so cannot be in Suggests.
zt_type_package <- function(type) {
  switch(type$id,
    int64 = "zuint",
    decimal = "decimal",
    timestamp = if (identical(type$unit, "ns")) "zutempo",
    NULL
  )
}

zt_has_package <- function(pkg) {
  requireNamespace(pkg, quietly = TRUE)
}

zt_require_type_package <- function(type, call = NULL) {
  pkg <- zt_type_package(type)
  if (!is.null(pkg) && !zt_has_package(pkg)) {
    zutable_abort(
      "type",
      sprintf("type %s needs package '%s', which is not installed",
              format(type), pkg),
      package = pkg, call = call
    )
  }
  invisible(type)
}

is_zutable_type <- function(x) inherits(x, "zutable_type")

# --- parsing ---------------------------------------------------------------

# Resolve a captured expression to a type. `env` is where non-type names,
# such as a variable holding a type or an enum's levels, are looked up.
parse_type <- function(expr, env = parent.frame(), call = NULL) {
  type <- parse_type_expr(expr, env, call)
  zt_require_type_package(type, call)
}

parse_type_expr <- function(expr, env, call) {
  bad <- function(msg) zutable_abort("type", msg, call = call)

  if (is_zutable_type(expr)) {
    return(expr)
  }
  if (is.character(expr)) {
    if (length(expr) != 1L || is.na(expr)) {
      bad("a type given as a string must be one string")
    }
    parsed <- tryCatch(str2lang(expr), error = function(e) NULL)
    if (is.null(parsed) || is.character(parsed)) {
      bad(sprintf("cannot read %s as a type", encodeString(expr, quote = '"')))
    }
    return(parse_type_expr(parsed, env, call))
  }
  if (is.symbol(expr)) {
    name <- as.character(expr)
    if (name %in% names(zt_simple_types)) {
      return(zt_type(zt_simple_types[[name]]))
    }
    if (name %in% zt_unsigned_types) {
      bad(sprintf(
        "unsigned type %s is not supported yet (design section 19, Q2)", name
      ))
    }
    if (name == "timestamp") {
      return(zt_timestamp("us", "UTC"))
    }
    # A caller variable holding a type, or a string naming one.
    value <- tryCatch(
      eval(expr, env),
      error = function(e) bad(sprintf("unknown type `%s`", name))
    )
    if (is_zutable_type(value) || is.character(value)) {
      return(parse_type_expr(value, env, call))
    }
    bad(sprintf("unknown type `%s`", name))
  }
  if (is.call(expr) && is.symbol(expr[[1L]])) {
    fn <- as.character(expr[[1L]])
    args <- as.list(expr)[-1L]
    switch(fn,
      timestamp = return(parse_timestamp(args, env, bad)),
      decimal = return(parse_decimal(args, env, bad)),
      enum = return(parse_enum(args, env, bad, call)),
      list = {
        if (length(args) != 1L || !is.null(names(args))) {
          bad("list() takes one type, the type of its elements")
        }
        return(zt_type("list", value = parse_type(args[[1L]], env, call)))
      },
      struct = return(parse_struct(args, env, call, bad)),
      r_class = {
        cls <- eval_type_arg(args, 1L, "class", env, bad)
        if (!is.character(cls) || length(cls) != 1L || is.na(cls) ||
            !nzchar(cls)) {
          bad("r_class() takes one class name")
        }
        return(zt_type("r_class", class = cls))
      },
      extension = {
        name <- eval_type_arg(args, 1L, "name", env, bad)
        if (!is.character(name) || length(name) != 1L || is.na(name)) {
          bad("extension() takes an extension name")
        }
        return(zt_extension_type(name, bad))
      },
      `(` = return(parse_type_expr(args[[1L]], env, call))
    )
    bad(sprintf("unknown type `%s()`", fn))
  }
  bad("not a type")
}

# The i-th argument of a type call, by position or by `name`, evaluated.
eval_type_arg <- function(args, i, name, env, bad, default = NULL) {
  nms <- names(args) %||% rep("", length(args))
  if (name %in% nms) {
    expr <- args[[which(nms == name)[1L]]]
  } else {
    unnamed <- which(nms == "")
    if (length(unnamed) < i) {
      return(default)
    }
    expr <- args[[unnamed[i]]]
  }
  # A bare unit such as `timestamp(us)` reads as the string.
  if (is.symbol(expr) && name %in% c("unit", "tz")) {
    return(as.character(expr))
  }
  tryCatch(eval(expr, env), error = function(e) {
    bad(sprintf("cannot evaluate the `%s` of a type: %s", name,
                conditionMessage(e)))
  })
}

zt_timestamp <- function(unit = "us", tz = "UTC") {
  zt_type("timestamp", unit = unit, tz = tz)
}

parse_timestamp <- function(args, env, bad) {
  unit <- eval_type_arg(args, 1L, "unit", env, bad, default = "us")
  tz <- eval_type_arg(args, 2L, "tz", env, bad, default = NULL)
  if (!is.character(unit) || length(unit) != 1L ||
      !unit %in% zt_timestamp_units) {
    bad("timestamp() unit must be one of \"s\", \"ms\", \"us\", \"ns\"")
  }
  if (!is.null(tz) &&
      (!is.character(tz) || length(tz) != 1L || is.na(tz) || !nzchar(tz))) {
    bad("timestamp() tz must be one non-empty time zone name, or NULL")
  }
  if (!is.null(tz) && !zt_known_zone(tz)) {
    bad(sprintf("timestamp() tz \"%s\" is not one of OlsonNames()", tz))
  }
  zt_timestamp(unit, tz)
}

parse_decimal <- function(args, env, bad) {
  p <- eval_type_arg(args, 1L, "precision", env, bad)
  s <- eval_type_arg(args, 2L, "scale", env, bad, default = 0L)
  whole <- function(v) {
    is.numeric(v) && length(v) == 1L && !is.na(v) && v == trunc(v)
  }
  if (!whole(p) || p < 1 || p > 76) {
    bad("decimal() precision must be a whole number from 1 to 76")
  }
  if (!whole(s) || s < 0 || s > p) {
    bad("decimal() scale must be a whole number from 0 to the precision")
  }
  zt_type("decimal", precision = as.integer(p), scale = as.integer(s))
}

parse_enum <- function(args, env, bad, call) {
  levels <- eval_type_arg(args, 1L, "levels", env, bad)
  if (is.character(levels)) levels <- zt_enter_strings(levels, "enum() levels", call)
  if (!is.character(levels) || anyNA(levels) || anyDuplicated(levels)) {
    bad("enum() levels must be distinct, non-missing strings")
  }
  zt_type("enum", levels = levels)
}

parse_struct <- function(args, env, call, bad) {
  nms <- names(args)
  if (!is.null(nms)) nms <- zt_enter_strings(nms, "struct() field names", call)
  if (length(args) == 0L || is.null(nms) || any(!nzchar(nms))) {
    bad("struct() takes named fields")
  }
  if (anyDuplicated(nms)) {
    bad("struct() field names must be unique")
  }
  fields <- lapply(seq_along(args), function(i) {
    parse_field(args[[i]], nms[[i]], env, call)
  })
  names(fields) <- nms
  zt_type("struct", fields = fields)
}

# --- extension types ------------------------------------------------------

# Sibling vector classes register under an extension name (§4.1), as they
# do with zuarrow: the registry maps the name to a prototype of the R class
# and to the storage type.
zt_registry <- new.env(parent = emptyenv())
zt_registry$extensions <- list()

#' Register an R vector class as an extension type
#'
#' A package whose vector class has an Arrow extension name, such as a
#' geometry class, registers it so that `zutable` types its columns as that
#' extension rather than as an opaque `r_class()`. Call it from the
#' package's `.onLoad()`.
#'
#' @param name The extension name, for example `"geoarrow.wkb"`.
#' @param ptype A zero-length vector of the class. Its first class names
#'   the class, and `ptype[NA_integer_]` is the type's missing value.
#' @param storage The storage type, as in [schema()], for example `binary`.
#' @return The extension type, invisibly.
#' @export
#' @examples
#' register_extension_type("example.celsius", structure(double(), class = "celsius"), float64)
#' schema(t = extension("example.celsius"))
register_extension_type <- function(name, ptype, storage) {
  call <- sys.call()
  if (!is.character(name) || length(name) != 1L || is.na(name) ||
      !nzchar(name)) {
    zutable_abort("type", "the extension name must be one non-empty string", call = call)
  }
  if (!is.object(ptype) || length(ptype) != 0L) {
    zutable_abort("type", "the prototype must be a zero-length classed vector", call = call)
  }
  storage <- parse_type(substitute(storage), parent.frame(), call)
  zt_registry$extensions[[name]] <- list(
    name = name, ptype = ptype, class = class(ptype)[[1L]], storage = storage
  )
  invisible(zt_extension_type(name))
}

zt_extension_type <- function(name, bad = NULL) {
  entry <- zt_registry$extensions[[name]]
  if (is.null(entry)) {
    msg <- sprintf("extension type \"%s\" is not registered", name)
    if (is.null(bad)) zutable_abort("type", msg, call = NULL) else bad(msg)
  }
  zt_type("extension", name = name, storage = entry$storage)
}

zt_extension_for_class <- function(x) {
  for (entry in zt_registry$extensions) {
    if (inherits(x, entry$class)) {
      return(zt_type("extension", name = entry$name, storage = entry$storage))
    }
  }
  NULL
}

# --- formatting ------------------------------------------------------------

#' @export
format.zutable_type <- function(x, ...) {
  switch(x$id,
    timestamp = if (is.null(x$tz)) {
      sprintf("timestamp(\"%s\")", x$unit)
    } else {
      sprintf("timestamp(\"%s\", \"%s\")", x$unit, x$tz)
    },
    decimal = sprintf("decimal(%d, %d)", x$precision, x$scale),
    enum = sprintf("enum(c(%s))", paste(encodeString(x$levels, quote = '"'),
                                        collapse = ", ")),
    list = sprintf("list(%s)", format(x$value)),
    struct = sprintf("struct(%s)", paste(
      vapply(names(x$fields), function(n) {
        paste0(n, " = ", format_field_type(x$fields[[n]]))
      }, ""), collapse = ", ")),
    r_class = sprintf("r_class(\"%s\")", x$class),
    extension = sprintf("extension(\"%s\")", x$name),
    x$id
  )
}

#' @export
print.zutable_type <- function(x, ...) {
  cat("<zutable_type> ", format(x), "\n", sep = "")
  invisible(x)
}

`%||%` <- function(x, y) if (is.null(x)) y else x
