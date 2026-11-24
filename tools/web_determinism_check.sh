#!/usr/bin/env bash
# Checks that the web build (wasm) simulates exactly like native: exports a temporary copy of
# the project whose main scene replays tests/sim/golden/bot_brawl.res, runs it in headless
# Chrome and prints whether every per-tick checksum matched the natively recorded ones.
# Needs the web export templates, Chrome and `npm install` in tools/web_smoke.
#   tools/web_determinism_check.sh
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/godot_env.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git -C "$REPO_ROOT" ls-files -z | (cd "$REPO_ROOT" && xargs -0 cp --parents -t "$TMP")
mkdir -p "$TMP/webdet"
cp "$REPO_ROOT/tests/sim/golden/bot_brawl.res" "$TMP/webdet/"
cat > "$TMP/webdet/golden_check.gd" <<'GD'
extends Node

func _ready() -> void:
	var replay := load("res://webdet/bot_brawl.res") as Replay
	var started := Time.get_ticks_msec()
	var mismatch := replay.verify()
	print("GOLDEN_CHECK mismatch=%d ticks=%d final=%x ms=%d" % [mismatch, replay.tick_count(),
			replay.checksums[replay.checksums.size() - 1], Time.get_ticks_msec() - started])
GD
printf '[gd_scene format=3]\n\n[ext_resource type="Script" path="res://webdet/golden_check.gd" id="1"]\n\n[node name="GoldenCheck" type="Node"]\nscript = ExtResource("1")\n' \
  > "$TMP/webdet/golden_check.tscn"
sed -i 's|^run/main_scene=.*|run/main_scene="res://webdet/golden_check.tscn"|' "$TMP/project.godot"
GODOT="$GODOT" "$TMP/tools/export_web.sh" "$TMP/build/web" >/dev/null
OUT="$(node "$REPO_ROOT/tools/web_smoke/smoke.mjs" "$TMP/build/web" "$TMP/shot.png" --marker=GOLDEN_CHECK --settle=200)"
LINE="$(grep -o 'GOLDEN_CHECK[^"]*' <<<"$OUT" || true)"
echo "${LINE:-no GOLDEN_CHECK line}"
[[ "$LINE" == *"mismatch=-1 "* ]]
