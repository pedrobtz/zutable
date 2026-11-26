# fresh session, zutable NOT attached but installed on libPaths
.libPaths(c("/tmp/zutable-hunt/lib", .libPaths()))
w <- readRDS("w_int.rds"); print(w); print(is.unsorted(w)); print("zutable" %in% loadedNamespaces()); .Internal(inspect(w))
s <- readRDS("w_str.rds"); print(s); print(Encoding(s)); print(anyNA(s)); s[1] <- "q"; print(s)
f <- readRDS("w_fct.rds"); print(f); print(sort(f))
t <- readRDS("tab.rds"); print(class(t)); print(t$k)
