#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
: "${AUTOPRODUCTIVE_SIGN_IDENTITY:?Set AUTOPRODUCTIVE_SIGN_IDENTITY to the app signing identity}"
[ "$#" -eq 1 ] || { printf 'Usage: %s OUTPUT_PATH\n' "$0" >&2; exit 2; }
OUTPUT=$1
BUILD_DIR=$(mktemp -d /tmp/autoproductive-bucket-build.XXXXXX)
trap 'rm -rf "$BUILD_DIR"' EXIT
SDK=$(xcrun --sdk macosx --show-sdk-path)
for ARCH in arm64 x86_64; do
  xcrun swiftc -O -emit-library -sdk "$SDK" -target "$ARCH-apple-macos14.0" \
    -module-cache-path "$BUILD_DIR/cache-$ARCH" "$ROOT/Components/FileBucketStorage/main.swift" -o "$BUILD_DIR/$ARCH.dylib"
done
xcrun lipo -create "$BUILD_DIR/arm64.dylib" "$BUILD_DIR/x86_64.dylib" -output "$BUILD_DIR/fileBucket.dylib"
codesign --force --sign "$AUTOPRODUCTIVE_SIGN_IDENTITY" "$BUILD_DIR/fileBucket.dylib" >/dev/null 2>&1
mkdir -p "$(dirname -- "$OUTPUT")"
cp "$BUILD_DIR/fileBucket.dylib" "$OUTPUT"
printf 'Built signed universal File Bucket storage component: %s\n' "$OUTPUT"
