test_that("joins agree with merge() for every kind, NA keys both ways", {
  withr::local_seed(31)
  f <- join_frames()
  x <- as_zutable(f$x)
  y <- as_zutable(f$y)
  for (na_equal in c(TRUE, FALSE)) {
    for (how in c("inner", "left", "right", "full")) {
      r <- join(x, y, on = .(k == k2), how = how, na_equal = na_equal)
      got <- data.frame(xi = r$xi, yi = r$yi)
      got <- got[order(got$xi, got$yi, method = "radix", na.last = TRUE), , drop = FALSE]
      rownames(got) <- NULL
      want <- merge_pairs(f$x, f$y, "k", "k2", how %in% c("left", "full"),
                          how %in% c("right", "full"), na_equal)
      expect_identical(got, want, info = paste(how, na_equal))
    }
    inner <- merge_pairs(f$x, f$y, "k", "k2", FALSE, FALSE, na_equal)
    semi <- join(x, y, on = .(k == k2), how = "semi", na_equal = na_equal)
    anti <- join(x, y, on = .(k == k2), how = "anti", na_equal = na_equal)
    expect_identical(semi$xi, sort(unique(inner$xi)))
    expect_identical(anti$xi, setdiff(f$x$xi, inner$xi))
    expect_identical(names(semi), names(x))
  }
})

test_that("a two-key join agrees with merge() for every kind, NA keys both ways", {
  withr::local_seed(33)
  f <- join_frames()
  x <- as_zutable(f$x)
  y <- as_zutable(f$y)
  # merge()'s `incomparables` works on one column only, so for
  # na_equal = FALSE each missing key gets a sentinel no other row has.
  unmatched <- function(d, k, s, tag, base) {
    d[[k]][is.na(d[[k]])] <- base - which(is.na(d[[k]]))
    d[[s]][is.na(d[[s]])] <- paste0(tag, which(is.na(d[[s]])))
    d
  }
  for (na_equal in c(TRUE, FALSE)) {
    fx <- if (na_equal) f$x else unmatched(f$x, "k", "s", "x", -1000L)
    fy <- if (na_equal) f$y else unmatched(f$y, "k2", "s2", "y", -2000L)
    for (how in c("inner", "left", "right", "full")) {
      r <- join(x, y, on = .(k == k2, s == s2), how = how, na_equal = na_equal)
      got <- data.frame(xi = r$xi, yi = r$yi)
      got <- got[order(got$xi, got$yi, method = "radix", na.last = TRUE), , drop = FALSE]
      rownames(got) <- NULL
      want <- merge_pairs(fx, fy, c("k", "s"), c("k2", "s2"),
                          how %in% c("left", "full"), how %in% c("right", "full"),
                          na_equal = TRUE)
      expect_identical(got, want, info = paste(how, na_equal))
    }
  }
})

test_that("rows come in x's order, then y's within a row of x", {
  withr::local_seed(32)
  f <- join_frames()
  r <- join(as_zutable(f$x), as_zutable(f$y), on = .(k == k2), how = "left")
  expect_false(is.unsorted(r$xi))
  for (i in unique(r$xi)) {
    expect_false(is.unsorted(r$yi[r$xi == i], na.rm = TRUE))
  }
  full <- join(as_zutable(f$x), as_zutable(f$y), on = .(k == k2), how = "full")
  tail_rows <- is.na(full$xi)
  expect_true(all(tail_rows[seq(sum(!tail_rows) + 1L, length.out = sum(tail_rows))]))
  expect_false(is.unsorted(full$yi[tail_rows]))
  right <- join(as_zutable(f$x), as_zutable(f$y), on = .(k == k2), how = "right")
  expect_false(is.unsorted(right$yi))
})

test_that("multiple picks the first, the last, or refuses", {
  x <- zutable(id = c(1L, 2L), k = c(1L, 2L))
  y <- zutable(k = c(1L, 1L, 2L), v = c("a", "b", "c"))
  expect_identical(join(x, y, on = k)$v, c("a", "b", "c"))
  expect_identical(join(x, y, on = k, multiple = "first")$v, c("a", "c"))
  expect_identical(join(x, y, on = k, multiple = "last")$v, c("b", "c"))
  cnd <- expect_error(join(x, y, on = k, multiple = "error"),
                      class = "zutable_multiple_error")
  expect_match(conditionMessage(cnd), "row 1 of x matches 2 rows")
  expect_identical(join(x[k == 2L], y, on = k, multiple = "error")$v, "c")
  # For a right join, per row of y.
  expect_error(join(y, x, on = k, how = "right", multiple = "error"),
               class = "zutable_multiple_error")
  expect_identical(join(y, x, on = k, how = "right", multiple = "first")$v, c("a", "c"))
  # A right join counts rows of x per row of y: y's duplicate keys each
  # match one row of x, which is no fan-out, in both executors.
  for (ex in c("kernel", "reference")) {
    r <- with_executor(ex, join(x, y, on = k, how = "right", multiple = "error"))
    expect_identical(r$v, c("a", "b", "c"), info = ex)
    expect_identical(r$id, c(1L, 1L, 2L), info = ex)
    expect_snapshot(with_executor(ex, join(y, x, on = k, how = "right", multiple = "error")),
                    error = TRUE)
  }
})

test_that("keys appear once, under x's name; a y-only row takes y's key", {
  x <- zutable(a = c(1L, 2L), p = c("x1", "x2"))
  y <- zutable(b = c(2L, 3L), q = c("y2", "y3"))
  r <- join(x, y, on = .(a == b), how = "full")
  expect_identical(names(r), c("a", "p", "q"))
  expect_identical(r$a, c(1L, 2L, 3L))
  expect_identical(r$p, c("x1", "x2", NA))
  expect_identical(format(schema(r)), c("a int32", "p string", "q string"))
  s <- schema(join(as_zutable(data.frame(a = 1:2), schema(a = not_null(int32))),
                   as_zutable(data.frame(a = 2:3, v = 1:2), schema(a = not_null(int32), v = not_null(int32))),
                   on = a, how = "left"))
  expect_identical(format(s), c("a not_null(int32)", "v int32"))
})

test_that("a name clash is an error unless suffix is given", {
  x <- zutable(k = 1:2, v = c(1, 2))
  y <- zutable(k = 1:2, v = c(3, 4))
  expect_error(join(x, y, on = k), class = "zutable_schema_error")
  r <- join(x, y, on = k, suffix = c(".x", ".y"))
  expect_identical(names(r), c("k", "v.x", "v.y"))
  expect_error(join(x, y, on = k, suffix = c(".a", ".a")), class = "zutable_syntax_error")
})

test_that("refusals", {
  x <- zutable(k = 1:2, d = 1.5)
  y <- zutable(k = c(1, 2), j = 1:2)
  expect_error(join(x, y, on = k), class = "zutable_type_error")
  expect_error(join(x, y, on = nope), class = "zutable_schema_error")
  expect_error(join(x, y, on = .(d == j)), class = "zutable_type_error")
  expect_error(join(x, y, on = .(k + 1)), class = "zutable_syntax_error")
  expect_error(join(x, x, on = k, how = "outer"), class = "zutable_syntax_error")
  expect_error(join(x, x, on = k, multiple = "any"), class = "zutable_syntax_error")
  expect_error(join(x, x, on = k, na_equal = NA), class = "zutable_syntax_error")
  expect_error(join(x, data.frame(k = 1:2), on = k), class = "zutable_type_error")
  expect_error(join(x, x, on = .(k, k)), class = "zutable_syntax_error")
})

test_that("int64 keys match by value, NA as NA, in both executors (#60)", {
  skip_if_not_installed("zuint")
  vals <- c("0", NA, "9223372036854775807", "-9223372036854775807",
            "9218868437227405313", "9218868437227405314", "9218868437227405312", "1")
  a <- zutable(k = zuint::int64(vals), i = seq_along(vals))
  b <- zutable(k = zuint::int64(c("0", "9218868437227405314", "9223372036854775807",
                                  "-9223372036854775807", NA, "9218868437227405312")),
               v = 1:6)
  ak <- as.character(a$k)
  bk <- as.character(b$k)
  for (na_equal in c(TRUE, FALSE)) {
    # Brute force over every pair, keys compared as decimal text.
    want <- do.call(rbind, lapply(seq_along(ak), function(i) {
      hit <- which(vapply(bk, USE.NAMES = FALSE, function(y) {
        if (is.na(ak[[i]]) || is.na(y)) na_equal && is.na(ak[[i]]) && is.na(y)
        else ak[[i]] == y
      }, NA))
      if (length(hit)) data.frame(i = i, v = unname(hit))
    }))
    for (ex in c("kernel", "reference")) {
      withr::local_options(zutable.executor = ex)
      got <- join(a, b, on = k, na_equal = na_equal)
      expect_identical(plain(got[select = .(i, v)]), plain(want),
                       info = paste(ex, na_equal))
    }
  }
})

test_that("a join's nullability comes from the schemas, not the data (#65)", {
  sa <- schema(k = not_null(int32), a = not_null(string))
  sb <- schema(k = not_null(int32), v = not_null(float64))
  a <- as_zutable(data.frame(k = 1:2, a = c("p", "q")), sa)
  b_all <- as_zutable(data.frame(k = 1:2, v = c(1, 2)), sb)
  b_some <- as_zutable(data.frame(k = c(1L, 3L), v = c(1, 3)), sb)
  # The rule (design §4.3, D54): the side a join does not preserve becomes
  # nullable; a key is nullable when either side's key is and y's rows
  # can appear alone.
  want <- list(
    inner = schema(k = not_null(int32), a = not_null(string), v = not_null(float64)),
    left = schema(k = not_null(int32), a = not_null(string), v = float64),
    right = schema(k = not_null(int32), a = string, v = not_null(float64)),
    full = schema(k = not_null(int32), a = string, v = float64),
    semi = sa, anti = sa
  )
  for (ex in c("kernel", "reference")) {
    withr::local_options(zutable.executor = ex)
    for (how in names(want)) {
      for (b in list(b_all, b_some)) {
        j <- join(a, b, on = k, how = how)
        expect_identical(schema(j), want[[how]], info = paste(ex, how))
        expect_identical(zt_explain_lines(j)[[1L]],
                         sprintf("table  %s", paste(format(want[[how]]), collapse = ", ")),
                         info = paste(ex, how))
        expect_no_error(conform(j, schema(j)))
      }
    }
  }
  # A nullable key on either side makes the key nullable where y's rows
  # can stand alone.
  bn <- as_zutable(data.frame(k = c(1L, NA), v = c(1, 3)), schema(k = int32, v = float64))
  expect_false(schema(join(a, bn, on = k, how = "left"))$fields$k$nullable)
  expect_true(schema(join(a, bn, on = k, how = "full"))$fields$k$nullable)
  expect_true(schema(join(a, bn, on = k, how = "right"))$fields$k$nullable)
})

test_that("join(on =) is spelled as the bracket is (#83)", {
  x <- zutable(k = c(1L, 2L, 3L), j = c("a", "b", "a"), xv = 1:3)
  y <- zutable(k = c(1L, 3L), j = c("a", "a"), yv = c(10, 30))
  want_k <- join(x, y, on = .(k == k), suffix = c(".x", ".y"))
  want_kj <- join(x, y, on = .(k == k, j == j))
  # A variable named like a column: bare names are columns, never it.
  k <- "j"
  j <- "nothing"
  expect_identical(join(x, y, on = k, suffix = c(".x", ".y")), want_k)
  expect_identical(join(x, y, on = c(k, j)), want_kj)
  expect_identical(join(x, y, on = "k", suffix = c(".x", ".y")), want_k)
  expect_identical(join(x, y, on = c("k", "j")), want_kj)
  keys <- c("k", "j")
  expect_identical(join(x, y, on = ..keys), want_kj)
  f <- function(tab, by) join(tab, y, on = ..by)
  expect_identical(f(x, c("k", "j")), want_kj)
  one <- "k"
  expect_identical(join(x, y, on = ..one, suffix = c(".x", ".y")), want_k)
  expect_error(join(x, y, on = ..no_such_variable), class = "zutable_syntax_error")
  bad <- 3
  expect_error(join(x, y, on = ..bad), class = "zutable_syntax_error")
  expect_error(join(x, y, on = c(k + 1)), class = "zutable_syntax_error")
  expect_error(join(x, y, on = "nope"), class = "zutable_schema_error")
})
