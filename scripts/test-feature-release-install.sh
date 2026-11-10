#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
: "${AUTOPRODUCTIVE_SIGN_IDENTITY:?Set AUTOPRODUCTIVE_SIGN_IDENTITY to the app signing identity}"
[ "$#" -ge 2 ] && [ "$#" -le 3 ] || { printf 'Usage: %s RELEASE_DIRECTORY VERSION [ARCHITECTURE]\n' "$0" >&2; exit 2; }
TEST_DIR=$(mktemp -d /tmp/autoproductive-release-install.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -parse-as-library -DMODULAR_FEATURES -module-cache-path "$TEST_DIR/cache" \
  "$ROOT/AutoProductive/Models/FeatureComponentSupport.swift" \
  "$ROOT/AutoProductive/Models/FeaturePackageManifest.swift" \
  "$ROOT/AutoProductive/Models/FeatureSelectionState.swift" \
  "$ROOT/AutoProductive/Models/FeatureInputPlan.swift" \
  "$ROOT/AutoProductive/Services/FeaturePackageStore.swift" \
  "$ROOT/AutoProductive/Services/FeaturePackageDownloader.swift" \
  "$ROOT/AutoProductive/Services/FeaturePackageRepository.swift" \
  "$ROOT/AutoProductive/Services/FeaturePackageGenerations.swift" \
  "$ROOT/AutoProductive/Services/FeatureComponentRunner.swift" \
  "$ROOT/AutoProductive/Services/FeatureComponentDispatcher.swift" \
  "$ROOT/AutoProductive/Services/FeatureToolLibrary.swift" \
  "$ROOT/AutoProductive/Services/FeatureToolValidation.swift" \
  "$ROOT/AutoProductive/Services/FeatureInstallationCoordinator.swift" \
  "$ROOT/AutoProductive/Services/FeatureInstallationSession.swift" \
  "$ROOT/Tests/FeatureReleaseInstall/main.swift" -o "$TEST_DIR/tests"
codesign --force --sign "$AUTOPRODUCTIVE_SIGN_IDENTITY" --options runtime "$TEST_DIR/tests" >/dev/null 2>&1
"$TEST_DIR/tests" "$1" "$2" "$ROOT/AutoProductive/Info.plist" ${3:+"$3"}
