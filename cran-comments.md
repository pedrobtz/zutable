## Submission

This is the first submission of zutable. It provides typed tables: a data frame
that knows the name, Apache Arrow logical type and nullability of each
column. Tables are queried through the bracket, with SQL's clauses as named
arguments. A C kernel does the grouping, sorting, joining and reducing, and
other packages can use its header through `LinkingTo`.

The package has no `Imports`. Its one `LinkingTo` is zufast (on CRAN since
2026-11-16), and everything else is in `Suggests`.

## Ported code

Three sorting algorithms are ported to C from their C++ originals, each in
its own file under `inst/include/zutable/`:

* pdqsort (Orson Peters, zlib licence) in `pdqsort.inc`;
* Vergesort (Morwenn, MIT) in `vergesort.inc`;
* ska sort (Malte Skarupke, Boost Software License 1.0) in `skasort.inc`.

Each file keeps its original's notice and lists what was changed. The
authors are in `Authors@R` as `ctb` and `cph`, and `inst/COPYRIGHTS` records
the licences. No code is vendored as a file.

## Test environments

The pre-submission check is the R CMD check matrix of the
pedrobtz/r-actions `r-cmd-check.yml` workflow, run with `--as-cran`:

* GitHub Actions: macOS (R release), Windows (R release and R-devel),
  Ubuntu (R release and oldrel-1).
* CRAN-like containers on R-devel: GCC 16, clang 23, ubuntu-clang, and the
  noSuggests and noLD flavours.

Alongside it:

* On R-devel: ASan and UBSan, valgrind memcheck, LTO, rchk, the compilers'
  static analysers, and CRAN's rcnst, rlibro and vnu checks.
* The test suite under `gctorture2(step = 20)`, daily.
* Allocation-failure injection, in which each allocation after
  `library(zutable)` fails in turn.
* The kernel's C tests without R, and a fixture package built against the
  installed header, on macOS, Windows and Linux. The kernel also runs under
  a coverage-guided fuzzer.

## R CMD check results

0 errors | 0 warnings | 1 note

* This is a new submission.
