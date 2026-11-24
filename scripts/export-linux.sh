#!/usr/bin/env bash
# Builds the Linux executable: build/linux/emberdeep.x86_64 (data embedded, single file).
# Needs export templates: run scripts/fetch-godot.sh --templates once.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-}"
if [[ -z "$GODOT" ]]; then
  if [[ -x "$ROOT/.tools/godot" ]]; then GODOT="$ROOT/.tools/godot"; else GODOT="godot"; fi
fi

mkdir -p "$ROOT/build/linux"
"$GODOT" --headless --path "$ROOT/game" --import >/dev/null 2>&1 || true
"$GODOT" --headless --path "$ROOT/game" --export-release "Linux" "$ROOT/build/linux/emberdeep.x86_64"
chmod +x "$ROOT/build/linux/emberdeep.x86_64"
echo "Built $ROOT/build/linux/emberdeep.x86_64"
