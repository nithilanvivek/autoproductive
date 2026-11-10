#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_DIR=$(mktemp -d /tmp/autoproductive-dispatcher.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -module-cache-path "$TEST_DIR/cache" \
  "$ROOT/AutoProductive/Models/ClipboardTransform.swift" \
  "$ROOT/Components/ClipboardTransform/main.swift" -o "$TEST_DIR/clipboard"
xcrun swiftc -module-cache-path "$TEST_DIR/cache" \
  "$ROOT/Components/Wait/main.swift" -o "$TEST_DIR/wait"
xcrun swiftc -module-cache-path "$TEST_DIR/cache" \
  "$ROOT/Components/ReadFile/main.swift" -o "$TEST_DIR/read-file"
xcrun swiftc -module-cache-path "$TEST_DIR/cache" \
  "$ROOT/Components/SetClipboard/main.swift" -o "$TEST_DIR/set-clipboard"
for ACTION in WRITE APPEND CREATE_FOLDER COPY MOVE TRASH; do
  xcrun swiftc -D "ACTION_$ACTION" -module-cache-path "$TEST_DIR/cache" \
    "$ROOT/Components/FileMutation/main.swift" -o "$TEST_DIR/$ACTION"
done
for ACTION in SOUND BRIGHTNESS; do
  xcrun swiftc -D "ACTION_$ACTION" -module-cache-path "$TEST_DIR/cache" \
    "$ROOT/Components/SystemControl/main.swift" -o "$TEST_DIR/$ACTION"
done
for ACTION in PRESS_KEY PASTE TYPE_TEXT CLICK MOVE_POINTER SCROLL; do
  xcrun swiftc -D "ACTION_$ACTION" -module-cache-path "$TEST_DIR/cache" \
    "$ROOT/AutoProductive/Models/FeatureInputPlan.swift" \
    "$ROOT/Components/InputEvents/main.swift" -o "$TEST_DIR/$ACTION"
done
for ACTION in OPEN_URL OPEN_APP COMPOSE_MAIL; do
  xcrun swiftc -D "ACTION_$ACTION" -module-cache-path "$TEST_DIR/cache" \
    "$ROOT/Components/OpenTarget/main.swift" -o "$TEST_DIR/$ACTION"
done
for ACTION in SCREEN_PIXEL SCREEN_IMAGE; do
  xcrun swiftc -D "ACTION_$ACTION" -module-cache-path "$TEST_DIR/cache" \
    "$ROOT/Components/ScreenWait/main.swift" -o "$TEST_DIR/$ACTION"
done
for ACTION in SHELL APPLESCRIPT; do
  xcrun swiftc -D "ACTION_$ACTION" -module-cache-path "$TEST_DIR/cache" \
    "$ROOT/Components/ScriptPlan/main.swift" -o "$TEST_DIR/$ACTION"
done
for ACTION in PROMPT CHOOSE MESSAGE; do
  xcrun swiftc -D "ACTION_$ACTION" -module-cache-path "$TEST_DIR/cache" \
    "$ROOT/Components/DialogPlan/main.swift" -o "$TEST_DIR/$ACTION"
done
xcrun swiftc -module-cache-path "$TEST_DIR/cache" \
  "$ROOT/Components/WindowPlan/main.swift" -o "$TEST_DIR/window"
HOST_DEFINE=
if [ "${AUTOPRODUCTIVE_TEST_MODULAR:-0}" = 1 ]; then HOST_DEFINE=-DMODULAR_FEATURES; fi
xcrun swiftc -parse-as-library ${HOST_DEFINE:+"$HOST_DEFINE"} -module-cache-path "$TEST_DIR/cache" \
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
  "$ROOT/AutoProductive/Services/FeatureToolLibrary.swift" \
  "$ROOT/AutoProductive/Services/FeatureInstallationCoordinator.swift" \
  "$ROOT/AutoProductive/Services/FeatureToolValidation.swift" \
  "$ROOT/AutoProductive/Services/FeatureInstallationSession.swift" \
  "$ROOT/AutoProductive/Services/FeatureComponentDispatcher.swift" \
  "$ROOT/Tests/FeatureDispatcher/main.swift" -o "$TEST_DIR/tests"
codesign --force --sign - --options runtime "$TEST_DIR/tests" >/dev/null 2>&1
"$TEST_DIR/tests" "$TEST_DIR/clipboard" "$TEST_DIR/wait" "$TEST_DIR/read-file" \
  "$TEST_DIR/WRITE" "$TEST_DIR/APPEND" "$TEST_DIR/CREATE_FOLDER" \
  "$TEST_DIR/COPY" "$TEST_DIR/MOVE" "$TEST_DIR/TRASH" "$TEST_DIR/SOUND" "$TEST_DIR/BRIGHTNESS" "$TEST_DIR/set-clipboard" \
  "$TEST_DIR/PRESS_KEY" "$TEST_DIR/PASTE" "$TEST_DIR/TYPE_TEXT" "$TEST_DIR/CLICK" "$TEST_DIR/MOVE_POINTER" "$TEST_DIR/SCROLL" \
  "$TEST_DIR/OPEN_URL" "$TEST_DIR/OPEN_APP" "$TEST_DIR/COMPOSE_MAIL" "$TEST_DIR/SCREEN_PIXEL" "$TEST_DIR/SCREEN_IMAGE" \
  "$TEST_DIR/SHELL" "$TEST_DIR/APPLESCRIPT" "$TEST_DIR/PROMPT" "$TEST_DIR/CHOOSE" "$TEST_DIR/MESSAGE" "$TEST_DIR/window"
