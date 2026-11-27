# How strings enter (D58, #64): column values, literals, enum levels and
# names. In the session's UTF-8 locale an unknown non-ASCII string is
# converted from native (its bytes unchanged); under LC_ALL=C, where its
# bytes mean nothing, it is a zutable_value_error naming the column.

test_that("strings of every marked encoding enter as UTF-8 (#64)", {
  utf8 <- "café"
  latin <- iconv(utf8, "UTF-8", "latin1")
  expect_identical(Encoding(latin), "latin1")
  z <- zutable(s = c(utf8, latin, "plain", NA))
  expect_identical(charToRaw(z$s[[2L]]), charToRaw(utf8))
  expect_identical(Encoding(z$s[1:2]), c("UTF-8", "UTF-8"))
  f <- factor(c(latin, "a"), levels = c(latin, "a"))
  z <- zutable(f = f)
  expect_identical(charToRaw(levels(z$f)[[1L]]), charToRaw(utf8))
  expect_identical(Encoding(schema(z)$fields$f$type$levels[[1L]]), "UTF-8")
  s <- schema(e = enum(c(latin, "a")))
  expect_identical(charToRaw(s$fields$e$type$levels[[1L]]), charToRaw(utf8))
  z <- zutable(s = utf8)
  expect_identical(nrow(z[s == latin]), 1L)
  expect_identical(nrow(z[s %in% c(latin, "x")]), 1L)
  cols <- list(1L)
  names(cols) <- latin
  z <- as_zutable(cols)
  expect_identical(charToRaw(names(z)), charToRaw(utf8))
  expect_identical(Encoding(names(schema(z))), "UTF-8")
  sch <- do.call(schema, stats::setNames(list(quote(int32)), latin))
  expect_identical(charToRaw(names(sch)), charToRaw(utf8))
  sch <- do.call(schema, list(st = as.call(c(as.name("struct"),
                                              stats::setNames(list(quote(int32)), latin)))))
  expect_identical(charToRaw(names(sch$fields$st$type$fields)), charToRaw(utf8))
  st <- zutable(st = structure(list(1L), names = latin, class = "data.frame",
                               row.names = c(NA, -1L)))
  expect_identical(charToRaw(names(st$st)), charToRaw(utf8))
  expect_identical(charToRaw(names(schema(st)$fields$st$type$fields)), charToRaw(utf8))
  u <- zutable(s = "x")
  u$s <- latin
  expect_identical(charToRaw(u$s), charToRaw(utf8))
  u[1, "s"] <- latin
  expect_identical(Encoding(u$s), "UTF-8")
})

test_that("a string marked bytes is refused for string (#64)", {
  b <- "caf\xc3\xa9"
  Encoding(b) <- "bytes"
  expect_error(zutable(s = b), class = "zutable_value_error")
  expect_error(as_zutable(data.frame(s = b)), class = "zutable_value_error")
  expect_error(zutable(f = factor(b)), class = "zutable_value_error")
  z <- zutable(s = "x")
  expect_error(z$s <- b, class = "zutable_value_error")
  expect_error(z[s == b], class = "zutable_value_error")
  expect_error(schema(e = enum(b)), class = "zutable_value_error")
})

test_that("unknown non-ASCII strings: native bytes in UTF-8, an error in C (#64)", {
  skip_on_cran()
  # POSIX locale names; R on Windows (>= 4.2) runs in UTF-8 only.
  skip_on_os("windows")
  lines <- c(
    "x <- rawToChar(as.raw(c(0x63, 0x61, 0x66, 0xc3, 0xa9)))",
    "out <- function(code) tryCatch({ v <- code; paste(c('ok', as.character(charToRaw(v))), collapse = ' ') },",
    "  zutable_value_error = function(e) 'value_error', error = function(e) paste('other', class(e)[[1L]]))",
    "cat(out(zutable(s = x)$s), '\\n')",
    "cat(out(as_zutable(data.frame(s = x))$s), '\\n')",
    "cat(out(levels(zutable(f = factor(x))$f)), '\\n')",
    "cat(out(names(as_zutable(stats::setNames(list(1L), x)))), '\\n')",
    "cat(out({ z <- zutable(s = 'a'); z$s <- x; z$s }), '\\n')",
    "cat(out({ z <- zutable(s = 'a'); nrow(z[s == x]); 'a' }), '\\n')",
    "cat(out(schema(e = enum(x))$fields$e$type$levels), '\\n')"
  )
  want_utf8 <- rep("ok 63 61 66 c3 a9", 7L)
  want_utf8[[6L]] <- "ok 61"
  got <- trimws(run_script(lines, env = c("LC_ALL=en_US.UTF-8", "LANG=en_US.UTF-8")))
  expect_identical(got, want_utf8)
  got <- trimws(run_script(lines, env = c("LC_ALL=C", "LANG=C")))
  expect_identical(got, rep("value_error", 7L))
})
