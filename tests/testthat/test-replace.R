test_that("a fitting value keeps the schema", {
  z <- as_zutable(sample_frame())
  s <- schema(z)
  z$px <- seq(1, 6)
  expect_identical(z$px, as.double(1:6))
  z$id <- 7
  expect_identical(z$id, rep(7L, 6L))
  z[["g"]] <- "x"
  z[2:3, "px"] <- c(0.5, 0.25)
  z[1, "k"] <- "hi"
  z$day <- NA
  expect_identical(schema(z), s)
  expect_identical(z$px[1:3], c(1, 0.5, 0.25))
  expect_identical(as.character(z$k[[1L]]), "hi")
  expect_true(all(is.na(z$day)))
  z[c("id", "px")] <- list(1L, 2)
  expect_identical(z$px, rep(2, 6L))
  z[[2L, "g"]] <- "y"
  expect_identical(z$g[[2L]], "y")
  expect_identical(schema(z), s)
})

test_that("a misfitting value is a schema error and leaves the table", {
  z <- as_zutable(sample_frame())
  before <- z
  expect_error(z$id <- 1.5, class = "zutable_schema_error")
  expect_error(z$id <- "1", class = "zutable_schema_error")
  expect_error(z$id <- 2^31, class = "zutable_schema_error")
  expect_error(z$px <- "a", class = "zutable_schema_error")
  expect_error(z$day <- "2026-01-01", class = "zutable_schema_error")
  expect_error(z$k <- "medium", class = "zutable_schema_error")
  expect_error(z[["g"]] <- 1L, class = "zutable_schema_error")
  expect_error(z[1, "id"] <- 0.5, class = "zutable_schema_error")
  expect_error(z$px <- 1:2, class = "zutable_value_error")
  expect_identical(z, before)
})

test_that("removing, adding and renaming columns are schema errors", {
  z <- as_zutable(sample_frame())
  before <- z
  expect_error(z$px <- NULL, class = "zutable_schema_error")
  expect_error(z[["px"]] <- NULL, class = "zutable_schema_error")
  expect_error(z$new <- 1, class = "zutable_schema_error")
  expect_error(z[["new"]] <- 1, class = "zutable_schema_error")
  expect_error(z[, "new"] <- 1, class = "zutable_schema_error")
  expect_error(names(z) <- letters[1:5], class = "zutable_schema_error")
  expect_error(colnames(z) <- letters[1:5], class = "zutable_schema_error")
  expect_error(dimnames(z) <- list(NULL, letters[1:5]),
               class = "zutable_schema_error")
  expect_identical(z, before)
})

test_that("NA into a not_null column is a value error", {
  z <- as_zutable(data.frame(a = 1:3), schema(a = not_null(int32)))
  expect_error(z$a <- NA, class = "zutable_value_error")
  expect_error(z[2, "a"] <- NA, class = "zutable_value_error")
  expect_identical(z$a, 1:3)
})

test_that("a timestamp column keeps its zone and unit on replacement", {
  z <- zutable(t = .POSIXct(0, "UTC"))
  expect_error(z$t <- .POSIXct(0, "Europe/Lisbon"),
               class = "zutable_schema_error")
  z$t <- .POSIXct(1, "UTC")
  expect_identical(unclass(z$t)[[1L]], 1)
  ms <- as_zutable(list(t = .POSIXct(0, "UTC")),
                   schema(t = timestamp("ms", "UTC")))
  expect_error(ms$t <- .POSIXct(0.0005, "UTC"), class = "zutable_value_error")
})
