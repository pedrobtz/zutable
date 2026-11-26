# What carries metadata (D59, #66): a bare column reference keeps its
# field's, renamed or not; a computed expression gets none; a plan over
# one source keeps the table's; a join keeps x's; rbind() its first's.

meta_table <- function() {
  s <- schema(id = not_null(int32), px = field(float64, metadata = c(unit = "USD")),
              g = field(string, metadata = c(role = "group")), .metadata = c(src = "x"))
  as_zutable(data.frame(id = 1:3, px = c(1, 2, 3), g = c("a", "b", "a")), s)
}

field_meta <- function(x, name) schema(x)$fields[[name]]$metadata

test_that("bare references keep field metadata through every clause (#66)", {
  for (ex in c("kernel", "reference")) {
    withr::local_options(zutable.executor = ex)
    m <- meta_table()
    usd <- c(unit = "USD")
    grp <- c(role = "group")
    routes <- list(
      select = m[select = .(px)],
      renamed = m[select = .(price = px)],
      all = m[select = .(.all)],
      col = m[select = .(px = .col("px"))],
      value_form = m[, "px"],
      where = m[id > 1],
      order = m[order = desc(px)],
      limit = m[limit = 2],
      distinct = m[select = .(px), distinct = TRUE],
      copy = copy(m)
    )
    for (nm in names(routes)) {
      r <- routes[[nm]]
      pname <- if (nm == "renamed") "price" else "px"
      expect_identical(field_meta(r, pname), usd, info = paste(ex, nm))
      expect_identical(metadata(r), c(src = "x"), info = paste(ex, nm))
    }
    # Two routes to the same column agree.
    expect_identical(schema(m[select = .(px)]), schema(m[, "px"]))
    b <- m[by = g, select = .(s = sum(px), p = first(px))]
    expect_identical(field_meta(b, "g"), grp, info = ex)
    expect_identical(field_meta(b, "s"), character(), info = ex)
    expect_identical(field_meta(b, "p"), character(), info = ex)
    expect_identical(metadata(b), c(src = "x"), info = ex)
    b <- m[by = .(grp = g), select = .(n = count())]
    expect_identical(field_meta(b, "grp"), grp, info = ex)
    b <- m[by = .(u = upper(g)), select = .(n = count())]
    expect_identical(field_meta(b, "u"), character(), info = ex)
    c2 <- m[select = .(px, d = px * 2, k = cast(px, float64), o = over(sum(px), by = g))]
    expect_identical(field_meta(c2, "px"), usd, info = ex)
    for (n in c("d", "k", "o")) expect_identical(field_meta(c2, n), character(), info = n)
    s <- m[select = .(n = count())]
    expect_identical(metadata(s), c(src = "x"), info = ex)
    u <- copy(m)
    u[, px := px * 2]
    expect_identical(field_meta(u, "px"), usd)
    expect_identical(metadata(u), c(src = "x"))
  }
})

test_that("a join keeps x's table metadata and the fields' own; rbind the first's (#66)", {
  m <- meta_table()
  y <- as_zutable(data.frame(g = c("a", "b"), w = c(10, 20)),
                  schema(g = field(string, metadata = c(role = "y-group")),
                         w = field(float64, metadata = c(unit = "kg")), .metadata = c(src = "y")))
  for (ex in c("kernel", "reference")) {
    withr::local_options(zutable.executor = ex)
    for (how in c("inner", "left", "right", "full", "semi", "anti")) {
      j <- join(m, y, on = g, how = how)
      expect_identical(metadata(j), c(src = "x"), info = paste(ex, how))
      expect_identical(field_meta(j, "px"), c(unit = "USD"), info = paste(ex, how))
      expect_identical(field_meta(j, "g"), c(role = "group"), info = paste(ex, how))
      if (!how %in% c("semi", "anti")) {
        expect_identical(field_meta(j, "w"), c(unit = "kg"), info = paste(ex, how))
      }
    }
  }
  expect_identical(metadata(rbind(m, m[1])), c(src = "x"))
  expect_identical(schema(rbind(m, m[1])), schema(m))
})
