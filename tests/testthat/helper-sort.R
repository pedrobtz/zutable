# Keys for test-key-order.R: sizes either side of every threshold of the
# hybrid (zutable/sort.h), and key vectors of every kind and shape.

sort_sizes <- c(
  0L,
  1L,
  2L,
  23L,
  24L,
  25L,
  127L,
  128L,
  129L,
  999L,
  1000L,
  1001L,
  5000L
)

key_of <- function(kind, n) {
  switch(
    kind,
    int = sample(
      c(NA, -5:5, .Machine$integer.max, -.Machine$integer.max),
      n,
      TRUE
    ),
    int_wide = sample.int(1e9, n, TRUE) * sample(c(-1L, 1L), n, TRUE),
    dbl = sample(
      c(NA, NaN, -0, 0, Inf, -Inf, stats::runif(20, -1e300, 1e300)),
      n,
      TRUE
    ),
    dbl_wide = c(stats::rnorm(n), NA, NaN, -0)[sample(n + 3L, n)],
    lgl = sample(c(TRUE, FALSE, NA), n, TRUE),
    fct = factor(
      sample(c(letters[1:5], NA), n, TRUE),
      levels = c("e", "a", "d", "c", "b")
    ),
    date = as.Date("2026-01-01") + sample(c(NA, -400:400), n, TRUE),
    posix = as.POSIXct("2026-01-01", tz = "UTC") +
      sample(c(NA, stats::runif(50, -1e8, 1e8)), n, TRUE),
    sorted = c(seq_len(n - n %/% 100L), sample.int(max(n, 1L), n %/% 100L)),
    reversed = rev(seq_len(n))
  )
}

kinds <- c(
  "int",
  "int_wide",
  "dbl",
  "dbl_wide",
  "lgl",
  "fct",
  "date",
  "posix",
  "sorted",
  "reversed"
)

