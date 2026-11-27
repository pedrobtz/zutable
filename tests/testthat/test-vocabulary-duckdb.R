# DuckDB is the oracle for the vocabulary (design §14): every row of the
# table, under every signature, is run locally and as SQL over the same
# columns, and the results compared.





test_that("every vocabulary row agrees with DuckDB", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("DBI")
  skip_conformance_under_torture()
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
  # The count made on 2026-11-26 (#78): a row or signature lost from the
  # comparison fails here; one added raises the count, and the floor with it.
  expect_gte(checked, 597L)
})

test_that("the special forms agree with DuckDB", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("DBI")
  skip_conformance_under_torture()
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

test_that("binary numeric functions agree with DuckDB on every pair of edge values", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("DBI")
  skip_conformance_under_torture()
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  edge <- c(-Inf, -3.75, -2, -1, -0.5, -0, 0, 0.5, 1, 2, 3.75, Inf, NaN, NA)
  grid <- expand.grid(a = edge, b = edge)
  cols <- list(c1 = grid$a, c2 = grid$b)
  n <- nrow(grid)
  fns <- c("+", "-", "*", "/", "%/%", "%%", "^", "==", "!=", "<", "<=", ">",
           ">=")
  for (fn in fns) {
    node <- vocab_node(fn, c("float64", "float64"))
    res <- duck_compare(con, node, cols, n, FALSE)
    expect_true(same_values(res$want, res$got, node$type),
                info = diff_info(fn, c("float64", "float64"), cols, res, node$type))
  }
  for (fn in c("abs", "sqrt", "exp", "log", "round", "floor", "ceiling")) {
    node <- vocab_node(fn, "float64")
    res <- duck_compare(con, node, list(c1 = edge), length(edge), FALSE)
    expect_true(same_values(res$want, res$got, node$type),
                info = diff_info(fn, "float64", list(c1 = edge), res, node$type))
  }
})

test_that("date_trunc() and the date parts of UTC timestamps agree with DuckDB (#78)", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("DBI")
  skip_conformance_under_torture()
  con <- duck_connect()
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  withr::local_seed(20261126)
  # Instants from 1901 to 2099, at quarter seconds (exact in a double),
  # and the turn of each unit, either side.
  e <- c(round(stats::runif(400, -2.2e9, 4.1e9)) + sample(c(0, 0.25, 0.5, 0.75), 400, TRUE),
         utc_edges <- as.double(as.POSIXct(c("2026-01-01", "2025-12-31 23:59:59.75",
                                             "2024-02-29 12:00", "2026-03-30", "1970-01-01",
                                             "1969-12-31 23:59:59.5"), tz = "UTC")), NA)
  z <- as_zutable(data.frame(t = .POSIXct(e, "UTC")))
  df <- data.frame(e = e)
  duckdb::duckdb_register(con, "t", df)
  units <- c("second", "minute", "hour", "day", "week", "month", "quarter", "year")
  for (unit in units) {
    got <- posixct_to_us(z[select = .(r = date_trunc(..unit, t))]$r)
    want <- DBI::dbGetQuery(con, sprintf(paste(
      "SELECT epoch_us(date_trunc('%s', make_timestamp(CAST(round(e * 1e6) AS BIGINT))))",
      "AS r FROM t"), unit))$r
    expect_identical(got, as.double(want), info = unit)
  }
  parts <- z[select = .(y = year(t), m = month(t), d = day(t), dt = cast(t, date))]
  want <- DBI::dbGetQuery(con, paste(
    "SELECT CAST(year(s) AS INTEGER) AS y, CAST(month(s) AS INTEGER) AS m,",
    "CAST(day(s) AS INTEGER) AS d, CAST(s AS DATE) AS dt",
    "FROM (SELECT make_timestamp(CAST(round(e * 1e6) AS BIGINT)) AS s FROM t)"))
  expect_identical(parts$y, want$y)
  expect_identical(parts$m, want$m)
  expect_identical(parts$d, want$d)
  expect_identical(as.double(parts$dt), as.double(want$dt))
})

test_that("zoned timestamps agree with DuckDB's ICU in zones east and west (#78)", {
  skip_conformance_under_torture()
  con <- duck_connect_icu()
  withr::local_seed(20261127)
  # Half-hour, 45-minute and southern zones, and zones whose change falls
  # at midnight; instants at random from 1990 to 2037 and then crowded
  # around every change of 2026, where the wall clock skips or repeats.
  zones <- c("America/New_York", "Europe/London", "Asia/Kolkata", "Australia/Lord_Howe",
             "America/Sao_Paulo", "Pacific/Chatham", "Asia/Kathmandu", "America/Havana")
  units <- c("second", "minute", "hour", "day", "week", "month", "quarter", "year")
  for (tz in zones) {
    DBI::dbExecute(con, sprintf("SET TimeZone = '%s'", tz))
    span <- as.double(as.POSIXct(c("2025-12-01", "2027-01-31"), tz = "UTC"))
    grid <- seq(span[[1L]], span[[2L]], by = 900)
    local <- as.POSIXlt(.POSIXct(grid, tz))$gmtoff
    change <- grid[which(diff(local) != 0) + 1L]
    near <- unlist(lapply(change, function(x) x + c(-5400, -3600, -1800, -0.25, 0, 0.25,
                                                    1800, 3600, 5400)))
    e <- c(round(stats::runif(200, 6.3e8, 2.1e9)) + sample(c(0, 0.25, 0.5), 200, TRUE),
           near, NA)
    z <- as_zutable(data.frame(t = .POSIXct(e, tz)))
    duckdb::duckdb_register(con, "t", data.frame(e = e), overwrite = TRUE)
    input <- posixct_to_us(.POSIXct(e, "UTC"))
    ts <- "to_timestamp(CAST(e AS DOUBLE))"
    # R reads the system's tzdata and DuckDB its own ICU copy, and the two
    # can differ on a zone's rules (Havana from 2026 on a 2026 runner).
    # Compare only where both put the same offset at the input and at
    # ICU's answer; most instants must remain.
    agrees <- function(s) {
      w <- floor(s[!is.na(s)])
      r_off <- as.double(as.POSIXct(format(.POSIXct(w, tz), "%Y-%m-%d %H:%M:%S"),
                                    tz = "UTC")) - w
      duckdb::duckdb_register(con, "o", data.frame(s = w), overwrite = TRUE)
      icu_off <- DBI::dbGetQuery(con, paste(
        "SELECT date_part('timezone', to_timestamp(CAST(s AS DOUBLE))) AS o FROM o"))$o
      out <- rep(TRUE, length(s))
      out[!is.na(s)] <- r_off == icu_off
      out
    }
    same <- agrees(e)
    expect_gte(sum(same), length(e) / 2)
    for (unit in units) {
      got <- posixct_to_us(z[select = .(r = date_trunc(..unit, t))]$r)
      want <- as.double(DBI::dbGetQuery(con, sprintf(
        "SELECT epoch_us(date_trunc('%s', %s)) AS r FROM t", unit, ts))$r)
      keep <- same & agrees(want / 1e6)
      expect_gte(sum(keep), length(e) / 2)
      expect_trunc_matches_icu(got[keep], want[keep], input[keep], tz, paste(tz, unit))
    }
    parts <- z[select = .(y = year(t), m = month(t), d = day(t), dt = cast(t, date))]
    want <- DBI::dbGetQuery(con, sprintf(paste(
      "SELECT CAST(year(%1$s) AS INTEGER) AS y, CAST(month(%1$s) AS INTEGER) AS m,",
      "CAST(day(%1$s) AS INTEGER) AS d, CAST(%1$s AS DATE) AS dt FROM t"), ts))
    expect_identical(parts$y[same], want$y[same], info = tz)
    expect_identical(parts$m[same], want$m[same], info = tz)
    expect_identical(parts$d[same], want$d[same], info = tz)
    expect_identical(as.double(parts$dt)[same], as.double(want$dt)[same], info = tz)
  }
})
