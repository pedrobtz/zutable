test_that("base functions give the same result as on the plain frame", {
  df <- sample_frame()
  z <- as_zutable(df)
  expect_identical(plain(head(z, 3)), plain(head(df, 3)))
  expect_identical(plain(tail(z, 2)), plain(tail(df, 2)))
  expect_identical(plain(subset(z, px > 8, select = c(id, g))),
                   plain(subset(df, px > 8, select = c(id, g))))
  expect_identical(lapply(split(z, z$g), plain),
                   lapply(split(df, df$g), plain))
  dup <- rbind(df, df[2:3, ])
  rownames(dup) <- NULL
  expect_identical(plain(unique(as_zutable(dup))), plain(unique(dup)))
  expect_identical(lapply(z, class), lapply(df, class))
  expect_identical(vapply(z, function(c) sum(is.na(c)), 0L),
                   vapply(df, function(c) sum(is.na(c)), 0L))
  expect_identical(coef(lm(px ~ id, data = z)), coef(lm(px ~ id, data = df)))
  expect_identical(dim(z), dim(df))
  expect_identical(nrow(z), 6L)
  expect_identical(names(z), names(df))
  expect_identical(z$px, df$px)
  expect_identical(z[["g"]], df[["g"]])
})

test_that("results of base functions are zutables of the same schema", {
  z <- as_zutable(sample_frame())
  for (r in list(head(z), tail(z), unique(z), split(z, z$g)[[1L]])) {
    expect_s3_class(r, "zutable")
    expect_identical(schema(r), schema(z))
  }
  expect_identical(schema(subset(z, select = g)), schema(g = string))
})

test_that("value forms select rows and columns, and always return a table", {
  z <- as_zutable(sample_frame())
  df <- sample_frame()
  expect_identical(plain(z[2:3, ]), plain(df[2:3, ]))
  expect_identical(plain(z[2:3]), plain(df[2:3, ]))
  expect_identical(plain(z[-1, ]), plain(df[-1, ]))
  expect_identical(plain(z[df$px > 10 & !is.na(df$px), ]),
                   plain(df[df$px > 10 & !is.na(df$px), ]))
  expect_identical(plain(z[, c("g", "id")]), plain(df[, c("g", "id")]))
  expect_identical(plain(z[, 2L]), plain(df[, 2L, drop = FALSE]))
  expect_identical(plain(z[, c(TRUE, FALSE)]),
                   plain(df[, c(TRUE, FALSE, TRUE, FALSE, TRUE)]))
  expect_identical(plain(z[1, "px", drop = TRUE]), plain(df[1, "px", drop = FALSE]))
  expect_s3_class(z[, "px"], "zutable")
  expect_identical(nrow(z[integer(), ]), 0L)
})

test_that("refused value forms", {
  z <- as_zutable(sample_frame())
  expect_error(z["a", ], class = "zutable_syntax_error")
  expect_error(z["id"], class = "zutable_syntax_error")
  expect_error(z[rep(TRUE, 7L), ], class = "zutable_syntax_error")
  expect_error(z[, rep(TRUE, 6L)], class = "zutable_syntax_error")
  expect_error(z[, "nope"], class = "zutable_schema_error")
  expect_error(z[, c("id", "id")], class = "zutable_schema_error")
  expect_error(z[, 9L], class = "zutable_schema_error")
  nn <- as_zutable(data.frame(a = 1:2), schema(a = not_null(int32)))
  expect_error(nn[c(1L, 5L), ], class = "zutable_value_error")
  expect_identical(nrow(as_zutable(sample_frame())[c(1L, 9L), ]), 2L)
})

test_that("one position is rows here and columns inside base R (D43)", {
  z <- as_zutable(sample_frame())
  expect_identical(nrow(z[2:3]), 2L)
  base_view <- evalq(function(x) x[2:3], asNamespace("stats"))
  expect_identical(names(base_view(z)), c("g", "px"))
  expect_s3_class(base_view(z), "zutable")
  base_set <- evalq(function(x) { x$id <- "changed"; x }, asNamespace("stats"))
  out <- base_set(z)
  expect_identical(class(out), "data.frame")
  expect_identical(out$id[[1L]], "changed")
  expect_identical(z$id, 1:6)
  base_rename <- evalq(function(x) { names(x)[1] <- "new"; x }, asNamespace("stats"))
  expect_error(base_rename(z), class = "zutable_schema_error")
  expect_identical(z, `rownames<-`(z, letters[1:6]))
  expect_false(zt_aware(asNamespace("stats")))
  expect_true(zt_aware(globalenv()))
  expect_true(zt_aware(asNamespace("zutable")))
})
