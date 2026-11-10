#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
: "${AUTOPRODUCTIVE_SIGN_IDENTITY:?Set AUTOPRODUCTIVE_SIGN_IDENTITY to the app signing identity}"
TEST_DIR=$(mktemp -d /tmp/autoproductive-audio-component-test.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT
sh "$ROOT/scripts/build-audio-mixer-tool.sh" "$TEST_DIR/audioMixer.dylib"
xcrun swiftc -parse-as-library -module-cache-path "$TEST_DIR/cache" \
  "$ROOT/AutoProductive/Services/AudioVolumeEngine.swift" \
  "$ROOT/AutoProductive/Services/FeatureToolLibrary.swift" \
  "$ROOT/AutoProductive/Services/FeatureAudioMixerLibrary.swift" \
  "$ROOT/Tests/AudioMixerComponent/main.swift" -o "$TEST_DIR/tests"
codesign --force --sign "$AUTOPRODUCTIVE_SIGN_IDENTITY" --options runtime "$TEST_DIR/tests" >/dev/null 2>&1
"$TEST_DIR/tests" "$TEST_DIR/audioMixer.dylib"
