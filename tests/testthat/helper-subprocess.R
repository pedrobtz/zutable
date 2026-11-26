# Runs `lines` as a script at top level in a fresh Rscript, with zutable
# loaded as this session has it (load_all() of the source, or the
# installed copy), and returns its output lines (stdout and stderr).
# `env` is passed to system2() ("NAME=value"), e.g. a locale.
run_script <- function(lines, env = character()) {
  path <- getNamespaceInfo("zutable", "path")
  load <- if (file.exists(file.path(path, "R", "zutable.R"))) {
    sprintf("invisible(suppressMessages(pkgload::load_all(%s, quiet = TRUE)))", deparse(path))
  } else {
    sprintf("suppressMessages(library(zutable, lib.loc = %s))", deparse(dirname(path)))
  }
  script <- withr::local_tempfile(fileext = ".R")
  writeLines(c(load, lines), script, useBytes = TRUE)
  out <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"),
                                  c("--vanilla", shQuote(script)), stdout = TRUE,
                                  stderr = TRUE, env = env))
  out
}
