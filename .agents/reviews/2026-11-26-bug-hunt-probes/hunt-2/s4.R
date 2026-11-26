source("pre.R")
meta <- function(x) .Call(zutable:::zt_sorted_meta, x)
head_ <- "A\n3\n263682\n197888\n5\nUTF-8\n238\n2\n1\n262153\n13\nzt_sorted_int\n2\n1\n262153\n7\nzutable\n2\n13\n1\n13\n254\n"
cases <- list(
  ok = "19\n2\n13\n3\n1\n2\n3\n13\n2\n1\n1\n254\n",
  lie = "19\n2\n13\n3\n3\n1\n2\n13\n2\n1\n1\n254\n",
  lie_na = "19\n2\n13\n3\n1\nNA\n2\n13\n2\n1\n1\n254\n",
  badcode = "19\n2\n13\n3\n3\n1\n2\n13\n2\n7\n5\n254\n",
  meta_len1 = "19\n2\n13\n3\n1\n2\n3\n13\n1\n1\n254\n",
  meta_len0 = "19\n2\n13\n3\n1\n2\n3\n13\n0\n254\n",
  meta_real = "19\n2\n13\n3\n1\n2\n3\n14\n2\n1\n1\n254\n",
  meta_null = "19\n2\n13\n3\n1\n2\n3\n254\n254\n",
  payload_list = "19\n2\n19\n0\n13\n2\n1\n1\n254\n",
  payload_null = "19\n2\n254\n13\n2\n1\n1\n254\n",
  payload_real_in_int_class = "19\n2\n14\n3\n3\n1\n2\n13\n2\n1\n1\n254\n",
  state_len1 = "19\n1\n13\n3\n1\n2\n3\n254\n",
  state_len0 = "19\n0\n254\n",
  state_int = "13\n3\n1\n2\n3\n254\n",
  state_null = "254\n254\n"
)
which <- commandArgs(TRUE)[1]
u <- unserialize(charToRaw(paste0(head_, cases[[which]])))
cat(which, ": typeof", typeof(u), "len", length(u), "meta", paste(meta(u), collapse = ","), "\n")
print(u); cat("is.unsorted", is.unsorted(u), "anyNA", anyNA(u), "sort", sort(u), "order", order(u), "\n")
u[1] <- 9L; print(u); cat("meta after write", paste(meta(u), collapse=","), "\n")
