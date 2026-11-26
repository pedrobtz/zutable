# Struct (data.frame) columns are taken and assigned by row (#55): a
# per-row loop over plain lists is the oracle, under both executors.

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

test_that("coalesce(), ifelse() and case() take struct values by row (#55)", {
  for (ex in c("kernel", "reference")) {
    withr::local_options(zutable.executor = ex)
    s <- struct_table()
    r1 <- struct_rows(s$st)
    r2 <- struct_rows(s$st2)
    na_row <- list(a = NA_integer_, b = NA_character_)
    want_co <- struct_from_rows(Map(function(a, b) if (struct_null(a)) b else a, r1, r2), s$st)
    want_if <- struct_from_rows(Map(function(f, a, b) {
      if (is.na(f)) na_row else if (f) a else b
    }, s$flag, r1, r2), s$st)
    want_case <- struct_from_rows(Map(function(f, a, b) if (isTRUE(f)) a else b,
                                      s$flag, r1, r2), s$st)
    got <- s[select = .(co = coalesce(st, st2), ie = ifelse(flag, st, st2),
                        ca = case(flag ~ st, .default = st2))]
    expect_identical(plain(got$co), plain(want_co), info = ex)
    expect_identical(plain(got$ie), plain(want_if), info = ex)
    expect_identical(plain(got$ca), plain(want_case), info = ex)
    expect_no_error(conform(got, schema(got)))
  }
})

test_that("first(), last() and over() take struct values by row (#55)", {
  for (ex in c("kernel", "reference")) {
    withr::local_options(zutable.executor = ex)
    s <- struct_table()
    rows <- struct_rows(s$st)
    groups <- split(seq_len(nrow(s)), s$id)
    want_first <- struct_from_rows(lapply(groups, function(g) rows[[g[[1L]]]]), s$st)
    want_last <- struct_from_rows(lapply(groups, function(g) rows[[g[[length(g)]]]]), s$st)
    got <- s[by = id, select = .(f = first(st), l = last(st))]
    expect_identical(plain(got$f), plain(want_first), info = ex)
    expect_identical(plain(got$l), plain(want_last), info = ex)
    got <- s[by = id, select = .(f = first(st), m = r(sum(id), int32))]
    expect_identical(plain(got$f), plain(want_first), info = ex)
    expect_no_error(conform(got, schema(got)))
    want_over <- struct_from_rows(lapply(s$id, function(i) rows[[groups[[as.character(i)]][[1L]]]]),
                                  s$st)
    got <- s[select = .(id, f = over(first(st), by = id))]
    expect_identical(plain(got$f), plain(want_over), info = ex)
    expect_no_error(conform(got, schema(got)))
  }
})
