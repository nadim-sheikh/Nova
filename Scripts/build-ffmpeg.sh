#!/bin/zsh
# Rebuilds the full-decoder ffmpeg that Nova links ahead of MPVKit's whitelisted copy.
#
#   Scripts/build-ffmpeg.sh            # builds arm64 + x86_64, installs into ThirdParty/ffmpeg/lib
#
# MPVKit's prebuilt libavcodec only enables a curated set of decoders (no DNxHD, DV, Theora,
# CineForm, MXF...). This builds the same ffmpeg release with every decoder, demuxer, parser and
# bitstream filter, reusing MPVKit's dav1d for AV1 software decoding. Needs only Xcode: no
# Homebrew, nasm or pkg-config (a tiny shim answers ffmpeg's dav1d query). Takes ~10 minutes.
set -euo pipefail

FFMPEG_TAG="n8.1.2"   # must match the ffmpeg version MPVKit's libmpv was built against
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/ThirdParty/ffmpeg/lib"
WORK="$(mktemp -d /private/tmp/nova-ffmpeg-XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
SDK="$(xcrun --show-sdk-path)"

# MPVKit's artifacts live in whichever DerivedData folder resolved the package.
DAV1D_FW="$(find "$HOME/Library/Developer/Xcode/DerivedData" -type d -path "*macos-arm64_x86_64/Libdav1d.framework" 2>/dev/null | head -1)"
[ -n "$DAV1D_FW" ] || { echo "Resolve the MPVKit package in Xcode first (Libdav1d.framework not found)."; exit 1; }

echo "==> Downloading ffmpeg $FFMPEG_TAG"
curl -sSL -o "$WORK/ffmpeg.tar.gz" "https://github.com/FFmpeg/FFmpeg/archive/refs/tags/$FFMPEG_TAG.tar.gz"
tar xzf "$WORK/ffmpeg.tar.gz" -C "$WORK"
SRC="$WORK/FFmpeg-$FFMPEG_TAG"

# ffmpeg includes <dav1d/dav1d.h>; point it at the framework's headers under that name.
INC="$WORK/dav1d-include"; mkdir -p "$INC"
if [ -d "$DAV1D_FW/Headers/dav1d" ]; then ln -s "$DAV1D_FW/Headers/dav1d" "$INC/dav1d"; else ln -s "$DAV1D_FW/Headers" "$INC/dav1d"; fi
mkdir -p "$WORK/bin"
cat > "$WORK/bin/pkg-config" <<PKG
#!/bin/sh
case "\$*" in
  --version) echo "0.29.2"; exit 0;;
  *dav1d*) case "\$*" in
    *--cflags*) echo "-I$INC";;
    *--libs*) echo "-F$(dirname "$DAV1D_FW") -framework Libdav1d";;
    *--modversion*) echo "1.5.3";;
    *) exit 0;;
  esac;;
  *) exit 1;;
esac
PKG
chmod +x "$WORK/bin/pkg-config"

build_arch() {
  ARCH=$1
  BUILD="$WORK/build-$ARCH"; mkdir -p "$BUILD"; cd "$BUILD"
  EXTRA=()
  # No x86 assembler on this Mac, so the Intel slice uses C paths (still correct, just slower).
  if [ "$ARCH" = "x86_64" ]; then EXTRA=(--enable-cross-compile --disable-x86asm); fi
  echo "==> Configuring $ARCH"
  "$SRC/configure" --prefix="$WORK/out/$ARCH" --target-os=darwin --arch="$ARCH" "${EXTRA[@]}" \
    --cc="xcrun clang" --pkg-config="$WORK/bin/pkg-config" \
    --extra-cflags="-arch $ARCH -mmacosx-version-min=13.0 -isysroot $SDK" \
    --extra-ldflags="-arch $ARCH -mmacosx-version-min=13.0 -isysroot $SDK" \
    --enable-static --disable-shared --enable-pic --enable-runtime-cpudetect \
    --disable-programs --disable-doc --disable-debug --enable-optimizations \
    --enable-version3 --disable-gpl \
    --enable-videotoolbox --enable-audiotoolbox --enable-libdav1d \
    --disable-libxml2 --disable-sdl2 --disable-securetransport \
    --disable-devices --disable-indevs --disable-outdevs \
    --disable-encoders --enable-encoder=png --enable-encoder=mjpeg \
    --disable-muxers --enable-muxer=image2 \
    --enable-decoders --enable-demuxers --enable-parsers --enable-bsfs --enable-protocols --enable-filters \
    > "$BUILD/configure.log" 2>&1 || { tail -20 "$BUILD/configure.log"; exit 1; }
  echo "==> Building $ARCH"
  make -j"$(sysctl -n hw.ncpu)" > "$BUILD/make.log" 2>&1 || { tail -30 "$BUILD/make.log"; exit 1; }
  make install > /dev/null 2>&1
}
build_arch arm64
build_arch x86_64

echo "==> Installing universal libraries into $DEST"
mkdir -p "$DEST"
for lib in "$WORK/out/arm64/lib"/*.a; do
  name="$(basename "$lib")"
  lipo -create "$lib" "$WORK/out/x86_64/lib/$name" -output "$DEST/$name"
done
find "$ROOT/ThirdParty" -name '._*' -delete 2>/dev/null || true
lipo -info "$DEST/libavcodec.a"
echo "Done."
