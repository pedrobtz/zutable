#!/bin/sh
# Prints the directory holding zufast's C headers (zufast.h), for -I, with
# no need for R: $ZUFAST_INCLUDE if set; else the installed package's, when
# Rscript exists; else a shallow clone of zufast's release tag under build/
# (the mutation runner has no R). DESCRIPTION's LinkingTo names the version.
set -eu
if [ -n "${ZUFAST_INCLUDE:-}" ]; then
  printf '%s\n' "$ZUFAST_INCLUDE"
  exit 0
fi
if command -v Rscript >/dev/null 2>&1; then
  dir=$(Rscript -e 'cat(system.file("include", package = "zufast"))')
  if [ -n "$dir" ]; then
    printf '%s\n' "$dir"
    exit 0
  fi
fi
tag=$(sed -n 's/^ *zufast (>= *\([0-9.]*\)).*/\1/p' DESCRIPTION)
[ -n "$tag" ] || { echo "zufast-include: no zufast version in DESCRIPTION" >&2; exit 1; }
dest=build/zufast-$tag
if [ ! -f "$dest/inst/include/zufast.h" ]; then
  git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$tag" \
    https://github.com/pedrobtz/zufast.git "$dest" >&2
fi
printf '%s\n' "$PWD/$dest/inst/include"
