#!/bin/zsh
# Frame-accuracy harness: compiles every app source except main.swift together with
# harness/main.swift, links the same libraries as the app, opens a real window and checks
# load/step/seek/play/reverse/capture/on-screen frames plus timecode copy/paste and menus.
#
#   Scripts/harness/make-test-clips.sh /tmp/clips     # once: frame-numbered clips in every container
#   Scripts/harness/build-and-run.sh /tmp/clips/*.mkv /tmp/clips/*.avi ...
#
# Run on an idle machine: heavy concurrent builds delay rendering and produce false
# "on-screen" failures. Needs the MPVKit package resolved by Xcode (DerivedData) first.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HERE="$(cd "$(dirname "$0")" && pwd)"
DD="$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/Nova-*/SourcePackages 2>/dev/null | head -1)"
[ -n "$DD" ] || { echo "Resolve the MPVKit package in Xcode first."; exit 1; }
FFLAGS=(); LFLAGS=()
for d in "$DD"/artifacts/*/*/*.xcframework/macos-arm64_x86_64; do
  case "$d" in *-GPL*|*smbclient*) continue;; esac   # same framework names as the LGPL set
  FFLAGS+=("-F$d"); LFLAGS+=("-L$d")
done
FRAMEWORKS=(Libmpv Libavcodec Libavdevice Libavfilter Libavformat Libavutil Libswresample Libswscale Libssl Libcrypto Libass Libfreetype Libfribidi Libharfbuzz Libshaderc_combined lcms2 Libplacebo Libdovi Libunibreak gmp nettle hogweed gnutls Libdav1d Libuavs3d Libuchardet Libbluray Libluajit AVFoundation CoreAudio AudioToolbox CoreVideo CoreFoundation CoreMedia Metal VideoToolbox)
FWARGS=(); for f in "${FRAMEWORKS[@]}"; do FWARGS+=("-framework" "$f"); done
FORCE=()
for lib in libavcodec libavformat libavutil libavfilter libavdevice libswresample libswscale; do
  FORCE+=("-Xlinker" "-force_load" "-Xlinker" "$ROOT/ThirdParty/ffmpeg/lib/$lib.a")
done
SOURCES=("${(@f)$(find "$ROOT/Nova" -name '*.swift' -not -name 'main.swift' -not -name '._*')}")
OUT="$(mktemp -d /private/tmp/nova-harness-XXXXXX)"
swiftc -Onone -target arm64-apple-macos13.0 -module-name NovaHarness \
  "${FORCE[@]}" "${FFLAGS[@]}" "${LFLAGS[@]}" "${FWARGS[@]}" \
  -lMoltenVK -lbz2 -liconv -lexpat -lresolv -lxml2 -lz -lc++ -Xlinker -no_warn_duplicate_libraries \
  -o "$OUT/novaharness" "${SOURCES[@]}" "$HERE/main.swift" 2>&1 | grep -E "error:" || true
[ -x "$OUT/novaharness" ] || { echo "harness failed to build"; exit 1; }
cd "$OUT" && mkdir -p shots && "$OUT/novaharness" "$@"
