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
#' keys keep row order. Strings sort by the bytes of their UTF-8 text.
#'
#' @param ... Key vectors of one length (integer, double, logical,
#'   character, factor, `integer64`, `Date`, `POSIXct`, or a list of raw
#'   vectors), or a data frame or list of them.
#' @param decreasing One logical, or one per key column.
#' @param na.last `TRUE`, `FALSE` or `NA`; for `key_rank()` also `"keep"`,
#'   which ranks a row with a missing key `NA`.
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
key_order <- function(..., decreasing = FALSE, na.last = TRUE) {
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
      is.null(attributes(x)) && (is.double(x) || is.integer(x) || is.logical(x))
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
  k <- zt_sort_keys(list(...), decreasing, call)
  na <- zt_na_last(na.last, call, keep = FALSE)
  if (!length(k$keys)) {
    return(integer())
  }
  if (k$base) {
    return(zt_base_order(k, na))
  }
  .Call(zt_key_order, k$keys, k$i64, k$dec, na)
}

#' @rdname key_order
#' @export
key_rank <- function(
  ...,
  ties = c("min", "first", "dense"),
  decreasing = FALSE,
  na.last = TRUE
) {
  call <- sys.call()
  ties <- zt_match_ties(ties, call)
  k <- zt_sort_keys(list(...), decreasing, call)
  # "keep" ranks the rows without a missing key among themselves, as NA
  # does, and keeps the others as NA; the kernel ranks those rows 0.
  keep <- identical(na.last, "keep")
  na <- if (keep) -1L else zt_na_last(na.last, call, keep = TRUE)
  if (!length(k$keys)) {
    return(integer())
  }
  if (k$base) {
    k <- zt_base_codes(k)
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

# The key columns as the kernel takes them: integer (factor codes, raw,
# Date), logical, double (integer64 flagged, Date and POSIXct stripped);
# `base` when a character or raw-list key sends the order to base R.
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
  base <- any(vapply(cols, function(k) is.character(k) || is.list(k), NA))
  keys <- lapply(cols, function(k) {
    if (is.factor(k)) {
      return(as.integer(unclass(k)))
    }
    if (is.raw(k)) {
      return(as.integer(k))
    }
    if (is.list(k)) {
      return(k)
    }
    attributes(k) <- NULL
    k
  })
  list(keys = keys, i64 = i64, dec = dec, base = base)
}

# Strings and raw lists until the kernel sorts them (Stage 12): every
# other key becomes its dense rank, missing kept, and base R's radix order
# sorts strings in C-locale byte order of their UTF-8 text.
zt_base_codes <- function(k) {
  keys <- lapply(seq_along(k$keys), function(j) {
    v <- k$keys[[j]]
    if (is.character(v)) {
      return(enc2utf8(v))
    }
    if (is.list(v)) {
      return(vapply(
        v,
        function(e) {
          if (is.null(e)) {
            NA_character_
          } else {
            paste(format(as.hexmode(as.integer(e)), width = 2L), collapse = "")
          }
        },
        ""
      ))
    }
    r <- .Call(zt_key_rank, list(v), k$i64[j], FALSE, 1L, 3L)
    r[is.na(v)] <- NA_integer_
    r
  })
  # Ranks of each key in base order, so the kernel ranks the composite.
  codes <- lapply(seq_along(keys), function(j) {
    v <- keys[[j]]
    if (!is.character(v)) {
      return(v)
    }
    u <- sort(unique(v[!is.na(v)]), method = "radix")
    match(v, u)
  })
  list(keys = codes, i64 = rep(FALSE, length(codes)), dec = k$dec, base = FALSE)
}

zt_base_order <- function(k, na) {
  k <- zt_base_codes(k)
  .Call(zt_key_order, k$keys, k$i64, k$dec, na)
}
