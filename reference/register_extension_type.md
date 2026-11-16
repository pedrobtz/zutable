# Register an R vector class as an extension type

A package whose vector class has an Arrow extension name, such as a
geometry class, registers it so that `zutable` types its columns as that
extension rather than as an opaque `r_class()`. Call it from the
package's `.onLoad()`.

## Usage

``` r
register_extension_type(name, ptype, storage)
```

## Arguments

- name:

  The extension name, for example `"geoarrow.wkb"`.

- ptype:

  A zero-length vector of the class. Its first class names the class,
  and `ptype[NA_integer_]` is the type's missing value.

- storage:

  The storage type, as in
  [`schema()`](https://pedrobtz.github.io/zutable/reference/schema.md),
  for example `binary`.

## Value

The extension type, invisibly.

## Examples

``` r
register_extension_type("example.celsius", structure(double(), class = "celsius"), float64)
schema(t = extension("example.celsius"))
#> <zutable_schema> 1 field
#>   t extension("example.celsius")
```
