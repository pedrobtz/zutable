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
    ), call = zt_eval_call())
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

# The nearest whole microsecond first (§4.1), then split, so a fraction that
# rounds to 10^6 microseconds carries into the second (#51). The count is an
# exactly integral double below 2^53 within the limit of posixct_to_us().
zt_format_timestamp <- function(x, tz) {
  secs <- zt_strip(unclass(x))
  count <- posixct_to_us(secs, "timestamp", zt_eval_call())
  whole <- floor(count / 1e6)
  us <- count - whole * 1e6
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
      date = zt_format_date(x),
      timestamp = zt_format_timestamp(x, from$tz %||% "UTC"),
      enum = as.character(x)
    ),
    date = {
      if (f == "timestamp") {
        wall <- zt_wall_clock(floor(posixct_to_us(x, "timestamp", zt_eval_call()) / 1e6),
                              from$tz %||% "UTC")
        return(zt_as_date(floor(wall / 86400)))
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
        # §4.3: a value with a part finer than the target unit cannot be
        # represented there (#59).
        step <- c(s = 1e6, ms = 1e3, us = 1)[[to$unit]]
        if (step > 1) {
          us <- posixct_to_us(x, "timestamp", zt_eval_call())
          zt_cast_fail(x, is.na(us) | us %% step == 0, from, to)
        }
        attr(x, "tzone") <- tz
        return(x)
      }
      if (f == "date") {
        # D63: the first instant of the day on the local wall clock, within
        # 2^33 seconds of 1970 (posixct_to_us(), #69).
        out <- zt_wall_to_instant(zt_strip(unclass(x)) * 86400, tz)
        zt_cast_fail(x, is.na(out) | abs(out) < zt_posixct_limit, from, to)
        return(.POSIXct(out, tz))
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

# --- the civil calendar and the wall clock ------------------------------------

# Days from 1970-01-01 of a proleptic Gregorian date, for any year
# (H. Hinnant's days_from_civil, as zufast's datetime.h has it); exact in
# doubles, with %/% as floor division.
zt_days_from_civil <- function(y, m, d) {
  y <- y - (m <= 2)
  era <- y %/% 400
  yoe <- y - era * 400
  doy <- (153 * (m + ifelse(m > 2, -3, 9)) + 2) %/% 5 + d - 1
  doe <- yoe * 365 + yoe %/% 4 - yoe %/% 100 + doy
  era * 146097 + doe - 719468
}

zt_civil_from_days <- function(z) {
  z <- z + 719468
  era <- z %/% 146097
  doe <- z - era * 146097
  yoe <- (doe - doe %/% 1460 + doe %/% 36524 - doe %/% 146096) %/% 365
  doy <- doe - (365 * yoe + yoe %/% 4 - yoe %/% 100)
  mp <- (5 * doy + 2) %/% 153
  d <- doy - (153 * mp + 2) %/% 5 + 1
  m <- mp + ifelse(mp < 10, 3, -9)
  list(y = yoe + era * 400 + (m <= 2), m = m, d = d)
}

# A date's ISO 8601 text through zufast: YYYY-MM-DD for years 0000 to 9999,
# the expanded form with a sign and six digits otherwise (#58).
zt_format_date <- function(x) {
  .Call(zt_format_date_days, as.double(zt_strip(unclass(x))))
}

# The wall clock in `tz` at whole-second instants `t`, as seconds counted
# as if the wall clock were UTC.
zt_wall_clock <- function(t, tz) {
  lt <- as.POSIXlt(.POSIXct(t, tz), tz = tz)
  zt_days_from_civil(lt$year + 1900, lt$mon + 1, lt$mday) * 86400 +
    lt$hour * 3600 + lt$min * 60 + floor(lt$sec)
}

# The UTC offset of `tz` at whole-second instants `t`, in seconds.
zt_zone_offset <- function(t, tz) zt_wall_clock(t, tz) - t

# D63: the instant at which `tz`'s wall clock reads `wall` (seconds counted
# as if the wall clock were UTC). A wall time that does not exist (a
# spring-forward gap) is the first instant after the gap. One that occurs
# twice keeps the offset `prefer` (the input's) when it exists at that
# offset, and takes the earlier instant otherwise. Never NA for a value.
zt_wall_to_instant <- function(wall, tz, prefer = NULL) {
  out <- rep(NA_real_, length(wall))
  ok <- !is.na(wall)
  if (!any(ok)) return(out)
  w <- floor(wall[ok])
  frac <- wall[ok] - w
  cands <- list(zt_zone_offset(w - 172800, tz), zt_zone_offset(w + 172800, tz),
                zt_zone_offset(w, tz))
  if (!is.null(prefer)) cands <- c(list(prefer[ok]), cands)
  valid <- lapply(cands, function(o) zt_zone_offset(w - o, tz) == o)
  res <- rep(NA_real_, length(w))
  if (!is.null(prefer)) {
    res[valid[[1L]]] <- (w - cands[[1L]])[valid[[1L]]]
  }
  # The earlier instant is the one at the larger offset.
  best <- rep(-Inf, length(w))
  for (i in seq_along(cands)) {
    best <- ifelse(valid[[i]], pmax(best, cands[[i]]), best)
  }
  pick <- is.na(res) & is.finite(best)
  res[pick] <- (w - best)[pick]
  gap <- is.na(res)
  if (any(gap)) {
    # The transition lies in (w - max offset, w - min offset]: search for
    # the first second at which the offset is no longer the one before.
    os <- do.call(cbind, cands)[gap, , drop = FALSE]
    lo <- w[gap] - apply(os, 1L, max)
    hi <- w[gap] - apply(os, 1L, min)
    before <- zt_zone_offset(lo, tz)
    while (any(hi - lo > 1)) {
      mid <- floor((lo + hi) / 2)
      moved <- zt_zone_offset(mid, tz) != before
      hi <- ifelse(moved, mid, hi)
      lo <- ifelse(moved, lo, mid)
    }
    res[gap] <- hi
    frac[gap] <- 0
  }
  out[ok] <- res + frac
  out
}

# ISO 8601 date-times read in `tz`, each string by its own form (#54):
# "YYYY-MM-DD", or that with " " or "T" and "HH:MM", "HH:MM:SS" or
# "HH:MM:SS.f" (one to six digits). NULL when any string is in no form, or
# names a date or time that does not exist; local times are resolved by
# D63's rule.
zt_parse_timestamp <- function(value, tz) {
  pat <- paste0("^([0-9]{4})-([0-9]{2})-([0-9]{2})",
                "(?:[ T]([0-9]{2}):([0-9]{2})(?::([0-9]{2})(?:\\.([0-9]{1,6}))?)?)?$")
  value <- as.character(value)
  ok <- !is.na(value)
  m <- regmatches(value[ok], regexec(pat, value[ok], perl = TRUE))
  if (any(lengths(m) == 0L)) return(NULL)
  f <- matrix(unlist(m), ncol = 8L, byrow = TRUE)
  num <- function(j, default = 0) {
    v <- suppressWarnings(as.double(f[, j]))
    v[!nzchar(f[, j])] <- default
    v
  }
  y <- num(2L); mo <- num(3L); d <- num(4L)
  h <- num(5L); mi <- num(6L); s <- num(7L)
  us <- as.double(substr(paste0(f[, 8L], "000000"), 1L, 6L))
  days <- zt_days_from_civil(y, mo, d)
  back <- zt_civil_from_days(days)
  if (any(mo < 1 | mo > 12 | back$m != mo | back$d != d | h > 23 | mi > 59 |
          s > 59)) {
    return(NULL)
  }
  out <- rep(NA_real_, length(value))
  out[ok] <- zt_wall_to_instant(days * 86400 + h * 3600 + mi * 60 + s + us / 1e6, tz)
  # Past 2^33 seconds a POSIXct holds no exact microsecond (posixct_to_us()),
  # so such a string names no timestamp (#69).
  if (any(abs(out[ok]) >= zt_posixct_limit)) return(NULL)
  .POSIXct(out, tz)
}
