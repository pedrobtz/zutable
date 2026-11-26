.libPaths(c("/tmp/zutable-hunt/lib", .libPaths()))
library(zutable)
chk <- function(label, ok) cat(if (isTRUE(ok)) "ok  " else "FAIL", label, "\n")
try_ <- function(expr) tryCatch({expr; "no error"}, error = function(e) paste(class(e)[1], conditionMessage(e)))
