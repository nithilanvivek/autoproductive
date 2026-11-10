#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
: "${AUTOPRODUCTIVE_SIGN_IDENTITY:?Set AUTOPRODUCTIVE_SIGN_IDENTITY to the app signing identity}"
[ "$#" -eq 1 ] || { printf 'Usage: %s OUTPUT_PATH\n' "$0" >&2; exit 2; }
OUTPUT=$1
BUILD_DIR=$(mktemp -d /tmp/autoproductive-finder-cut.XXXXXX)
trap 'rm -rf "$BUILD_DIR"' EXIT
xcrun clang -O2 -dynamiclib -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 \
  "$ROOT/Components/FinderCut/finder_cut.c" -o "$BUILD_DIR/finderCut.dylib"
codesign --force --sign "$AUTOPRODUCTIVE_SIGN_IDENTITY" "$BUILD_DIR/finderCut.dylib" >/dev/null 2>&1
mkdir -p "$(dirname -- "$OUTPUT")"
cp "$BUILD_DIR/finderCut.dylib" "$OUTPUT"
printf 'Built signed universal Finder Command-X tool: %s\n' "$OUTPUT"
