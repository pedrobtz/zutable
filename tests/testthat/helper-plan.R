# Helpers of test-plan.R, kept here so that test_check(shuffle = TRUE)
# defines them before any test runs.

# The R vector each logical type is held in, by base R's predicates: an
# oracle apart from vector_problem() (#72).
base_type_is <- function(v, id) {
  plain_class <- is.null(oldClass(v))
  switch(id,
    int32 = is.integer(v) && plain_class,
    float64 = is.double(v) && plain_class,
    bool = is.logical(v) && plain_class,
    string = is.character(v) && plain_class,
    date = is.double(v) && identical(oldClass(v), "Date"),
    stop("no base reading for ", id)
  )
}
