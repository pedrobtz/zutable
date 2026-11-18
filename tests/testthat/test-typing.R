# Typing, generated from the vocabulary table: every function under every
# combination of argument types, accepted exactly when one of its
# signatures says so, with the result type that signature declares.


test_that("every function accepts exactly the types its signatures declare", {
  checked <- 0L
  # Typing is pure R; under gctorture at step 20 every tenth combination.
  stride <- if (under_torture()) 10L else 1L
  for (entry in zt_vocab) {
    if (!length(entry$sigs)) next
    arities <- unique(unlist(lapply(entry$sigs, function(s) {
      n <- length(s$args)
      if (isTRUE(s$variadic)) c(n, n + 1L) else n
    })))
    for (k in arities) {
      combos <- if (k == 0L) list(character()) else
        as.list(as.data.frame(t(expand.grid(rep(list(typing_ids), k),
                                            stringsAsFactors = FALSE))))
      for (ids in combos) {
        checked <- checked + 1L
        if (checked %% stride) next
        ids <- unname(unlist(ids))
        expected <- NULL
        for (s in entry$sigs) {
          expected <- sig_accepts(s, ids)
          if (!is.null(expected)) break
        }
        got <- tryCatch(vocab_node(entry$name, ids)$type,
                        zutable_type_error = function(e) NULL)
        expect_identical(got, expected, info = sprintf(
          "%s(%s)", entry$name, paste(ids, collapse = ", ")))
      }
    }
  }
  expect_gt(checked, 4000L)
})

test_that("the typing rules of design §7.2 hold", {
  s <- schema(i = int32, j = int32, f = float64, s = string, d = date,
              b = bool, k = enum(c("lo", "hi")))
  ty <- function(e) format(zt_translate(e, s, environment())$type)
  expect_identical(ty(quote(i + j)), "int32")
  expect_identical(ty(quote(i + f)), "float64")
  expect_identical(ty(quote(i / j)), "float64")
  expect_identical(ty(quote(i == f)), "bool")
  expect_identical(ty(quote(s < s)), "bool")
  expect_identical(ty(quote(sum(i))), "float64")
  expect_identical(ty(quote(mean(i))), "float64")
  expect_identical(ty(quote(count())), "int32")
  expect_identical(ty(quote(.N)), "int32")
  expect_identical(ty(quote(max(d))), "date")
  expect_identical(ty(quote(d - d)), "int32")
  expect_identical(ty(quote(d + 1L)), "date")
})

test_that("literals take their context's type when exactly representable", {
  s <- schema(i = int32, d = date, k = enum(c("lo", "hi")),
              t = timestamp("us", "UTC"))
  tr <- function(e) zt_translate(e, s, environment())
  expect_identical(format(tr(quote(i + 1))$type), "int32")
  expect_identical(format(tr(quote(i + 1.5))$type), "float64")
  expect_identical(tr(quote(d >= "2026-01-01"))$args[[2L]]$type, zt_type("date"))
  expect_error(tr(quote(d >= "2026-13-01")), class = "zutable_type_error")
  expect_error(tr(quote(d >= "yesterday")), class = "zutable_type_error")
  expect_identical(format(tr(quote(k == "lo"))$type), "bool")
  expect_error(tr(quote(k == "medium")), class = "zutable_type_error")
  expect_error(tr(quote(k < "lo")), class = "zutable_type_error")
  expect_identical(format(tr(quote(coalesce(i, NA)))$type), "int32")
  expect_identical(format(tr(quote(t > "2026-01-01 09:30"))$type), "bool")
  cutoff <- as.Date("2026-06-01")
  expect_identical(tr(quote(d < cutoff))$args[[2L]]$value, cutoff)
})

test_that("names: columns win, ..name forces the caller, constants fold", {
  s <- schema(i = int32, x = int32)
  x <- 100L
  node <- zt_translate(quote(i + x), s, environment())
  expect_identical(node$args[[2L]]$kind, "col")
  node <- zt_translate(quote(i + ..x), s, environment())
  expect_identical(node$args[[2L]]$value, 100L)
  node <- zt_translate(quote(i + (x2 * 2L)), s, list2env(list(x2 = 21L)))
  expect_identical(node$args[[2L]]$value, 42L)
  expect_error(zt_translate(quote(i + nope), s, environment()),
               class = "zutable_syntax_error")
  expect_error(zt_translate(quote(i + 1:2), s, environment()),
               class = "zutable_type_error")
})

test_that("unknown functions and nested aggregates are type errors", {
  s <- schema(i = int32)
  cnd <- expect_error(zt_translate(quote(my_model(i)), s, environment()),
                      class = "zutable_type_error")
  expect_identical(cnd$fn, "my_model")
  expect_match(conditionMessage(cnd), "r(", fixed = TRUE)
  expect_error(zt_translate(quote(sum(max(i))), s, environment()),
               class = "zutable_type_error")
  expect_error(zt_translate(quote(upper(i)), s, environment()),
               class = "zutable_type_error")
})

test_that("nullability follows each function's NA rule", {
  s <- schema(a = not_null(int32), b = int32)
  nl <- function(e) zt_translate(e, s, environment())$nullable
  expect_false(nl(quote(a + 1L)))
  expect_true(nl(quote(a + b)))
  expect_false(nl(quote(is.na(b))))
  expect_false(nl(quote(count(b))))
  expect_false(nl(quote(coalesce(b, a))))
  expect_true(nl(quote(coalesce(b, b))))
  expect_true(nl(quote(a %/% 2L)))
  expect_true(nl(quote(sum(a))))
})

test_that("synonyms resolve to the SQL names", {
  s <- schema(x = string, n = float64)
  expect_identical(zt_translate(quote(toupper(x)), s, environment())$fn, "upper")
  expect_identical(zt_translate(quote(paste0(x, x)), s, environment())$fn, "concat")
  expect_identical(zt_translate(quote(avg(n)), s, environment())$fn, "mean")
})

test_that("every function carries a lineage kind (§8.5 rule 4)", {
  for (e in zt_vocab) {
    expect_true(e$lineage %in% c("identity", "transformation", "aggregation"),
                info = e$name)
  }
  expect_true(zt_vocab$count$masking)
  expect_identical(zt_vocab$sum$lineage, "aggregation")
})

test_that("a type variable needs one type: enum levels and zones must agree", {
  s <- schema(k1 = enum(c("a", "b")), k2 = enum(c("a", "c")),
              t1 = timestamp("us", "UTC"), t2 = timestamp("us", "Asia/Tokyo"),
              t0 = timestamp("us"), b = bool)
  tr <- function(e) zt_translate(e, s, environment())
  expect_error(tr(quote(k1 == k2)), class = "zutable_type_error")
  expect_error(tr(quote(coalesce(k1, k2))), class = "zutable_type_error")
  expect_error(tr(quote(ifelse(b, t1, t2))), class = "zutable_type_error")
  expect_identical(format(tr(quote(coalesce(k1, k1)))$type), 'enum(c("a", "b"))')
  # Instants compare across zones, but never with a time without one.
  expect_identical(format(tr(quote(t1 < t2))$type), "bool")
  expect_error(tr(quote(t1 < t0)), class = "zutable_type_error")
})
