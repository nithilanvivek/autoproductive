#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_DIR=$(mktemp -d /tmp/autoproductive-clipboard-component.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -module-cache-path "$TEST_DIR/cache" \
  "$ROOT/AutoProductive/Models/ClipboardTransform.swift" \
  "$ROOT/Components/ClipboardTransform/main.swift" -o "$TEST_DIR/clipboard-transform"
python3 "$ROOT/Tests/ClipboardComponent/test.py" "$TEST_DIR/clipboard-transform"
