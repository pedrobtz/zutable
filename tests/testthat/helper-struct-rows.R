# Helpers of test-struct-rows.R, kept here so that test_check(shuffle = TRUE)
# defines them before any test runs.

struct_rows <- function(st) {
  lapply(seq_len(nrow(st)), function(i) lapply(st, function(col) col[[i]]))
}

struct_from_rows <- function(rows, like) {
  out <- lapply(names(like), function(nm) {
    v <- vapply(rows, function(r) r[[nm]], like[[nm]][0][NA_integer_])
    attributes(v) <- NULL
    storage.mode(v) <- storage.mode(like[[nm]])
    v
  })
  structure(out, names = names(like), class = "data.frame",
            row.names = c(NA_integer_, -length(rows)))
}

struct_null <- function(r) all(vapply(r, is.na, NA))

struct_table <- function() {
  zutable(
    id = c(1L, 1L, 2L, 3L, 3L),
    flag = c(TRUE, FALSE, NA, TRUE, FALSE),
    st = data.frame(a = c(1L, NA, 3L, NA, 5L), b = c("x", NA, "z", NA, "v")),
    st2 = data.frame(a = 6:10, b = c("p", "q", "r", "s", "t"))
  )
}
