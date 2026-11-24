#!/usr/bin/env bash
# Runs the headless test suite. Extra arguments go to the runner, e.g. --filter=sim/
# Env: SKIP_IMPORT=1 skips the import step; TEST_TIMEOUT (seconds, default 600).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/godot_env.sh"

if [[ "${SKIP_IMPORT:-0}" != "1" ]]; then
  godot_import
fi
timeout "${TEST_TIMEOUT:-600}" "$GODOT" --headless --path "$REPO_ROOT" res://tests/runner.tscn -- "$@"
