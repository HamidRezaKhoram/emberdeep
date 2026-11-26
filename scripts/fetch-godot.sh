#!/usr/bin/env bash
# Downloads the pinned Godot editor (and, with --templates, the export templates)
# into .tools/ so builds don't depend on whatever Godot is installed system-wide.
# Works on Linux x86_64 and macOS (universal build).
#   scripts/fetch-godot.sh               # editor only (~60 MB Linux, ~160 MB macOS), enough for tests
#   scripts/fetch-godot.sh --templates   # + export templates (~1 GB), needed to build the executable
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.6.3}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$ROOT/.tools"
BASE="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable"

mkdir -p "$TOOLS"
case "$(uname -s)" in
  Darwin)
    APP="$TOOLS/Godot_v${GODOT_VERSION}.app"
    BIN="$APP/Contents/MacOS/Godot"
    if [[ ! -x "$BIN" ]]; then
      echo "Downloading Godot ${GODOT_VERSION} (macOS)..."
      curl -fSL -o "$TOOLS/godot.zip" "$BASE/Godot_v${GODOT_VERSION}-stable_macos.universal.zip"
      rm -rf "$TOOLS/unzip" && ditto -x -k "$TOOLS/godot.zip" "$TOOLS/unzip"
      rm -rf "$APP" && mv "$TOOLS/unzip/Godot.app" "$APP"
      rm -rf "$TOOLS/unzip" "$TOOLS/godot.zip"
    fi
    TPL_DIR="$HOME/Library/Application Support/Godot/export_templates/${GODOT_VERSION}.stable"
    ;;
  *)
    BIN="$TOOLS/Godot_v${GODOT_VERSION}-stable_linux.x86_64"
    if [[ ! -x "$BIN" ]]; then
      echo "Downloading Godot ${GODOT_VERSION}..."
      curl -fSL -o "$TOOLS/godot.zip" "$BASE/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
      unzip -oq "$TOOLS/godot.zip" -d "$TOOLS"
      rm "$TOOLS/godot.zip"
      chmod +x "$BIN"
    fi
    TPL_DIR="$HOME/.local/share/godot/export_templates/${GODOT_VERSION}.stable"
    ;;
esac
ln -sf "$BIN" "$TOOLS/godot"

if [[ "${1:-}" == "--templates" ]]; then
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
