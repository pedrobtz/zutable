#!/bin/sh
# tools/ci/platform.sh: every per-OS check, in order, run once per runner by
# platforms.yaml as `sh tools/ci/platform.sh <os>` (r-actions platforms.yml);
# set -e names the one that failed.
set -eu
os=$1
cc=cc
cxx=c++
if [ "$os" = windows ]; then
  cc="$(R CMD config CC)"
  cxx="$(R CMD config CXX17)"
fi
# Every kernel header compiles alone, C11 and C++17, with and without R.
CC="$cc" CXX="$cxx" sh tools/check-headers
# The C tests build and pass without R headers.
CC="$cc" CXX="$cxx" sh tools/ci/c-tests.sh
# ... and under ASan and UBSan where the toolchain has them.
if [ "$os" = ubuntu ]; then
  CC="$cc" CXX="$cxx" CFLAGS_EXTRA="-fsanitize=address,undefined -fno-sanitize-recover=all" \
    OUT=build/c-tests-asan sh tools/ci/c-tests.sh
fi
# The fuzz corpus's reach over the kernel's headers, with Xcode's clang and
# llvm-cov (tools/fuzz/reach.sh, #73).
if [ "$os" = macos ]; then
  sh tools/fuzz/reach.sh
fi
# A sibling's package builds against the installed header with LinkingTo
# alone, and runs with zutable gone from the library.
sh tools/ci/consumer.sh
