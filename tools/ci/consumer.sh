#!/bin/sh
# The consumer fixture (design-kernel 8, R10.4): tools/zutabletest has
# LinkingTo: zutable and nothing else of it. It is installed from a copy
# under build/, with no -I of its own, so only the installed headers can
# satisfy its #include; then zutable is removed from the library, and the
# fixture's tests run without it, against base R, over a library holding
# only the fixture and testthat's dependencies (so that a zutable in the
# user or site library cannot satisfy them either). Run from the package
# root, by tools/ci/platform.sh on every OS: sh tools/ci/consumer.sh
set -eu
root=$(pwd -W 2>/dev/null || pwd)   # a Windows path under Rtools' shell
work="$root/build/consumer"
rm -rf "$work"
mkdir -p "$work/lib"
lib="$work/lib"
sep=:
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) sep=';' ;; esac
R_LIBS="$lib${R_LIBS:+$sep$R_LIBS}"
export R_LIBS
R CMD INSTALL --no-docs --no-multiarch -l "$lib" .
cp -R tools/zutabletest "$work/"
R CMD INSTALL --no-multiarch -l "$lib" "$work/zutabletest"
version=$(sed -n 's/^Version: *//p' DESCRIPTION)
rm -rf "$lib/zutable"
view="$work/view"
mkdir -p "$view" "$work/none"
VIEW="$view" Rscript "$root/tools/ci/consumer-view.R"
R_LIBS="$lib$sep$view"
R_LIBS_USER="$work/none"
R_LIBS_SITE="$work/none"
export R_LIBS R_LIBS_USER R_LIBS_SITE
cd "$work/zutabletest/tests/testthat"
ZUTABLETEST_ZUTABLE_ABSENT=true ZUTABLETEST_ZUTABLE_VERSION="$version" \
  Rscript "$root/tools/ci/consumer-run.R"
