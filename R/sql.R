# SQL text for a typed expression, in DuckDB's dialect, from the vocabulary
# table's spellings. This is the per-expression part of the emitter of
# design §11.4: the vocabulary is tested against DuckDB through it (§14).
# Numbers are written with sprintf(), which no session option changes.

zt_sql_ident <- function(x) paste0('"', gsub('"', '""', x, fixed = TRUE), '"')

zt_sql_type <- function(type) {
  switch(type$id,
    bool = "BOOLEAN", int32 = "INTEGER", float64 = "DOUBLE",
    string = "VARCHAR", date = "DATE",
    timestamp = "TIMESTAMP",
    zutable_abort("engine", sprintf("no SQL type for %s", format(type)))
  )
}

zt_sql_literal <- function(value, type) {
  one <- function(v) {
    if (zt_is_null(v)) {
      return(sprintf("CAST(NULL AS %s)", zt_sql_type(type)))
    }
    switch(type$id,
      bool = if (isTRUE(v)) "TRUE" else "FALSE",
      int32 = sprintf("CAST(%d AS INTEGER)", v),
      float64 = if (is.nan(v)) "CAST('nan' AS DOUBLE)" else
        if (v == Inf) "CAST('inf' AS DOUBLE)" else
          if (v == -Inf) "CAST('-inf' AS DOUBLE)" else
            sprintf("CAST(%.17g AS DOUBLE)", v),
      string = zt_quote_sql_string(v),
      date = sprintf("DATE '%s'", format(v, "%Y-%m-%d")),
      timestamp = sprintf("TIMESTAMP '%s'", zt_format_timestamp(v, "UTC")),
      enum = zt_quote_sql_string(as.character(v)),
      zutable_abort("engine", sprintf("no SQL literal for %s", format(type)))
    )
  }
  parts <- vapply(seq_along(value), function(i) one(zt_take(value, i)), "")
  if (length(parts) == 1L) parts else sprintf("(%s)", paste(parts, collapse = ", "))
}

zt_sql_expr <- function(node) {
  switch(node$kind,
    col = zt_sql_ident(node$name),
    lit = zt_sql_literal(node$value, node$type),
    r = zutable_abort("engine", paste(
      "an r() expression runs in the local executor only; it cannot be",
      "sent to an engine"
    )),
    call = {
      args <- vapply(node$args, zt_sql_expr, "")
      if (node$fn == "case") {
        k <- node$n_conds
        whens <- sprintf("WHEN %s THEN %s", args[seq_len(k)], args[k + seq_len(k)])
        return(sprintf("(CASE %s ELSE %s END)", paste(whens, collapse = " "),
                       args[[2L * k + 1L]]))
      }
      if (node$fn == "cast") {
        if (identical(node$type$id, "enum")) {
          zutable_abort("engine", "cast() to an enum has no SQL spelling yet")
        }
        return(sprintf("CAST(%s AS %s)", args[[1L]], zt_sql_type(node$type)))
      }
      entry <- zt_vocab[[node$fn]]
      types <- lapply(node$args, function(a) a$type)
      entry$sql(args, types, node$type)
    }
  )
}
