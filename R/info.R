#' Information about the zutable build
#'
#' Reports the package version, the version of the kernel header the
#' shared object was built with, and the version of the `zufast` headers it
#' was compiled against.
#'
#' @return A named list: `version`, a [package_version]; `header` and
#'   `zufast`, version strings.
#' @export
#' @examples
#' zutable_info()
zutable_info <- function() {
  native <- .Call(zt_info)
  list(version = utils::packageVersion("zutable"), header = native$header,
       zufast = native$zufast)
}
