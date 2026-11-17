#!/bin/sh
# Fetches the C++ originals of the kernel's ported sorts, at the commits
# the ports were made from, into build/originals/, checking each file's
# SHA-256. They are the oracle of tests/c/ports/test-ports.cpp and are
# never shipped (design-kernel 4.3).
set -eu
dest=build/originals
mkdir -p "$dest"
sha() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}
fetch() { # fetch <repo> <commit> <file> <sha256>
  out="$dest/$(basename "$3")"
  if [ ! -f "$out" ] || [ "$(sha "$out")" != "$4" ]; then
    curl -fsSL -o "$out" "https://raw.githubusercontent.com/$1/$2/$3"
  fi
  got=$(sha "$out")
  if [ "$got" != "$4" ]; then
    echo "fetch-originals: $1 $3 has SHA-256 $got, not $4" >&2
    exit 1
  fi
}
fetch orlp/pdqsort b1ef26a55cdb60d236a5cb199c4234c704f46726 pdqsort.h \
  1916aff237fc7ecc638dec6397662334552a1b6f823fa65011a8dfe831237fc0
fetch Morwenn/vergesort a1a5081f4989b0db443e81d0143a3507d16f8195 vergesort.h \
  44c3c4f9a6e59ab5851cc31eda77f052da85dcfb27d286825de934c55e35ebfa
fetch skarupke/ska_sort 2c14d4bf7b667032ed28a481065f721385e33849 ska_sort.hpp \
  440456435f9052998bd48fbc501870ce3975bcff400b906783768694f37264ca
echo "$dest"
