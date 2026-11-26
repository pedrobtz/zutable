# fresh session, zutable not installed anywhere on the library path
print(tryCatch(find.package("zutable"), error = function(e) "zutable not found"))
w <- readRDS("w_int.rds"); print(w); print(length(w)); 
s <- readRDS("w_str.rds"); print(s)
f <- readRDS("w_fct.rds"); print(f)
t <- readRDS("tab.rds"); print(unclass(t)); 
