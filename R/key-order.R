#' Order and rank rows by keys
#'
#' `key_order()` gives the stable permutation that sorts rows by one or
#' more keys, as `order(method = "radix")` does; `key_rank()` gives each
#' row's rank, as `rank()` does. Both run the kernel's hybrid sort: the
#' keys become one normalised integer per row, sorted by radix, counting
#' sort, Vergesort or pdqsort, whichever its size and shape favour.
#'
#' The order is base R's: numbers ascending, `FALSE` before `TRUE`, factors
#' by level, `-0` equal to `0`. `NA` and `NaN` are equal, and go last with
#' `na.last = TRUE`, first with `FALSE`, and with `NA` their rows are left
#' out. `decreasing` reverses a key's order but not the stability: equal
#' keys keep row order. Strings sort by the bytes of their UTF-8 text,
#' or with `collate = TRUE` in the locale's order, through `stringi`'s
#' collation keys, which are computed once per distinct string.
#'
#' @param ... Key vectors of one length (integer, double, logical,
#'   character, factor, `integer64`, `Date`, `POSIXct`, or a list of raw
#'   vectors), or a data frame or list of them.
#' @param decreasing One logical, or one per key column.
#' @param na.last `TRUE`, `FALSE` or `NA`; for `key_rank()` also `"keep"`,
#'   which ranks a row with a missing key `NA`.
#' @param collate `FALSE` sorts strings by bytes; `TRUE` in the order of
#'   the current locale, as `stringi::stri_order()` does. `TRUE` needs the
#'   `stringi` package, and is a `zutable_collate_error` without it.
#' @param ties For `key_rank()`: `"min"` gives equal keys the lowest rank
#'   of their run, as `rank(ties.method = "min")`; `"first"` ranks them in
#'   row order; `"dense"` numbers the distinct keys 1, 2, ... A row with a
#'   missing key ranks on its own under `"min"`, as `rank()` ranks `NA`;
#'   under `"dense"` the rows of one missing key share a rank.
#' @return An integer vector: for `key_order()` a permutation (shorter
#'   than the input when `na.last = NA` drops rows), for `key_rank()` one
#'   rank per row.
#' @export
#' @examples
#' x <- c(3, 1, NA, 2, 1)
#' key_order(x)
#' key_order(x, decreasing = TRUE, na.last = FALSE)
#' key_order(c("b", "a", "b"), c(2, 1, 1))
#' key_rank(x)
#' key_rank(x, ties = "dense")
key_order <- function(..., decreasing = FALSE, na.last = TRUE,
                      collate = FALSE) {
  # One plain integer, double or logical vector: straight to the kernel,
  # for the many small sorts of a grouped operation (design-kernel 4.3).
  if (
    ...length() == 1L &&
      is.logical(decreasing) &&
      length(decreasing) == 1L &&
      !is.na(decreasing) &&
      is.logical(na.last) &&
      length(na.last) == 1L
  ) {
    x <- ..1
    if (
      is.null(attributes(x)) &&
        (is.double(x) || is.integer(x) || is.logical(x)) &&
        length(x) <= .Machine$integer.max
    ) {
      na <- if (is.na(na.last)) {
        -1L
      } else if (na.last) {
        1L
      } else {
        0L
      }
      return(.Call(zt_key_order, list(x), FALSE, decreasing, na))
    }
  }
  call <- sys.call()
  collate <- zt_check_collate(collate, call)
  k <- zt_sort_keys(list(...), decreasing, call)
  na <- zt_na_last(na.last, call, keep = FALSE)
  if (!length(k$keys)) {
    return(integer())
  }
  if (k$strings) {
    k <- zt_string_codes(k, collate)
  }
  .Call(zt_key_order, k$keys, k$i64, k$dec, na)
}

#' @rdname key_order
#' @export
key_rank <- function(
  ...,
  ties = c("min", "first", "dense"),
  decreasing = FALSE,
  na.last = TRUE,
  collate = FALSE
) {
  call <- sys.call()
  ties <- zt_match_ties(ties, call)
  collate <- zt_check_collate(collate, call)
  k <- zt_sort_keys(list(...), decreasing, call)
  # "keep" ranks the rows without a missing key among themselves, as NA
  # does, and keeps the others as NA; the kernel ranks those rows 0.
  keep <- identical(na.last, "keep")
  na <- if (keep) -1L else zt_na_last(na.last, call, keep = TRUE)
  if (!length(k$keys)) {
    return(integer())
  }
  if (k$strings) {
    k <- zt_string_codes(k, collate)
  }
  r <- .Call(
    zt_key_rank,
    k$keys,
    k$i64,
    k$dec,
    na,
    match(ties, c("min", "first", "dense"))
  )
  if (na < 0L) {
    if (keep) r[r == 0L] <- NA_integer_ else r <- r[r != 0L]
  }
  r
}

zt_match_ties <- function(ties, call) {
  if (!is.character(ties) || !length(ties) || anyNA(ties)) {
    zutable_abort(
      "type",
      "`ties` is \"min\", \"first\" or \"dense\"",
      call = call
    )
  }
  if (length(ties) > 1L) {
    ties <- ties[[1L]]
  }
  if (!ties %in% c("min", "first", "dense")) {
    zutable_abort(
      "type",
      sprintf("`ties` is \"min\", \"first\" or \"dense\", not \"%s\"", ties),
      call = call
    )
  }
  ties
}

# na.last as the kernel's integer: 1 last, 0 first, -1 dropped.
zt_na_last <- function(na.last, call, keep) {
  if (!is.logical(na.last) || length(na.last) != 1L) {
    zutable_abort(
      "type",
      if (keep) {
        "`na.last` is TRUE, FALSE, NA or \"keep\""
      } else {
        "`na.last` is TRUE, FALSE or NA"
      },
      call = call
    )
  }
  if (is.na(na.last)) {
    -1L
  } else if (na.last) {
    1L
  } else {
    0L
  }
}

#' Sort values
#'
#' `key_sort()` returns `x` sorted, as `sort(x, method = "radix")` does, by
#' the order of [key_order()]. The result remembers that it is sorted and
#' whether it holds a missing value, so a later `sort()`, `is.unsorted()`
#' or `anyNA()` on it answers at once, without a pass over the values.
#' Modifying the result in place forgets both.
#'
#' Numbers, logicals, factors and dates are marked. Strings are not marked
#' sorted, since base R's sortedness of strings is its own collation, which
#' byte order and `stringi`'s need not match, and base R reads no missing
#' value mark on strings; nor is an `integer64` vector, whose order is not
#' that of its doubles.
#'
#' @param x A key vector: integer, double, logical, character, factor,
#'   `integer64`, `Date`, `POSIXct`, or a list of raw vectors.
#' @inheritParams key_order
#' @param decreasing `TRUE` or `FALSE`.
#' @return `x` in sorted order, with its class and levels; without its
#'   missing values when `na.last = NA`.
#' @export
#' @examples
#' s <- key_sort(c(3, 1, NA, 2))
#' s
#' is.unsorted(s, na.rm = TRUE)
#' key_sort(c("b", "A", "a"))
#' if (requireNamespace("stringi", quietly = TRUE)) {
#'   key_sort(c("b", "A", "a"), collate = TRUE)
#' }
key_sort <- function(x, decreasing = FALSE, na.last = TRUE, collate = FALSE) {
  call <- sys.call()
  cols <- zt_key_columns(list(x), call)
  if (length(cols) != 1L) {
    zutable_abort("type", "`x` is one key vector", call = call)
  }
  if (!is.logical(decreasing) || length(decreasing) != 1L || is.na(decreasing)) {
    zutable_abort("type", "`decreasing` is TRUE or FALSE", call = call)
  }
  o <- key_order(x, decreasing = decreasing, na.last = na.last,
                 collate = collate)
  zt_mark_sorted(x[o], decreasing, na.last)
}

# y, already sorted, wrapped with what is known of it (src/altrep.c): its
# sortedness in base R's codes and whether it has no missing value. A list
# or an integer64 vector is returned as it is; strings carry no_na only.
zt_mark_sorted <- function(y, decreasing, na.last) {
  if (!typeof(y) %in% c("integer", "double", "logical", "character") ||
      inherits(y, "integer64")) {
    return(y)
  }
  no_na <- !anyNA(y)
  # R's codes (Rinternals.h): 1 increasing and -1 decreasing with NA last,
  # 2 and -2 with NA first; NA_integer_ is UNKNOWN_SORTEDNESS.
  sorted <- if (is.character(y)) {
    NA_integer_
  } else if (no_na || isTRUE(na.last)) {
    if (decreasing) -1L else 1L
  } else {
    if (decreasing) -2L else 2L
  }
  a <- attributes(y)
  attributes(y) <- NULL
  w <- .Call(zt_sorted_wrap, y, sorted, no_na)
  attributes(w) <- a
  w
}

zt_check_collate <- function(collate, call) {
  if (!is.logical(collate) || length(collate) != 1L || is.na(collate)) {
    zutable_abort("type", "`collate` is TRUE or FALSE", call = call)
  }
  if (collate && !zt_has_stringi()) {
    zutable_abort(
      "collate",
      "`collate = TRUE` needs the stringi package; install it, or sort by bytes with `collate = FALSE`",
      call = call
    )
  }
  collate
}

zt_has_stringi <- function() requireNamespace("stringi", quietly = TRUE)

# The key columns as the kernel takes them: integer (factor codes, raw,
# Date), logical, double (integer64 flagged, Date and POSIXct stripped);
# `strings` when a character or raw-list key needs zt_string_codes().
zt_sort_keys <- function(args, decreasing, call) {
  cols <- zt_key_columns(args, call)
  if (
    !is.logical(decreasing) ||
      anyNA(decreasing) ||
      !(length(decreasing) %in% c(1L, length(cols)))
  ) {
    zutable_abort(
      "type",
      sprintf(
        "`decreasing` is one TRUE or FALSE, or one per key column (%d)",
        length(cols)
      ),
      call = call
    )
  }
  dec <- rep_len(decreasing, length(cols))
  i64 <- vapply(cols, function(k) inherits(k, "integer64"), NA)
  strings <- any(vapply(cols, function(k) is.character(k) || is.list(k), NA))
  list(keys = zt_native_keys(cols), i64 = i64, dec = dec, strings = strings)
}

# Character and raw-list keys as integer codes in their order (design-kernel
# 6.3, axis N): the rows are grouped, the distinct strings ranked by the
# kernel's string sort (zutable/strsort.h), byte order of the UTF-8 text or
# of stringi's collation keys, and each row coded by its string's rank;
# missing stays missing.
zt_string_codes <- function(k, collate = FALSE) {
  k$keys <- lapply(k$keys, function(v) {
    if (is.character(v) || is.list(v)) zt_str_codes(v, collate) else v
  })
  k$strings <- FALSE
  k
}

zt_str_codes <- function(v, collate) {
  if (is.character(v)) {
    v <- enc2utf8(v)
  }
  g <- zt_grp_native(list(v), length(v))
  u <- v[g$first]
  if (collate && is.character(u)) {
    u <- stringi::stri_sort_key(u)
  }
  .Call(zt_strings_rank, u)[g$id]
}
