#!/usr/bin/env bash
# Renders one arena screenshot with the arena preview under Xvfb (software OpenGL).
# Usage: tools/arena_shot.sh <out.png> [preview user args, e.g. --arena=res://... --view=fight]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/godot_env.sh"

OUT="$(realpath -m "${1:?usage: arena_shot.sh <out.png> [preview args]}")"
shift
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
timeout 300 xvfb-run -a -s "-screen 0 1920x1080x24" "$GODOT" --path "$REPO_ROOT" --rendering-driver opengl3 \
  --resolution 1280x720 res://presentation/arenas/arena_preview.tscn -- --shot="$OUT" "$@"
test -f "$OUT"
