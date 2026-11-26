.libPaths(c("/tmp/zutable-hunt/lib", .libPaths()))
suppressMessages(library(zutable))
try_ <- function(expr) tryCatch(expr, error = function(e) cat("ERROR<", class(e)[1], ">:", conditionMessage(e), "\n"))
ref <- function(expr) { op <- options(zutable.executor = "reference"); on.exit(options(op)); expr }
both <- function(q, label = deparse(substitute(q))[1]) {
  q <- substitute(q); env <- parent.frame()
  a <- tryCatch(as.data.frame(eval(q, env)), error = function(e) paste("ERR", conditionMessage(e)))
  op <- options(zutable.executor = "reference")
  b <- tryCatch(as.data.frame(eval(q, env)), error = function(e) paste("ERR", conditionMessage(e)))
  options(op)
  if (!identical(a, b)) { cat("DIFF:", label, "\n"); print(a); print(b) } else cat("same:", label, "\n")
  invisible(a)
}
