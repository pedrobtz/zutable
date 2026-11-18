# For test-grp-join.R: grp_join() against merge(sort = FALSE).

# The pairs merge() finds for key data frames xk and yk, in x then y order,
# under type and multiple.
merge_join_pairs <- function(xk, yk, type = "inner", multiple = "all") {
  names(yk) <- names(xk)
  xd <- cbind(xk, .xi = seq_len(nrow(xk)))
  yd <- cbind(yk, .yi = seq_len(nrow(yk)))
  m <- merge(xd, yd, by = names(xk), sort = FALSE)
  m <- m[order(m$.xi, m$.yi), c(".xi", ".yi")]
  if (type == "semi") return(list(x = unique(m$.xi)))
  if (type == "anti") return(list(x = setdiff(seq_len(nrow(xk)), m$.xi)))
  if (multiple == "first") m <- m[!duplicated(m$.xi), ]
  if (multiple == "last") m <- m[!duplicated(m$.xi, fromLast = TRUE), ]
  xi <- m$.xi
  yi <- m$.yi
  if (type == "left") {
    miss <- setdiff(seq_len(nrow(xk)), xi)
    xi <- c(xi, miss)
    yi <- c(yi, rep(NA_integer_, length(miss)))
    o <- order(xi)
    xi <- xi[o]
    yi <- yi[o]
  }
  list(x = as.integer(xi), y = as.integer(yi))
}

expect_joins_merge <- function(xk, yk, info = NULL) {
  for (type in c("inner", "left", "semi", "anti")) {
    for (multiple in c("all", "first", "last")) {
      expect_identical(
        grp_join(xk, yk, type = type, multiple = multiple),
        merge_join_pairs(xk, yk, type, multiple),
        info = paste(info, type, multiple)
      )
    }
  }
}
