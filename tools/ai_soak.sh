#!/usr/bin/env bash
# AI-vs-AI soak and difficulty harness (headless). Options: tools/ai_soak.sh --help
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/godot_env.sh"

if [[ "${SKIP_IMPORT:-0}" != "1" ]]; then
  godot_import >/dev/null 2>&1
fi
exec "$GODOT" --headless --path "$REPO_ROOT" -s "$REPO_ROOT/tools/ai_soak.gd" -- "$@"
