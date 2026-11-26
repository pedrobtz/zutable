# Joins and binding (design §10). join() runs on the kernel's grp_join()
# (design-kernel 6.4); the reference join in R over match() stays as its
# oracle (D29), under options(zutable.executor = "reference").

#' Join two tables
#'
#' `join()` matches the rows of `x` and `y` on key columns. Pairs come in
#' `x`'s row order and, within a row of `x`, in `y`'s; `right` and `full`
#' joins add `y`'s rows in `y`'s order. Key columns appear once, under
#' `x`'s names; for a row only `y` has, they take `y`'s values.
#'
#' @param x,y Zutables.
#' @param on The keys: a column, `.(a, b)`, or `.(id == customer_id)`
#'   where the names differ. Each pair of keys must have the same type.
#' @param how `"inner"`, `"left"`, `"right"`, `"full"`, `"semi"` (the rows
#'   of `x` with a match) or `"anti"` (those without).
#' @param multiple When a row of `x` matches several rows of `y` (for a
#'   right join, a row of `y` several of `x`): `"all"` pairs, the
#'   `"first"` or `"last"` match, or `"error"`, a `zutable_multiple_error`.
#' @param na_equal Whether a missing key matches a missing key: `TRUE`, as
#'   R and data.table do, or `FALSE`, as SQL does.
#' @param suffix Two suffixes for non-key columns both tables have, such as
#'   `c(".x", ".y")`; without it such a clash is a `zutable_schema_error`.
#' @return A zutable.
#' @export
#' @examples
#' orders <- zutable(id = c(1L, 2L, 3L), customer = c(10L, 20L, 10L))
#' people <- zutable(customer_id = c(10L, 20L), name = c("Ada", "Linus"))
#' join(orders, people, on = .(customer == customer_id))
#' join(orders, people, on = .(customer == customer_id), how = "anti")
join <- function(x, y, on, how = "inner", multiple = "all", na_equal = TRUE,
                 suffix = NULL) {
  call <- sys.call()
  if (!is_zutable(x) || !is_zutable(y)) {
    zutable_abort("type", "join() takes two zutables", call = call)
  }
  zt_validate(x, call)
  zt_validate(y, call)
  how <- zt_choice(how, c("inner", "left", "right", "full", "semi", "anti"),
                   "how", call)
  multiple <- zt_choice(multiple, c("all", "first", "last", "error"),
                        "multiple", call)
  if (!is.logical(na_equal) || length(na_equal) != 1L || is.na(na_equal)) {
    zutable_abort("syntax", "`na_equal` is TRUE or FALSE", call = call)
  }
  if (!is.null(suffix) && (!is.character(suffix) || length(suffix) != 2L ||
                           anyNA(suffix) || identical(suffix[[1L]], suffix[[2L]]))) {
    zutable_abort("syntax", "`suffix` is two different strings", call = call)
  }
  keys <- zt_parse_on(substitute(on), x, y, call)
  pairs <- if (identical(getOption("zutable.executor", "kernel"), "reference")) {
    zt_join_pairs(x, y, keys, how, multiple, na_equal, call)
  } else {
    zt_join_pairs_kernel(x, y, keys, how, multiple, na_equal, call)
  }
  zt_join_build(x, y, keys, pairs, how, suffix, call)
}

zt_choice <- function(v, choices, what, call) {
  if (!is.character(v) || length(v) != 1L || !v %in% choices) {
    zutable_abort("syntax", sprintf("`%s` is one of %s", what,
                                    paste0('"', choices, '"', collapse = ", ")),
                  call = call)
  }
  v
}

# on = id, .(a, b), .(id == customer_id), or c("a", "b"): pairs of names.
zt_parse_on <- function(e, x, y, call) {
  bad <- function(msg) zutable_abort("syntax", msg, call = call)
  if (is.character(e) || (is.call(e) && identical(e[[1L]], as.name("c")))) {
    v <- eval(e)
    e <- as.call(c(as.name("."), lapply(v, as.name)))
  }
  items <- if (is.call(e) && identical(e[[1L]], as.name("."))) as.list(e)[-1L] else list(e)
  if (!length(items)) bad("`on` names at least one key")
  xs <- character()
  ys <- character()
  for (it in items) {
    if (is.symbol(it)) {
      a <- b <- as.character(it)
    } else if (is.call(it) && identical(it[[1L]], as.name("==")) &&
               is.symbol(it[[2L]]) && is.symbol(it[[3L]])) {
      a <- as.character(it[[2L]])
      b <- as.character(it[[3L]])
    } else {
      bad("each key of `on` is a column, or `x_col == y_col`")
    }
    if (!a %in% names(x)) {
      zutable_abort("schema", sprintf("key `%s` is not a column of x", a), call = call)
    }
    if (!b %in% names(y)) {
      zutable_abort("schema", sprintf("key `%s` is not a column of y", b), call = call)
    }
    tx <- attr(x, "schema")$fields[[a]]$type
    ty <- attr(y, "schema")$fields[[b]]$type
    if (!identical(tx, ty)) {
      zutable_abort("type", sprintf(
        "key `%s` is %s in x and `%s` is %s in y; the types must be the same",
        a, format(tx), b, format(ty)
      ), call = call)
    }
    if (!tx$id %in% c(zt_equatable, "int64", "decimal")) {
      zutable_abort("type", sprintf("cannot join on a value of type %s", format(tx)),
                    call = call)
    }
    xs <- c(xs, a)
    ys <- c(ys, b)
  }
  if (anyDuplicated(xs) || anyDuplicated(ys)) bad("a key is named twice in `on`")
  list(x = xs, y = ys)
}

# int64 values (doubles holding the bits) as text of their two 32-bit
# halves: as doubles NA's bits read as -0 and some values as NaN, which
# match() would merge with 0 or with each other (#60).
zt_int64_bits_key <- function(bits) {
  h <- matrix(readBin(writeBin(bits, raw(), endian = "little"), "integer",
                      n = 2L * length(bits), size = 4L, endian = "little"), nrow = 2L)
  paste(h[1L, ], h[2L, ])
}

# Index pairs (x row, y row): x's order, then y's within an x row; NA in
# `yi` for an x row with no match (left), NA in `xi` for a y row with none.
zt_join_pairs <- function(x, y, keys, how, multiple, na_equal, call,
                          sides = c("x", "y")) {
  if (how == "right") {
    # The left join of y with x, in y's order, then x's within a y row;
    # `multiple` counts rows of x per row of y.
    r <- zt_join_pairs(y, x, list(x = keys$y, y = keys$x), "left",
                       multiple, na_equal, call, sides = c("y", "x"))
    return(list(xi = r$yi, yi = r$xi))
  }
  nx <- .row_names_info(x, 2L)
  ny <- .row_names_info(y, 2L)
  code <- NULL
  miss_x <- logical(nx)
  miss_y <- logical(ny)
  for (k in seq_along(keys$x)) {
    a <- x[[keys$x[[k]]]]
    b <- y[[keys$y[[k]]]]
    v <- if (is.factor(a)) {
      c(as.character(a), as.character(b))
    } else if (inherits(a, "integer64")) {
      zt_int64_bits_key(c(zt_strip(unclass(a)), zt_strip(unclass(b))))
    } else {
      c(zt_strip(unclass(a)), zt_strip(unclass(b)))
    }
    miss_x <- miss_x | zt_is_null(a)
    miss_y <- miss_y | zt_is_null(b)
    ck <- match(v, unique(v))
    if (is.null(code)) {
      code <- ck
    } else {
      combined <- paste(code, ck)
      code <- match(combined, unique(combined))
    }
  }
  xc <- code[seq_len(nx)]
  yc <- code[nx + seq_len(ny)]
  if (!na_equal) {
    # SQL: a missing key matches nothing.
    xc[miss_x] <- NA_integer_
    yc[miss_y] <- NA_integer_
  }
  by_code <- split(seq_len(ny), factor(yc, levels = seq_len(max(c(code, 0L)))))
  hits <- lapply(xc, function(cd) if (is.na(cd)) integer() else by_code[[cd]])
  counts <- lengths(hits)
  if (how %in% c("semi", "anti")) {
    keep <- if (how == "semi") which(counts > 0L) else which(counts == 0L)
    return(list(xi = keep, yi = NULL))
  }
  if (multiple == "error" && any(counts > 1L)) {
    i <- which(counts > 1L)[[1L]]
    zt_multiple_abort(lapply(keys$x, function(k) x[[k]]), i, counts[[i]], call, sides)
  }
  if (multiple == "first") hits <- lapply(hits, utils::head, 1L)
  if (multiple == "last") hits <- lapply(hits, utils::tail, 1L)
  counts <- lengths(hits)
  if (how %in% c("left", "full")) {
    hits[counts == 0L] <- list(NA_integer_)
    counts <- lengths(hits)
  }
  xi <- rep(seq_len(nx), counts)
  yi <- unlist(hits, use.names = FALSE)
  if (how == "inner") {
    keep <- !is.na(yi)
    xi <- xi[keep]
    yi <- yi[keep]
  }
  if (how == "full") {
    extra <- setdiff(seq_len(ny), yi)
    xi <- c(xi, rep(NA_integer_, length(extra)))
    yi <- c(yi, extra)
  }
  list(xi = as.integer(xi), yi = as.integer(yi))
}

# The same pairs as zt_join_pairs(), from the kernel: inner, left, semi and
# anti from grp_join(); right as the left join of y with x, swapped; full
# as the left join with the rows of y no pair has (design-kernel 6.4).
zt_join_pairs_kernel <- function(x, y, keys, how, multiple, na_equal, call,
                                 sides = c("x", "y")) {
  if (how == "right") {
    r <- zt_join_pairs_kernel(y, x, list(x = keys$y, y = keys$x), "left",
                              multiple, na_equal, call, sides = c("y", "x"))
    return(list(xi = r$yi, yi = r$xi))
  }
  xc <- lapply(keys$x, function(k) x[[k]])
  yc <- lapply(keys$y, function(k) y[[k]])
  k <- zt_join_pair_keys(xc, yc, call)
  xmask <- ymask <- NULL
  if (!na_equal) {
    # SQL: a missing key matches nothing.
    xmask <- Reduce(`|`, lapply(xc, zt_is_null))
    ymask <- Reduce(`|`, lapply(yc, zt_is_null))
  }
  type <- switch(how, full = "left", how)
  j <- zt_join_index(k, type, multiple, xmask, ymask, call, sides)
  if (how %in% c("semi", "anti")) return(list(xi = j$x, yi = NULL))
  if (how == "full") {
    ny <- .row_names_info(y, 2L)
    seen <- logical(ny)
    seen[j$y[!is.na(j$y)]] <- TRUE
    extra <- which(!seen)
    j$x <- c(j$x, rep(NA_integer_, length(extra)))
    j$y <- c(j$y, extra)
  }
  list(xi = j$x, yi = j$y)
}

zt_join_build <- function(x, y, keys, pairs, how, suffix, call) {
  sx <- attr(x, "schema")
  sy <- attr(y, "schema")
  if (how %in% c("semi", "anti")) {
    return(zt_subset(x, pairs$xi, NULL, call))
  }
  y_rest <- setdiff(names(sy), keys$y)
  x_rest <- setdiff(names(sx), keys$x)
  clash <- intersect(c(keys$x, x_rest), y_rest)
  if (length(clash) && is.null(suffix)) {
    zutable_abort("schema", sprintf(paste(
      "both tables have a column `%s` that is not a key; give `suffix`, as",
      "in suffix = c(\".x\", \".y\")"
    ), clash[[1L]]), call = call)
  }
  x_names <- ifelse(names(sx) %in% clash, paste0(names(sx), suffix[[1L]]), names(sx))
  y_names <- ifelse(y_rest %in% clash, paste0(y_rest, suffix[[2L]]), y_rest)
  if (anyDuplicated(c(x_names, y_names))) {
    zutable_abort("schema", "the suffixes give two columns the same name", call = call)
  }
  xi <- pairs$xi
  yi <- pairs$yi
  # Nullability is static (§4.3, #65): the side the join does not preserve
  # becomes nullable whatever rows this data leaves unmatched.
  y_alone <- how %in% c("right", "full")
  x_alone <- how %in% c("left", "full")
  cols <- list()
  fields <- list()
  for (k in seq_along(names(sx))) {
    f <- sx$fields[[k]]
    v <- zt_take(x[[f$name]], xi)
    nullable <- f$nullable || (y_alone && !f$name %in% keys$x)
    ki <- match(f$name, keys$x)
    if (!is.na(ki) && y_alone) {
      # A row only y has takes y's key.
      fill <- is.na(xi)
      if (any(fill)) {
        v <- zt_assign(v, fill, zt_take(y[[keys$y[[ki]]]], yi[fill]))
      }
      nullable <- f$nullable || sy$fields[[keys$y[[ki]]]]$nullable
    }
    cols[[x_names[[k]]]] <- v
    fields[[length(fields) + 1L]] <- new_field(x_names[[k]], f$type, nullable, f$metadata)
  }
  for (k in seq_along(y_rest)) {
    f <- sy$fields[[y_rest[[k]]]]
    cols[[y_names[[k]]]] <- zt_take(y[[f$name]], yi)
    fields[[length(fields) + 1L]] <- new_field(y_names[[k]], f$type,
                                               f$nullable || x_alone, f$metadata)
  }
  # D59: a join keeps x's table metadata and each carried field's.
  new_zutable(cols, new_schema(fields, sx$metadata), length(xi))
}

#' Bind the rows of zutables
#'
#' `rbind()` stacks zutables whose schemas are identical: the same names,
#' types, nullability and metadata, in the same order. Anything else is a
#' `zutable_schema_error`.
#'
#' @param ... Zutables.
#' @param deparse.level Ignored.
#' @return A zutable.
#' @export
#' @examples
#' a <- zutable(id = 1:2, x = c(1.5, 2))
#' rbind(a, a)
rbind.zutable <- function(..., deparse.level = 1) {
  args <- list(...)
  call <- sys.call()
  args <- args[!vapply(args, is.null, NA)]
  if (!length(args)) return(NULL)
  if (!all(vapply(args, is_zutable, NA))) {
    zutable_abort("schema", "rbind() of a zutable takes only zutables", call = call)
  }
  for (a in args) zt_validate(a, call)
  s <- attr(args[[1L]], "schema")
  for (i in seq_along(args)[-1L]) {
    if (!identical(attr(args[[i]], "schema"), s)) {
      zutable_abort("schema", sprintf(
        "argument %d's schema differs from the first's; rbind() needs identical schemas",
        i
      ), call = call)
    }
  }
  cols <- lapply(names(s), function(nm) {
    parts <- lapply(args, function(a) a[[nm]])
    zt_concat(parts)
  })
  names(cols) <- names(s)
  n <- sum(vapply(args, function(a) .row_names_info(a, 2L), 0L))
  new_zutable(cols, s, n)
}

# Concatenate vectors of one type, keeping the first's attributes.
zt_concat <- function(parts) {
  first <- parts[[1L]]
  if (is.data.frame(first)) return(do.call(rbind, lapply(parts, as.data.frame)))
  if (is.list(first) && !is.object(first)) return(do.call(c, parts))
  out <- do.call(c, lapply(parts, function(p) { attributes(p) <- NULL; p }))
  a <- attributes(first)
  a$names <- NULL
  if (length(a)) attributes(out) <- a
  out
}
