# cast() (design §4.3, §7.1): conversion between types that errors on the
# first value it cannot represent, never a silent NA or a rounded value.

zt_cast_targets <- list(
  bool = c("bool", "int32", "float64", "string"),
  int32 = c("int32", "bool", "float64", "string", "int64"),
  int64 = "int64",
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
  # int64's vector lives in zuint (§4.1): absent, a type error naming it.
  zt_require_type_package(to, ctx$call)
  zt_node("call", fn = "cast", args = list(x), type = to,
          nullable = x$nullable, aggregate = x$aggregate)
}

# int32 into int64, exact (§4.3), as zuint's vector.
zt_int32_to_int64 <- function(x) {
  attributes(x) <- NULL
  getExportedValue("zuint", "int64")(x)
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

# Shortest decimal text that reads back as the same double (Ryu, through
# zufast), with the spellings DuckDB uses for the non-finite values (D49).
zt_format_double <- function(x) {
  x <- as.double(x)
  out <- .Call(zt_format_f64, x)
  out[is.nan(x)] <- "nan"
  out[x %in% Inf] <- "inf"
  out[x %in% -Inf] <- "-inf"
  out[zt_is_null(x)] <- NA_character_
  out
}

# A correctly rounded double for each string, or NA (zufast's fast_float);
# R's as.double() is not correctly rounded on every platform.
zt_parse_double <- function(x) {
  .Call(zt_parse_f64, enc2utf8(trimws(as.character(x))))
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
    int64 = zt_int32_to_int64(x),
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
      d <- zt_parse_double(x)
      zt_cast_fail(x, !zt_is_null(d), from, to)
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
  values <- lapply(node$args[-seq_len(k)], function(a) zt_recycle_n(zt_eval(a, cols, n), n))
  out <- values[[k + 1L]]
  done <- rep(FALSE, n)
  for (i in seq_len(k)) {
    take <- !done & conds[[i]] %in% TRUE
    out <- zt_assign(out, take, zt_take(values[[i]], take))
    done <- done | take
  }
  out
}
