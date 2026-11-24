# Sourced by the other tools/*.sh scripts: resolves REPO_ROOT and the Godot binary ($GODOT).
# Set GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64 to choose a binary explicitly.

GODOT_VERSION="4.7.2"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -z "${GODOT:-}" ]]; then
  if command -v godot >/dev/null 2>&1; then
    GODOT="$(command -v godot)"
  elif [[ -x "$HOME/tools/godot/Godot_v${GODOT_VERSION}-stable_linux.x86_64" ]]; then
    GODOT="$HOME/tools/godot/Godot_v${GODOT_VERSION}-stable_linux.x86_64"
  else
    echo "error: no Godot found. Set GODOT to a Godot ${GODOT_VERSION} binary." >&2
    exit 1
  fi
fi

if ! "$GODOT" --version 2>/dev/null | grep -q "^${GODOT_VERSION}\.stable"; then
  echo "warning: $GODOT is not Godot ${GODOT_VERSION}-stable ($("$GODOT" --version 2>/dev/null))" >&2
fi

# Imports assets and refreshes the global class cache. Needed after a fresh clone and
# after adding assets or class_name scripts; incremental and quick otherwise.
godot_import() {
  "$GODOT" --headless --path "$REPO_ROOT" --import
}
