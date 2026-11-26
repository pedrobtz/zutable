# Information about the zutable build

Reports the package version, the version of the kernel header the shared
object was built with, and the version of the `zufast` headers it was
compiled against.

## Usage

``` r
zutable_info()
```

## Value

A named list: `version`, a
[package_version](https://rdrr.io/r/base/numeric_version.html); `header`
and `zufast`, version strings.

## Examples

``` r
zutable_info()
#> $version
#> [1] ‘0.1.0’
#> 
#> $header
#> [1] "0.1.0"
#> 
#> $zufast
#> [1] "0.1.0"
#> 
```
