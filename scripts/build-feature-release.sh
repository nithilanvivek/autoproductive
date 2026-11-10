#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
: "${AUTOPRODUCTIVE_SIGN_IDENTITY:?Set AUTOPRODUCTIVE_SIGN_IDENTITY to the app signing identity}"
if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
  printf 'Usage: %s VERSION OUTPUT_DIRECTORY SPARKLE_SIGN_UPDATE [UNIVERSAL_PACKAGES]\n' "$0" >&2
  exit 2
fi
VERSION=$1
OUTPUT=$2
SIGNER=$3
case "$VERSION" in ''|.|..|*[!A-Za-z0-9._-]*) printf 'Invalid version.\n' >&2; exit 2 ;; esac
[ -x "$SIGNER" ] || { printf 'Sparkle sign_update is not executable.\n' >&2; exit 2; }
[ ! -e "$OUTPUT" ] || { printf 'Output already exists; release packages must be immutable.\n' >&2; exit 2; }
PARENT=$(dirname -- "$OUTPUT")
mkdir -p "$PARENT"
STAGING=$(mktemp -d "$PARENT/.autoproductive-release.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
UNIVERSAL="$STAGING/universal"
mkdir -p "$UNIVERSAL"
if [ "$#" -eq 4 ]; then
  cp "$4"/*.package "$UNIVERSAL/"
else
for ACTION in transformClipboard wait readFile writeFile appendFile createFolder copyFile moveFile trashFile \
  adjustSound adjustBrightness setClipboard pressKey pasteClipboard typeText click movePointer scroll \
  openURL openApp composeMail screenPixel screenImage shell appleScript prompt choose message notification window; do
  sh "$ROOT/scripts/build-feature-component.sh" "$ACTION" "$UNIVERSAL/action.$ACTION.package"
done
sh "$ROOT/scripts/build-finder-cut-tool.sh" "$UNIVERSAL/tool.finderCut.package"
sh "$ROOT/scripts/build-file-bucket-storage.sh" "$UNIVERSAL/tool.fileBucket.package"
sh "$ROOT/scripts/build-keep-awake-assertions.sh" "$UNIVERSAL/tool.keepAwake.package"
sh "$ROOT/scripts/build-audio-mixer-tool.sh" "$UNIVERSAL/tool.audioMixer.package"
sh "$ROOT/scripts/build-dock-preview-tool.sh" "$UNIVERSAL/tool.dockPreviews.package"
fi
xcrun swiftc -parse-as-library -module-cache-path "$STAGING/cache" \
  "$ROOT/AutoProductive/Models/FeatureComponentSupport.swift" \
  "$ROOT/AutoProductive/Models/FeaturePackageManifest.swift" \
  "$ROOT/ReleaseTools/FeatureManifest/main.swift" -o "$STAGING/manifest-tool"
PUBLIC_KEY=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$ROOT/AutoProductive/Info.plist")
for ARCH in arm64 x86_64; do
  PACKAGES="$STAGING/packages/$VERSION/$ARCH"
  CATALOGUE="$STAGING/releases/$VERSION/$ARCH"
  mkdir -p "$PACKAGES" "$CATALOGUE"
  for PACKAGE in "$UNIVERSAL"/*.package; do
    [ -f "$PACKAGE" ] || { printf 'No universal packages found.\n' >&2; exit 1; }
    /usr/bin/lipo "$PACKAGE" -thin "$ARCH" -output "$PACKAGES/$(basename -- "$PACKAGE")"
    codesign --verify --strict "$PACKAGES/$(basename -- "$PACKAGE")"
  done
  "$STAGING/manifest-tool" "$VERSION" "$ARCH" "$PACKAGES" "$CATALOGUE/features.json" "$SIGNER" "$PUBLIC_KEY"
done
rm -rf "$STAGING/cache" "$STAGING/manifest-tool" "$UNIVERSAL"
mv "$STAGING" "$OUTPUT"
printf 'Prepared feature packages in %s\n' "$OUTPUT"
