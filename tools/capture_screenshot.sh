#!/usr/bin/env bash
# Screenshots the game after N frames, rendered under Xvfb with Movie Maker (software OpenGL).
# Usage: tools/capture_screenshot.sh <out.png> [frames=40] [-- user args, e.g. --menu=mode_select]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/godot_env.sh"

OUT="$(realpath -m "${1:?usage: capture_screenshot.sh <out.png> [frames] [-- args]}")"
FRAMES="${2:-40}"
shift $(( $# < 2 ? $# : 2 ))
[[ "${1:-}" == "--" ]] && shift

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path "$REPO_ROOT" --rendering-driver opengl3 \
  --write-movie "$TMP/frame.png" --fixed-fps 60 --quit-after "$FRAMES" -- "$@" > "$TMP/log.txt" 2>&1 || { cat "$TMP/log.txt"; exit 1; }
grep -E "ERROR|SCRIPT ERROR" "$TMP/log.txt" && echo "(errors above)" >&2
LAST="$(ls "$TMP"/frame*.png | sort | tail -1)"
cp "$LAST" "$OUT"
echo "wrote $OUT"
