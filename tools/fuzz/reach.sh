#!/bin/sh
# The fuzz corpus's reach over the kernel's headers (#73): fuzz.yml's own
# reach report covers its `sources` only, the harness's invariants.c, while
# the code under test is inst/include/zutable/*.h and *.inc. This builds the
# standalone driver (harness.c with ZT_FUZZ_MAIN) for clang's source-based
# coverage, replays tools/fuzz/corpus once, and fails when the headers'
# lines reached fall below REACH_FLOOR percent. Needs clang, llvm-profdata
# and llvm-cov (xcrun's on macOS); platform.sh runs it on macOS.
set -eu
floor=${REACH_FLOOR:-70}
out=${OUT:-build/fuzz-reach}
cc=${REACH_CC:-clang}
if [ "$(uname)" = Darwin ]; then
  profdata="xcrun llvm-profdata"
  cov="xcrun llvm-cov"
else
  profdata=llvm-profdata
  cov=llvm-cov
fi
zinc="-I$(sh tools/ci/zufast-include.sh)"
mkdir -p "$out"
$cc -std=c11 -O1 -g -DZT_FUZZ_MAIN -fprofile-instr-generate -fcoverage-mapping \
  -Iinst/include $zinc tools/fuzz/harness.c tools/fuzz/invariants.c -o "$out/reach" -lm
rm -f "$out/reach.profraw"
LLVM_PROFILE_FILE="$out/reach.profraw" "$out/reach" tools/fuzz/corpus/*
$profdata merge -sparse "$out/reach.profraw" -o "$out/reach.profdata"
$cov export "$out/reach" -instr-profile="$out/reach.profdata" -format=lcov \
  inst/include/zutable/*.h inst/include/zutable/*.inc > "$out/reach.lcov"
awk -F'[:,]' -v floor="$floor" '
  /^SF:/ { f = $2; sub(".*/inst/include/", "", f) }
  /^DA:/ { k = f ":" $2; if (!(k in seen)) { seen[k] = 1; n[f]++; total++ }
           if ($3 > 0 && !(k in hit)) { hit[k] = 1; h[f]++; reached++ } }
  END {
    for (f in n) printf "%-32s %5d of %5d lines\n", f, h[f], n[f]
    pct = total ? 100 * reached / total : 0
    printf "fuzz reach over the headers: %.1f%% of %d lines (floor %s%%)\n", pct, total, floor
    if (pct < floor) { print "fuzz reach below its floor"; exit 1 }
  }' "$out/reach.lcov"
