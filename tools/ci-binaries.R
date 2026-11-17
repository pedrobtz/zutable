# pre-install for the R-devel Linux legs (r-actions README, "pre-install"):
# duckdb, in Suggests as the vocabulary's oracle (design section 14), has no
# R-devel binary on CRAN and takes about 45 minutes to build from source.
# cran.r-universe.dev builds Linux binaries of CRAN's releases. Install the
# binary for this R if r-universe has one, else the one built for the
# previous R minor, which R-devel loads in practice; if it ever does not,
# requireNamespace() fails and the DuckDB oracle tests skip on that leg
# (they run on every R-release leg). Never build duckdb from source here.
# 2026-11-17: r-universe serves only the source tarball under bin/linux for
# duckdb, so this finds nothing and the dependency install builds it; the
# sanitizers caller allows 90 minutes for that cold build.
if (R.version$status != "Under development (unstable)" ||
    Sys.info()[["sysname"]] != "Linux") quit(save = "no")
os <- readLines("/etc/os-release")
codename <- sub(".*=", "", grep("^VERSION_CODENAME=", os, value = TRUE))
if (!length(codename) || !nzchar(codename)) quit(save = "no")
major <- as.integer(R.version$major)
minor <- as.integer(sub("[.].*", "", R.version$minor))
for (m in c(minor, minor - 1L)) {
  repo <- sprintf("https://cran.r-universe.dev/bin/linux/%s-%s/%d.%d/",
                  codename, R.version$arch, major, m)
  ap <- tryCatch(utils::available.packages(repos = repo, fields = "Built"),
                 error = function(e) NULL)
  if (is.null(ap) || !"duckdb" %in% rownames(ap)) next
  built <- ap["duckdb", "Built"]
  if (is.na(built) || !startsWith(built, "R ")) next
  cat("duckdb binary from", repo, "(built", built, ")\n")
  utils::install.packages("duckdb", repos = repo)
  quit(save = "no")
}
cat("no duckdb binary for this R; leaving it to the dependency install\n")
