# Information about the zutable build

Reports the package version. Later versions add the version of the
`zufast` headers the kernel was built against and its build flags.

## Usage

``` r
zutable_info()
```

## Value

A named list with element `version`, a
[package_version](https://rdrr.io/r/base/numeric_version.html).

## Examples

``` r
zutable_info()
#> $version
#> [1] ‘0.0.0.9000’
#> 
```
