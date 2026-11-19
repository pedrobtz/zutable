#!/bin/sh
# Builds the kernel's C tests with Mull for mutation.yaml: each file compiled
# in a command of its own with $MULL_CC (Mull re-parses every file from its
# recorded command line), then linked. The kernel is header-only, so the
# mutants are in inst/include, reached through the tests.
set -eu
out=build/mutation
mkdir -p "$out"
cc=${MULL_CC:?MULL_CC is set by the r-actions mutation workflow}
zinc="-I$(sh tools/ci/zufast-include.sh)"
for t in tests/c/test-*.c; do
  name=$(basename "$t" .c)
  $cc -std=c11 -g -DZT_TEST_QUICK -Iinst/include $zinc -c "$t" -o "$out/$name.o"
  $cc "$out/$name.o" -o "$out/$name" -lm
done
# The fuzz target's driver (tools/fuzz), on fewer random inputs: its oracle
# compares every kind of key, NA and NaN with an equality of its own, which
# the unit tests above do for some kinds only.
for f in harness invariants; do
  $cc -std=c11 -g -DZT_FUZZ_MAIN -DZT_FUZZ_RUNS=3000 -Iinst/include $zinc \
    -c "tools/fuzz/$f.c" -o "$out/fuzz-$f.o"
done
$cc "$out/fuzz-harness.o" "$out/fuzz-invariants.o" -o "$out/fuzz-smoke" -lm
