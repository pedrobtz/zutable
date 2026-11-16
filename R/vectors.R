# Types and R vectors (design §4.1): what type an R vector has, whether a
# vector is a valid value of a type, and each type's missing value.

# --- inference -------------------------------------------------------------

# The type of an R vector, or a zutable_type_error. `what` names the column
# in messages.
infer_type <- function(x, what = "column", call = NULL) {
  type <- infer_type_raw(x, what, call)
  zt_require_type_package(type, call)
}

infer_type_raw <- function(x, what, call) {
  bad <- function(msg) {
    zutable_abort("type", sprintf("column `%s`: %s", what, msg), call = call)
  }
  if (is.data.frame(x)) {
    s <- infer_schema(x, call)
    return(zt_type("struct", fields = s$fields))
  }
  if (is.factor(x)) {
    return(zt_type("enum", levels = levels(x)))
  }
  if (inherits(x, "Date")) {
    return(zt_type("date"))
  }
  if (inherits(x, "POSIXct")) {
    # D38: no zone means an instant shown in local time; typed as UTC.
    return(zt_timestamp("us", posixct_tz(x)))
  }
  if (inherits(x, "zutempo_instant")) {
    return(zt_timestamp("ns", "UTC"))
  }
  if (inherits(x, "integer64")) {
    return(zt_type("int64"))
  }
  if (inherits(x, "decimal")) {
    return(infer_decimal(x, bad))
  }
  ext <- zt_extension_for_class(x)
  if (!is.null(ext)) {
    return(ext)
  }
  if (is.object(x)) {
    return(zt_type("r_class", class = class(x)[[1L]]))
  }
  if (is.logical(x)) return(zt_type("bool"))
  if (is.integer(x)) return(zt_type("int32"))
  if (is.double(x)) return(zt_type("float64"))
  if (is.character(x)) return(zt_type("string"))
  if (is.list(x)) {
    return(infer_list(x, what, call, bad))
  }
  bad(sprintf("an R %s vector has no zutable type", typeof(x)))
}

posixct_tz <- function(x) {
  tz <- attr(x, "tzone")
  if (is.null(tz) || length(tz) == 0L || is.na(tz[[1L]]) ||
      !nzchar(tz[[1L]])) {
    return("UTC")
  }
  tz[[1L]]
}

infer_list <- function(x, what, call, bad) {
  present <- x[!vapply(x, is.null, NA)]
  if (length(present) == 0L) {
    bad("the element type of a list with no elements cannot be inferred; give a schema")
  }
  if (all(vapply(present, is.raw, NA))) {
    return(zt_type("binary"))
  }
  types <- lapply(present, infer_type_raw, what = what, call = call)
  first <- types[[1L]]
  for (t in types[-1L]) {
    if (!identical(t, first)) {
      bad(sprintf("list elements have different types: %s and %s",
                  format(first), format(t)))
    }
  }
  zt_type("list", value = first)
}

# decimal(p, s): the scale is the vector's; the precision is the smallest of
# Arrow's two widths, 38 and 76 digits, that holds every value (D39).
infer_decimal <- function(x, bad) {
  s <- decimal_scale(x)
  d <- decimal_digits(x)
  if (anyNA(d[!is.na(unclass(x))])) {
    bad("a decimal value that is not a finite number has no Arrow type")
  }
  p <- max(c(1L, d), na.rm = TRUE)
  if (p > 76L) {
    bad("a decimal value has more than 76 digits")
  }
  zt_type("decimal", precision = if (p <= 38L) 38L else 76L,
          scale = max(s, 0L))
}

decimal_scale <- function(x) {
  s <- attr(x, "scale")
  if (is.null(s)) 0L else as.integer(s)
}

# The number of digits of each value's unscaled integer, NA for a value
# that is missing or not a finite number.
decimal_digits <- function(x) {
  v <- unclass(x)
  ok <- !is.na(v) & grepl("^-?[0-9]+(\\.[0-9]+)?$", v)
  digits <- gsub("^0+", "", gsub("[-.]", "", v[ok]))
  out <- rep(NA_integer_, length(v))
  out[ok] <- pmax(nchar(digits), 1L)
  out
}

# --- checking a vector against a type -------------------------------------

# NULL when `x` is a valid vector of `type`, else the reason it is not.
# Element-wise checks of list and struct types make nested types enforced
# (§4.1).
vector_problem <- function(x, type) {
  plain <- function(test) if (test && !is.object(x)) NULL else "wrong vector"
  switch(type$id,
    bool = plain(is.logical(x)),
    int32 = plain(is.integer(x)),
    float64 = plain(is.double(x)),
    string = plain(is.character(x)),
    int64 = if (inherits(x, "zu_int64")) NULL else "not a zu_int64 vector",
    date = if (inherits(x, "Date")) NULL else "not a Date vector",
    timestamp = {
      if (identical(type$unit, "ns")) {
        if (inherits(x, "zutempo_instant")) NULL else "not a zutempo instant"
      } else if (!inherits(x, "POSIXct")) {
        "not a POSIXct vector"
      } else if (!is.null(type$tz) && !identical(posixct_tz(x), type$tz)) {
        sprintf("time zone %s, not %s", posixct_tz(x), type$tz)
      } else if (is.null(type$tz) && !identical(posixct_tz(x), "UTC")) {
        sprintf("time zone %s for a time without a zone", posixct_tz(x))
      }
    },
    decimal = {
      if (!inherits(x, "decimal")) {
        "not a decimal vector"
      } else if (decimal_scale(x) != type$scale) {
        sprintf("scale %d, not %d", decimal_scale(x), type$scale)
      } else {
        d <- decimal_digits(x)
        if (anyNA(d[!is.na(unclass(x))])) {
          "a decimal value that is not a finite number"
        } else if (any(d > type$precision, na.rm = TRUE)) {
          sprintf("a value with more than %d digits", type$precision)
        }
      }
    },
    enum = {
      if (!is.factor(x)) {
        "not a factor"
      } else if (!identical(levels(x), type$levels)) {
        "factor levels differ from the enum's"
      }
    },
    binary = {
      if (!is.list(x) || is.object(x)) {
        "not a list"
      } else if (!all(vapply(x, function(e) is.null(e) || is.raw(e), NA))) {
        "an element that is not a raw vector"
      }
    },
    list = {
      if (!is.list(x) || is.object(x)) {
        "not a list"
      } else {
        for (i in seq_along(x)) {
          e <- x[[i]]
          if (is.null(e)) next
          p <- vector_problem(e, type$value)
          if (!is.null(p)) {
            return(sprintf("element %d: %s", i, p))
          }
        }
        NULL
      }
    },
    struct = {
      if (!is.data.frame(x)) {
        "not a data frame"
      } else if (!identical(names(x), names(type$fields))) {
        "its columns differ from the struct's fields"
      } else {
        for (n in names(x)) {
          p <- vector_problem(x[[n]], type$fields[[n]]$type)
          if (!is.null(p)) {
            return(sprintf("field `%s`: %s", n, p))
          }
        }
        NULL
      }
    },
    r_class = if (inherits(x, type$class)) NULL else
      sprintf("not of class %s", type$class),
    extension = {
      entry <- zt_registry$extensions[[type$name]]
      if (inherits(x, entry$class)) NULL else
        sprintf("not of class %s", entry$class)
    },
    "unknown type"
  )
}

# Raise when `x` is not a valid vector of `type`.
check_vector <- function(x, type, what = "column", call = NULL) {
  p <- vector_problem(x, type)
  if (!is.null(p)) {
    zutable_abort("type", sprintf("column `%s` is not %s: %s", what,
                                  format(type), p), call = call)
  }
  invisible(x)
}

# --- missing values --------------------------------------------------------

#' A typed missing value
#'
#' `na(type)` is a length-one missing value of a type, for the types base R
#' has no `NA` literal for. It declares a column to be filled later:
#' `zutable(id = 1:3, total = na(decimal(18, 4)))`.
#'
#' @param type A type, as in [schema()].
#' @return A length-one vector of `type`, missing.
#' @export
#' @examples
#' na(int32)
#' na(timestamp("us", "UTC"))
#' na(enum(c("lo", "hi")))
na <- function(type) {
  type <- parse_type(substitute(type), parent.frame(), sys.call())
  na_of(type)
}

na_of <- function(type, call = NULL) {
  switch(type$id,
    bool = NA,
    int32 = NA_integer_,
    float64 = NA_real_,
    string = NA_character_,
    date = structure(NA_real_, class = "Date"),
    timestamp = {
      if (identical(type$unit, "ns")) {
        zutable_abort("type", paste(
          "na() of timestamp(\"ns\") waits on a missing-value constructor",
          "in 'zutempo'"
        ), call = call)
      }
      structure(NA_real_, class = c("POSIXct", "POSIXt"),
                tzone = type$tz %||% "UTC")
    },
    int64 = structure(int64_na_bits(), class = c("zu_int64", "integer64")),
    decimal = structure(NA_character_, scale = type$scale,
                        class = c("decimal", "vctrs_vctr")),
    enum = factor(NA_character_, levels = type$levels),
    binary = list(NULL),
    list = list(NULL),
    struct = {
      cols <- lapply(type$fields, function(f) na_of(f$type, call))
      structure(cols, names = names(type$fields), class = "data.frame",
                row.names = c(NA_integer_, -1L))
    },
    r_class = zutable_abort("type", sprintf(
      "r_class(\"%s\") has no typed missing value", type$class
    ), call = call),
    extension = {
      ptype <- zt_registry$extensions[[type$name]]$ptype
      out <- ptype[NA_integer_]
      # A class with no `[` method loses its attributes; restore them.
      if (!identical(class(out), class(ptype))) attributes(out) <- attributes(ptype)
      out
    }
  )
}

# INT64_MIN, bit64's NA, as the double whose bits it is.
int64_na_bits <- function() {
  readBin(as.raw(c(0, 0, 0, 0, 0, 0, 0, 0x80)), "double", size = 8L,
          endian = "little")
}

# --- POSIXct as microseconds ----------------------------------------------

# The limit of §4.1: a POSIXct within 2^33 seconds of 1970 holds the whole
# number of microseconds nearest its double exactly, through the trip to
# double seconds and back.
zt_posixct_limit <- 2^33

# Whole microseconds since 1970 nearest each stored double, as an exactly
# integral double, or a zutable_value_error for an instant outside the
# limit. Split into whole seconds and the fraction so no product rounds:
# the whole part times 1e6 is below 2^53, and the fraction is exact.
posixct_to_us <- function(x, what = "column", call = NULL) {
  secs <- as.double(unclass(x))
  attributes(secs) <- NULL
  out_of_range <- !is.na(secs) & !(abs(secs) < zt_posixct_limit)
  if (any(out_of_range)) {
    i <- which(out_of_range)[[1L]]
    zutable_abort("value", sprintf(paste(
      "column `%s`: row %d is %s seconds from 1970; a POSIXct holds exact",
      "microseconds only within 2^33 seconds (years 1698 to 2242)"
    ), what, i, format(secs[[i]], digits = 15L)), call = call)
  }
  whole <- floor(secs)
  whole * 1e6 + round((secs - whole) * 1e6)
}
