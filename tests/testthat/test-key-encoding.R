# String keys are compared by their text, whatever their encoding
# (design-kernel 6.1): an unknown-encoded (native) non-ASCII string equals
# its UTF-8-marked twin. testthat reads this file as UTF-8, so the native
# string is built from its bytes; it is alone in its vector, as a latin1
# element beside it would force the translation and hide the bug.

test_that("an unknown-encoded key equals its UTF-8 twin in the kernel (#50)", {
  skip_unless_utf8_locale()
  nat <- native_jose()
  utf <- enc2utf8("José")
  expect_identical(Encoding(nat), "unknown")
  expect_identical(Encoding(utf), "UTF-8")
  # The oracle is base R, whose match() and unique() compare by text.
  x <- c(nat, "Ana")
  y <- c("Ana", utf)
  expect_identical(grp_match(x, y), match(x, y))
  expect_identical(grp_match(y, x), match(y, x))
  v <- c(utf, nat, "Ana", nat)
  expect_identical(grp(v)$id, match(v, unique(v)))
  expect_identical(grp(v)$n, length(unique(v)))
  expect_identical(grp(v, sort = TRUE)$n, length(unique(v)))
  expect_identical(grp(nat, 1L)$n, 1L)
  j <- grp_join(x, y)
  base <- merge(data.frame(k = x, i = seq_along(x)), data.frame(k = y, j = seq_along(y)))
  expect_identical(sort(j$x), sort(base$i))
  expect_identical(j$y[order(j$x)], base$j[order(base$i)])
  s <- grp_reduce(c(1, 2, 3, 4), v, "sum")
  expect_identical(as.vector(s), as.vector(tapply(c(1, 2, 3, 4), match(v, unique(v)), sum)))
  # The order: equal text ties, so stability keeps row order.
  expect_identical(key_order(v), order(enc2utf8(v), method = "radix"))
  expect_identical(key_rank(v), as.integer(rank(match(enc2utf8(v), sort(unique(enc2utf8(v)))),
                                                ties.method = "min")))
  expect_identical(enc2utf8(as.vector(key_sort(v))), sort(enc2utf8(v), method = "radix"))
})

test_that("an unknown-encoded key groups and joins as the reference does (#50)", {
  skip_unless_utf8_locale()
  nat <- native_jose()
  utf <- enc2utf8("José")
  # Built so that the table's column keeps its native element; a column
  # entering a zutable may be normalised (D58), so the r() key below
  # also yields a native string from inside the bracket.
  z <- zutable(s = c(utf, "Ana", utf), v = c(1, 2, 3))
  q <- function() z[, .(n = count(), t = sum(v)), by = .(s), order = s]
  expect_identical(plain(with_executor("kernel", q())),
                   plain(with_executor("reference", q())))
  native_of <- function(s) {
    # Only the first: the key then holds both encodings of one text.
    out <- s
    out[match(utf, s)] <- nat
    out
  }
  qr <- function() z[, .(n = count()), by = .(k = r(native_of(s), string)), order = k]
  kr <- plain(with_executor("kernel", qr()))
  rr <- plain(with_executor("reference", qr()))
  expect_identical(kr, rr)
  expect_identical(nrow(kr), 2L)
  # An r() string result is UTF-8, as the table's strings are.
  qs <- function() z[, .(k = r(native_of(s), string))]
  expect_identical(Encoding(plain(qs())$k[[1L]]), "UTF-8")
  y <- zutable(s = c("Ana", utf), w = c(10, 20))
  qj <- function() join(z, y, on = s)
  expect_identical(plain(with_executor("kernel", qj())),
                   plain(with_executor("reference", qj())))
})

test_that("a \"bytes\" string is a zutable_value_error at every kernel entry (#50, #68)", {
  b <- rawToChar(as.raw(c(0x4a, 0x6f, 0x73, 0xc3, 0xa9)))
  Encoding(b) <- "bytes"
  expect_identical(Encoding(b), "bytes")
  x <- c("a", b)
  e <- "zutable_value_error"
  expect_error(grp(x), class = e)
  expect_error(grp(x, sort = TRUE), class = e)
  expect_error(grp_match(x, "a"), class = e)
  expect_error(grp_match("a", x), class = e)
  expect_error(grp_join(x, c("a", "b")), class = e)
  expect_error(grp_join(structure(1:2, levels = x, class = "factor"), c("a", "b")), class = e)
  expect_error(grp_reduce(c(1, 2), x, "sum"), class = e)
  expect_error(grp_reduce(x, grp(1:2), "min"), class = e)
  expect_error(key_order(x), class = e)
  expect_error(key_sort(x), class = e)
  expect_error(key_rank(x), class = e)
  # A bytes string that is ASCII is not marked, so it is text.
  a <- "abc"
  Encoding(a) <- "bytes"
  expect_identical(grp(c(a, "abc"))$n, 1L)
})
