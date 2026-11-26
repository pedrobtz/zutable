# Helpers of test-cast.R, kept here so that test_check(shuffle = TRUE)
# defines them before any test runs.

# The nearest whole microsecond of each double, from its exact decimal
# expansion (a double's expansion is finite and %.60f prints all of it), so
# no floating-point product decides the rounding. No double lies exactly
# halfway between two microseconds.
us_oracle <- function(x) {
  vapply(x, function(v) {
    s <- sprintf("%.60f", abs(v))
    whole <- as.double(sub("\\..*$", "", s))
    frac <- sub("^[^.]*\\.", "", s)
    us <- as.double(substr(frac, 1L, 6L)) + (substr(frac, 7L, 7L) >= "5")
    sign(v) * (whole * 1e6 + us)
  }, 0)
}

us_text <- function(us) {
  sec <- floor(us / 1e6)
  micro <- us - sec * 1e6
  frac <- ifelse(micro == 0, "", sub("0+$", "", sprintf(".%06d", as.integer(micro))))
  paste0(format(.POSIXct(sec, "UTC"), "%Y-%m-%d %H:%M:%S", tz = "UTC"), frac)
}
