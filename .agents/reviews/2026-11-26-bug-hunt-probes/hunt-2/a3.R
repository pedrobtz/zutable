source("pre.R")
print(body(order)); 
y <- sort(c(3, NA, 1), na.last = TRUE, method = "radix"); print(order(y, na.last = NA)); print(order(y, na.last = NA, method="radix"))
w <- key_sort(c(3, NA, 1)); print(order(w, na.last = NA)); print(order(w, na.last = NA, method = "radix"));print(order(w, na.last = NA, method = "shell"))
print(sort.int(w, index.return = TRUE)); print(sort(w, method = "radix")); print(sort(w, method = "quick"))
