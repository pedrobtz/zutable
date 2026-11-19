# Named to load before helper-sort.R, which reads under_torture().
# The gctorture caller sets ZUTABLE_GCTORTURE=true for its step-20 runs
# (.github/workflows/gctorture.yaml), where the whole suite no longer fits
# in the job's time. Tests that repeat pure-R work, or one native path at
# many sizes, do less there; every other workflow runs them in full.
under_torture <- function() identical(Sys.getenv("ZUTABLE_GCTORTURE"), "true")

skip_under_torture <- function(why = "million-row input under gctorture at step 20") {
  if (under_torture()) testthat::skip(why)
}

# The DuckDB conformance tests check zutable's SQL, written in R, against
# DuckDB's results: at step 20 they torture the oracle, not native code.
skip_conformance_under_torture <- function() {
  skip_under_torture("DuckDB conformance under gctorture at step 20")
}
