# The closed vocabulary (design §7.1). Every function allowed in a clause is
# one entry of `zt_vocab`: its SQL name and R synonyms, the signatures it
# accepts, its result type, its NA rule, its implementation in the local
# executor, its spelling in DuckDB's SQL, and its lineage kind (§8.5 rule
# 4). The type checker, the executor, the SQL spelling, the documentation
# (?vocabulary) and the tests are all read from this one table.
#
# Semantics chosen where R and SQL differ (design D44 to D49): NaN is a
# value and NA the null; strings compare by bytes; aggregates follow SQL's
# null rules; `paste0()` propagates NA; `ifelse()` keeps R's NA condition,
# `case()` SQL's; `substr()` keeps R's (start, stop).

vocab_entry <- function(name, sigs, impl, sql, synonyms = character(),
                        kind = "scalar", nullable = "propagate",
                        lineage = if (kind == "aggregate") "aggregation" else
                          "transformation",
                        masking = FALSE, arg_names = character(),
                        doc = "") {
  list(name = name, synonyms = synonyms, sigs = sigs, impl = impl, sql = sql,
       kind = kind, nullable = nullable, lineage = lineage, masking = masking,
       arg_names = arg_names, doc = doc)
}

sig <- function(args, result, T = NULL, variadic = FALSE, check = NULL) {
  list(args = args, result = result, T = T, variadic = variadic,
       check = check)
}

zt_num <- c("int32", "float64")
zt_ordered <- c("bool", "int32", "float64", "string", "date", "timestamp")
zt_equatable <- c(zt_ordered, "enum")
zt_value_types <- c(zt_equatable, "binary", "list", "struct", "int64",
                    "decimal")

# Timestamps compare as instants, but a zoned one never with a zoneless one.
zt_same_zoning <- function(types) {
  ts <- Filter(function(t) identical(t$id, "timestamp"), types)
  length(unique(vapply(ts, function(t) is.null(t$tz), NA))) <= 1L
}

# --- helpers for implementations ---------------------------------------------

zt_int_result <- function(x) {
  bad <- !is.na(x) & abs(x) > .Machine$integer.max
  if (any(bad)) {
    zutable_abort("value", sprintf(
      "int32 overflow: %s is outside +/-(2^31 - 1); cast to float64 first",
      format(x[bad][[1L]], digits = 15L)
    ), call = zt_eval_call())
  }
  as.integer(x)
}

# NA wins over NaN: R's NA op NaN may give NaN, but a null operand gives
# a null result (D46, D47).
zt_na_wins <- function(out, a, b) {
  out[zt_is_null(a) | zt_is_null(b)] <- NA_real_
  out
}

# Byte-order comparison of strings, whatever the session's collation:
# ranks in radix (C-locale) order.
zt_str_rank <- function(a, b) {
  u <- sort(unique(c(a, b)), method = "radix", na.last = NA)
  list(match(a, u), match(b, u))
}

# Numeric order with NaN equal to itself and above every number (D45),
# NA propagating.
zt_compare <- function(op, a, b, ta, tb) {
  if (identical(ta$id, "string")) {
    r <- zt_str_rank(a, b)
    a <- r[[1L]]
    b <- r[[2L]]
  } else if (identical(ta$id, "enum")) {
    a <- as.character(a)
    b <- as.character(b)
    return(switch(op, `==` = a == b, `!=` = a != b))
  } else {
    a <- unclass(a)
    b <- unclass(b)
    attributes(a) <- NULL
    attributes(b) <- NULL
    if (is.double(a) || is.double(b)) {
      na <- zt_is_null(a) | zt_is_null(b)
      an <- is.nan(a)
      bn <- is.nan(b)
      a2 <- ifelse(an, Inf, a)
      b2 <- ifelse(bn, Inf, b)
      # Break the Inf tie between NaN and Inf: NaN is greater.
      ra <- an * 1
      rb <- bn * 1
      cmp <- sign(ifelse(a2 == b2, ra - rb, ifelse(a2 < b2, -1, 1)))
      out <- switch(op, `==` = cmp == 0, `!=` = cmp != 0, `<` = cmp < 0,
                    `<=` = cmp <= 0, `>` = cmp > 0, `>=` = cmp >= 0)
      out[na] <- NA
      return(out)
    }
  }
  do.call(op, list(a, b))
}

zt_cmp_entry <- function(op, sql_op, types) {
  sigs <- list(
    sig(c("T", "T"), "bool", T = types),
    sig(c("int32", "float64"), "bool"),
    sig(c("float64", "int32"), "bool"),
    sig(c("timestamp", "timestamp"), "bool", check = zt_same_zoning)
  )
  vocab_entry(
    op, sigs,
    impl = function(v, t, r, n) zt_compare(op, v[[1L]], v[[2L]], t[[1L]], t[[2L]]),
    sql = function(a, t, r) {
      sprintf("(%s %s %s)", a[[1L]], sql_op, a[[2L]])
    },
    doc = "comparison"
  )
}

zt_strip <- function(x) {
  attributes(x) <- NULL
  x
}

zt_as_date <- function(x) structure(as.double(x), class = "Date")

zt_arith_entry <- function(op) {
  f <- match.fun(op)
  sigs <- list(
    sig(c("int32", "int32"), "int32"),
    sig(c("float64", "float64"), "float64"),
    sig(c("int32", "float64"), "float64"),
    sig(c("float64", "int32"), "float64")
  )
  if (op == "+") {
    sigs <- c(sigs, list(sig(c("date", "int32"), "date"),
                         sig(c("int32", "date"), "date")))
  }
  if (op == "-") {
    sigs <- c(sigs, list(sig(c("date", "int32"), "date"),
                         sig(c("date", "date"), "int32"),
                         sig("int32", "int32"), sig("float64", "float64")))
  }
  vocab_entry(
    op, sigs,
    impl = function(v, t, r, n) {
      if (length(v) == 1L) {
        return(if (r$id == "int32") zt_int_result(-as.double(v[[1L]])) else -v[[1L]])
      }
      a <- as.double(zt_strip(unclass(v[[1L]])))
      b <- as.double(zt_strip(unclass(v[[2L]])))
      out <- zt_na_wins(f(a, b), a, b)
      switch(r$id,
        int32 = zt_int_result(out),
        date = zt_as_date(out),
        out
      )
    },
    sql = function(a, t, r) {
      if (length(a) == 1L) return(sprintf("(- %s)", a[[1L]]))
      ids <- vapply(t, function(x) x$id, "")
      if (all(ids == "date") && op == "-") {
        return(sprintf("CAST((%s - %s) AS INTEGER)", a[[1L]], a[[2L]]))
      }
      if (any(ids == "date")) {
        return(sprintf("(%s %s %s)", a[[1L]], op, a[[2L]]))
      }
      if (r$id == "int32") {
        # Computed in BIGINT and range-checked, as the local executor does.
        return(sprintf("CAST((CAST(%s AS BIGINT) %s %s) AS INTEGER)",
                       a[[1L]], op, a[[2L]]))
      }
      sprintf("(CAST(%s AS DOUBLE) %s CAST(%s AS DOUBLE))", a[[1L]], op, a[[2L]])
    },
    doc = "arithmetic"
  )
}

zt_num1 <- function(name, f, sqlf, synonyms = character(), keep_int = FALSE,
                    doc = "") {
  sigs <- if (keep_int) {
    list(sig("int32", "int32"), sig("float64", "float64"))
  } else {
    list(sig("int32", "float64"), sig("float64", "float64"))
  }
  vocab_entry(name, sigs,
    impl = function(v, t, r, n) {
      x <- v[[1L]]
      if (r$id == "int32") return(x)
      suppressWarnings(f(as.double(x)))
    },
    sql = function(a, t, r) {
      if (r$id == "int32") return(a[[1L]])
      sqlf(sprintf("CAST(%s AS DOUBLE)", a[[1L]]))
    },
    synonyms = synonyms, doc = doc)
}

zt_trunc_unit <- function(unit, x, type) {
  if (identical(type$id, "date")) {
    lt <- as.POSIXlt(x, tz = "UTC")
    y <- lt$year + 1900L
    m <- lt$mon + 1L
    out <- switch(unit,
      year = sprintf("%04d-01-01", y),
      quarter = sprintf("%04d-%02d-01", y, (m - 1L) %/% 3L * 3L + 1L),
      month = sprintf("%04d-%02d-01", y, m),
      week = NULL,
      day = NULL
    )
    if (unit == "week") return(x - (lt$wday + 6L) %% 7L)
    if (unit == "day") return(x)
    out[is.na(x)] <- NA
    return(as.Date(out))
  }
  tz <- type$tz %||% "UTC"
  lt <- as.POSIXlt(x, tz = tz)
  fmt <- switch(unit,
    year = "%Y-01-01 00:00:00", quarter = NULL, month = "%Y-%m-01 00:00:00",
    week = NULL, day = "%Y-%m-%d 00:00:00", hour = "%Y-%m-%d %H:00:00",
    minute = "%Y-%m-%d %H:%M:00", second = "%Y-%m-%d %H:%M:%S"
  )
  if (unit == "quarter") {
    q <- (lt$mon %/% 3L) * 3L + 1L
    s <- sprintf("%04d-%02d-01 00:00:00", lt$year + 1900L, q)
  } else if (unit == "week") {
    d <- as.Date(format(x, "%Y-%m-%d", tz = tz)) - (lt$wday + 6L) %% 7L
    s <- paste(format(d), "00:00:00")
  } else {
    s <- format(x, fmt, tz = tz)
  }
  s[is.na(x)] <- NA
  out <- as.POSIXct(s, tz = tz, format = "%Y-%m-%d %H:%M:%S")
  attr(out, "tzone") <- tz
  out
}

zt_date_part <- function(part, x, type) {
  tz <- if (identical(type$id, "timestamp")) type$tz %||% "UTC" else "UTC"
  lt <- as.POSIXlt(x, tz = tz)
  out <- switch(part, year = lt$year + 1900L, month = lt$mon + 1L,
                day = lt$mday)
  out <- as.integer(out)
  out[is.na(x)] <- NA_integer_
  out
}

zt_like_regex <- function(p) {
  chars <- strsplit(p, "")[[1L]]
  rx <- vapply(chars, function(ch) {
    if (ch == "%") ".*" else if (ch == "_") "." else
      gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1", ch)
  }, "")
  paste0("^(?s)", paste(rx, collapse = ""), "$")
}

# Aggregate helpers: SQL's null rules (D46). The null elements are dropped;
# over no values the result is the type's missing value.
zt_agg_values <- function(x) x[!zt_is_null(x)]

zt_minmax <- function(x, type, want_max) {
  v <- zt_agg_values(x)
  if (!length(v)) return(na_of(type))
  if (identical(type$id, "string")) {
    s <- sort(unique(v), method = "radix")
    return(if (want_max) s[[length(s)]] else s[[1L]])
  }
  if (identical(type$id, "bool")) {
    return(if (want_max) any(v) else all(v))
  }
  raw <- zt_strip(unclass(v))
  nan <- is.nan(raw)
  if (want_max && any(nan)) {
    out <- NaN
  } else if (!want_max && all(nan)) {
    out <- NaN
  } else {
    r <- raw[!nan]
    out <- if (want_max) max(r) else min(r)
  }
  zt_restore(out, x, type)
}

zt_restore <- function(value, like, type) {
  switch(type$id,
    int32 = as.integer(value),
    date = zt_as_date(value),
    timestamp = structure(as.double(value), class = c("POSIXct", "POSIXt"),
                          tzone = type$tz %||% "UTC"),
    value
  )
}

zt_quote_sql_string <- function(x) paste0("'", gsub("'", "''", x, fixed = TRUE), "'")

# --- the table ------------------------------------------------------------------

zt_vocab_list <- list(
  # arithmetic
  zt_arith_entry("+"),
  zt_arith_entry("-"),
  zt_arith_entry("*"),
  vocab_entry("/", list(sig(c("int32", "int32"), "float64"),
                        sig(c("float64", "float64"), "float64"),
                        sig(c("int32", "float64"), "float64"),
                        sig(c("float64", "int32"), "float64")),
    impl = function(v, t, r, n) {
      a <- as.double(v[[1L]])
      b <- as.double(v[[2L]])
      zt_na_wins(a / b, a, b)
    },
    sql = function(a, t, r) {
      sprintf("(CAST(%s AS DOUBLE) / CAST(%s AS DOUBLE))", a[[1L]], a[[2L]])
    },
    doc = "arithmetic; always float64"),
  vocab_entry("%/%", list(sig(c("int32", "int32"), "int32"),
                          sig(c("float64", "float64"), "float64"),
                          sig(c("int32", "float64"), "float64"),
                          sig(c("float64", "int32"), "float64")),
    impl = function(v, t, r, n) {
      if (r$id == "int32") return(suppressWarnings(v[[1L]] %/% v[[2L]]))
      # floor(x / y), not R's own %/%, which differs for infinite operands
      # (D48).
      a <- as.double(v[[1L]])
      b <- as.double(v[[2L]])
      zt_na_wins(floor(a / b), a, b)
    },
    sql = function(a, t, r) {
      if (r$id == "int32") {
        return(sprintf(paste0("(CASE WHEN %2$s = 0 THEN NULL ELSE CAST(",
                              "floor(CAST(%1$s AS DOUBLE) / CAST(%2$s AS ",
                              "DOUBLE)) AS INTEGER) END)"), a[[1L]], a[[2L]]))
      }
      sprintf("floor(CAST(%s AS DOUBLE) / CAST(%s AS DOUBLE))", a[[1L]], a[[2L]])
    },
    nullable = "always", doc = "floor division; a zero int32 divisor gives NA"),
  vocab_entry("%%", list(sig(c("int32", "int32"), "int32"),
                         sig(c("float64", "float64"), "float64"),
                         sig(c("int32", "float64"), "float64"),
                         sig(c("float64", "int32"), "float64")),
    impl = function(v, t, r, n) {
      if (r$id == "int32") return(suppressWarnings(v[[1L]] %% v[[2L]]))
      # x - y * floor(x / y), not R's own %%, which differs for infinite
      # operands (D48).
      a <- as.double(v[[1L]])
      b <- as.double(v[[2L]])
      zt_na_wins(a - b * floor(a / b), a, b)
    },
    sql = function(a, t, r) {
      if (r$id == "int32") {
        return(sprintf(paste0("(CASE WHEN %2$s = 0 THEN NULL ELSE CAST(",
                              "((CAST(%1$s AS BIGINT) %% %2$s) + %2$s) %% %2$s",
                              " AS INTEGER) END)"), a[[1L]], a[[2L]]))
      }
      sprintf(paste0("(CAST(%1$s AS DOUBLE) - CAST(%2$s AS DOUBLE) * ",
                     "floor(CAST(%1$s AS DOUBLE) / CAST(%2$s AS DOUBLE)))"),
              a[[1L]], a[[2L]])
    },
    nullable = "always", doc = "modulo with the divisor's sign"),
  vocab_entry("^", list(sig(c("int32", "int32"), "float64"),
                        sig(c("float64", "float64"), "float64"),
                        sig(c("int32", "float64"), "float64"),
                        sig(c("float64", "int32"), "float64")),
    impl = function(v, t, r, n) {
      a <- as.double(v[[1L]])
      b <- as.double(v[[2L]])
      out <- a^b
      # NA propagates, unlike R's NA^0 and 1^NA (D46).
      out[zt_is_null(a) | zt_is_null(b)] <- NA_real_
      out
    },
    sql = function(a, t, r) {
      # R's power, which differs from IEEE 754's pow() for a negative base,
      # infinite ones included, with an infinite or fractional exponent
      # (NaN), and for a zero base with a negative exponent (Inf, whatever
      # the zero's sign).
      x <- sprintf("CAST(%s AS DOUBLE)", a[[1L]])
      y <- sprintf("CAST(%s AS DOUBLE)", a[[2L]])
      sprintf(paste0("(CASE WHEN %1$s = 0 AND %2$s < 0 THEN CAST('inf' AS DOUBLE)",
                     " WHEN %1$s < 0 AND (isinf(%2$s) OR %2$s <> floor(%2$s))",
                     " THEN CAST('nan' AS DOUBLE)",
                     " ELSE pow(%1$s, %2$s) END)"), x, y)
    },
    doc = "power, as R's ^; always float64"),
  zt_num1("abs", abs, function(x) sprintf("abs(%s)", x), keep_int = TRUE),
  zt_num1("sqrt", sqrt, function(x) sprintf("sqrt(%s)", x)),
  zt_num1("exp", exp, function(x) sprintf("exp(%s)", x)),
  zt_num1("log", log, function(x) sprintf(
    "(CASE WHEN %1$s < 0 THEN CAST('nan' AS DOUBLE) ELSE ln(%1$s) END)", x),
    doc = "natural logarithm"),
  # rounding
  vocab_entry("round", list(sig("int32", "int32"), sig("float64", "float64"),
                            sig(c("int32", "int32"), "int32"),
                            sig(c("float64", "int32"), "float64")),
    impl = function(v, t, r, n) {
      if (r$id == "int32") return(v[[1L]])
      d <- if (length(v) > 1L) v[[2L]] else 0L
      if (!length(v[[1L]]) || !length(d)) return(double())
      out <- round(v[[1L]], d)
      out[zt_is_null(d)] <- NA_real_
      out
    },
    sql = function(a, t, r) {
      if (r$id == "int32") return(a[[1L]])
      d <- if (length(a) > 1L) a[[2L]] else "0"
      sprintf("round_even(%s, %s)", a[[1L]], d)
    },
    arg_names = c("x", "digits"),
    doc = "rounding half to even, as R"),
  zt_num1("floor", floor, function(x) sprintf("floor(%s)", x), keep_int = TRUE),
  zt_num1("ceiling", ceiling, function(x) sprintf("ceiling(%s)", x),
          keep_int = TRUE),
  # comparison
  zt_cmp_entry("==", "=", zt_equatable),
  zt_cmp_entry("!=", "<>", zt_equatable),
  zt_cmp_entry("<", "<", zt_ordered),
  zt_cmp_entry("<=", "<=", zt_ordered),
  zt_cmp_entry(">", ">", zt_ordered),
  zt_cmp_entry(">=", ">=", zt_ordered),
  vocab_entry("between", list(
    sig(c("T", "T", "T"), "bool", T = zt_ordered),
    sig(c("int32", "float64", "float64"), "bool"),
    sig(c("float64", "int32", "int32"), "bool")),
    impl = function(v, t, r, n) {
      zt_compare(">=", v[[1L]], v[[2L]], t[[1L]], t[[2L]]) &
        zt_compare("<=", v[[1L]], v[[3L]], t[[1L]], t[[3L]])
    },
    sql = function(a, t, r) {
      sprintf("(%s BETWEEN %s AND %s)", a[[1L]], a[[2L]], a[[3L]])
    },
    doc = "lo <= x <= hi"),
  # logic
  vocab_entry("&", list(sig(c("bool", "bool"), "bool")),
    impl = function(v, t, r, n) v[[1L]] & v[[2L]],
    sql = function(a, t, r) sprintf("(%s AND %s)", a[[1L]], a[[2L]]),
    nullable = "propagate", doc = "three-valued and"),
  vocab_entry("|", list(sig(c("bool", "bool"), "bool")),
    impl = function(v, t, r, n) v[[1L]] | v[[2L]],
    sql = function(a, t, r) sprintf("(%s OR %s)", a[[1L]], a[[2L]]),
    doc = "three-valued or"),
  vocab_entry("!", list(sig("bool", "bool")),
    impl = function(v, t, r, n) !v[[1L]],
    sql = function(a, t, r) sprintf("(NOT %s)", a[[1L]]),
    doc = "not"),
  vocab_entry("is.na", lapply(zt_value_types, function(id) sig(id, "bool")),
    impl = function(v, t, r, n) zt_is_null(v[[1L]]),
    sql = function(a, t, r) sprintf("(%s IS NULL)", a[[1L]]),
    nullable = "never", synonyms = "is_null",
    doc = "missing; NaN is a value, not missing"),
  vocab_entry("coalesce", list(sig("T", "T", variadic = TRUE, T = zt_value_types)),
    impl = function(v, t, r, n) {
      out <- zt_recycle_n(v[[1L]], n)
      for (x in v[-1L]) {
        miss <- which(zt_is_null(out))
        if (!length(miss)) break
        x <- zt_recycle_n(x, n)
        out <- zt_assign(out, miss, zt_take(x, miss))
      }
      out
    },
    sql = function(a, t, r) sprintf("coalesce(%s)", paste(a, collapse = ", ")),
    nullable = "all", doc = "the first value that is not missing"),
  vocab_entry("ifelse", list(sig(c("bool", "T", "T"), "T", T = zt_value_types)),
    impl = function(v, t, r, n) {
      cond <- rep_len(v[[1L]], n)
      yes <- zt_recycle_n(v[[2L]], n)
      out <- zt_recycle_n(v[[3L]], n)
      take <- which(cond %in% TRUE)
      out <- zt_assign(out, take, zt_take(yes, take))
      zt_assign(out, which(is.na(cond)), na_of(r))
    },
    sql = function(a, t, r) sprintf(
      "(CASE WHEN %1$s IS NULL THEN NULL WHEN %1$s THEN %2$s ELSE %3$s END)",
      a[[1L]], a[[2L]], a[[3L]]),
    nullable = "always", arg_names = c("test", "yes", "no"),
    doc = "an NA condition gives NA, as in R"),
  # strings
  vocab_entry("nchar", list(sig("string", "int32")),
    impl = function(v, t, r, n) nchar(v[[1L]], type = "chars"),
    sql = function(a, t, r) sprintf("CAST(length(%s) AS INTEGER)", a[[1L]]),
    synonyms = "length", doc = "number of characters"),
  vocab_entry("upper", list(sig("string", "string")),
    impl = function(v, t, r, n) toupper(v[[1L]]),
    sql = function(a, t, r) sprintf("upper(%s)", a[[1L]]),
    synonyms = "toupper"),
  vocab_entry("lower", list(sig("string", "string")),
    impl = function(v, t, r, n) tolower(v[[1L]]),
    sql = function(a, t, r) sprintf("lower(%s)", a[[1L]]),
    synonyms = "tolower"),
  vocab_entry("substr", list(sig(c("string", "int32", "int32"), "string")),
    impl = function(v, t, r, n) substr(v[[1L]], v[[2L]], v[[3L]]),
    sql = function(a, t, r) sprintf(paste0(
      "(CASE WHEN %1$s IS NULL OR %2$s IS NULL OR %3$s IS NULL THEN NULL ",
      "WHEN %3$s < greatest(%2$s, 1) THEN '' ELSE substring(%1$s, ",
      "greatest(%2$s, 1), %3$s - greatest(%2$s, 1) + 1) END)"),
      a[[1L]], a[[2L]], a[[3L]]),
    arg_names = c("x", "start", "stop"),
    doc = "characters start to stop, as R's substr()"),
  vocab_entry("concat", list(sig("string", "string", variadic = TRUE)),
    impl = function(v, t, r, n) {
      out <- do.call(paste0, v)
      if (!length(out) || any(lengths(v) == 0L)) return(character())
      miss <- Reduce(`|`, lapply(v, function(x) rep_len(is.na(x), length(out))))
      out[miss] <- NA_character_
      out
    },
    sql = function(a, t, r) sprintf("(%s)", paste(a, collapse = " || ")),
    synonyms = "paste0", doc = "joins strings; NA if any is NA"),
  vocab_entry("trim", list(sig("string", "string")),
    impl = function(v, t, r, n) trimws(v[[1L]], whitespace = "[ \t\r\n]"),
    sql = function(a, t, r) sprintf(
      "trim(%s, ' ' || chr(9) || chr(13) || chr(10))", a[[1L]]),
    synonyms = "trimws", doc = "removes spaces, tabs and line breaks at both ends"),
  # patterns
  vocab_entry("like", list(sig(c("string", "string"), "bool")),
    impl = function(v, t, r, n) {
      p <- v[[2L]]
      x <- v[[1L]]
      m <- max(length(x), length(p))
      if (!length(x) || !length(p)) return(logical())
      x <- rep_len(x, m)
      p <- rep_len(p, m)
      out <- rep(NA, m)
      for (pat in unique(p[!is.na(p)])) {
        k <- which(p %in% pat & !is.na(x))
        out[k] <- grepl(zt_like_regex(pat), x[k], perl = TRUE)
      }
      out
    },
    sql = function(a, t, r) sprintf("(%s LIKE %s)", a[[1L]], a[[2L]]),
    doc = "SQL LIKE: % any run, _ one character"),
  vocab_entry("starts_with", list(sig(c("string", "string"), "bool")),
    impl = function(v, t, r, n) startsWith(v[[1L]], v[[2L]]),
    sql = function(a, t, r) sprintf("starts_with(%s, %s)", a[[1L]], a[[2L]]),
    synonyms = "startsWith"),
  # dates
  vocab_entry("year", list(sig("date", "int32"), sig("timestamp", "int32")),
    impl = function(v, t, r, n) zt_date_part("year", v[[1L]], t[[1L]]),
    sql = function(a, t, r) sprintf("CAST(year(%s) AS INTEGER)", a[[1L]])),
  vocab_entry("month", list(sig("date", "int32"), sig("timestamp", "int32")),
    impl = function(v, t, r, n) zt_date_part("month", v[[1L]], t[[1L]]),
    sql = function(a, t, r) sprintf("CAST(month(%s) AS INTEGER)", a[[1L]])),
  vocab_entry("day", list(sig("date", "int32"), sig("timestamp", "int32")),
    impl = function(v, t, r, n) zt_date_part("day", v[[1L]], t[[1L]]),
    sql = function(a, t, r) sprintf("CAST(day(%s) AS INTEGER)", a[[1L]])),
  vocab_entry("date_trunc", list(
    sig(c("string", "date"), "arg2",
        check = function(t) TRUE),
    sig(c("string", "timestamp"), "arg2")),
    impl = function(v, t, r, n) {
      unit <- v[[1L]]
      if (length(unit) != 1L || !unit %in% c("year", "quarter", "month",
                                             "week", "day", "hour", "minute",
                                             "second") ||
          identical(t[[2L]]$id, "date") && unit %in% c("hour", "minute", "second")) {
        zutable_abort("value", sprintf("date_trunc() has no unit \"%s\" for %s",
                                       unit, format(t[[2L]])), call = zt_eval_call())
      }
      zt_trunc_unit(unit, v[[2L]], t[[2L]])
    },
    sql = function(a, t, r) {
      if (identical(r$id, "date")) {
        return(sprintf("CAST(date_trunc(%s, %s) AS DATE)", a[[1L]], a[[2L]]))
      }
      sprintf("date_trunc(%s, %s)", a[[1L]], a[[2L]])
    },
    arg_names = c("unit", "x"),
    doc = "the start of the year, quarter, month, week (Monday), day, hour, minute or second"),
  # aggregates (SQL's null rules, D46)
  vocab_entry("count", list(sig(character(), "int32"),
                            lapply(zt_value_types, function(id) sig(id, "int32"))[[1L]]),
    impl = function(v, t, r, n) {
      if (!length(v)) return(as.integer(n))
      as.integer(sum(!zt_is_null(v[[1L]])))
    },
    sql = function(a, t, r) {
      if (!length(a)) return("CAST(count(*) AS INTEGER)")
      sprintf("CAST(count(%s) AS INTEGER)", a[[1L]])
    },
    kind = "aggregate", nullable = "never", masking = TRUE,
    doc = "rows, or values that are not missing"),
  vocab_entry("count_distinct", lapply(zt_equatable, function(id) sig(id, "int32")),
    impl = function(v, t, r, n) {
      as.integer(length(unique(zt_agg_values(v[[1L]]))))
    },
    sql = function(a, t, r) sprintf("CAST(count(DISTINCT %s) AS INTEGER)", a[[1L]]),
    kind = "aggregate", nullable = "never", masking = TRUE,
    synonyms = "n_distinct", doc = "distinct values that are not missing"),
  vocab_entry("sum", list(sig("int32", "float64"), sig("float64", "float64")),
    impl = function(v, t, r, n) {
      x <- zt_agg_values(as.double(v[[1L]]))
      if (!length(x)) NA_real_ else sum(x)
    },
    sql = function(a, t, r) sprintf("sum(CAST(%s AS DOUBLE))", a[[1L]]),
    kind = "aggregate", nullable = "always", doc = "always float64"),
  vocab_entry("mean", list(sig("int32", "float64"), sig("float64", "float64")),
    impl = function(v, t, r, n) {
      x <- zt_agg_values(as.double(v[[1L]]))
      if (!length(x)) NA_real_ else mean(x)
    },
    sql = function(a, t, r) sprintf("avg(CAST(%s AS DOUBLE))", a[[1L]]),
    kind = "aggregate", nullable = "always", synonyms = "avg"),
  vocab_entry("min", lapply(zt_ordered, function(id) sig(id, "arg1")),
    impl = function(v, t, r, n) zt_minmax(v[[1L]], t[[1L]], FALSE),
    sql = function(a, t, r) {
      sprintf("min(%s)", a[[1L]])
    },
    kind = "aggregate", nullable = "always"),
  vocab_entry("max", lapply(zt_ordered, function(id) sig(id, "arg1")),
    impl = function(v, t, r, n) zt_minmax(v[[1L]], t[[1L]], TRUE),
    sql = function(a, t, r) {
      sprintf("max(%s)", a[[1L]])
    },
    kind = "aggregate", nullable = "always"),
  vocab_entry("first", list(sig("T", "T", T = zt_value_types)),
    impl = function(v, t, r, n) {
      x <- v[[1L]]
      if (!zt_nrow_of(x)) na_of(r) else zt_take(x, 1L)
    },
    sql = function(a, t, r) sprintf("first(%s ORDER BY \".zt_row\")", a[[1L]]),
    kind = "aggregate", nullable = "always", doc = "the first value, missing or not"),
  vocab_entry("last", list(sig("T", "T", T = zt_value_types)),
    impl = function(v, t, r, n) {
      x <- v[[1L]]
      k <- zt_nrow_of(x)
      if (!k) na_of(r) else zt_take(x, k)
    },
    sql = function(a, t, r) sprintf("last(%s ORDER BY \".zt_row\")", a[[1L]]),
    kind = "aggregate", nullable = "always", doc = "the last value, missing or not"),
  vocab_entry("any", list(sig("bool", "bool")),
    impl = function(v, t, r, n) {
      x <- zt_agg_values(v[[1L]])
      if (!length(x)) NA else any(x)
    },
    sql = function(a, t, r) sprintf("bool_or(%s)", a[[1L]]),
    kind = "aggregate", nullable = "always"),
  vocab_entry("all", list(sig("bool", "bool")),
    impl = function(v, t, r, n) {
      x <- zt_agg_values(v[[1L]])
      if (!length(x)) NA else all(x)
    },
    sql = function(a, t, r) sprintf("bool_and(%s)", a[[1L]]),
    kind = "aggregate", nullable = "always")
)

# count's second signature: one argument of any value type.
zt_vocab_list[[which(vapply(zt_vocab_list, function(e) e$name, "") == "count")]]$sigs <-
  c(list(sig(character(), "int32")),
    lapply(zt_value_types, function(id) sig(id, "int32")))

# The special forms (case, cast, %in%, r) are typed by hand in R/expr.R and
# R/cast.R; their entries carry the rest of the row.
zt_vocab_list <- c(zt_vocab_list, list(
  vocab_entry("%in%", list(),
    impl = function(v, t, r, n) {
      x <- v[[1L]]
      out <- if (identical(t[[1L]]$id, "string")) x %in% v[[2L]] else
        zt_strip(unclass(x)) %in% zt_strip(unclass(v[[2L]]))
      out[zt_is_null(x)] <- NA
      out
    },
    sql = function(a, t, r) sprintf("(%s IN %s)", a[[1L]], a[[2L]]),
    doc = "membership in a set of constants; NA for a missing value"),
  vocab_entry("case", list(),
    impl = NULL, sql = NULL, nullable = "always",
    doc = "`condition ~ value` pairs and `.default`; an NA condition is skipped"),
  vocab_entry("cast", list(), impl = NULL, sql = NULL,
    doc = "conversion that errors on the first value it cannot represent")
))

names(zt_vocab_list) <- vapply(zt_vocab_list, function(e) e$name, "")
zt_vocab <- zt_vocab_list

zt_vocab_synonyms <- local({
  out <- character()
  for (e in zt_vocab) {
    for (s in e$synonyms) out[[s]] <- e$name
  }
  out
})

zt_vocab_lookup <- function(fn) {
  if (!is.null(zt_vocab[[fn]]) && length(zt_vocab[[fn]]$sigs)) {
    return(zt_vocab[[fn]])
  }
  canon <- zt_vocab_synonyms[fn]
  if (!is.na(canon)) return(zt_vocab[[canon]])
  NULL
}
