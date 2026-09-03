#!/bin/bash
# Installs Nova's light-mode and dark-mode app icons.
#
#   Scripts/install-theme-icons.sh <light-icon> <dark-icon>
#
# Each source can be any image macOS reads (.png, .ico, .icns, .jpg). Both are converted to
# 1024x1024 PNGs, installed as the AppIconLight / AppIconDark image sets used at runtime, and the
# dark one also becomes the static bundle icon shown in Finder and in the Dock when Nova isn't
# running. For a sharp result, supply 1024x1024 artwork.
set -euo pipefail

LIGHT_SOURCE="${1:?usage: $0 <light-icon> <dark-icon>}"
DARK_SOURCE="${2:?usage: $0 <light-icon> <dark-icon>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASSETS="$ROOT/Nova/Assets.xcassets"

install_set() {
  # Assign separately: every argument to `local` is expanded before any of them is set.
  local source="$1"
  local name="$2"
  local dir="$ASSETS/$name.imageset"
  mkdir -p "$dir"
  sips -s format png "$source" --out "$dir/$name.png" >/dev/null
  # Square it off at 1024 so every Dock and About size scales down from one image.
  sips -z 1024 1024 "$dir/$name.png" --out "$dir/$name.png" >/dev/null
  cat > "$dir/Contents.json" <<JSON
{
  "images" : [
    {
      "filename" : "$name.png",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON
  local width
  width=$(sips -g pixelWidth "$dir/$name.png" | awk '/pixelWidth/ {print $2}')
  echo "  $name: installed at ${width}x${width}"
}

echo "Installing theme icons:"
install_set "$LIGHT_SOURCE" AppIconLight
install_set "$DARK_SOURCE" AppIconDark

# The static icon can't follow the theme, so use the dark artwork: a dark squircle reads correctly
# on both light and dark Dock and Finder backgrounds.
"$ROOT/Scripts/make-app-icon.sh" "$ASSETS/AppIconDark.imageset/AppIconDark.png"
