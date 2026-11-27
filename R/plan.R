# Plans (design §8). A plan is a source and a list of steps, each with its
# output schema and the typed expressions that produce it. It is built and
# checked before any data is read, and kept, as metadata only, on the
# result it made (§8.5 rules 1 to 5, D51).

zt_plan_source <- function(x) {
  # A chained bracket's source is the result before it, whose record is
  # kept as the parent (§5.1: steps are chained brackets).
  list(kind = "table", namespace = NULL, name = NULL, anonymous = TRUE,
       schema = attr(x, "schema", exact = TRUE),
       parent = attr(x, "plan", exact = TRUE))
}

zt_step <- function(op, schema, ...) {
  list(op = op, schema = schema, ...)
}

# Mark every column reference in a node with the step whose output it
# reads (rule 1).
zt_resolve <- function(node, from) {
  if (identical(node$kind, "col")) {
    node$from <- from
  } else if (identical(node$kind, "call")) {
    node$args <- lapply(node$args, zt_resolve, from = from)
  } else if (identical(node$kind, "window")) {
    node$agg <- zt_resolve(node$agg, from)
    node$by <- lapply(node$by, zt_resolve, from = from)
  }
  node
}

zt_plan_query <- function(x, q, env, call) {
  in_schema <- attr(x, "schema", exact = TRUE)
  steps <- list()
  cur <- in_schema
  if (!is.null(q$where)) {
    pred <- zt_translate(q$where, cur, env, call)
    if (!identical(pred$type$id, "bool")) {
      zutable_abort("type", sprintf(
        "`where` must be a condition (bool); it is %s", zt_format_type(pred)
      ), call = call)
    }
    if (pred$aggregate) {
      zutable_abort("type", paste(
        "`where` filters rows before grouping and cannot hold an aggregate;",
        "use `having`"
      ), call = call)
    }
    steps[[length(steps) + 1L]] <- zt_step("filter", cur,
                                           predicate = zt_resolve(pred, 0L))
  }
  # select: the projection, or with `by`, `having` or an aggregate, the
  # aggregation (§5.2, §5.3).
  by <- if (is.null(q$by)) NULL else zt_parse_by(q$by, cur, env, call)
  sel <- if (is.null(q$select)) NULL else zt_parse_select(q$select, cur, env, call)
  aggregate <- !is.null(by) || !is.null(q$having) ||
    any(vapply(sel, function(n) isTRUE(n$aggregate), NA))
  if (aggregate) {
    st <- zt_plan_aggregate(by, sel, q$having, cur, env, call)
    # D59: a plan over one source keeps the table's metadata.
    st$schema$metadata <- cur$metadata
    st$by <- lapply(st$by, zt_resolve, from = length(steps))
    st$exprs <- lapply(st$exprs, zt_resolve, from = length(steps))
    steps[[length(steps) + 1L]] <- st
    cur <- st$schema
    in_schema <- cur
  } else if (!is.null(sel)) {
    out <- new_schema(lapply(names(sel), function(n) zt_node_field(n, sel[[n]], cur)),
                      cur$metadata)
    steps[[length(steps) + 1L]] <- zt_step(
      "project", out, exprs = lapply(sel, zt_resolve, from = length(steps))
    )
    cur <- out
  }
  if (isTRUE(q$distinct)) {
    steps[[length(steps) + 1L]] <- zt_step("distinct", cur)
  } else if (!isFALSE(q$distinct)) {
    zutable_abort("syntax", "`distinct` is TRUE or FALSE", call = call)
  }
  if (!is.null(q$order)) {
    keys <- zt_parse_order(q$order, cur, in_schema, !is.null(sel) || aggregate,
                           isTRUE(q$distinct), env, call)
    steps[[length(steps) + 1L]] <- zt_step("sort", cur, keys = keys)
  }
  if (!is.null(q$limit)) {
    # D62: a user's own error keeps its message inside the package's.
    n <- tryCatch(eval(q$limit, env), error = function(e) {
      zutable_abort("syntax", sprintf("`limit` failed to evaluate: %s", conditionMessage(e)),
                    call = call)
    })
    if (!is.numeric(n) || length(n) != 1L || is.na(n) || n < 0 || n != trunc(n)) {
      zutable_abort("syntax", "`limit` is a whole number of rows, 0 or more",
                    call = call)
    }
    steps[[length(steps) + 1L]] <- zt_step("limit", cur, n = as.double(n))
  }
  structure(list(source = zt_plan_source(x), steps = steps, schema = cur),
            class = "zutable_plan")
}

# The output field of a select or `by` element (D59): a bare column
# reference keeps its field's metadata, renamed or not; a computed
# expression gets none.
zt_node_field <- function(name, node, input) {
  meta <- if (identical(node$kind, "col") && node$name %in% names(input)) {
    input$fields[[node$name]]$metadata
  } else {
    character()
  }
  new_field(name, node$type, isTRUE(node$nullable), meta)
}

# by = col, .(a, b), .(week = date_trunc("week", day)), or a character
# vector of column names: a named list of typed key nodes.
zt_parse_by <- function(e, schema, env, call) {
  if (!zt_is_clause(e, names(schema))) {
    v <- tryCatch(eval(e, env), error = function(err) {
      zutable_abort("syntax", sprintf(paste(
        "`by` is a column, .(a, b), .(name = expression), or a character",
        "vector of column names; evaluating `%s` failed: %s"
      ), paste(deparse(e), collapse = " "), conditionMessage(err)), call = call)
    })
    if (!is.character(v) || anyNA(v) || !length(v)) {
      zutable_abort("syntax", paste(
        "`by` is a column, .(a, b), .(name = expression), or a character",
        "vector of column names"
      ), call = call)
    }
    e <- as.call(c(as.name("."), lapply(v, as.name)))
  }
  items <- if (is.call(e) && identical(e[[1L]], as.name("."))) as.list(e)[-1L] else list(e)
  nms <- names(items) %||% rep("", length(items))
  out <- list()
  for (k in seq_along(items)) {
    it <- items[[k]]
    nm <- nms[[k]]
    if (!nzchar(nm)) {
      if (is.symbol(it) && as.character(it) %in% names(schema)) {
        nm <- as.character(it)
      } else {
        zutable_abort("syntax", sprintf(
          "the computed key `%s` needs a name, as in by = .(name = %s)",
          paste(deparse(it), collapse = " "), paste(deparse(it), collapse = " ")
        ), call = call)
      }
    }
    if (nm %in% names(out)) {
      zutable_abort("schema", sprintf("`by` names `%s` twice", nm), call = call)
    }
    if (is.symbol(it) && !as.character(it) %in% names(schema)) {
      zutable_abort("schema", sprintf("`by` column `%s` does not exist",
                                      as.character(it)), call = call)
    }
    node <- zt_translate(it, schema, env, call)
    if (isTRUE(node$aggregate) || zt_is_lit(node)) {
      zutable_abort("type", sprintf(
        "the key `%s` of `by` is an expression of the columns, not an aggregate",
        nm
      ), call = call)
    }
    if (!node$type$id %in% c(zt_equatable, "int64", "decimal")) {
      zutable_abort("type", sprintf("cannot group by a value of type %s",
                                    zt_format_type(node)), call = call)
    }
    out[[nm]] <- node
  }
  out
}

# The aggregation step: keys, then one aggregate (or key expression) per
# result column, then `having`. Every column a select element mentions
# outside an aggregate must be a key, as in SQL.
zt_plan_aggregate <- function(by, sel, having, input, env, call) {
  keys <- names(by)
  exprs <- list()
  for (nm in names(sel)) {
    node <- sel[[nm]]
    # A bare key named again is already in the result, first.
    if (identical(node$kind, "col") && nm %in% keys && identical(node$name, nm)) next
    if (nm %in% keys) {
      zutable_abort("schema", sprintf(
        "the result would have two columns named `%s`; it is a `by` key", nm
      ), call = call)
    }
    if (identical(node$kind, "window")) {
      zutable_abort("syntax", "over() is for a query without `by` or aggregates",
                    call = call)
    }
    bad <- zt_ungrouped_columns(node, keys, by)
    if (length(bad)) {
      zutable_abort("type", sprintf(paste(
        "in an aggregate query each column is an aggregate or a `by` key;",
        "`%s` uses `%s` outside an aggregate"
      ), nm, bad[[1L]]), call = call)
    }
    exprs[[nm]] <- node
  }
  fields <- c(
    lapply(keys, function(k) zt_node_field(k, by[[k]], input)),
    lapply(names(exprs), function(n) zt_node_field(n, exprs[[n]], input))
  )
  out <- new_schema(fields)
  hv <- NULL
  if (!is.null(having)) {
    scope <- new_schema(c(out$fields, input$fields[setdiff(names(input), names(out))]))
    hv <- zt_translate(having, scope, env, call)
    if (!identical(hv$type$id, "bool")) {
      zutable_abort("type", sprintf("`having` must be a condition (bool); it is %s",
                                    zt_format_type(hv)), call = call)
    }
    bad <- setdiff(zt_ungrouped_columns(hv, names(out), NULL), names(out))
    if (length(bad)) {
      zutable_abort("type", sprintf(paste(
        "`having` uses `%s` outside an aggregate; it may name the result's",
        "columns, or aggregate the input's"
      ), bad[[1L]]), call = call)
    }
  }
  zt_step("aggregate", out, by = by, exprs = exprs, having = hv)
}

# Columns a node mentions outside any aggregate, other than the keys (a
# key may be named, or its expression repeated).
zt_ungrouped_columns <- function(node, keys, by) {
  if (!is.null(by)) {
    for (k in names(by)) {
      if (identical(zt_strip_from(node), zt_strip_from(by[[k]]))) return(character())
    }
  }
  switch(node$kind,
    col = if (node$name %in% keys) character() else node$name,
    call = if (identical(zt_vocab[[node$fn]]$kind, "aggregate")) character() else
      unique(unlist(lapply(node$args, zt_ungrouped_columns, keys = keys, by = by))),
    r = setdiff(node$columns, keys),
    window = character(),
    character()
  )
}

zt_strip_from <- function(node) {
  node$from <- NULL
  if (identical(node$kind, "call")) node$args <- lapply(node$args, zt_strip_from)
  node
}

zt_format_type <- function(node) {
  if (is.null(node$type)) "NA" else format(node$type)
}

# select = .(a, b = expr, .all, -c): a named list of typed nodes.
zt_parse_select <- function(e, schema, env, call) {
  if (is.symbol(e) || !(is.call(e) && identical(e[[1L]], as.name(".")))) {
    if (is.symbol(e) && as.character(e) %in% names(schema)) {
      e <- call(".", e)
    } else {
      zutable_abort("syntax", paste(
        "`select` is .(...): a column, `name = expression`, .all or -name;",
        "a computed column needs a name, as in .(total = px * qty)"
      ), call = call)
    }
  }
  items <- as.list(e)[-1L]
  nms <- names(items) %||% rep("", length(items))
  out <- list()
  for (k in seq_along(items)) {
    it <- items[[k]]
    nm <- nms[[k]]
    if (!nzchar(nm) && identical(it, as.name(".all"))) {
      for (f in schema$fields) out[[f$name]] <- zt_col_node(f)
      next
    }
    if (!nzchar(nm) && is.call(it) && identical(it[[1L]], as.name("-")) &&
        length(it) == 2L && is.symbol(it[[2L]])) {
      drop <- as.character(it[[2L]])
      if (!drop %in% names(out)) {
        zutable_abort("syntax", sprintf(
          "-%s leaves out a column already selected; it comes after .all",
          drop
        ), call = call)
      }
      out[[drop]] <- NULL
      next
    }
    if (!nzchar(nm)) {
      if (is.symbol(it) && as.character(it) %in% names(schema)) {
        nm <- as.character(it)
      } else {
        zutable_abort("syntax", sprintf(paste(
          "the computed column `%s` needs a name, as in .(name = %s);",
          "names in a schema are deliberate"
        ), paste(deparse(it), collapse = " "), paste(deparse(it), collapse = " ")),
        call = call)
      }
    }
    if (nm %in% names(out)) {
      zutable_abort("schema", sprintf(
        "the result would have two columns named `%s`", nm
      ), call = call)
    }
    node <- zt_translate(it, schema, env, call)
    if (zt_is_lit(node) && is.null(node$type)) {
      zutable_abort("type", sprintf(
        "column `%s` is a bare NA, which has no type; write na(<type>)", nm
      ), call = call)
    }
    out[[nm]] <- node
  }
  if (!length(out)) {
    zutable_abort("syntax", "`select` selects no column", call = call)
  }
  out
}

# order = key or .(k1, desc(k2)): result columns, and input columns for a
# query that is not distinct. Each key is a typed node and a direction.
zt_parse_order <- function(e, result, input, projected, distinct, env, call) {
  items <- if (is.call(e) && identical(e[[1L]], as.name("."))) as.list(e)[-1L] else list(e)
  scope <- result
  if (projected && !distinct) {
    extra <- setdiff(names(input), names(result))
    scope <- new_schema(c(result$fields, input$fields[extra]))
  }
  lapply(items, function(it) {
    desc <- FALSE
    if (is.call(it) && identical(it[[1L]], as.name("desc"))) {
      if (length(it) != 2L) {
        zutable_abort("syntax", "desc() takes one key", call = call)
      }
      desc <- TRUE
      it <- it[[2L]]
    }
    node <- zt_translate(it, scope, env, call)
    if (zt_is_lit(node)) {
      zutable_abort("syntax", "an `order` key is an expression of the columns",
                    call = call)
    }
    if (!node$type$id %in% c(zt_ordered, "enum")) {
      zutable_abort("type", sprintf("cannot order by a value of type %s",
                                    zt_format_type(node)), call = call)
    }
    if (distinct && !all(zt_node_columns(node) %in% names(result))) {
      zutable_abort("syntax", paste(
        "with `distinct`, `order` may name only result columns, as in SQL"
      ), call = call)
    }
    list(node = zt_resolve(node, NA_integer_), desc = desc)
  })
}

zt_node_columns <- function(node) {
  switch(node$kind,
    col = node$name,
    call = unique(unlist(lapply(node$args, zt_node_columns))),
    r = node$columns,
    window = unique(c(zt_node_columns(node$agg),
                      unlist(lapply(node$by, zt_node_columns)))),
    character()
  )
}

# The record kept on a result: metadata only. Environments are dropped, so
# the record never keeps a table, or anything else, alive (rule 5).
zt_plan_record <- function(plan) {
  strip <- function(v) {
    if (is.environment(v)) return(NULL)
    if (is.list(v) && !is.data.frame(v)) {
      cl <- class(v)
      out <- lapply(v, strip)
      attributes(out) <- attributes(v)
      class(out) <- cl
      return(out)
    }
    v
  }
  strip(unclass(plan))
}

# --- explain --------------------------------------------------------------------

#' Explain how a table is computed
#'
#' `explain()` prints, one step per line, the plan that made a table: its
#' source, and each step's operation and output schema. It is plain text,
#' written to be read by a person or an agent.
#'
#' When the 'dplyr' package is loaded, `dplyr::explain()` reaches the same
#' method, whichever package was attached last (design D50).
#'
#' @param x A zutable.
#' @param ... Not used.
#' @return `x`, invisibly.
#' @export
#' @examples
#' x <- zutable(id = 1:3, px = c(1.5, 2, 2.5))
#' explain(x[px > 1.6, .(id, twice = px * 2)])
explain <- function(x, ...) {
  UseMethod("explain")
}

#' @export
explain.default <- function(x, ...) {
  if (isNamespaceLoaded("dplyr")) {
    return(getExportedValue("dplyr", "explain")(x, ...))
  }
  zutable_abort("type", "explain() takes a zutable", call = sys.call())
}

#' @export
explain.zutable <- function(x, ...) {
  zt_validate(x, sys.call())
  cat(zt_explain_lines(x), sep = "\n")
  invisible(x)
}

zt_explain_lines <- function(x) {
  rec <- attr(x, "plan", exact = TRUE)
  fmt_schema <- function(s) paste(format(s), collapse = ", ")
  if (is.null(rec)) {
    return(sprintf("table  %s", fmt_schema(attr(x, "schema"))))
  }
  src <- rec$source
  lines <- if (!is.null(src$parent)) {
    zt_explain_lines(structure(list(), plan = src$parent))
  } else {
    sprintf("source  %s  %s",
            if (isTRUE(src$anonymous)) "<anonymous table>" else src$name,
            fmt_schema(src$schema))
  }
  for (st in rec$steps) {
    lines <- c(lines, switch(st$op,
      filter = sprintf("filter  %s", zt_format_node(st$predicate)),
      project = sprintf("project %s", paste(vapply(names(st$exprs), function(n) {
        e <- st$exprs[[n]]
        t <- format(st$schema$fields[[n]])
        if (identical(e$kind, "col") && identical(e$name, n)) t else
          paste0(t, " = ", zt_format_node(e))
      }, ""), collapse = ", ")),
      aggregate = {
        k <- if (length(st$by)) sprintf("by %s", paste(vapply(names(st$by), function(n) {
          e <- st$by[[n]]
          if (identical(e$kind, "col") && identical(e$name, n)) n else
            paste0(n, " = ", zt_format_node(e))
        }, ""), collapse = ", ")) else "all rows"
        a <- vapply(names(st$exprs), function(n) {
          paste0(format(st$schema$fields[[n]]), " = ", zt_format_node(st$exprs[[n]]))
        }, "")
        h <- if (!is.null(st$having)) c(sprintf("having  %s", zt_format_node(st$having)))
        c(sprintf("aggregate %s: %s", k, paste(a, collapse = ", ")), h)
      },
      update = {
        sets <- vapply(st$stmts, function(t) {
          paste0(t$name, if (t$kind == "set") " := " else " <- ", zt_format_node(t$node))
        }, "")
        c(sprintf("update  %s", paste(sets, collapse = "; ")),
          if (!is.null(st$where)) sprintf("  where %s", zt_format_node(st$where)),
          if (length(st$by)) sprintf("  by %s", paste(names(st$by), collapse = ", ")))
      },
      distinct = "distinct",
      sort = sprintf("sort    %s", paste(vapply(st$keys, function(k) {
        paste0(zt_format_node(k$node), if (k$desc) " desc" else "")
      }, ""), collapse = ", ")),
      limit = sprintf("limit   %s", format(st$n, scientific = FALSE))
    ))
  }
  unknown <- rec$unknown
  if (length(unknown)) {
    lines <- c(lines, sprintf("written outside the plan: %s",
                              paste(unknown, collapse = ", ")))
  }
  lines
}

zt_infix <- c("+", "-", "*", "/", "%/%", "%%", "^", "==", "!=", "<", "<=",
              ">", ">=", "&", "|", "%in%")

zt_format_node <- function(node) {
  switch(node$kind,
    col = node$name,
    lit = {
      v <- node$value
      if (zt_nrow_of(v) != 1L) {
        sprintf("c(%s)", paste(vapply(seq_along(v), function(i) {
          zt_format_lit(zt_take(v, i), node$type)
        }, ""), collapse = ", "))
      } else {
        zt_format_lit(v, node$type)
      }
    },
    r = sprintf("r(%s)", paste(deparse(node$expr), collapse = " ")),
    window = sprintf("over(%s%s)", zt_format_node(node$agg),
                     if (length(node$by)) paste0(", by = ", paste(vapply(node$by,
                       zt_format_node, ""), collapse = ", ")) else ""),
    call = {
      a <- vapply(node$args, zt_format_node, "")
      if (node$fn %in% zt_infix && length(a) == 2L) {
        sprintf("(%s %s %s)", a[[1L]], node$fn, a[[2L]])
      } else if (node$fn %in% c("-", "!") && length(a) == 1L) {
        sprintf("%s%s", node$fn, a[[1L]])
      } else if (node$fn == "cast") {
        sprintf("cast(%s, %s)", a[[1L]], format(node$type))
      } else if (node$fn == "case") {
        k <- node$n_conds
        sprintf("case(%s, .default = %s)", paste(sprintf("%s ~ %s", a[seq_len(k)],
                                                  a[k + seq_len(k)]), collapse = ", "),
                a[[2L * k + 1L]])
      } else {
        sprintf("%s(%s)", node$fn, paste(a, collapse = ", "))
      }
    }
  )
}

zt_format_lit <- function(v, type) {
  if (is.null(type) || zt_is_null(v)) return("NA")
  switch(type$id,
    string = encodeString(v, quote = '"'),
    float64 = sprintf("%.15g", v),
    int32 = sprintf("%dL", v),
    bool = if (v) "TRUE" else "FALSE",
    date = sprintf("date \"%s\"", zt_format_date(v)),
    timestamp = sprintf("timestamp \"%s\"", zt_format_timestamp(v, type$tz %||% "UTC")),
    enum = encodeString(as.character(v), quote = '"'),
    format(v)
  )
}

# D50: register explain() on dplyr's generic when dplyr loads, so the call
# reaches zutable's method whichever package was attached last.
zt_register_s3 <- function(pkg, generic, class, method) {
  register <- function(...) {
    registerS3method(generic, class, method, envir = asNamespace(pkg))
  }
  if (isNamespaceLoaded(pkg)) register()
  setHook(packageEvent(pkg, "onLoad"), register)
}

.onLoad <- function(libname, pkgname) {
  zt_register_s3("dplyr", "explain", "zutable", explain.zutable)
  # D57: the print-skip flag lasts until the top-level expression ends.
  zt_remove_print_callback()
  addTaskCallback(zt_clear_print_skip, name = "zutable_print_skip")
  invisible()
}

.onUnload <- function(libpath) {
  zt_remove_print_callback()
  invisible()
}

zt_remove_print_callback <- function() {
  while ("zutable_print_skip" %in% getTaskCallbackNames()) {
    removeTaskCallback("zutable_print_skip")
  }
}
