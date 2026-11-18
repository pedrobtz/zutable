#' Group rows by keys
#'
#' `grp()` gives each row the identifier of its key's group, with the
#' number of groups, each group's size, and the order that puts each
#' group's rows together. It is the kernel the bracket's `by` runs on.
#'
#' Identifiers follow first appearance, so for one key `grp(x)$id` is
#' `match(x, unique(x))`; with `sort = TRUE` they follow the keys' sort
#' order, `NA` last, and `g$keys` is sorted. `NA` equals `NA`; for doubles
#' `NA` and `NaN` are different keys and `-0` equals `0`. Strings are equal
#' when their text is, whatever their encoding.
#'
#' @param ... Key vectors of one length (integer, double, logical,
#'   character, factor, `integer64`, or a list of raw vectors), or a data
#'   frame or list of them.
#' @param sort Number the groups in key order rather than first appearance.
#' @return A list: `id` (integer, 1-based), `n`, `sizes`, `starts` (into
#'   `order`), `order` (a permutation, stable within a group) and `keys`
#'   (the key columns, one row per group, in identifier order).
#' @export
#' @examples
#' g <- grp(c("b", "a", "b", NA))
#' g$id
#' g$keys
#' grp(c(2, 1, 2), c("x", "x", "y"), sort = TRUE)$id
grp <- function(..., sort = FALSE) {
  call <- sys.call()
  keys <- zt_key_columns(list(...), call)
  if (!is.logical(sort) || length(sort) != 1L || is.na(sort)) {
    zutable_abort("type", "`sort` is TRUE or FALSE", call = call)
  }
  zt_grp_build(keys, sort)
}

# grp() of checked key columns (zt_key_columns()).
zt_grp_build <- function(keys, sort) {
  n <- if (length(keys)) length(keys[[1L]]) else 0L
  if (isTRUE(sort)) {
    g <- zt_grp_sort_route(keys, n)
    if (!is.null(g)) return(zt_mark_first_key(g))
  }
  g <- zt_grp_native(keys, n)
  out <- list(id = g$id, n = g$n, sizes = g$sizes, starts = g$starts,
              order = g$order,
              keys = lapply(keys, zt_take, idx = g$first))
  if (isTRUE(sort)) {
    if (g$n > 1L) out <- zt_grp_sorted(out, n)
    out <- zt_mark_first_key(out)
  }
  out
}

# With sort = TRUE the first key column of g$keys is sorted, NA last: it
# carries that, as key_sort()'s values do (D22).
zt_mark_first_key <- function(g) {
  if (length(g$keys)) {
    g$keys[[1L]] <- zt_mark_sorted(g$keys[[1L]], FALSE, TRUE)
  }
  g
}

zt_grp_native <- function(keys, n, force_bits = NA_integer_) {
  .Call(zt_grp, zt_native_keys(keys), zt_i64_keys(keys), as.double(n),
        as.integer(force_bits))
}

# grp(sort = TRUE) by sorting every row and cutting the runs, when the keys
# are fixed width and the rule of D44 says it beats hashing (design-kernel
# 4.2, axis O); NULL to hash instead. force = TRUE sorts whenever the keys
# allow it (a test hook).
zt_grp_sort_route <- function(keys, n, force = FALSE) {
  if (!length(keys) || any(vapply(keys, function(k) is.character(k) || is.list(k), NA))) {
    return(NULL)
  }
  g <- .Call(zt_grp_sort, zt_native_keys(keys), zt_i64_keys(keys), as.double(n),
             isTRUE(force))
  if (is.null(g)) return(NULL)
  list(id = g$id, n = g$n, sizes = g$sizes, starts = g$starts, order = g$order,
       keys = lapply(keys, zt_take, idx = g$first))
}

zt_i64_keys <- function(keys) vapply(keys, function(k) inherits(k, "integer64"), NA)

zt_native_keys <- function(keys) {
  lapply(keys, function(k) {
    if (is.factor(k)) return(as.integer(unclass(k)))
    if (is.raw(k)) return(as.integer(k))
    if (is.list(k)) return(k)
    attributes(k) <- NULL
    k
  })
}

# The key columns of grp()'s arguments: vectors, data frames and lists of
# them, of one length, of the six kinds (design-kernel 6.1).
zt_key_columns <- function(args, call) {
  cols <- list()
  for (a in args) {
    if (is.data.frame(a) || (is.list(a) && !is.object(a) &&
                             !all(vapply(a, function(e) is.null(e) || is.raw(e), NA)))) {
      cols <- c(cols, unname(as.list(a)))
    } else {
      cols <- c(cols, list(a))
    }
  }
  lens <- vapply(cols, length, 0)
  if (length(unique(lens)) > 1L) {
    zutable_abort("length", sprintf("key columns have lengths %s",
                                    paste(unique(lens), collapse = ", ")), call = call)
  }
  if (length(lens) && lens[[1L]] > .Machine$integer.max) {
    zutable_abort("length", "a key column has more than 2^31 - 1 rows", call = call)
  }
  for (k in cols) {
    # typeof(), not is.integer(), which is FALSE for a factor.
    type <- typeof(k)
    ok <- type %in% c("integer", "logical", "double", "character", "raw") ||
      (type == "list" && !is.object(k) &&
         all(vapply(k, function(e) is.null(e) || is.raw(e), NA)))
    if (!ok) {
      zutable_abort("type", sprintf(
        "a key column of class %s is not one of the key kinds", class(k)[[1L]]
      ), call = call)
    }
  }
  cols
}

# Renumber groups in the keys' sort order, NA last (design-kernel 6.2): the
# kernel's sort over the distinct keys, for the keys and sizes the sort
# route (zt_grp_sort_route) leaves to hashing. NA and NaN are separate
# groups that tie in the order, so they keep first appearance.
zt_grp_sorted <- function(g, n) {
  k <- zt_sort_keys(g$keys, FALSE, sys.call())
  if (k$strings) k <- zt_string_codes(k)
  o <- .Call(zt_key_order, k$keys, k$i64, k$dec, 1L)
  newid <- integer(g$n)
  newid[o] <- seq_len(g$n)
  id <- newid[g$id]
  sizes <- g$sizes[o]
  ord <- order(id, method = "radix")
  list(id = id, n = g$n, sizes = sizes,
       starts = cumsum(c(1L, sizes))[seq_len(g$n)], order = ord,
       keys = lapply(g$keys, zt_take, idx = o))
}
