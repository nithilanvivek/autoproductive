#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_DIR=$(mktemp -d /tmp/autoproductive-bucket-tests.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -parse-as-library -module-cache-path "$TEST_DIR/cache" \
  "$ROOT/AutoProductive/Models/FeatureComponentSupport.swift" \
  "$ROOT/AutoProductive/Models/FileBucketDropLayout.swift" \
  "$ROOT/AutoProductive/Models/ClipboardTransform.swift" \
  "$ROOT/AutoProductive/Models/FeaturePackageManifest.swift" \
  "$ROOT/AutoProductive/Models/FeatureSelectionState.swift" \
  "$ROOT/AutoProductive/Models/FeatureInputPlan.swift" \
  "$ROOT/AutoProductive/Models/ProblemReport.swift" \
  "$ROOT/AutoProductive/Models/ReportDiagnostics.swift" \
  "$ROOT/AutoProductive/Services/FileBucket.swift" \
  "$ROOT/AutoProductive/Services/FeaturePackageStore.swift" \
  "$ROOT/AutoProductive/Services/FeaturePackageDownloader.swift" \
  "$ROOT/AutoProductive/Services/FeaturePackageRepository.swift" \
  "$ROOT/AutoProductive/Services/FeaturePackageGenerations.swift" \
  "$ROOT/AutoProductive/Services/FeatureComponentRunner.swift" \
  "$ROOT/AutoProductive/Services/FeatureComponentDispatcher.swift" \
  "$ROOT/AutoProductive/Services/FeatureToolLibrary.swift" \
  "$ROOT/AutoProductive/Services/FeatureFileBucketStorage.swift" \
  "$ROOT/Tests/FileBucketTests.swift" -o "$TEST_DIR/tests" -framework AppKit -framework SwiftUI
if [ -n "${AUTOPRODUCTIVE_SIGN_IDENTITY:-}" ]; then
  codesign --force --sign "$AUTOPRODUCTIVE_SIGN_IDENTITY" --options runtime "$TEST_DIR/tests" >/dev/null 2>&1
fi
"$TEST_DIR/tests" "$@"
