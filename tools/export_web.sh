#!/usr/bin/env bash
# Exports the single-threaded web build to build/web (or the directory given as $1).
# Needs the Godot 4.7.2 web export templates (web_nothreads_*.zip) installed.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/godot_env.sh"

OUT="${1:-$REPO_ROOT/build/web}"
mkdir -p "$OUT" "$REPO_ROOT/build"
# Keeps Godot from importing export output as project assets.
touch "$REPO_ROOT/build/.gdignore"

COMMIT="${GITHUB_SHA:-$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)}"
printf '{"commit": "%s", "date": "%s"}\n' "${COMMIT:0:7}" "$(date -u +%Y-%m-%dT%H:%MZ)" \
  > "$REPO_ROOT/build_info.json"

godot_import
"$GODOT" --headless --path "$REPO_ROOT" --export-release "Web" "$OUT/index.html"

for f in index.html index.js index.wasm index.pck; do
  if [[ ! -s "$OUT/$f" ]]; then
    echo "error: export did not produce $OUT/$f" >&2
    exit 1
  fi
done
du -sh "$OUT"
