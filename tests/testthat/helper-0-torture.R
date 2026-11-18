# Named to load before helper-sort.R, which reads under_torture().
# The gctorture caller sets ZUTABLE_GCTORTURE=true for its step-20 runs
# (.github/workflows/gctorture.yaml), where the whole suite no longer fits
# in the job's time. Tests that repeat pure-R work, or one native path at
# many sizes, do less there; every other workflow runs them in full.
under_torture <- function() identical(Sys.getenv("ZUTABLE_GCTORTURE"), "true")

skip_under_torture <- function() {
  if (under_torture()) {
    testthat::skip("million-row input under gctorture at step 20")
  }
}
