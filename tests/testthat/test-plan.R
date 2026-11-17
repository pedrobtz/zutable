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
      if (!f$nullable) {
        expect_false(any(zt_is_null(v)), info = paste(deparse(sel), f$name))
      }
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
