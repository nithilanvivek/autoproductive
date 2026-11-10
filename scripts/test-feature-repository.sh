#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_DIR=$(mktemp -d /tmp/autoproductive-repository.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -parse-as-library -module-cache-path "$TEST_DIR/cache" \
  "$ROOT/AutoProductive/Models/FeaturePackageManifest.swift" \
  "$ROOT/AutoProductive/Services/FeaturePackageStore.swift" \
  "$ROOT/AutoProductive/Services/FeaturePackageDownloader.swift" \
  "$ROOT/AutoProductive/Services/FeaturePackageRepository.swift" \
  "$ROOT/Tests/FeatureRepository/main.swift" -o "$TEST_DIR/tests"
"$TEST_DIR/tests"
