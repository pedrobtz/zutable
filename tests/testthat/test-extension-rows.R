# Extension and r_class() columns keep their class and attributes through
# every row operation (#57); base R over the unclassed values is the oracle.

test_that("extension and r_class() columns survive every row operation (#57)", {
  withr::defer(zt_registry$extensions[["example.celsius"]] <- NULL)
  register_extension_type("example.celsius", structure(double(), class = "celsius"), float64)
  for (ex in c("kernel", "reference")) {
    withr::local_options(zutable.executor = ex)
    t <- structure(c(1.5, NA, 3, 4.25), class = "celsius")
    m <- structure(c(10, 20, 30, 40), class = "myclass", unit = "m")
    z <- zutable(t = t, m = m, i = c(1L, 2L, 3L, 2L))
    expect_identical(schema(z)$fields$t$type$id, "extension")
    expect_identical(schema(z)$fields$m$type$id, "r_class")
    check <- function(res, rows, what) {
      info <- paste(ex, what)
      expect_no_error(conform(res, schema(res)))
      expect_identical(class(res$t), "celsius", info = info)
      expect_identical(unclass(res$t), unclass(t)[rows], info = info)
      expect_identical(attributes(res$m), attributes(m), info = info)
      expect_identical(as.vector(unclass(res$m)), as.vector(unclass(m))[rows], info = info)
    }
    check(z[i > 1], c(2L, 3L, 4L), "where")
    check(z[2:3], 2:3, "value form")
    check(z[c(TRUE, FALSE, TRUE, FALSE)], c(1L, 3L), "logical value form")
    check(z[order = desc(i)], c(3L, 2L, 4L, 1L), "order")
    check(z[limit = 2], 1:2, "limit")
    check(z[order = i, limit = 3], c(1L, 2L, 4L), "order and limit")
    check(z[select = .(t, m, i), distinct = TRUE], 1:4, "distinct")
    check(head(z, 2), 1:2, "head")
    check(rbind(z, z[1]), c(1:4, 1L), "rbind")
    y <- zutable(i = c(2L, 3L), v = c("b", "c"))
    j <- join(z, y, on = i)
    check(j, c(2L, 3L, 4L), "join")
    l <- join(y, z, on = i, how = "left")
    expect_identical(unclass(l$t), unclass(t)[c(2L, 4L, 3L)], info = paste(ex, "join y"))
    expect_identical(class(l$t), "celsius")
    expect_identical(attributes(l$m), attributes(m))
  }
})
