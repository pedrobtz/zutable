# Pretend a sibling package is installed or absent, whatever the library
# holds: zt_has_package() is the one place the types ask.
local_packages <- function(present, frame = parent.frame()) {
  local_mocked_bindings(
    zt_has_package = function(pkg) pkg %in% present,
    .env = frame
  )
}

# A zu_int64 vector built by hand in bit64's layout, so the int64 type
# can be tested without zuint installed.
zu_int64_of <- function(x) {
  bits <- writeBin(as.integer(x), raw(), size = 4L, endian = "little")
  out <- double(length(x))
  for (i in seq_along(x)) {
    lo <- bits[(4L * i - 3L):(4L * i)]
    hi <- if (x[[i]] < 0) as.raw(rep(0xff, 4L)) else as.raw(rep(0, 4L))
    out[[i]] <- readBin(c(lo, hi), "double", size = 8L, endian = "little")
  }
  structure(out, class = c("zu_int64", "integer64"))
}
