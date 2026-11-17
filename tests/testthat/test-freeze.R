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
