#!/usr/bin/env bash
# Plays a seeded 2-hero game through the real input pipeline in a real window,
# saves a screenshot and prints a one-line summary. Needs a display.
#   scripts/smoke.sh [screenshot.png] [steps]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-}"
if [[ -z "$GODOT" ]]; then
  if [[ -x "$ROOT/.tools/godot" ]]; then GODOT="$ROOT/.tools/godot"; else GODOT="godot"; fi
fi
SHOT="$(realpath -m "${1:-$ROOT/build/smoke.png}")"
mkdir -p "$(dirname "$SHOT")"
timeout 300 "$GODOT" --path "$ROOT/game" -- --smoke --shot="$SHOT" --steps="${2:-400}" 2>&1 | grep -E "SMOKE|SCRIPT ERROR|ERROR"
