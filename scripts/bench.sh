#!/usr/bin/env bash
# Performance budgets: grows a 300-room dungeon and times the hot paths against
# game/tests/budgets.json. Exits 1 when anything is over budget. See docs/PERFORMANCE.md.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-}"
if [[ -z "$GODOT" ]]; then
  if [[ -x "$ROOT/.tools/godot" ]]; then GODOT="$ROOT/.tools/godot"; else GODOT="godot"; fi
fi
"$GODOT" --headless --path "$ROOT/game" --import >/dev/null 2>&1 || true
TIMEOUT=()
if command -v timeout >/dev/null; then TIMEOUT=(timeout 300)
elif command -v gtimeout >/dev/null; then TIMEOUT=(gtimeout 300); fi
${TIMEOUT[@]+"${TIMEOUT[@]}"} "$GODOT" --headless --path "$ROOT/game" res://tests/bench.tscn 2>&1 | grep -vE "^Godot Engine|^$"
exit "${PIPESTATUS[0]}"
