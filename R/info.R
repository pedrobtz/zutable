#' Information about the zutable build
#'
#' Reports the package version. Later versions add the version of the
#' `zufast` headers the kernel was built against and its build flags.
#'
#' @return A named list with element `version`, a [package_version].
#' @export
#' @examples
#' zutable_info()
zutable_info <- function() {
  list(version = utils::packageVersion("zutable"))
}
