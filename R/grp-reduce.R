#' Reduce values by group
#'
#' `grp_reduce()` computes a statistic of `x` for each group of `by`, in one
#' pass over the rows. With several columns in `x`, each with its own `fn`,
#' all of them are reduced in that one pass, and the rows are grouped once.
#'
#' The statistics follow base R: `sum`, `prod` and `mean` are base `sum()`,
#' `prod()` and `mean()` over each group's values, bit for bit, and return
#' double, for integer `x` too. `min` and `max` keep `x`'s type and class;
#' character values compare by their bytes in UTF-8, not by locale. `count`
#' is the group's size, `nobs` its values that are not missing, and
#' `first` and `last` its first and last value.
#'
#' With `na.rm = TRUE`, the default, missing values (`NA`, and `NaN` for
#' doubles, as [is.na()] has them) are left out; a group with no other
#' value gives `NA` for `sum`, `prod`, `mean`, `min` and `max`, where base
#' `sum()` would give 0 and `min()` `Inf`. With `na.rm = FALSE` a missing
#' value makes the group's statistic missing, as in base R, and `first` and
#' `last` return the value in place.
#'
#' @param x A vector, or a list or data frame of vectors as long as the
#'   keys; a list is several columns, so a list column goes inside one. `count`, `nobs`, `first` and `last` take any vector; `min` and
#'   `max` also integer, double, logical, character, `Date` and `POSIXct`
#'   ones; `sum`, `prod` and `mean` take numbers and logicals.
#' @param by The result of [grp()], or key vectors for [grp()] to group by:
#'   a vector, or a data frame or list of them.
#' @param fn The statistic: `"sum"`, `"prod"`, `"mean"`, `"min"`, `"max"`,
#'   `"count"`, `"nobs"`, `"first"` or `"last"`; one, or one per column of
#'   `x`.
#' @param na.rm Leave missing values out.
#' @param broadcast `"none"` for one value per group, in the order of
#'   `grp()`'s identifiers, so that it lines up with `keys`; or one value per
#'   row: `"replace"`, each row's group value, `"subtract"`, `x` less it, or
#'   `"divide"`, `x` over it. A character or factor `x` takes `"none"` and
#'   `"replace"` only.
#' @return A vector when `x` is one vector, else a list with one per column.
#'   When `by` is key vectors, the [grp()] result is attached as the
#'   attribute `"groups"`, so that its `keys` and `sizes` need no second
#'   grouping.
#' @export
#' @examples
#' g <- grp(c("a", "b", "a", "b"))
#' grp_reduce(c(1, 2, 3, NA), g, "sum")
#' grp_reduce(c(1, 2, 3, NA), g, "sum", na.rm = FALSE)
#' grp_reduce(list(v = c(1, 2, 3, 4), w = 4:1), g, c("mean", "max"))
#' grp_reduce(c(1, 2, 3, 4), g, "mean", broadcast = "subtract")
#' s <- grp_reduce(c(5, 1, 2), c("x", "y", "x"), "sum")
#' attr(s, "groups")$keys
grp_reduce <- function(x, by, fn = "sum", na.rm = TRUE, broadcast = "none") {
  call <- sys.call()
  one <- !is.data.frame(x) && !(is.list(x) && !is.object(x))
  xs <- if (one) list(x) else as.list(x)
  if (!length(xs)) zutable_abort("type", "`x` has no columns", call = call)
  if (!is.logical(na.rm) || length(na.rm) != 1L || is.na(na.rm)) {
    zutable_abort("type", "`na.rm` is TRUE or FALSE", call = call)
  }
  broadcast <- zt_choice(broadcast, c("none", "replace", "subtract", "divide"),
                         "broadcast", call)
  if (!is.character(fn) || anyNA(fn) || !length(fn) ||
      !(length(fn) %in% c(1L, length(xs)))) {
    zutable_abort("fn", sprintf(
      "`fn` is one statistic name, or one for each of the %d columns of `x`", length(xs)
    ), call = call)
  }
  unknown <- setdiff(fn, zt_reduce_fns)
  if (length(unknown)) {
    zutable_abort("fn", sprintf("`fn` \"%s\" is not one of %s", unknown[[1L]],
                                paste0("\"", zt_reduce_fns, "\"", collapse = ", ")),
                  call = call)
  }
  fn <- rep_len(fn, length(xs))
  keyed <- !zt_is_grp(by)
  g <- if (keyed) zt_grp_build(zt_key_columns(list(by), call), FALSE) else zt_check_grp(by, call)
  n <- length(g$id)
  prep <- vector("list", length(xs))
  for (k in seq_along(xs)) {
    v <- xs[[k]]
    if (is.data.frame(v) || is.null(v) || !is.vector(v) && !is.atomic(v)) {
      zutable_abort("type", sprintf("column %d of `x` is not a vector", k), call = call)
    }
    if (length(v) != n) {
      zutable_abort("length", sprintf(
        "column %d of `x` has %.0f values for %d rows of keys", k, as.double(length(v)), n
      ), call = call)
    }
    prep[[k]] <- zt_reduce_prepare(v, fn[[k]], na.rm, broadcast, k, call)
  }
  res <- .Call(zt_reduce_routine(), g$id, as.integer(g$n), lapply(prep, function(p) p$x),
               match(fn, zt_reduce_fns) - 1L, rep(na.rm, length(xs)),
               rep(TRUE, length(xs)))
  out <- vector("list", length(xs))
  for (k in seq_along(xs)) {
    r <- prep[[k]]$post(res[[k]])
    out[[k]] <- switch(broadcast,
      none = r,
      replace = zt_take(r, g$id),
      subtract = xs[[k]] - r[g$id],
      divide = xs[[k]] / r[g$id]
    )
  }
  names(out) <- names(xs)
  if (one) out <- out[[1L]]
  if (keyed) attr(out, "groups") <- g
  out
}

zt_reduce_fns <- c("sum", "prod", "mean", "min", "max", "count", "nobs", "first", "last")

# A grp() result, as grp_reduce()'s `by` may be one: the names it has.
zt_is_grp <- function(by) {
  is.list(by) && !is.data.frame(by) &&
    identical(names(by), c("id", "n", "sizes", "starts", "order", "keys"))
}

# A grp() object, as the kernel reads it (#68): id integer, one per row,
# in 1 .. n; n one integer >= 0, never coerced; sizes and starts integer,
# n of them; order integer, one per row; keys a list. A hand-edited one is
# a classed error here, never the kernel's.
zt_check_grp <- function(g, call) {
  n <- g$n
  if (!is.integer(n) || length(n) != 1L || is.na(n) || n < 0L) {
    zutable_abort("type", "`by` is a grp() result, and its `n` is one integer, at least 0",
                  call = call)
  }
  rows <- length(g$id)
  ok <- is.integer(g$id) && is.integer(g$sizes) && length(g$sizes) == n &&
    is.integer(g$starts) && length(g$starts) == n &&
    is.integer(g$order) && length(g$order) == rows && is.list(g$keys)
  if (!ok) {
    zutable_abort("type", sprintf(
      "`by` is a grp() result, whose `id` and `order` are integer, one per row, and `sizes` and `starts` integer, %d of them",
      n
    ), call = call)
  }
  if (rows && (anyNA(g$id) || min(g$id) < 1L || max(g$id) > n)) {
    zutable_abort("value", sprintf(
      "`by` is a grp() result, whose `id` holds group numbers 1 .. %d", n
    ), call = call)
  }
  g
}

# What the kernel reads for column v under fn (x: integer, logical, double
# or NULL), and post, which turns the kernel's result into grp_reduce()'s.
zt_reduce_prepare <- function(v, fn, na_rm, broadcast, k, call) {
  numeric <- (is.numeric(v) || is.logical(v)) && !inherits(v, "integer64")
  ordered <- numeric || is.character(v) ||
    ((is.double(v) || is.integer(v)) && !is.factor(v) && !inherits(v, "integer64") &&
       (inherits(v, "Date") || inherits(v, "POSIXct")))
  refuse <- function(what) {
    zutable_abort("fn", sprintf("`fn` \"%s\" is not defined for column %d, of class %s%s",
                                fn, k, class(v)[[1L]], what), call = call)
  }
  if (fn %in% c("sum", "prod", "mean") && !numeric) refuse("")
  if (fn %in% c("min", "max") && !ordered) refuse("")
  if (broadcast %in% c("subtract", "divide") && !numeric) {
    zutable_abort("fn", sprintf(
      "broadcast \"%s\" needs numbers, and column %d is of class %s", broadcast, k,
      class(v)[[1L]]
    ), call = call)
  }
  # Without a copy when there is nothing to strip.
  plain <- function(v) {
    if (!is.null(attributes(v))) attributes(v) <- NULL
    v
  }
  # Missing as is.na() has it, as an integer column with NA where missing.
  present <- function(v) {
    if ((is.integer(v) || is.logical(v) || is.double(v)) && !inherits(v, "integer64")) {
      return(plain(v))
    }
    s <- rep(1L, length(v))
    s[is.na(v)] <- NA_integer_
    s
  }
  switch(fn,
    sum = , prod = , mean = list(x = plain(v), post = identity),
    min = , max = {
      if (is.character(v)) {
        zt_check_text(v, sprintf("column %d of `x`", k), call)
        # Byte order, through the kernel's sorted groups (design-kernel 6.3):
        # each string's rank among the distinct ones, then back.
        s <- zt_grp_build(list(v), TRUE)
        code <- s$id
        code[is.na(v)] <- NA_integer_
        list(x = code, post = function(r) {
          out <- s$keys[[1L]][r]
          attributes(out) <- NULL
          out
        })
      } else if (is.logical(v)) {
        list(x = plain(v), post = identity)
      } else {
        keep <- attributes(v)[setdiff(names(attributes(v)), c("names", "dim", "dimnames"))]
        list(x = plain(v), post = function(r) {
          attributes(r) <- keep
          r
        })
      }
    },
    count = list(x = NULL, post = identity),
    nobs = list(x = present(v), post = identity),
    first = , last = list(x = if (na_rm) present(v) else NULL, post = function(r) {
      out <- v[r]
      names(out) <- NULL
      out
    })
  )
}

# Base sum(), prod() and mean() accumulate in long double unless R was
# built without it (capabilities("long.double") FALSE, R CMD check's nold
# leg), and then in double; the kernel takes the same, to stay bit for bit.
zt_long_double <- function() isTRUE(capabilities("long.double"))
zt_reduce_routine <- function() if (zt_long_double()) zt_reduce_r else zt_reduce_r_double

# The executor's reductions (design 5.3, D46): SQL's null rules, so NA is
# missing and dropped, and NaN is a value. id: group ids 1 .. ng; xs: the
# columns the kernel reads, as zt_reduce_prepare() makes them.
zt_reduce_ids <- function(id, ng, xs, fns, na_rm = TRUE) {
  .Call(zt_reduce_routine(), id, as.integer(ng), xs, match(fns, zt_reduce_fns) - 1L,
        rep_len(na_rm, length(xs)), rep(FALSE, length(xs)))
}
