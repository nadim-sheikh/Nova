#!/bin/bash
# Builds Nova and packages it as a ready-to-install disk image.
#
#   Scripts/make-dmg.sh                      # builds a universal Release app, then the DMG
#   Scripts/make-dmg.sh <Nova.app>           # packages an app you already built
#   Scripts/make-dmg.sh --theme dark [app]   # force the installer window's look
#
# Finder shows the one background image stored in the disk image, so the theme is fixed when the
# DMG is built and looks the same for everyone. Without --theme it follows this Mac's appearance.
#
# Output: build/Nova-<version>.dmg
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
WORK="$BUILD/dmg"
VENV="$BUILD/dmg-venv"
mkdir -p "$WORK"

THEME=""
if [ "${1:-}" = "--theme" ]; then
  THEME="${2:?--theme needs light or dark}"
  shift 2
fi
if [ -z "$THEME" ]; then
  # Match the appearance of the Mac building the image.
  if [ "$(defaults read -g AppleInterfaceStyle 2>/dev/null || echo Light)" = "Dark" ]; then
    THEME="dark"
  else
    THEME="light"
  fi
fi

APP="${1:-}"
if [ -z "$APP" ]; then
  # Build on the system disk, never on the project volume: exFAT/FAT volumes get `._` sidecar
  # files written into the app bundle, and codesign refuses to sign a bundle containing them.
  DERIVED="$(mktemp -d /private/tmp/nova-release-XXXXXX)"
  trap 'rm -rf "$DERIVED"' EXIT
  echo "==> Building a universal Release app"
  xcodebuild -project "$ROOT/Nova.xcodeproj" -scheme Nova -configuration Release \
    -derivedDataPath "$DERIVED" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build >/dev/null
  APP="$DERIVED/Build/Products/Release/Nova.app"
fi
[ -d "$APP" ] || { echo "No app bundle at $APP"; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || echo "1.0")
OUTPUT="$BUILD/Nova-$VERSION.dmg"

echo "==> Rendering installer artwork"
swift "$ROOT/Scripts/render-dmg-background.swift" "$WORK" "$THEME" >/dev/null
echo "    theme: $THEME"
# One TIFF carrying both scales, so the window looks right on Retina and non-Retina displays.
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" -out "$WORK/background.tiff" >/dev/null

if [ ! -x "$VENV/bin/dmgbuild" ]; then
  echo "==> Installing dmgbuild into $VENV"
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet --disable-pip-version-check dmgbuild
fi

echo "==> Building $(basename "$OUTPUT")"
rm -f "$OUTPUT"
"$VENV/bin/dmgbuild" \
  -s "$ROOT/Scripts/dmg-settings.py" \
  -D app="$APP" \
  -D background="$WORK/background.tiff" \
  -D volume_icon="$APP/Contents/Resources/AppIcon.icns" \
  "Nova" "$OUTPUT"

echo
echo "Done: $OUTPUT ($(du -h "$OUTPUT" | cut -f1))"
