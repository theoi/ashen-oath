#!/usr/bin/env bash
# Records a scene with Godot's Movie Maker under Xvfb (software OpenGL) and encodes an mp4.
# Usage: tools/capture_clip.sh <res://scene.tscn> <out.mp4> [frames=180] [-- user args for the scene]
# Movie Maker runs at a fixed 60 FPS, so the clip plays at real speed however slow rendering is.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/godot_env.sh"

SCENE="${1:?usage: capture_clip.sh <res://scene.tscn> <out.mp4> [frames]}"
OUT="$(realpath -m "${2:?usage: capture_clip.sh <res://scene.tscn> <out.mp4> [frames]}")"
FRAMES="${3:-180}"
shift $(( $# < 3 ? $# : 3 ))
[[ "${1:-}" == "--" ]] && shift

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path "$REPO_ROOT" --rendering-driver opengl3 \
  --write-movie "$TMP/clip.avi" --fixed-fps 60 --quit-after "$FRAMES" "$SCENE" -- "$@"
ffmpeg -loglevel error -y -i "$TMP/clip.avi" -c:v libx264 -pix_fmt yuv420p -crf 23 "$OUT"
echo "wrote $OUT"
