# The design's central claim: every step's schema is known, exact and
# checked before data is read. Over generated queries, the plan's schema
# describes the executed result exactly.

test_that("the plan's schema describes the executed result exactly", {
  withr::local_seed(7)
  df <- bracket_frame()
  z <- as_zutable(df, schema(id = not_null(int32), g = string, k = int32,
                             px = not_null(float64), flag = bool, day = date))
  for (trial in 1:60) {
    picks <- sample(seq_along(plan_exprs), sample(1:4, 1))
    items <- plan_exprs[picks]
    names(items) <- paste0("v", seq_along(items))
    sel <- as.call(c(as.name("."), items))
    q <- bquote(z[px > -3, .(sel), order = desc(id)])
    q[[4L]] <- sel
    r <- eval(q)
    s <- schema(r)
    for (f in s$fields) {
      v <- r[[f$name]]
      expect_null(vector_problem(v, f$type), info = paste(deparse(sel), f$name))
      # And by base R's own reading of the vector, not the validator (#72).
      expect_true(base_type_is(v, f$type$id), info = paste(deparse(sel), f$name))
      if (!f$nullable) {
        expect_false(any(zt_is_null(v)), info = paste(deparse(sel), f$name))
      }
    }
  }
})

test_that("plan, result and the clauses' rules agree on every schema (#72)", {
  # The schema the plan records (what explain() prints) and schema() of the
  # executed result, against types and nullability derived by hand from
  # each clause's rule: count() is never null and every other aggregate
  # may be (an empty or all-NA group); a key or a bare column keeps its
  # nullability; a join makes the side that may be unmatched nullable,
  # and its key nullable when either side's key is (D54). Inputs are
  # not_null and nullable in turn, and y's key the other way from x's.
  ty <- function(id, null) if (null) id else sprintf("not_null(%s)", id)
  plan_schema <- function(r) {
    rec <- attr(r, "plan", exact = TRUE)
    if (is.null(rec)) return(attr(r, "schema"))
    st <- Filter(function(s) !is.null(s$schema), rec$steps)
    if (length(st)) st[[length(st)]]$schema else rec$source$schema
  }
  check <- function(r, want, info) {
    want <- paste(names(want), want)
    expect_identical(unname(vapply(schema(r)$fields, format, "")), want, info = info)
    expect_identical(unname(vapply(plan_schema(r)$fields, format, "")), want, info = info)
    for (f in schema(r)$fields) {
      v <- r[[f$name]]
      expect_true(base_type_is(v, f$type$id), info = paste(info, f$name))
      if (!f$nullable) expect_false(anyNA(v), info = paste(info, f$name))
    }
  }
  for (nn in c(TRUE, FALSE)) {
    null_x <- !nn
    null_y <- nn
    w <- function(id, null) if (null) as.name(id) else call("not_null", as.name(id))
    xd <- data.frame(id = 1:6, g = c("a", "b", "a", "d", "b", "a"),
                     px = c(1, 2, 3, 4, 5, 6))
    if (null_x) xd[2, ] <- list(NA, NA, NA)
    x <- as_zutable(xd, eval(bquote(schema(
      id = .(w("int32", null_x)), g = .(w("string", null_x)),
      px = .(w("float64", null_x))))))
    yd <- data.frame(g = c("a", "c", "b"), w = c(10L, 20L, 30L), v = c(1, NA, 2))
    if (null_y) yd$g[3] <- NA
    y <- as_zutable(yd, eval(bquote(schema(
      g = .(w("string", null_y)), w = not_null(int32), v = float64))))
    info <- if (nn) "x not_null" else "x nullable"
    gx <- ty("string", null_x)

    check(x[px > 2 | is.na(px)], c(id = ty("int32", null_x), g = gx,
                                    px = ty("float64", null_x)), paste(info, "where"))
    agg <- c(g = gx, n = ty("int32", FALSE), s = "float64", m = "int32",
             c2 = ty("int32", FALSE), mn = "float64", si = "float64")
    check(x[, .(n = count(), s = sum(px), m = max(id), c2 = count(px),
                mn = mean(px), si = sum(id)), by = g], agg, paste(info, "by"))
    check(x[, .(n = count(), s = sum(px), m = max(id), c2 = count(px),
                mn = mean(px), si = sum(id)), by = g, having = n > 1], agg,
          paste(info, "having"))
    check(x[, .(id, t = over(sum(px), by = g), u = over(count(), by = g),
                k = g, mx = over(max(id), by = g))],
          c(id = ty("int32", null_x), t = "float64", u = ty("int32", FALSE),
            k = gx, mx = "int32"), paste(info, "over"))

    xs <- c(id = ty("int32", null_x), g = gx, px = ty("float64", null_x))
    key_either <- ty("string", null_x || null_y)
    joins <- list(
      inner = c(xs, w = ty("int32", FALSE), v = "float64"),
      left = c(xs, w = "int32", v = "float64"),
      right = c(id = "int32", g = key_either, px = "float64",
                w = ty("int32", FALSE), v = "float64"),
      full = c(id = "int32", g = key_either, px = "float64", w = "int32", v = "float64"),
      semi = xs,
      anti = xs
    )
    for (how in names(joins)) {
      check(join(x, y, on = g, how = how), joins[[how]], paste(info, "join", how))
      # A plan over a join's result: a filter keeps the join's schema.
      check(join(x, y, on = g, how = how)[!is.na(g)], joins[[how]],
            paste(info, "join", how, "then where"))
    }
  }
})

test_that("not_null is carried by bare columns and by NA-free functions", {
  z <- as_zutable(data.frame(a = 1:3, b = c(1L, NA, 3L)),
                  schema(a = not_null(int32), b = int32))
  s <- schema(z[, .(a, b, c = a + 1L, d = is.na(b), e = a %/% 2L)])
  expect_identical(vapply(s$fields, function(f) f$nullable, NA),
                   c(a = FALSE, b = TRUE, c = FALSE, d = FALSE, e = TRUE))
})

test_that("the plan record obeys the lineage rules (§8.5, 1 to 5)", {
  z <- zutable(id = 1:3, px = c(1.5, 2, 2.5), qty = c(1L, 2L, 3L))
  lim <- 1
  r <- z[px > lim, .(id, notional = px * qty), order = desc(notional)]
  rec <- attr(r, "plan")
  steps <- rec$steps
  expect_identical(vapply(steps, function(s) s$op, ""), c("filter", "project", "sort"))
  # 1: references are resolved to a step's input.
  proj <- steps[[2L]]
  expect_identical(proj$exprs$notional$args[[1L]]$from, 1L)
  expect_identical(steps[[1L]]$predicate$args[[1L]]$from, 0L)
  # 2: each output column keeps the expression that made it.
  expect_identical(names(proj$exprs), c("id", "notional"))
  expect_identical(proj$exprs$notional$fn, "*")
  # 3: the source has an identity, here anonymous and saying so.
  expect_true(rec$source$anonymous)
  # 4: functions carry their lineage kind, read from the vocabulary.
  expect_identical(zt_vocab[[proj$exprs$notional$fn]]$lineage, "transformation")
  # 5: the record is metadata only: no environment, no table.
  has_env <- function(v) {
    if (is.environment(v) || is.data.frame(v)) return(TRUE)
    if (is.list(v)) return(any(vapply(v, has_env, NA)))
    FALSE
  }
  expect_false(has_env(rec))
  g <- function() z[, .(m = r(px * 2, float64))]
  expect_false(has_env(attr(g(), "plan")))
})

test_that("a write outside the plan marks the column's lineage unknown (rule 6)", {
  z <- zutable(id = 1:3, px = c(1.5, 2, 2.5))
  r <- z[, .(id, twice = px * 2)]
  r$twice <- c(0, 0, 0)
  expect_identical(attr(r, "plan")$unknown, "twice")
  expect_match(zt_explain_lines(r), "written outside the plan: twice", all = FALSE)
})
