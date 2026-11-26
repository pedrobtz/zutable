#' Join keys as index pairs
#'
#' `grp_join()` matches the rows of `x` and `y` on key columns and returns
#' the index pairs, never a table. Pairs come in `x`'s row order and,
#' within a row of `x`, in `y`'s. `grp_match()` is the first match of each
#' row of `x`, as [base::match()] gives for one key, over one or several keys.
#'
#' `NA` matches `NA`; for doubles `NA` and `NaN` are different keys and
#' `-0` matches `0`. Strings match when their text does, whatever their
#' encoding; a factor matches by its labels, against a factor or a
#' character key. Integer, logical and double keys match by value. A
#' character key against a number, or an `integer64` key against anything
#' but another, is a `zutable_type_error`.
#'
#' @param x,y Key vectors (integer, double, logical, character, factor,
#'   `integer64`, or a list of raw vectors), or a data frame or list of
#'   them. A data frame uses all its columns, unless `by` names some.
#' @param by `NULL`, to pair the key columns of `x` and `y` by position, or
#'   the names of the key columns, when `x` and `y` are data frames or named
#'   lists. A named element, as in `c(customer = "id")`, pairs `x`'s
#'   `customer` with `y`'s `id`.
#' @param type `"inner"`, `"left"` (every row of `x`, with `NA` in `y` when
#'   it has no match), `"semi"` (the rows of `x` with a match) or `"anti"`
#'   (those without).
#' @param multiple When a row of `x` matches several rows of `y`: `"all"`
#'   pairs, the `"first"` or `"last"` match, or `"error"`, a
#'   `zutable_multiple_error` naming the first such key.
#' @return `grp_join()`: a list of `x` and `y`, integer row indices of one
#'   length; for `"semi"` and `"anti"`, `x` alone. `grp_match()`: an integer
#'   vector as long as `x`, `NA` where there is no match.
#' @export
#' @examples
#' grp_join(c("a", "b", "a"), c("b", "a", "a"))
#' grp_join(c(1, 2, 3), c(3, 1), type = "left")
#' grp_match(c("b", "z", "a"), c("a", "b", "b"))
#' orders <- data.frame(customer = c(10L, 20L, 10L), day = 1:3)
#' people <- data.frame(id = c(10L, 20L), name = c("Ada", "Linus"))
#' grp_join(orders, people, by = c(customer = "id"))
grp_join <- function(x, y, by = NULL, type = "inner", multiple = "all") {
  call <- sys.call()
  type <- zt_choice(type, c("inner", "left", "semi", "anti"), "type", call)
  multiple <- zt_choice(multiple, c("all", "first", "last", "error"),
                        "multiple", call)
  k <- zt_join_keys(x, y, by, call)
  zt_join_index(k, type, multiple, NULL, NULL, call)
}

#' @rdname grp_join
#' @export
grp_match <- function(x, y) {
  call <- sys.call()
  k <- zt_join_keys(x, y, NULL, call)
  zt_join_index(k, "left", "first", NULL, NULL, call)$y
}

# The key columns of each side, paired and converted to one native type
# per pair: list(x, y, i64, show), where show is x's columns as given, for
# an error to name a key by.
zt_join_keys <- function(x, y, by, call) {
  if (!is.null(by)) {
    if (!is.character(by) || !length(by) || anyNA(by) || any(by == "")) {
      zutable_abort("syntax", "`by` is NULL or the names of key columns", call = call)
    }
    xn <- names(by)
    if (is.null(xn)) xn <- by
    xn[xn == ""] <- by[xn == ""]
    yn <- unname(by)
    x <- zt_join_select(x, xn, "x", call)
    y <- zt_join_select(y, yn, "y", call)
  }
  xc <- zt_key_columns(list(x), call)
  yc <- zt_key_columns(list(y), call)
  if (!length(xc) || length(xc) != length(yc)) {
    zutable_abort("type", sprintf(
      "x has %d key columns and y has %d; they must be the same, and at least one",
      length(xc), length(yc)
    ), call = call)
  }
  zt_join_pair_keys(xc, yc, call)
}

zt_join_select <- function(v, cols, side, call) {
  if (!is.list(v) || is.null(names(v))) {
    zutable_abort("syntax", sprintf(
      "`by` names columns, so %s is a data frame or a named list", side
    ), call = call)
  }
  miss <- setdiff(cols, names(v))
  if (length(miss)) {
    zutable_abort("schema", sprintf("key `%s` is not a column of %s", miss[[1L]], side),
                  call = call)
  }
  # By position, so a name repeated in v takes the first.
  unname(lapply(cols, function(nm) v[[nm]]))
}

# Each pair of key columns to one native type (design-kernel 6.1):
# factors by their labels, numbers by value (to double when the types
# differ), strings, raw lists and integer64 only with their own kind.
zt_join_pair_keys <- function(xc, yc, call) {
  show <- xc
  i64 <- logical(length(xc))
  for (k in seq_along(xc)) {
    a <- xc[[k]]
    b <- yc[[k]]
    if (is.factor(a)) a <- as.character(a)
    if (is.factor(b)) b <- as.character(b)
    # After the labels: a factor's levels are its text here.
    zt_check_text(a, sprintf("key %d of x", k), call)
    zt_check_text(b, sprintf("key %d of y", k), call)
    kind <- function(v) {
      if (is.character(v)) "character" else if (is.list(v)) "raw list" else
        if (inherits(v, "integer64")) "integer64" else "number"
    }
    if (kind(a) != kind(b)) {
      zutable_abort("type", sprintf(
        "key %d is a %s in x and a %s in y; they cannot match", k, kind(a), kind(b)
      ), call = call)
    }
    i64[[k]] <- inherits(a, "integer64")
    a <- zt_native_keys(list(a))[[1L]]
    b <- zt_native_keys(list(b))[[1L]]
    if (typeof(a) != typeof(b)) {
      a <- as.double(a)
      b <- as.double(b)
    }
    xc[[k]] <- a
    yc[[k]] <- b
  }
  list(x = xc, y = yc, i64 = i64, show = show)
}

# The kernel's join of prepared keys (zt_join_keys): list(x, y), or list(x)
# for semi and anti. xmask, ymask: NULL, or rows that match nothing.
zt_join_index <- function(k, type, multiple, xmask, ymask, call,
                          sides = c("x", "y")) {
  ty <- match(type, c("inner", "left", "semi", "anti")) - 1L
  mu <- match(multiple, c("all", "first", "last", "error")) - 1L
  j <- .Call(zt_join, k$x, k$y, k$i64, ty, mu, xmask, ymask)
  if (!is.null(j$bad)) zt_multiple_abort(k$show, j$bad, j$count, call, sides)
  if (!is.null(j$pairs)) {
    zutable_abort("length", sprintf(
      "the join has %.0f pairs, more than the 2^31 - 1 rows a result can have",
      j$pairs
    ), call = call)
  }
  j
}

# multiple = "error": the first row of x with several matches, and its key;
# sides names the two tables, swapped for a right join.
zt_multiple_abort <- function(cols, i, count, call, sides = c("x", "y")) {
  # 15 digits, so a double names the key it is, not a rounding of it.
  key <- paste(vapply(cols, function(col) format(zt_take(col, i), digits = 15L), ""),
               collapse = ", ")
  zutable_abort("multiple", sprintf(
    "row %d of %s matches %d rows of %s on key (%s); multiple = \"error\"",
    i, sides[[1L]], count, sides[[2L]], key
  ), call = call)
}
