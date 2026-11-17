# A generated table for the bracket's tests: no NaN, so base R's own
# comparisons are an oracle (NaN's order is tested on its own, D47).
bracket_frame <- function(n = 60L) {
  data.frame(
    id = seq_len(n),
    g = sample(c("a", "B", "b", "A", "", NA), n, replace = TRUE),
    k = sample(c(-2L, 0L, 3L, 7L, NA), n, replace = TRUE),
    px = round(stats::runif(n, -5, 5), 1)[sample.int(n)],
    flag = sample(c(TRUE, FALSE, NA), n, replace = TRUE),
    day = as.Date("2026-01-01") + sample(c(0:30, NA), n, replace = TRUE),
    stringsAsFactors = FALSE
  )
}

# Expressions the plan property test draws from.
plan_exprs <- list(
  quote(px * 2), quote(k + 1L), quote(k / 2L), quote(px > 0), quote(g == "a"),
  quote(coalesce(k, 0L)), quote(nchar(g)), quote(upper(g)), quote(is.na(px)),
  quote(day + 1L), quote(year(day)), quote(ifelse(flag, k, -k)),
  quote(case(px > 1 ~ "hi", .default = "lo")), quote(cast(k, string)),
  quote(round(px, 1L)), quote(abs(k)), quote(concat(g, "!")), quote(id),
  quote(!flag), quote(between(px, -1, 1)), quote(k %/% 2L), quote(1L),
  quote(date_trunc("month", day))
)
