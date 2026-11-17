# pre-install for the R-devel Linux legs (r-actions README, "pre-install"):
# duckdb, in Suggests as the vocabulary's oracle (design section 14), has no
# R-devel binary on CRAN and takes about 45 minutes to build from source.
# cran.r-universe.dev builds Linux binaries of CRAN's releases for R-devel;
# install it from there first, and the dependency install leaves it alone.
if (R.version$status != "Under development (unstable)" ||
    Sys.info()[["sysname"]] != "Linux") quit(save = "no")
os <- readLines("/etc/os-release")
codename <- sub(".*=", "", grep("^VERSION_CODENAME=", os, value = TRUE))
if (!length(codename) || !nzchar(codename)) quit(save = "no")
rv <- paste(R.version$major, sub("[.].*", "", R.version$minor), sep = ".")
repo <- sprintf("https://cran.r-universe.dev/bin/linux/%s-%s/%s/",
                codename, R.version$arch, rv)
install.packages("duckdb", repos = repo)
