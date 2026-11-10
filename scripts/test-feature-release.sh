#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
: "${AUTOPRODUCTIVE_SIGN_IDENTITY:?Set AUTOPRODUCTIVE_SIGN_IDENTITY to the app signing identity}"
[ "$#" -ge 2 ] && [ "$#" -le 3 ] || { printf 'Usage: %s RELEASE_DIRECTORY VERSION [ARCHITECTURE]\n' "$0" >&2; exit 2; }
RELEASE=$1
TEST_DIR=$(mktemp -d /tmp/autoproductive-release-audit.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT
PACKAGE_DIR="$RELEASE/packages/$2${3:+/$3}"
for PACKAGE in "$PACKAGE_DIR"/*.package; do
  [ -f "$PACKAGE" ] || { printf 'No release packages found.\n' >&2; exit 1; }
  if [ "$#" -eq 3 ]; then
    [ "$(lipo -archs "$PACKAGE")" = "$3" ]
  else
    xcrun lipo "$PACKAGE" -verify_arch arm64
    xcrun lipo "$PACKAGE" -verify_arch x86_64
  fi
  codesign --verify --strict "$PACKAGE"
done
xcrun swiftc -parse-as-library -module-cache-path "$TEST_DIR/cache" \
  "$ROOT/AutoProductive/Models/FeatureComponentSupport.swift" \
  "$ROOT/AutoProductive/Models/FeaturePackageManifest.swift" \
  "$ROOT/AutoProductive/Services/FeaturePackageStore.swift" \
  "$ROOT/AutoProductive/Services/FeatureComponentRunner.swift" \
  "$ROOT/AutoProductive/Services/FeatureToolLibrary.swift" \
  "$ROOT/AutoProductive/Services/FeatureToolValidation.swift" \
  "$ROOT/Tests/FeatureReleaseAudit/main.swift" -o "$TEST_DIR/tests"
codesign --force --sign "$AUTOPRODUCTIVE_SIGN_IDENTITY" --options runtime "$TEST_DIR/tests" >/dev/null 2>&1
"$TEST_DIR/tests" "$RELEASE" "$ROOT/AutoProductive/Info.plist" "$2" ${3:+"$3"}
