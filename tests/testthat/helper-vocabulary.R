# Typed sample columns for the vocabulary's tests: NA, NaN, -0, the
# infinities, empty strings and non-ASCII text among ordinary values.
vocab_type_of <- function(id) {
  switch(id,
    timestamp = zt_timestamp("us", "UTC"),
    enum = zt_type("enum", levels = c("lo", "hi")),
    list = zt_type("list", value = zt_type("int32")),
    struct = zt_type("struct", fields = list(a = new_field("a", zt_type("int32")))),
    zt_type(id)
  )
}

vocab_sample <- function(id, n) {
  pick <- function(pool) pool[sample.int(length(pool), n, replace = TRUE)]
  switch(id,
    bool = pick(c(TRUE, FALSE, NA)),
    int32 = pick(c(-7L, -3L, -1L, 0L, 1L, 2L, 5L, 12L, NA)),
    float64 = pick(c(-2.5, -1, -0, 0, 0.5, 1, 3.75, 1e10, NaN, NA, Inf, -Inf)),
    string = pick(c("a", "B", "ab", "", " x y ", "café", "Zz", "a%b",
                    "Été", NA)),
    date = pick(as.Date("2026-01-01") + c(-400L, -1L, 0L, 31L, 59L, 200L, NA)),
    timestamp = pick(.POSIXct(1767225600 + c(-86400.5, 0, 3600.25, 7 * 86400,
                                             NA), "UTC")),
    enum = pick(factor(c("lo", "hi", NA), levels = c("lo", "hi"))),
    binary = pick(list(as.raw(1:2), raw(), NULL)),
    list = pick(list(1:2, NULL, 3L)),
    NULL
  )
}

vocab_columns <- function(ids, n) {
  if (!length(ids)) return(list())
  cols <- lapply(ids, vocab_sample, n = n)
  names(cols) <- paste0("c", seq_along(ids))
  cols
}

vocab_schema <- function(ids) {
  if (!length(ids)) return(new_schema())
  fields <- lapply(seq_along(ids), function(i) {
    new_field(paste0("c", i), vocab_type_of(ids[[i]]))
  })
  new_schema(fields)
}

# The call `fn(c1, c2, ...)` typed against columns of `ids`.
vocab_node <- function(fn, ids) {
  s <- vocab_schema(ids)
  args <- lapply(names(s), as.name)
  zt_translate(as.call(c(as.name(fn), args)), s, environment())
}

duck_compare <- function(con, node, cols, n, aggregate) {
  df <- as.data.frame(cols, stringsAsFactors = FALSE)
  if (!length(cols)) df <- data.frame(row.names = seq_len(n))
  df[[".zt_row"]] <- seq_len(n)
  duckdb::duckdb_register(con, "t", df, overwrite = TRUE)
  on.exit(duckdb::duckdb_unregister(con, "t"))
  sql <- sprintf("SELECT %s AS r FROM t%s", zt_sql_expr(node),
                 if (aggregate) "" else ' ORDER BY ".zt_row"')
  # Local first: an input it refuses with a value error is not compared.
  want <- zt_eval(node, cols, n)
  got <- DBI::dbGetQuery(con, sql)$r
  list(sql = sql, got = got, want = want)
}

same_values <- function(want, got, type) {
  if (type$id == "float64") {
    w <- as.double(want)
    g <- as.double(got)
    if (length(w) != length(g)) return(FALSE)
    if (!identical(is.na(w) & !is.nan(w), is.na(g) & !is.nan(g))) return(FALSE)
    if (!identical(is.nan(w), is.nan(g))) return(FALSE)
    ok <- !is.na(w)
    return(isTRUE(all.equal(w[ok], g[ok], tolerance = 1e-12)) || !any(ok))
  }
  if (type$id == "date") return(identical(as.double(want), as.double(got)))
  if (type$id == "timestamp") {
    return(isTRUE(all.equal(as.double(want), as.double(got), tolerance = 0)))
  }
  if (type$id == "enum") return(identical(as.character(want), as.character(got)))
  if (type$id == "string") return(identical(enc2utf8(want), enc2utf8(got)))
  identical(want, got)
}

# A signature's argument ids with each type variable given one concrete id.
sig_instances <- function(s) {
  ids <- s$args
  if (isTRUE(s$variadic)) ids <- c(ids, ids[[length(ids)]])
  if (!any(ids == "T")) return(list(ids))
  ts <- intersect(s$T, c("bool", "int32", "float64", "string", "date",
                         "timestamp", "enum"))
  lapply(ts, function(t) replace(ids, ids == "T", t))
}

# The rows where local and DuckDB differ, with their inputs.
diff_info <- function(fn, ids, cols, res, type) {
  w <- res$want
  g <- res$got
  rows <- integer()
  if (length(w) == length(g) && length(w) > 1L) {
    for (i in seq_along(w)) {
      if (!same_values(zt_take(w, i), zt_take(g, i), type)) rows <- c(rows, i)
    }
  }
  show <- function(v) paste(format(v), collapse = " | ")
  lines <- vapply(head(rows, 5L), function(i) {
    args <- vapply(cols, function(c) show(zt_take(c, i)), "")
    sprintf("  row %d: (%s) local %s, duckdb %s", i, paste(args, collapse = ", "),
            show(zt_take(w, i)), show(zt_take(g, i)))
  }, "")
  paste(c(sprintf("%s(%s): %s", fn, paste(ids, collapse = ", "), res$sql), lines),
        collapse = "\n")
}

sql_args <- c("bool", "int32", "float64", "string", "date", "timestamp", "enum")

typing_ids <- c("bool", "int32", "float64", "string", "date", "timestamp",
                "enum", "binary", "list")

# The independent reading of a signature, for typed (non-literal) columns.
sig_accepts <- function(s, ids) {
  want <- s$args
  if (isTRUE(s$variadic)) {
    if (length(ids) < length(want)) return(NULL)
    want <- c(want, rep(want[[length(want)]], length(ids) - length(want)))
  }
  if (length(want) != length(ids)) return(NULL)
  tslots <- which(want == "T")
  if (length(tslots)) {
    tid <- ids[[tslots[[1L]]]]
    if (any(ids[tslots] != tid)) return(NULL)
    if (!is.null(s$T) && !tid %in% s$T) return(NULL)
    want[tslots] <- tid
  }
  if (any(want != ids)) return(NULL)
  types <- lapply(ids, vocab_type_of)
  if (!is.null(s$check) && !isTRUE(s$check(types))) return(NULL)
  r <- s$result
  if (is.function(r)) return(r(types))
  if (identical(r, "T")) return(types[[tslots[[1L]]]])
  if (startsWith(r, "arg")) return(types[[as.integer(substring(r, 4L))]])
  zt_type(r)
}

ev <- function(.expr, ...) {
  cols <- list(...)
  s <- infer_schema(as.data.frame(cols, stringsAsFactors = FALSE))
  n <- if (length(cols)) zt_nrow_of(cols[[1L]]) else 0L
  zt_eval(zt_translate(.expr, s, parent.frame()), cols, n)
}

ec <- function(x, to) {
  s <- new_schema(list(new_field("x", infer_type(x))))
  node <- zt_translate(bquote(cast(x, .(to))), s, environment())
  zt_eval(node, list(x = x), zt_nrow_of(x))
}

# A DuckDB connection for the oracle tests that never touches the network:
# no extension is installed or loaded on demand (a test must not download,
# and valgrind sees DuckDB's HTTP client otherwise).
duck_connect <- function() {
  DBI::dbConnect(duckdb::duckdb(config = list(
    autoinstall_known_extensions = "false",
    autoload_known_extensions = "false"
  )))
}

# A DuckDB connection with its ICU extension, for the oracles of zoned time
# (#78), disconnected when `env` ends. ICU is loaded from DuckDB's local
# extension directory when it is there, and the test skips when it is not;
# with ZUTABLE_DUCKDB_ICU=true (the native coverage job's run sets it) it
# is installed over the network first, never on CRAN, and failing to load
# it is a failure, so that leg cannot skip in silence.
duck_connect_icu <- function(env = parent.frame()) {
  testthat::skip_if_not_installed("duckdb")
  testthat::skip_if_not_installed("DBI")
  con <- duck_connect()
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE), envir = env)
  required <- identical(Sys.getenv("ZUTABLE_DUCKDB_ICU"), "true")
  if (required) {
    testthat::skip_on_cran()
    DBI::dbExecute(con, "INSTALL icu")
  }
  ok <- tryCatch({
    DBI::dbExecute(con, "LOAD icu")
    TRUE
  }, error = function(e) if (required) stop(e) else FALSE)
  testthat::skip_if_not(ok, "DuckDB's ICU extension is not available offline")
  con
}

# The rows where DuckDB's ICU truncates to an instant after its input,
# which D63 does not: a wall time in a repeated (fall-back) hour ICU takes
# at the later offset, where D63 keeps the input's, so the two agree on
# the wall clock; and a wall time in a gap ICU reads at the offset from
# before the change, where D63 takes the first instant after the gap.
# There zutable's answer is not after the input and is one of those two;
# elsewhere the two agree exactly. Returns which rows differ.
expect_trunc_matches_icu <- function(got_us, icu_us, input_us, tz, info) {
  later <- !is.na(icu_us) & icu_us > input_us
  expect_identical(got_us[!later], icu_us[!later], info = info)
  if (any(later)) {
    at <- function(us) .POSIXct(us / 1e6, tz)
    wall <- function(us) format(at(us), "%Y-%m-%d %H:%M:%OS6")
    offset <- function(us) as.POSIXlt(at(us))$gmtoff
    g <- got_us[later]
    expect_true(all(g <= input_us[later]), info = info)
    same_wall <- wall(g) == wall(icu_us[later])
    gap_end <- offset(g - 1e6) != offset(g)
    expect_true(all(same_wall | gap_end), info = info)
  }
  later
}
