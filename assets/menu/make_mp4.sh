#!/bin/bash
# The PLAY animation as a film: renders every frame of assets/menu/play_intro.blend's scene (via
# play_intro.py --frames) and encodes them to docs/play-intro/play_intro.mp4 (1280x720, 30 fps, H.264).
#   bash assets/menu/make_mp4.sh [FRAMES_DIR]
set -e
HERE=$(cd "$(dirname "$0")/../.." && pwd)
FRAMES=${1:-$HERE/assets/menu/.frames}
BLENDER=${BLENDER:-"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"}
mkdir -p "$HERE/docs/play-intro"
if [ ! -f "$FRAMES/0001.png" ]; then
  "$BLENDER" -b -P "$HERE/assets/menu/play_intro.py" -- --frames "$FRAMES"
fi
cd "$FRAMES"
ffmpeg -loglevel error -y -framerate 30 -i %04d.png -c:v libx264 -pix_fmt yuv420p -crf 18 -movflags +faststart "$HERE/docs/play-intro/play_intro.mp4"
echo "docs/play-intro/play_intro.mp4"
