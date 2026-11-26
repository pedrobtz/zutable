# Helpers of test-metadata.R, kept here so that test_check(shuffle = TRUE)
# defines them before any test runs.

meta_table <- function() {
  s <- schema(id = not_null(int32), px = field(float64, metadata = c(unit = "USD")),
              g = field(string, metadata = c(role = "group")), .metadata = c(src = "x"))
  as_zutable(data.frame(id = 1:3, px = c(1, 2, 3), g = c("a", "b", "a")), s)
}

field_meta <- function(x, name) schema(x)$fields[[name]]$metadata
