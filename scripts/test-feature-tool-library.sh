#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
: "${AUTOPRODUCTIVE_SIGN_IDENTITY:?Set AUTOPRODUCTIVE_SIGN_IDENTITY to a development signing identity}"
TEST_DIR=$(mktemp -d /tmp/autoproductive-tool-library.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun clang -dynamiclib "$ROOT/Tests/FeatureToolLibrary/component.c" -o "$TEST_DIR/matching.dylib"
xcrun clang -dynamiclib "$ROOT/Tests/FeatureToolLibrary/component.c" -o "$TEST_DIR/unmatched.dylib"
codesign --force --sign "$AUTOPRODUCTIVE_SIGN_IDENTITY" "$TEST_DIR/matching.dylib" >/dev/null 2>&1
codesign --force --sign - "$TEST_DIR/unmatched.dylib" >/dev/null 2>&1
xcrun swiftc -parse-as-library -module-cache-path "$TEST_DIR/cache" \
  "$ROOT/AutoProductive/Models/FeaturePackageManifest.swift" \
  "$ROOT/AutoProductive/Services/FeaturePackageStore.swift" \
  "$ROOT/AutoProductive/Services/FeatureToolLibrary.swift" \
  "$ROOT/Tests/FeatureToolLibrary/main.swift" -o "$TEST_DIR/tests"
codesign --force --sign "$AUTOPRODUCTIVE_SIGN_IDENTITY" --options runtime "$TEST_DIR/tests" >/dev/null 2>&1
"$TEST_DIR/tests" "$TEST_DIR/matching.dylib" "$TEST_DIR/unmatched.dylib"
