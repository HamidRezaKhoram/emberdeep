#!/usr/bin/env bash
# Downloads the pinned Godot editor (and, with --templates, the export templates)
# into .tools/ so builds don't depend on whatever Godot is installed system-wide.
#   scripts/fetch-godot.sh               # editor only (~60 MB), enough for tests
#   scripts/fetch-godot.sh --templates   # + export templates (~1 GB), needed to build the executable
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.6.3}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$ROOT/.tools"
BASE="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable"
BIN="$TOOLS/Godot_v${GODOT_VERSION}-stable_linux.x86_64"

mkdir -p "$TOOLS"
if [[ ! -x "$BIN" ]]; then
  echo "Downloading Godot ${GODOT_VERSION}..."
  curl -fSL -o "$TOOLS/godot.zip" "$BASE/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
  unzip -oq "$TOOLS/godot.zip" -d "$TOOLS"
  rm "$TOOLS/godot.zip"
  chmod +x "$BIN"
fi
ln -sf "$BIN" "$TOOLS/godot"

if [[ "${1:-}" == "--templates" ]]; then
  TPL_DIR="$HOME/.local/share/godot/export_templates/${GODOT_VERSION}.stable"
  if [[ ! -f "$TPL_DIR/linux_release.x86_64" ]]; then
    echo "Downloading export templates (large)..."
    curl -fSL -o "$TOOLS/templates.tpz" "$BASE/Godot_v${GODOT_VERSION}-stable_export_templates.tpz"
    mkdir -p "$TPL_DIR"
    unzip -oq "$TOOLS/templates.tpz" -d "$TOOLS/tpl"
    mv "$TOOLS/tpl/templates/"* "$TPL_DIR/"
    rm -rf "$TOOLS/tpl" "$TOOLS/templates.tpz"
  fi
fi

"$TOOLS/godot" --version
