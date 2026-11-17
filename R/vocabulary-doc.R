# The vocabulary's help page is generated from the table itself
# (design §7.1), so the documentation cannot disagree with the checker.

zt_vocab_rd <- function() {
  item <- function(e) {
    sigs <- vapply(e$sigs, function(s) {
      a <- s$args
      if (isTRUE(s$variadic)) a[[length(a)]] <- paste0(a[[length(a)]], ", ...")
      r <- if (is.function(s$result)) "?" else s$result
      sprintf("(%s) -> %s", paste(a, collapse = ", "), r)
    }, "")
    syn <- if (length(e$synonyms)) {
      sprintf(" Also spelt %s.", paste0("\\code{", e$synonyms, "}", collapse = ", "))
    } else ""
    what <- if (nzchar(e$doc)) paste0(" ", toupper(substr(e$doc, 1, 1)),
                                      substring(e$doc, 2), ".") else ""
    sig_text <- if (length(sigs)) paste0(" Types: ", paste(unique(sigs), collapse = "; "), ".") else ""
    sprintf("\\item{\\code{%s}}{%s%s%s%s}", gsub("%", "\\\\%", e$name),
            if (e$kind == "aggregate") "Aggregate." else "",
            what, syn, gsub("%", "\\\\%", sig_text))
  }
  c(
    "@section Functions:",
    "Every function allowed in a clause, with the argument and result types it takes. T is one type throughout a signature.",
    "\\describe{",
    vapply(zt_vocab, item, ""),
    "}"
  )
}

#' The expression vocabulary
#'
#' Clauses of the bracket are written in a closed vocabulary of typed
#' functions: SQL's names, with R's spellings as synonyms. A function
#' outside it is a `zutable_type_error` at plan time; `r(expr, type)`
#' evaluates arbitrary R in the local executor, with its result type
#' declared and checked.
#'
#' Where R and SQL differ the vocabulary chooses one rule, the same in
#' every engine: a double's `NA` is the missing value and `NaN` a value,
#' equal to itself and above every number; strings compare by bytes;
#' aggregates skip missing values and give `NA` over none; `int32`
#' arithmetic that overflows is an error; `paste0()` gives `NA` when any
#' part is `NA`; `ifelse()` gives `NA` for an `NA` condition, while
#' `case()` skips it; `substr()` takes R's start and stop. A literal takes
#' the type of its context when it is exactly representable there, so
#' `qty + 1` is `int32` and `day >= "2026-01-01"` compares dates.
#'
#' @eval zt_vocab_rd()
#' @name vocabulary
#' @aliases r cast case
NULL
