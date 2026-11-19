#!/bin/sh
# Builds and runs the kernel's C tests without R (tests/c/*.c), with the
# compiler in CC and extra flags in CFLAGS_EXTRA (for sanitizers); then
# the fuzz target's invariants over random inputs (tools/fuzz/harness.c);
# the ported sorts against their C++ originals (tests/c/ports), with the
# C++ compiler in CXX, unless PORTS=0.
set -eu
cc=${CC:-cc}
cxx=${CXX:-c++}
out=${OUT:-build/c-tests}
zinc="-I$(sh tools/ci/zufast-include.sh)"
mkdir -p "$out"
for t in tests/c/test-*.c; do
  name=$(basename "$t" .c)
  $cc -std=c11 -O1 -g -Wall -Wextra -pedantic -Werror ${CFLAGS_EXTRA:-} \
    -Iinst/include $zinc "$t" -o "$out/$name" -lm
  "$out/$name"
done
# The reductions again with double accumulators, as an R without long
# double has them (src/reduce-double.c).
$cc -std=c11 -O1 -g -Wall -Wextra -pedantic -Werror ${CFLAGS_EXTRA:-} -DZT_PRECISION=0 \
  -Iinst/include $zinc tests/c/test-reduce.c -o "$out/test-reduce-double" -lm
"$out/test-reduce-double"
$cc -std=c11 -O1 -g -Wall -Wextra -pedantic -Werror ${CFLAGS_EXTRA:-} -DZT_FUZZ_MAIN \
  -Iinst/include $zinc tools/fuzz/harness.c tools/fuzz/invariants.c -o "$out/fuzz-smoke" -lm
"$out/fuzz-smoke"
if [ "${PORTS:-1}" != 0 ]; then
  orig=$(sh tools/ci/fetch-originals.sh)
  # The originals are not ours to hold to -Werror.
  $cxx -std=c++17 -O1 -g ${CFLAGS_EXTRA:-} -DZT_STANDALONE -Iinst/include -I"$orig" $zinc \
    tests/c/ports/test-ports.cpp -o "$out/test-ports"
  "$out/test-ports"
fi
