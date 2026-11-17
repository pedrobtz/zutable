# Typed expressions (design §7). A captured R expression is translated into
# a tree of nodes over a closed vocabulary (R/vocabulary.R), typed before
# any data is read, and evaluated column at a time.
#
# Nodes are lists of class `zt_node`:
#   col   a column of the input: `name`, `type`, `nullable`
#   lit   a constant: `value` (an R vector of `type`), `adaptable` when it
#         came from the code or the caller and may take its context's type
#   call  a vocabulary function: `fn`, `args`, `type`, `nullable`,
#         `aggregate`
#   r     the escape (§7.3): `expr`, `env`, `columns` it mentions, `type`
#
# Every node keeps its expression, references are resolved to the input's
# columns, and every function carries its lineage kind (§8.5 rules 1, 2, 4).

zt_node <- function(kind, ...) {
  structure(list(kind = kind, ...), class = "zt_node")
}

zt_col_node <- function(field) {
  zt_node("col", name = field$name, type = field$type,
          nullable = field$nullable, aggregate = FALSE)
}

zt_lit_node <- function(value, type = NULL, adaptable = TRUE) {
  zt_node("lit", value = value, type = type,
          nullable = any(zt_is_null(value)), adaptable = adaptable,
          aggregate = FALSE)
}

# --- translation -------------------------------------------------------------

# Translate a captured expression against a schema. Names that are columns
# are columns; any other name is a caller variable whose value enters as a
# constant, and a sub-expression that mentions no column is evaluated once
# in the caller's frame (§5.4). `..name` forces the caller's variable.
zt_translate <- function(expr, schema, env, call = NULL) {
  ctx <- list(schema = schema, env = env, call = call,
              columns = names(schema))
  zt_tr(expr, ctx)
}

zt_tr <- function(expr, ctx) {
  if (is.symbol(expr)) {
    name <- as.character(expr)
    if (name == ".N") {
      return(zt_tr(quote(count()), ctx))
    }
    if (startsWith(name, "..") && nchar(name) > 2L) {
      return(zt_constant(as.name(substring(name, 3L)), ctx))
    }
    if (name %in% ctx$columns) {
      return(zt_col_node(ctx$schema$fields[[name]]))
    }
    return(zt_constant(expr, ctx))
  }
  if (!is.call(expr)) {
    return(zt_constant(expr, ctx))
  }
  head <- expr[[1L]]
  if (!is.symbol(head)) {
    zutable_abort("type", paste(
      "a function in an expression must be named; use r() to call",
      "arbitrary R"
    ), call = ctx$call)
  }
  fn <- as.character(head)
  if (fn == "(") {
    return(zt_tr(expr[[2L]], ctx))
  }
  if (!zt_needs_data(expr, ctx)) {
    return(zt_constant(expr, ctx))
  }
  special <- zt_special_forms[[fn]]
  if (!is.null(special)) {
    return(special(expr, ctx))
  }
  entry <- zt_vocab_lookup(fn)
  if (is.null(entry)) {
    zutable_abort("type", sprintf(paste(
      "function `%s()` is not in zutable's vocabulary; write",
      "r(%s(...), <type>) to evaluate it as R"
    ), fn, fn), fn = fn, call = ctx$call)
  }
  args <- as.list(expr)[-1L]
  if (!is.null(names(args)) && any(nzchar(names(args)))) {
    args <- zt_match_named(entry, args, ctx)
  }
  nodes <- lapply(args, zt_tr, ctx = ctx)
  zt_type_call(entry, nodes, ctx)
}

# Whether an expression needs the data: it mentions a column, or is one of
# the forms that are never constant (count(), .N, r()).
zt_needs_data <- function(expr, ctx) {
  zt_mentions_column(expr, ctx$columns) ||
    any(c(".N", "count", "r", "cast", "case") %in%
          all.names(expr, functions = TRUE))
}

# Whether an expression refers to one of `cols`: a bare name that is a
# column, outside function position and outside the right of `$` and `@`.
zt_mentions_column <- function(e, cols) {
  if (is.symbol(e)) {
    return(as.character(e) %in% cols)
  }
  if (!is.call(e)) return(FALSE)
  head <- e[[1L]]
  args <- as.list(e)[-1L]
  if (identical(head, as.name("$")) || identical(head, as.name("@"))) {
    args <- args[1L]
  }
  if (!is.symbol(head) && zt_mentions_column(head, cols)) return(TRUE)
  any(vapply(args, function(a) !missing(a) && zt_mentions_column(a, cols), NA))
}

# Named arguments are only those an entry declares (digits =, .default =).
zt_match_named <- function(entry, args, ctx) {
  nms <- names(args)
  ok <- !nzchar(nms) | nms %in% entry$arg_names
  if (!all(ok)) {
    zutable_abort("syntax", sprintf(
      "`%s()` has no argument `%s`", entry$name, nms[!ok][[1L]]
    ), call = ctx$call)
  }
  ordered <- list()
  pos <- args[!nzchar(nms)]
  for (an in entry$arg_names) {
    if (an %in% nms) {
      ordered[[length(ordered) + 1L]] <- args[[an]]
    } else if (length(pos)) {
      ordered[[length(ordered) + 1L]] <- pos[[1L]]
      pos <- pos[-1L]
    }
  }
  c(ordered, pos)
}

# A constant from the caller's frame: evaluated once, typed by its vector.
zt_constant <- function(expr, ctx, allow_vector = FALSE) {
  value <- tryCatch(
    eval(expr, ctx$env),
    error = function(e) {
      zutable_abort("syntax", sprintf(
        "`%s` is not a column, and evaluating it failed: %s",
        paste(deparse(expr), collapse = " "), conditionMessage(e)
      ), call = ctx$call)
    }
  )
  zt_constant_value(value, expr, ctx, allow_vector)
}

zt_constant_value <- function(value, expr, ctx, allow_vector = FALSE) {
  if (!allow_vector && zt_nrow_of(value) != 1L) {
    zutable_abort("type", sprintf(
      "`%s` is a constant of length %d; a constant in an expression has length one",
      paste(deparse(expr), collapse = " "), zt_nrow_of(value)
    ), call = ctx$call)
  }
  if (is.logical(value) && !is.object(value) && all(is.na(value))) {
    # A bare NA is the missing value of whatever type the context needs.
    return(zt_lit_node(value, type = NULL))
  }
  type <- infer_type(value, "constant", ctx$call)
  if (is.character(value)) value <- enc2utf8(value)
  zt_lit_node(value, type = type)
}

# --- typing ------------------------------------------------------------------

zt_is_lit <- function(node) identical(node$kind, "lit")

# Type a call against its entry's signatures, in order; the first that
# matches wins. Literals adapt to their context's type when exactly
# representable (§4.3).
zt_type_call <- function(entry, nodes, ctx) {
  if (entry$kind == "aggregate" && any(vapply(nodes, function(n) n$aggregate, NA))) {
    zutable_abort("type", sprintf(
      "`%s()` is an aggregate; an aggregate cannot hold another", entry$name
    ), call = ctx$call)
  }
  for (sig in entry$sigs) {
    m <- zt_match_sig(sig, nodes)
    if (!is.null(m)) {
      return(zt_node(
        "call", fn = entry$name, args = m$args, type = m$result,
        nullable = zt_call_nullable(entry, m$args),
        aggregate = entry$kind == "aggregate" ||
          any(vapply(m$args, function(n) n$aggregate, NA))
      ))
    }
  }
  given <- vapply(nodes, function(n) {
    if (is.null(n$type)) "NA" else format(n$type)
  }, "")
  zutable_abort("type", sprintf(
    "`%s()` does not accept (%s); it takes %s", entry$name,
    paste(given, collapse = ", "), zt_sig_summary(entry)
  ), fn = entry$name, call = ctx$call)
}

zt_parameterless <- c("bool", "int32", "float64", "string", "date", "binary")

# The type an argument of id `id` takes when it is a literal: that of a
# typed argument with the same id, or the plain type for a parameterless id.
zt_context_type <- function(id, nodes) {
  for (n in nodes) {
    if (!zt_is_lit(n) && identical(n$type$id, id)) return(n$type)
  }
  if (id %in% zt_parameterless) return(zt_type(id))
  if (id == "timestamp") return(zt_timestamp("us", "UTC"))
  NULL
}

zt_match_sig <- function(sig, nodes) {
  n <- length(nodes)
  ids <- sig$args
  if (isTRUE(sig$variadic)) {
    if (n < length(ids)) return(NULL)
    ids <- c(ids, rep(ids[[length(ids)]], n - length(ids)))
  } else if (n != length(ids)) {
    return(NULL)
  }
  # The type variable T: the type of the first typed argument in a T slot,
  # else of the first non-NA literal there.
  t_type <- NULL
  for (i in which(ids == "T")) {
    if (!zt_is_lit(nodes[[i]])) { t_type <- nodes[[i]]$type; break }
  }
  if (is.null(t_type)) {
    for (i in which(ids == "T")) {
      if (!is.null(nodes[[i]]$type)) { t_type <- nodes[[i]]$type; break }
    }
  }
  if (any(ids == "T") && (is.null(t_type) ||
                          (!is.null(sig$T) && !t_type$id %in% sig$T))) {
    return(NULL)
  }
  out <- nodes
  types <- vector("list", n)
  for (i in seq_len(n)) {
    node <- nodes[[i]]
    target <- if (ids[[i]] == "T") t_type else zt_context_type(ids[[i]], nodes)
    if (zt_is_lit(node)) {
      if (is.null(target)) return(NULL)
      v <- zt_lit_adapt(node$value, target)
      if (is.null(v)) return(NULL)
      out[[i]] <- zt_lit_node(v, target)
      types[[i]] <- target
    } else {
      want <- if (ids[[i]] == "T") t_type$id else ids[[i]]
      if (!identical(node$type$id, want)) return(NULL)
      if (ids[[i]] == "T" && !identical(node$type, t_type)) return(NULL)
      types[[i]] <- node$type
    }
  }
  if (!is.null(sig$check) && !isTRUE(sig$check(types))) return(NULL)
  result <- if (is.function(sig$result)) sig$result(types) else
    if (identical(sig$result, "T")) t_type else
      if (startsWith(sig$result, "arg")) types[[as.integer(substring(sig$result, 4L))]] else
        zt_type(sig$result)
  list(args = out, types = types, result = result)
}

# A literal value as a vector of `type`, or NULL when it is not exactly
# representable there.
zt_lit_adapt <- function(value, type) {
  if (is.logical(value) && !is.object(value) && all(is.na(value))) {
    na <- tryCatch(na_of(type), error = function(e) NULL)
    if (is.null(na)) return(NULL)
    return(rep(na, length.out = length(value)))
  }
  fitted <- zt_fit_literal(value, type)
  if (!is.null(fitted)) {
    if (identical(type$id, "timestamp") && !identical(type$unit, "ns")) {
      attr(fitted, "tzone") <- type$tz %||% "UTC"
    }
    return(fitted)
  }
  if (is.character(value) && !is.object(value)) {
    if (identical(type$id, "date")) {
      ok <- is.na(value) | grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", value)
      d <- as.Date(value, format = "%Y-%m-%d", optional = TRUE)
      if (all(ok) && !anyNA(d[!is.na(value)])) return(d)
    }
    if (identical(type$id, "timestamp") && !identical(type$unit, "ns")) {
      ts <- zt_parse_timestamp(value, type$tz %||% "UTC")
      if (!is.null(ts)) return(ts)
    }
  }
  NULL
}

# ISO 8601 date-times, "YYYY-MM-DD[ T]HH:MM[:SS[.ffffff]]", read in `tz`.
zt_parse_timestamp <- function(value, tz) {
  pat <- "^[0-9]{4}-[0-9]{2}-[0-9]{2}([ T][0-9]{2}:[0-9]{2}(:[0-9]{2}(\\.[0-9]{1,6})?)?)?$"
  ok <- is.na(value) | grepl(pat, value)
  if (!all(ok)) return(NULL)
  v <- sub("T", " ", value, fixed = TRUE)
  out <- as.POSIXct(v, tz = tz, tryFormats = c("%Y-%m-%d %H:%M:%OS",
                                               "%Y-%m-%d %H:%M", "%Y-%m-%d"),
                    optional = TRUE)
  if (anyNA(out[!is.na(value)])) return(NULL)
  attr(out, "tzone") <- tz
  out
}

zt_call_nullable <- function(entry, args) {
  nl <- vapply(args, function(n) isTRUE(n$nullable), NA)
  switch(entry$nullable,
    never = FALSE,
    always = TRUE,
    all = all(nl),
    propagate = any(nl)
  )
}

zt_sig_summary <- function(entry) {
  sigs <- vapply(entry$sigs, function(s) {
    a <- s$args
    if (isTRUE(s$variadic)) a[[length(a)]] <- paste0(a[[length(a)]], ", ...")
    sprintf("(%s)", paste(a, collapse = ", "))
  }, "")
  paste(unique(sigs), collapse = " or ")
}

# --- evaluation ---------------------------------------------------------------

# Evaluate a typed node over columns (a named list of vectors, `n` rows).
zt_eval <- function(node, cols, n) {
  switch(node$kind,
    col = cols[[node$name]],
    lit = node$value,
    call = {
      if (node$fn == "case") return(zt_eval_case(node, cols, n))
      if (node$fn == "cast") {
        return(zt_cast_value(zt_eval(node$args[[1L]], cols, n),
                             node$args[[1L]]$type, node$type))
      }
      entry <- zt_vocab[[node$fn]]
      vals <- lapply(node$args, zt_eval, cols = cols, n = n)
      types <- lapply(node$args, function(a) a$type)
      out <- entry$impl(vals, types, node$type, n)
      out
    },
    r = zt_eval_r(node, cols, n)
  )
}

# Null elements: NA, but not NaN, for doubles (D47); NULL in lists.
zt_is_null <- function(x) {
  if (is.data.frame(x)) return(zt_struct_missing(x))
  if (is.list(x) && !is.object(x)) return(vapply(x, is.null, NA))
  if (is.double(x) && !inherits(x, "integer64")) return(is.na(x) & !is.nan(x))
  is.na(x)
}

# --- special forms -----------------------------------------------------------

zt_special_forms <- list(
  r = function(expr, ctx) {
    args <- as.list(expr)[-1L]
    if (length(args) != 2L) {
      zutable_abort("syntax", "r() takes an expression and its type: r(expr, type)",
                    call = ctx$call)
    }
    type <- parse_type(args[[2L]], ctx$env, ctx$call)
    mentioned <- intersect(all.names(args[[1L]]), ctx$columns)
    zt_node("r", expr = args[[1L]], env = ctx$env, columns = mentioned,
            type = type, nullable = TRUE, aggregate = FALSE, opaque = TRUE)
  },
  cast = function(expr, ctx) {
    args <- as.list(expr)[-1L]
    if (length(args) != 2L) {
      zutable_abort("syntax", "cast() takes a value and a type: cast(x, type)",
                    call = ctx$call)
    }
    x <- zt_tr(args[[1L]], ctx)
    to <- parse_type(args[[2L]], ctx$env, ctx$call)
    zt_type_cast(x, to, ctx)
  },
  case = function(expr, ctx) zt_type_case(expr, ctx),
  `%in%` = function(expr, ctx) {
    args <- as.list(expr)[-1L]
    x <- zt_tr(args[[1L]], ctx)
    if (zt_needs_data(args[[2L]], ctx)) {
      zutable_abort("type", "the right side of %in% is a set of constants",
                    call = ctx$call)
    }
    set <- eval(args[[2L]], ctx$env)
    if (anyNA(set)) {
      zutable_abort("value", "the set of %in% holds NA; test is.na() instead",
                    call = ctx$call)
    }
    if (is.null(x$type) || x$type$id %in% c("binary", "list", "struct", "r_class")) {
      zutable_abort("type", "%in% takes a column of a comparable type",
                    call = ctx$call)
    }
    v <- zt_lit_adapt(set, x$type)
    if (is.null(v)) {
      zutable_abort("type", sprintf(
        "the set of %%in%% is not %s", format(x$type)
      ), call = ctx$call)
    }
    zt_node("call", fn = "%in%", args = list(x, zt_lit_node(v, x$type)),
            type = zt_type("bool"), nullable = x$nullable,
            aggregate = x$aggregate)
  }
)

zt_type_case <- function(expr, ctx) {
  args <- as.list(expr)[-1L]
  nms <- names(args) %||% rep("", length(args))
  default <- if (".default" %in% nms) args[[".default"]] else NA
  pairs <- args[nms != ".default"]
  if (!length(pairs)) {
    zutable_abort("syntax", "case() takes `condition ~ value` pairs",
                  call = ctx$call)
  }
  conds <- list()
  values <- list()
  for (p in pairs) {
    if (!is.call(p) || !identical(p[[1L]], as.name("~")) || length(p) != 3L) {
      zutable_abort("syntax", "each argument of case() is `condition ~ value`",
                    call = ctx$call)
    }
    conds[[length(conds) + 1L]] <- zt_tr(p[[2L]], ctx)
    values[[length(values) + 1L]] <- zt_tr(p[[3L]], ctx)
  }
  values[[length(values) + 1L]] <- zt_tr(default, ctx)
  for (c in conds) {
    if (!is.null(c$type) && !identical(c$type$id, "bool") || zt_is_lit(c) &&
        !is.logical(c$value)) {
      zutable_abort("type", "a condition of case() must be bool",
                    call = ctx$call)
    }
  }
  conds <- lapply(conds, function(c) if (zt_is_lit(c)) zt_lit_node(as.logical(c$value), zt_type("bool")) else c)
  m <- zt_match_sig(list(args = "T", variadic = TRUE, result = "T"), values)
  if (is.null(m)) {
    zutable_abort("type", "the values of case() must have one type",
                  call = ctx$call)
  }
  all_args <- c(conds, m$args)
  zt_node("call", fn = "case", args = all_args, type = m$result,
          nullable = TRUE, n_conds = length(conds),
          aggregate = any(vapply(all_args, function(n) n$aggregate, NA)))
}

zt_eval_r <- function(node, cols, n) {
  mask <- list2env(cols[node$columns], parent = node$env)
  out <- eval(node$expr, mask)
  if (zt_nrow_of(out) == 1L && n != 1L) {
    out <- if (is.data.frame(out)) out[rep(1L, n), , drop = FALSE] else rep(out, length.out = n)
  }
  p <- if (zt_nrow_of(out) != n) sprintf("%d values for %d rows", zt_nrow_of(out), n) else
    vector_problem(out, node$type)
  if (!is.null(p)) {
    zutable_abort("type", sprintf("r(%s) was declared %s: %s",
                                  paste(deparse(node$expr), collapse = " "),
                                  format(node$type), p))
  }
  out
}
