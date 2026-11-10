#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
: "${AUTOPRODUCTIVE_SIGN_IDENTITY:?Set AUTOPRODUCTIVE_SIGN_IDENTITY to the app signing identity}"
TEST_DIR=$(mktemp -d /tmp/autoproductive-finder-cut-test.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT
sh "$ROOT/scripts/build-finder-cut-tool.sh" "$TEST_DIR/finderCut.dylib"
cat > "$TEST_DIR/incomplete.c" <<'EOF'
#include <stdint.h>
int32_t autoproductive_tool_api_version(void) { return 1; }
const char *autoproductive_tool_feature_id(void) { return "tool.finderCut"; }
EOF
xcrun clang -dynamiclib "$TEST_DIR/incomplete.c" -o "$TEST_DIR/incomplete.dylib"
codesign --force --sign "$AUTOPRODUCTIVE_SIGN_IDENTITY" "$TEST_DIR/incomplete.dylib" >/dev/null 2>&1
cat "$ROOT/Components/FinderCut/finder_cut.c" > "$TEST_DIR/updated.c"
printf '\nvoid autoproductive_test_new_version(void) {}\n' >> "$TEST_DIR/updated.c"
xcrun clang -dynamiclib "$TEST_DIR/updated.c" -o "$TEST_DIR/updated.dylib"
codesign --force --sign "$AUTOPRODUCTIVE_SIGN_IDENTITY" "$TEST_DIR/updated.dylib" >/dev/null 2>&1
xcrun swiftc -parse-as-library -module-cache-path "$TEST_DIR/cache" \
  "$ROOT/AutoProductive/Models/ClipboardTransform.swift" \
  "$ROOT/AutoProductive/Models/FeaturePackageManifest.swift" \
  "$ROOT/AutoProductive/Models/FeatureSelectionState.swift" \
  "$ROOT/AutoProductive/Models/FeatureComponentSupport.swift" \
  "$ROOT/AutoProductive/Models/FeatureInputPlan.swift" \
  "$ROOT/AutoProductive/Services/FeaturePackageStore.swift" \
  "$ROOT/AutoProductive/Services/FeaturePackageDownloader.swift" \
  "$ROOT/AutoProductive/Services/FeaturePackageRepository.swift" \
  "$ROOT/AutoProductive/Services/FeaturePackageGenerations.swift" \
  "$ROOT/AutoProductive/Services/FeatureComponentRunner.swift" \
  "$ROOT/AutoProductive/Services/FeatureInstallationCoordinator.swift" \
  "$ROOT/AutoProductive/Services/FeatureToolValidation.swift" \
  "$ROOT/AutoProductive/Services/FeatureComponentDispatcher.swift" \
  "$ROOT/AutoProductive/Services/FeatureToolLibrary.swift" \
  "$ROOT/AutoProductive/Services/FeatureFinderCut.swift" \
  "$ROOT/Tests/FinderCutComponent/main.swift" -o "$TEST_DIR/tests"
codesign --force --sign "$AUTOPRODUCTIVE_SIGN_IDENTITY" --options runtime "$TEST_DIR/tests" >/dev/null 2>&1
"$TEST_DIR/tests" "$TEST_DIR/finderCut.dylib" "$TEST_DIR/incomplete.dylib" "$TEST_DIR/updated.dylib"
