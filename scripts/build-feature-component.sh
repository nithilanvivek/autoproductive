#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [ "$#" -ne 2 ]; then
  printf 'Usage: %s ACTION OUTPUT_PATH\n' "$0" >&2
  exit 2
fi
ACTION=$1
OUTPUT=$2
DEFINE=
case "$ACTION" in
  transformClipboard) MAIN="$ROOT/Components/ClipboardTransform/main.swift" ;;
  setClipboard) MAIN="$ROOT/Components/SetClipboard/main.swift" ;;
  wait) MAIN="$ROOT/Components/Wait/main.swift" ;;
  readFile) MAIN="$ROOT/Components/ReadFile/main.swift" ;;
  writeFile) MAIN="$ROOT/Components/FileMutation/main.swift"; DEFINE=ACTION_WRITE ;;
  appendFile) MAIN="$ROOT/Components/FileMutation/main.swift"; DEFINE=ACTION_APPEND ;;
  createFolder) MAIN="$ROOT/Components/FileMutation/main.swift"; DEFINE=ACTION_CREATE_FOLDER ;;
  copyFile) MAIN="$ROOT/Components/FileMutation/main.swift"; DEFINE=ACTION_COPY ;;
  moveFile) MAIN="$ROOT/Components/FileMutation/main.swift"; DEFINE=ACTION_MOVE ;;
  trashFile) MAIN="$ROOT/Components/FileMutation/main.swift"; DEFINE=ACTION_TRASH ;;
  adjustSound) MAIN="$ROOT/Components/SystemControl/main.swift"; DEFINE=ACTION_SOUND ;;
  adjustBrightness) MAIN="$ROOT/Components/SystemControl/main.swift"; DEFINE=ACTION_BRIGHTNESS ;;
  pressKey) MAIN="$ROOT/Components/InputEvents/main.swift"; DEFINE=ACTION_PRESS_KEY ;;
  pasteClipboard) MAIN="$ROOT/Components/InputEvents/main.swift"; DEFINE=ACTION_PASTE ;;
  typeText) MAIN="$ROOT/Components/InputEvents/main.swift"; DEFINE=ACTION_TYPE_TEXT ;;
  click) MAIN="$ROOT/Components/InputEvents/main.swift"; DEFINE=ACTION_CLICK ;;
  movePointer) MAIN="$ROOT/Components/InputEvents/main.swift"; DEFINE=ACTION_MOVE_POINTER ;;
  scroll) MAIN="$ROOT/Components/InputEvents/main.swift"; DEFINE=ACTION_SCROLL ;;
  openURL) MAIN="$ROOT/Components/OpenTarget/main.swift"; DEFINE=ACTION_OPEN_URL ;;
  openApp) MAIN="$ROOT/Components/OpenTarget/main.swift"; DEFINE=ACTION_OPEN_APP ;;
  composeMail) MAIN="$ROOT/Components/OpenTarget/main.swift"; DEFINE=ACTION_COMPOSE_MAIL ;;
  screenPixel) MAIN="$ROOT/Components/ScreenWait/main.swift"; DEFINE=ACTION_SCREEN_PIXEL ;;
  screenImage) MAIN="$ROOT/Components/ScreenWait/main.swift"; DEFINE=ACTION_SCREEN_IMAGE ;;
  shell) MAIN="$ROOT/Components/ScriptPlan/main.swift"; DEFINE=ACTION_SHELL ;;
  appleScript) MAIN="$ROOT/Components/ScriptPlan/main.swift"; DEFINE=ACTION_APPLESCRIPT ;;
  prompt) MAIN="$ROOT/Components/DialogPlan/main.swift"; DEFINE=ACTION_PROMPT ;;
  choose) MAIN="$ROOT/Components/DialogPlan/main.swift"; DEFINE=ACTION_CHOOSE ;;
  message) MAIN="$ROOT/Components/DialogPlan/main.swift"; DEFINE=ACTION_MESSAGE ;;
  notification) MAIN="$ROOT/Components/DialogPlan/main.swift"; DEFINE=ACTION_NOTIFICATION ;;
  window) MAIN="$ROOT/Components/WindowPlan/main.swift" ;;
  *) printf 'Unknown component: %s\n' "$ACTION" >&2; exit 2 ;;
esac
BUILD_DIR=$(mktemp -d /tmp/autoproductive-component-build.XXXXXX)
trap 'rm -rf "$BUILD_DIR"' EXIT
SDK=$(xcrun --sdk macosx --show-sdk-path)
for ARCH in arm64 x86_64; do
  if [ "$ACTION" = transformClipboard ]; then
    xcrun swiftc -O -sdk "$SDK" -target "$ARCH-apple-macos14.0" \
      -module-cache-path "$BUILD_DIR/cache-$ARCH" \
      "$ROOT/AutoProductive/Models/ClipboardTransform.swift" "$MAIN" -o "$BUILD_DIR/$ARCH"
  elif [ "$MAIN" = "$ROOT/Components/InputEvents/main.swift" ]; then
    xcrun swiftc -O -sdk "$SDK" -target "$ARCH-apple-macos14.0" -D "$DEFINE" \
      -module-cache-path "$BUILD_DIR/cache-$ARCH" \
      "$ROOT/AutoProductive/Models/FeatureInputPlan.swift" "$MAIN" -o "$BUILD_DIR/$ARCH"
  elif [ -n "$DEFINE" ]; then
    xcrun swiftc -O -sdk "$SDK" -target "$ARCH-apple-macos14.0" -D "$DEFINE" \
      -module-cache-path "$BUILD_DIR/cache-$ARCH" "$MAIN" -o "$BUILD_DIR/$ARCH"
  else
    xcrun swiftc -O -sdk "$SDK" -target "$ARCH-apple-macos14.0" \
      -module-cache-path "$BUILD_DIR/cache-$ARCH" "$MAIN" -o "$BUILD_DIR/$ARCH"
  fi
done
xcrun lipo -create "$BUILD_DIR/arm64" "$BUILD_DIR/x86_64" -output "$BUILD_DIR/component"
codesign --force --sign - "$BUILD_DIR/component" >/dev/null 2>&1
mkdir -p "$(dirname -- "$OUTPUT")"
cp "$BUILD_DIR/component" "$OUTPUT"
printf 'Built universal %s component: %s\n' "$ACTION" "$OUTPUT"
