test_that("joins agree with DuckDB, NA keys matched or not", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("DBI")
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  withr::local_seed(33)
  f <- join_frames()
  duckdb::duckdb_register(con, "x", f$x)
  duckdb::duckdb_register(con, "y", f$y)
  x <- as_zutable(f$x)
  y <- as_zutable(f$y)
  sql <- c(inner = "INNER", left = "LEFT", right = "RIGHT", full = "FULL")
  for (na_equal in c(TRUE, FALSE)) {
    cond <- if (na_equal) "x.k IS NOT DISTINCT FROM y.k2" else "x.k = y.k2"
    for (how in names(sql)) {
      got <- sorted_frame(join(x, y, on = .(k == k2), how = how, na_equal = na_equal)[
        , .(xi, yi)])
      want <- sorted_frame(DBI::dbGetQuery(con, sprintf(
        "SELECT x.xi, y.yi FROM x %s JOIN y ON %s", sql[[how]], cond)))
      expect_identical(got, want, info = paste(how, na_equal))
    }
    semi <- join(x, y, on = .(k == k2), how = "semi", na_equal = na_equal)$xi
    want <- DBI::dbGetQuery(con, sprintf(
      "SELECT xi FROM x WHERE EXISTS (SELECT 1 FROM y WHERE %s) ORDER BY xi", cond))$xi
    expect_identical(semi, want)
    anti <- join(x, y, on = .(k == k2), how = "anti", na_equal = na_equal)$xi
    want <- DBI::dbGetQuery(con, sprintf(
      "SELECT xi FROM x WHERE NOT EXISTS (SELECT 1 FROM y WHERE %s) ORDER BY xi", cond))$xi
    expect_identical(anti, want)
  }
})
