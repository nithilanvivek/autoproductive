#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
[ "$#" -eq 1 ] || { printf 'Usage: %s OUTPUT_PATH\n' "$0" >&2; exit 2; }
exec sh "$ROOT/scripts/build-feature-component.sh" transformClipboard "$1"
