#!/bin/zsh
# Generates ten-second test clips in every container Nova should play. Each frame carries its
# number twice: as big text for humans and as a 10-bit strip of white boxes the harness decodes.
#   Scripts/harness/make-test-clips.sh <output-dir>
set -euo pipefail
OUT="${1:?output directory}"; mkdir -p "$OUT"; cd "$OUT"
FF="${FFMPEG:-$(command -v ffmpeg || echo "$HOME/bin/ffmpeg")}"
FONT=/System/Library/Fonts/Supplemental/Arial.ttf
BITS="drawbox=x=0:y=0:w=iw:h=90:color=black:t=fill"
for k in 0 1 2 3 4 5 6 7 8 9; do
  BITS="$BITS,drawbox=x=$((20 + k * 70)):y=15:w=60:h=60:color=white:t=fill:enable='gte(bitand(n\,$((1 << k)))\,1)'"
done
VF="$BITS,drawtext=fontfile=${FONT}:text='%{eif\:n\:d\:4}':fontsize=120:fontcolor=white:box=1:boxcolor=black@0.75:boxborderw=20:x=(w-tw)/2:y=(h-th)/2"
gen() { name=$1; rate=$2; size=$3; shift 3
  "$FF" -hide_banner -loglevel error -y -f lavfi -i "testsrc2=size=${size}:rate=${rate}" -f lavfi -i "sine=frequency=440:sample_rate=48000" -t 10 -vf "$VF" "$@" "$name" && echo "OK $name"; }
gen h264_2997.mkv 30000/1001 1280x720 -c:v libx264 -preset ultrafast -pix_fmt yuv420p -c:a aac
gen h264_2997.avi 30000/1001 1280x720 -c:v libx264 -preset ultrafast -pix_fmt yuv420p -c:a mp2
gen hevc_5994.mkv 60000/1001 1280x720 -c:v libx265 -preset ultrafast -pix_fmt yuv420p -x265-params log-level=none -c:a aac
gen xvid_25.avi 25 1280x720 -c:v mpeg4 -vtag xvid -q:v 4 -c:a mp2
gen wmv2_25.wmv 25 1280x720 -c:v wmv2 -q:v 4 -c:a wmav2
gen flv1_25.flv 25 1280x720 -c:v flv -q:v 4 -c:a aac
gen dnxhr_23976.mov 24000/1001 1280x720 -c:v dnxhd -profile:v dnxhr_lb -pix_fmt yuv422p -c:a pcm_s16le
gen theora_25.ogv 25 1280x720 -c:v libtheora -q:v 6 -c:a libvorbis
gen vp9_30.webm 30 1280x720 -c:v libvpx-vp9 -deadline realtime -cpu-used 8 -b:v 2M -c:a libopus
gen av1_24.mkv 24 1280x720 -c:v libsvtav1 -preset 12 -crf 40 -c:a libopus
gen h264_1080p60.mkv 60 1920x1080 -c:v libx264 -preset ultrafast -pix_fmt yuv420p -c:a aac
gen h264_2997.mp4 30000/1001 1280x720 -c:v libx264 -preset ultrafast -pix_fmt yuv420p -c:a aac
"$FF" -hide_banner -loglevel error -y -f lavfi -i "testsrc2=size=1280x720:rate=25" -t 5 -c:v libvpx-vp9 -deadline realtime -cpu-used 8 -b:v 1M -an flat.mp4
"$FF" -hide_banner -loglevel error -y -display_rotation 90 -i flat.mp4 -c copy vp9_rot90.mp4 && rm flat.mp4 && echo "OK vp9_rot90.mp4"
