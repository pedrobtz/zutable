# cast() (design §4.3, §7.1): conversion between types that errors on the
# first value it cannot represent, never a silent NA or a rounded value.

zt_cast_targets <- list(
  bool = c("bool", "int32", "float64", "string"),
  int32 = c("int32", "bool", "float64", "string"),
  float64 = c("float64", "int32", "string"),
  string = c("string", "bool", "int32", "float64", "date", "timestamp",
             "enum"),
  date = c("date", "string", "timestamp"),
  timestamp = c("timestamp", "date", "string"),
  enum = c("enum", "string")
)

zt_type_cast <- function(x, to, ctx) {
  from <- x$type
  if (zt_is_lit(x) && is.null(from)) {
    # cast(NA, type): the type's missing value.
    return(zt_lit_node(na_of(to), to))
  }
  ok <- to$id %in% (zt_cast_targets[[from$id]] %||% character())
  if (!ok || identical(to$id, "timestamp") && identical(to$unit, "ns")) {
    zutable_abort("type", sprintf("cast() from %s to %s is not supported",
                                  format(from), format(to)), call = ctx$call)
  }
  zt_node("call", fn = "cast", args = list(x), type = to,
          nullable = x$nullable, aggregate = x$aggregate)
}

zt_cast_fail <- function(x, ok, from, to) {
  bad <- which(!ok & !zt_is_null(x))
  if (length(bad)) {
    zutable_abort("value", sprintf(
      "cast() from %s to %s: value %d, %s, cannot be represented",
      format(from), format(to), bad[[1L]],
      encodeString(as.character(zt_take(x, bad[[1L]])), quote = '"')
    ))
  }
}

# Shortest decimal text that reads back as the same double, with the
# spellings DuckDB uses for the non-finite values.
zt_format_double <- function(x) {
  out <- rep(NA_character_, length(x))
  for (i in which(!zt_is_null(x))) {
    v <- x[[i]]
    out[[i]] <- if (is.nan(v)) "nan" else if (v == Inf) "inf" else
      if (v == -Inf) "-inf" else {
        s <- NULL
        for (d in 15:17) {
          s <- sprintf(paste0("%.", d, "g"), v)
          if (as.double(s) == v) break
        }
        s
      }
  }
  out
}

zt_format_timestamp <- function(x, tz) {
  secs <- zt_strip(unclass(x))
  whole <- floor(secs)
  us <- round((secs - whole) * 1e6)
  base <- format(.POSIXct(whole, tz), "%Y-%m-%d %H:%M:%S", tz = tz)
  frac <- ifelse(us == 0, "", sub("0+$", "", sprintf(".%06d", as.integer(us))))
  out <- paste0(base, frac)
  out[zt_is_null(secs)] <- NA_character_
  out
}

zt_cast_value <- function(x, from, to) {
  f <- from$id
  t <- to$id
  if (f == t && t != "timestamp" && t != "enum") return(x)
  switch(t,
    bool = {
      if (f == "int32") return(x != 0L)
      v <- tolower(trimws(x))
      out <- ifelse(v %in% c("true", "t"), TRUE,
                    ifelse(v %in% c("false", "f"), FALSE, NA))
      zt_cast_fail(x, !is.na(out), from, to)
      out
    },
    int32 = {
      if (f == "bool") return(as.integer(x))
      if (f == "float64") {
        ok <- is.finite(x) & x == trunc(x) & abs(x) <= .Machine$integer.max
        zt_cast_fail(x, ok, from, to)
        return(as.integer(x))
      }
      v <- trimws(x)
      ok <- grepl("^[+-]?[0-9]+$", v)
      d <- suppressWarnings(as.double(v))
      ok <- ok & !is.na(d) & abs(d) <= .Machine$integer.max
      zt_cast_fail(x, ok, from, to)
      as.integer(d)
    },
    float64 = {
      if (f %in% c("bool", "int32")) return(as.double(x))
      d <- suppressWarnings(as.double(trimws(x)))
      zt_cast_fail(x, !is.na(d) | is.nan(d), from, to)
      d
    },
    string = switch(f,
      bool = ifelse(x, "true", "false"),
      int32 = as.character(x),
      float64 = zt_format_double(x),
      date = format(x, "%Y-%m-%d"),
      timestamp = zt_format_timestamp(x, from$tz %||% "UTC"),
      enum = as.character(x)
    ),
    date = {
      if (f == "timestamp") {
        return(as.Date(format(x, "%Y-%m-%d", tz = from$tz %||% "UTC")))
      }
      d <- zt_lit_adapt(x, to)
      if (is.null(d)) {
        ok <- vapply(x, function(v) !is.null(zt_lit_adapt(v, to)), NA)
        zt_cast_fail(x, ok, from, to)
      }
      d
    },
    timestamp = {
      tz <- to$tz %||% "UTC"
      if (f == "timestamp") {
        attr(x, "tzone") <- tz
        return(x)
      }
      if (f == "date") {
        out <- as.POSIXct(format(x, "%Y-%m-%d"), tz = tz, format = "%Y-%m-%d")
        attr(out, "tzone") <- tz
        return(out)
      }
      out <- zt_parse_timestamp(x, tz)
      if (is.null(out)) {
        ok <- vapply(x, function(v) !is.null(zt_parse_timestamp(v, tz)), NA)
        zt_cast_fail(x, ok, from, to)
      }
      out
    },
    enum = {
      v <- as.character(x)
      ok <- v %in% to$levels
      zt_cast_fail(x, ok, from, to)
      factor(v, levels = to$levels)
    }
  )
}

zt_eval_case <- function(node, cols, n) {
  k <- node$n_conds
  conds <- lapply(node$args[seq_len(k)], function(a) rep_len(zt_eval(a, cols, n), n))
  values <- lapply(node$args[-seq_len(k)], function(a) {
    v <- zt_eval(a, cols, n)
    if (zt_nrow_of(v) == 1L && n != 1L) rep(v, length.out = n) else v
  })
  out <- values[[k + 1L]]
  done <- rep(FALSE, n)
  for (i in seq_len(k)) {
    take <- !done & conds[[i]] %in% TRUE
    out[take] <- values[[i]][take]
    done <- done | take
  }
  out
}
