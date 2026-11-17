# DuckDB is the oracle for the vocabulary (design §14): every row of the
# table, under every signature, is run locally and as SQL over the same
# columns, and the results compared.





test_that("every vocabulary row agrees with DuckDB", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("DBI")
  con <- duck_connect()
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  withr::local_seed(20261117)
  checked <- 0L
  for (entry in zt_vocab) {
    for (s in entry$sigs) {
      for (ids in sig_instances(s)) {
        if (!all(ids %in% sql_args)) next
        for (n in c(0L, 1L, 40L)) {
          cols <- vocab_columns(ids, n)
          node <- tryCatch(vocab_node(entry$name, ids), zutable_type_error = function(e) NULL)
          if (is.null(node)) next
          res <- tryCatch(duck_compare(con, node, cols, n, entry$kind == "aggregate"),
                          zutable_value_error = function(e) NULL)
          if (is.null(res)) next
          ok <- same_values(res$want, res$got, node$type)
          expect_true(ok, info = diff_info(entry$name, ids, cols, res, node$type))
          checked <- checked + 1L
        }
      }
    }
  }
  expect_gt(checked, 300L)
})

test_that("the special forms agree with DuckDB", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("DBI")
  con <- duck_connect()
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  withr::local_seed(20261118)
  n <- 40L
  cols <- list(i = vocab_sample("int32", n), f = vocab_sample("float64", n),
               s = vocab_sample("string", n), d = vocab_sample("date", n),
               b = vocab_sample("bool", n))
  s <- schema(i = int32, f = float64, s = string, d = date, b = bool)
  exprs <- list(
    quote(case(i > 2 ~ "big", i < 0 ~ "neg", .default = "small")),
    quote(case(b ~ f, .default = NA)),
    quote(i %in% c(1L, 2L, 12L)),
    quote(s %in% c("a", "B")),
    quote(cast(i, float64)), quote(cast(i, string)), quote(cast(b, int32)),
    quote(cast(f, string)), quote(cast(d, string)), quote(cast(i, bool)),
    quote(ifelse(b, i, -i)), quote(coalesce(f, 0)), quote(between(i, 0, 5)),
    quote(substr(s, 2L, 3L)), quote(substr(s, 0L, 1L)), quote(like(s, "a%")),
    quote(like(s, "_")), quote(date_trunc("month", d)), quote(date_trunc("week", d)),
    quote(date_trunc("quarter", d)), quote(round(f, 1L)), quote(d - 30L)
  )
  for (e in exprs) {
    node <- zt_translate(e, s, environment())
    res <- duck_compare(con, node, cols, n, FALSE)
    got <- res$got
    want <- res$want
    if (identical(node$fn, "cast") && identical(node$type$id, "string") &&
        identical(node$args[[1L]]$type$id, "float64")) {
      # Shortest round-trip text: compared by the number it reads back as.
      got <- suppressWarnings(as.double(got))
      want <- suppressWarnings(as.double(want))
      expect_identical(is.na(want), is.na(got), info = deparse(e))
      expect_identical(want[!is.na(want)], got[!is.na(got)], info = deparse(e))
      next
    }
    expect_true(same_values(want, got, node$type),
                info = paste(deparse(e), res$sql, sep = "\n"))
  }
})

test_that("text to double agrees with DuckDB's correctly rounded parser", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("DBI")
  con <- duck_connect()
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  withr::local_seed(20261119)
  v <- c(stats::runif(300, -1e6, 1e6), 10^stats::runif(300, -300, 300),
         2^-1074, (2 - 2^-52) * 2^1023)
  text <- c(sprintf("%.17g", v), sprintf("%.6e", v), "0.1", "1e-320", "123456789012345678901234567890")
  got <- zt_parse_double(text)
  df <- data.frame(s = text)
  duckdb::duckdb_register(con, "t", df)
  want <- DBI::dbGetQuery(con, "SELECT CAST(s AS DOUBLE) AS d FROM t")$d
  expect_identical(got, want)
})
