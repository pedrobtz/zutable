# DuckDB as the oracle for aggregate queries: a fixed corpus, each query
# with its SQL written by hand, compared after sorting by every column
# (DuckDB promises no group order; zutable's is tested on its own).

test_that("aggregate queries agree with DuckDB", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("DBI")
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  withr::local_seed(14)
  df <- bracket_frame(150L)
  z <- as_zutable(df)
  duckdb::duckdb_register(con, "t", df)
  cases <- list(
    list(quote(z[, .(n = count(), s = sum(px)), by = g]),
         "SELECT g, CAST(count(*) AS INTEGER) n, sum(px) s FROM t GROUP BY g"),
    list(quote(z[, .(m = mean(px), c = count(k)), by = .(g, flag)]),
         "SELECT g, flag f, avg(px) m, CAST(count(k) AS INTEGER) c FROM t GROUP BY g, flag"),
    list(quote(z[px > 0, .(hi = max(px), lo = min(g)), by = k]),
         "SELECT k, max(px) hi, min(g) lo FROM t WHERE px > 0 GROUP BY k"),
    list(quote(z[, .(n = count()), by = k, having = n > 25]),
         "SELECT k, CAST(count(*) AS INTEGER) n FROM t GROUP BY k HAVING count(*) > 25"),
    list(quote(z[select = .(n = count(), s = sum(k), d = count_distinct(g))]),
         "SELECT CAST(count(*) AS INTEGER) n, sum(k) s, CAST(count(DISTINCT g) AS INTEGER) d FROM t"),
    list(quote(z[, .(a = any(flag), b = all(flag)), by = g]),
         "SELECT g, bool_or(flag) a, bool_and(flag) b FROM t GROUP BY g"),
    list(quote(z[, .(n = count()), by = .(mon = date_trunc("month", day))]),
         "SELECT CAST(date_trunc('month', day) AS DATE) mon, CAST(count(*) AS INTEGER) n FROM t GROUP BY 1"),
    list(quote(z[select = .(id, s = over(sum(px), by = g))]),
         "SELECT id, sum(px) OVER (PARTITION BY g) s FROM t")
  )
  for (case in cases) {
    got <- sorted_frame(eval(case[[1L]]))
    want <- DBI::dbGetQuery(con, case[[2L]])
    names(want) <- names(got)
    want <- sorted_frame(want)
    for (nm in names(got)) {
      if (is.double(got[[nm]])) {
        expect_equal(got[[nm]], as.double(want[[nm]]), tolerance = 1e-12,
                     info = paste(deparse(case[[1L]]), nm))
      } else {
        expect_identical(got[[nm]], want[[nm]], info = paste(deparse(case[[1L]]), nm))
      }
    }
  }
})
