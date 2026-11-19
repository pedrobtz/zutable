# Thin wrappers over the C in src/, each one kernel operation through
# <zutable.h>. Arguments are checked here, so the C can trust them.

#' @noRd
zt_consume_groups <- function(x) {
  stopifnot(is.integer(x) || is.double(x))
  .Call(zt_consume_groups_c, x)
}

#' @noRd
zt_consume_order <- function(x, decreasing = FALSE, na.last = TRUE) {
  stopifnot(is.double(x), is.logical(decreasing), length(na.last) == 1L)
  na <- if (is.na(na.last)) -1L else as.integer(na.last)
  .Call(zt_consume_order_c, x, decreasing, na)
}

#' @noRd
zt_consume_join <- function(x, y) {
  stopifnot(is.integer(x), is.integer(y))
  .Call(zt_consume_join_c, x, y)
}

#' @noRd
zt_consume_sum <- function(id, ng, x) {
  stopifnot(is.integer(id), is.double(x), length(id) == length(x),
            all(id >= 1L & id <= ng))
  .Call(zt_consume_sum_c, id, as.integer(ng), x)
}

#' @noRd
zt_consume_version <- function() .Call(zt_consume_version_c)
