#!/bin/sh
# Builds and runs the kernel's C tests without R (tests/c/*.c), with the
# compiler in CC and extra flags in CFLAGS_EXTRA (for sanitizers).
set -eu
cc=${CC:-cc}
out=${OUT:-build/c-tests}
zinc="-I$(sh tools/ci/zufast-include.sh)"
mkdir -p "$out"
for t in tests/c/test-*.c; do
  name=$(basename "$t" .c)
  $cc -std=c11 -O1 -g -Wall -Wextra -pedantic -Werror ${CFLAGS_EXTRA:-} \
    -Iinst/include $zinc "$t" -o "$out/$name" -lm
  "$out/$name"
done
