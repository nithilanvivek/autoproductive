#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
: "${AUTOPRODUCTIVE_SIGN_IDENTITY:?Set AUTOPRODUCTIVE_SIGN_IDENTITY to the app signing identity}"
TEST_DIR=$(mktemp -d /tmp/autoproductive-tool-installation.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT
sh "$ROOT/scripts/build-finder-cut-tool.sh" "$TEST_DIR/finderCut.dylib"
sh "$ROOT/scripts/build-file-bucket-storage.sh" "$TEST_DIR/fileBucket.dylib"
sh "$ROOT/scripts/build-keep-awake-assertions.sh" "$TEST_DIR/keepAwake.dylib"
sh "$ROOT/scripts/build-audio-mixer-tool.sh" "$TEST_DIR/audioMixer.dylib"
sh "$ROOT/scripts/build-dock-preview-tool.sh" "$TEST_DIR/dockPreviews.dylib"
xcrun swiftc -parse-as-library -module-cache-path "$TEST_DIR/cache" \
  "$ROOT/AutoProductive/Models/FeaturePackageManifest.swift" \
  "$ROOT/AutoProductive/Models/FeatureSelectionState.swift" \
  "$ROOT/AutoProductive/Models/FeatureComponentSupport.swift" \
  "$ROOT/AutoProductive/Services/FeaturePackageStore.swift" \
  "$ROOT/AutoProductive/Services/FeaturePackageDownloader.swift" \
  "$ROOT/AutoProductive/Services/FeaturePackageRepository.swift" \
  "$ROOT/AutoProductive/Services/FeaturePackageGenerations.swift" \
  "$ROOT/AutoProductive/Services/FeatureComponentRunner.swift" \
  "$ROOT/AutoProductive/Services/FeatureToolLibrary.swift" \
  "$ROOT/AutoProductive/Services/FeatureToolValidation.swift" \
  "$ROOT/AutoProductive/Services/FeatureInstallationCoordinator.swift" \
  "$ROOT/Tests/ToolInstallation/main.swift" -o "$TEST_DIR/tests"
codesign --force --sign "$AUTOPRODUCTIVE_SIGN_IDENTITY" --options runtime "$TEST_DIR/tests" >/dev/null 2>&1
"$TEST_DIR/tests" "$TEST_DIR/finderCut.dylib" "$TEST_DIR/fileBucket.dylib" "$TEST_DIR/keepAwake.dylib" "$TEST_DIR/audioMixer.dylib" "$TEST_DIR/dockPreviews.dylib"
