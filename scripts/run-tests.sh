#!/usr/bin/env bash
# Imports the project (builds the class cache) and runs the headless test scene.
# Uses .tools/godot if present, else GODOT, else `godot` on PATH.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-}"
if [[ -z "$GODOT" ]]; then
  if [[ -x "$ROOT/.tools/godot" ]]; then GODOT="$ROOT/.tools/godot"; else GODOT="godot"; fi
fi

"$GODOT" --headless --path "$ROOT/game" --import >/dev/null 2>&1 || true
# A script parse error would leave the test scene idle forever, so cap the run
# and also fail on any engine-reported script error.
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT
set +e
timeout 180 "$GODOT" --headless --path "$ROOT/game" res://tests/tests.tscn 2>&1 | tee "$LOG"
STATUS=${PIPESTATUS[0]}
set -e
if grep -qE "SCRIPT ERROR|Parse Error|Failed to load script" "$LOG"; then
  echo "Script errors reported (see above)." >&2
  exit 1
fi
exit "$STATUS"
