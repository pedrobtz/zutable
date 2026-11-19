# For tools/ci/consumer.sh: copy testthat and its dependencies, and nothing
# else, into the library at VIEW, so that the fixture's tests run over a
# library that cannot hold zutable. A file, not `Rscript -e`: on Windows only
# the first line of a multi-line -e argument reaches R.
ip <- installed.packages()
need <- unique(c("testthat", unlist(tools::package_dependencies(
  "testthat", db = ip, which = c("Depends", "Imports", "LinkingTo"), recursive = TRUE
))))
base <- rownames(ip)[ip[, "Priority"] %in% "base"]
need <- setdiff(intersect(need, rownames(ip)), c(base, "zutable"))
for (p in need) {
  file.copy(file.path(ip[p, "LibPath"], p), Sys.getenv("VIEW"), recursive = TRUE)
}
cat(sprintf("library view: %d packages for testthat\n", length(need)))
