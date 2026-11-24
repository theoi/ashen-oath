#!/usr/bin/env bash
# Plays story mode Act 1 end to end through the real game (menus, scenes, fights on the sim,
# results, retries, save/continue, chapter select). See tests/story/story_autoplay.gd for args.
# Usage:
#   tools/story_playthrough.sh [args]                 headless, exits 0 when the act completes
#   tools/story_playthrough.sh --render [args]        under Xvfb (needed for --shots=DIR)
#   tools/story_playthrough.sh --movie=out.mp4 [args] record the run under Xvfb (30 fps)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/godot_env.sh"

MODE=headless
MOVIE=""
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --render) MODE=render ;;
    --movie=*) MODE=movie; MOVIE="$(realpath -m "${arg#--movie=}")" ;;
    *) ARGS+=("$arg") ;;
  esac
done

SCENE=res://tests/story/story_autoplay.tscn
case "$MODE" in
  headless)
    "$GODOT" --headless --path "$REPO_ROOT" "$SCENE" -- "${ARGS[@]}" ;;
  render)
    xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path "$REPO_ROOT" --rendering-driver opengl3 \
      "$SCENE" -- "${ARGS[@]}" ;;
  movie)
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path "$REPO_ROOT" --rendering-driver opengl3 \
      --write-movie "$TMP/run.avi" --fixed-fps 30 "$SCENE" -- "${ARGS[@]}" || true
    ffmpeg -loglevel error -y -i "$TMP/run.avi" -c:v libx264 -pix_fmt yuv420p -crf 24 "$MOVIE"
    echo "wrote $MOVIE" ;;
esac
