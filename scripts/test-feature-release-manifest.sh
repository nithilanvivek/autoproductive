#!/bin/sh
set -eu
umask 077
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_DIR=$(mktemp -d /tmp/autoproductive-release-manifest-test.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT
export AUTOPRODUCTIVE_TEST_KEY_PATH="$TEST_DIR/test-key"
xcrun swiftc -parse-as-library -module-cache-path "$TEST_DIR/cache" \
  "$ROOT/Tests/FeatureManifestTool/fake-signer.swift" -o "$TEST_DIR/signer"
xcrun swiftc -parse-as-library -module-cache-path "$TEST_DIR/cache" \
  "$ROOT/AutoProductive/Models/FeatureComponentSupport.swift" \
  "$ROOT/Tests/FeatureManifestTool/setup.swift" -o "$TEST_DIR/setup"
xcrun swiftc -parse-as-library -module-cache-path "$TEST_DIR/cache" \
  "$ROOT/AutoProductive/Models/FeatureComponentSupport.swift" \
  "$ROOT/AutoProductive/Models/FeaturePackageManifest.swift" \
  "$ROOT/ReleaseTools/FeatureManifest/main.swift" -o "$TEST_DIR/manifest-tool"
PUBLIC_KEY=$("$TEST_DIR/signer" --make-key)
"$TEST_DIR/setup" "$TEST_DIR/packages"
"$TEST_DIR/manifest-tool" 1.1 arm64 "$TEST_DIR/packages" "$TEST_DIR/features.json" "$TEST_DIR/signer" "$PUBLIC_KEY"
if "$TEST_DIR/manifest-tool" 1.1 arm64 "$TEST_DIR/packages" "$TEST_DIR/features.json" "$TEST_DIR/signer" "$PUBLIC_KEY" >/dev/null 2>&1; then
  printf 'Existing manifests must not be overwritten.\n' >&2; exit 1
fi
if "$TEST_DIR/manifest-tool" .. arm64 "$TEST_DIR/packages" "$TEST_DIR/unsafe.json" "$TEST_DIR/signer" "$PUBLIC_KEY" >/dev/null 2>&1; then
  printf 'Unsafe versions must be rejected.\n' >&2; exit 1
fi
rm "$TEST_DIR/packages/tool.audioMixer.package"
if "$TEST_DIR/manifest-tool" 1.1 arm64 "$TEST_DIR/packages" "$TEST_DIR/missing.json" "$TEST_DIR/signer" "$PUBLIC_KEY" >/dev/null 2>&1; then
  printf 'Incomplete packages must be rejected.\n' >&2; exit 1
fi
printf 'Passed signed release-catalogue creation, immutability and completeness checks.\n'
