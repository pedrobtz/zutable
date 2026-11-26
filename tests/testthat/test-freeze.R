test_that("every write route of §6 refuses a frozen table and leaves it", {
  z <- zutable(a = 1:3, b = c("x", "y", "z"))
  freeze(z)
  before <- plain(z)
  alias <- z
  expect_true(is_frozen(alias))
  routes <- list(
    function(t) t[, a := 0L],
    function(t) t[a > 1L, { a := 0L; b := "q" }],
    function(t) t[update = a := 0L],
    function(t) { t$a <- 0L; t },
    function(t) { t[["a"]] <- 0L; t },
    function(t) { t[1, "a"] <- 0L; t },
    function(t) { t[[1, "a"]] <- 0L; t }
  )
  for (r in routes) {
    expect_error(r(z), class = "zutable_frozen_error")
    expect_error(r(alias), class = "zutable_frozen_error")
  }
  expect_identical(plain(z), before)
  expect_identical(plain(alias), before)
})

test_that("queries read a frozen table, and their results are not frozen", {
  z <- zutable(a = 1:3)
  freeze(z)
  r <- z[a > 1L]
  expect_false(is_frozen(r))
  r[, a := 0L]
  expect_identical(z$a, 1:3)
  expect_output(print(z), "frozen")
})

test_that("a copy of a frozen table can be updated without changing it", {
  z <- zutable(a = 1:3)
  freeze(z)
  c2 <- copy(z)
  expect_false(is_frozen(c2))
  c2[, a := 9L]
  expect_identical(c2$a, rep(9L, 3L))
  expect_identical(z$a, 1:3)
  expect_true(is_frozen(z))
})

test_that("the mark is enforced in C: zt_commit() writes nothing", {
  z <- zutable(a = 1:3)
  freeze(z)
  status <- .Call(zt_commit, z, 1L, list(c(0L, 0L, 0L)), NULL)
  expect_identical(status, 1L)
  expect_identical(z$a, 1:3)
})

test_that("freeze() and copy() take zutables", {
  expect_error(freeze(data.frame(a = 1)), class = "zutable_type_error")
  expect_error(copy(1:3), class = "zutable_type_error")
  expect_false(is_frozen(data.frame()))
})

test_that("D43's route returns an honest data frame, frozen or not (#79)", {
  for (frozen in c(FALSE, TRUE)) {
    mk <- function() {
      f <- zutable(a = 1:3, b = c(1, 2, 3), e = factor(c("x", "x", "y"), levels = c("x", "y", "z")))
      f[, b := b]  # a plan record to strip
      if (frozen) freeze(f)
      f
    }
    f <- mk()
    expect_false(is.null(attr(f, "plan", exact = TRUE)))
    before <- plain(f)
    outs <- list(
      within = within(f, b <- b * 2),
      modifyList = modifyList(f, list(b = c(7, 8, 9))),
      replace = replace(f, "b", list(c(4, 5, 6))),
      droplevels = droplevels(f)
    )
    for (nm in names(outs)) {
      o <- outs[[nm]]
      info <- paste(nm, frozen)
      expect_identical(class(o), "data.frame", info = info)
      for (a in c("schema", "plan", "frozen", "properties")) {
        expect_null(attr(o, a, exact = TRUE), info = paste(info, a))
      }
    }
    # Base R's answers on the plain frame are the oracle.
    expect_identical(plain(outs$within), within(before, b <- b * 2))
    expect_identical(plain(outs$modifyList), modifyList(before, list(b = c(7, 8, 9))))
    expect_identical(plain(outs$droplevels), droplevels(before))
    # The object itself is never written, and keeps its mark.
    expect_identical(plain(f), before)
    expect_identical(is_frozen(f), frozen)
  }
})

test_that("is.na<- goes through the typed [<- (#79)", {
  f <- zutable(a = 1:3, b = c(1, 2, 3))
  freeze(f)
  expect_error(is.na(f) <- 1, class = "zutable_frozen_error")
  expect_true(is_zutable(f))
  expect_identical(f$a, 1:3)
  g <- zutable(a = 1:3, b = c(1, 2, 3))
  is.na(g) <- 1
  # Base R's answer, with the column keeping its type (int32's NA).
  want <- data.frame(a = 1:3, b = c(1, 2, 3))
  is.na(want) <- 1
  want$a <- as.integer(want$a)
  expect_true(is_zutable(g))
  expect_identical(plain(g), want)
  expect_no_error(conform(g, schema(g)))
  h <- as_zutable(data.frame(a = 1:3), schema(a = not_null(int32)))
  expect_error(is.na(h) <- 1, class = "zutable_value_error")
  expect_identical(h$a, 1:3)
})
