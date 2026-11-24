# Emberdeep: notes for AI assistants and contributors

Godot 4.6 / GDScript, 2D top-down, AI game master, procedurally grown dungeon, SRD 5.2.1 rules,
host-authoritative multiplayer (hot-seat, LAN, later Steam). Read `docs/ARCHITECTURE.md` first.

## Commands

- `scripts/fetch-godot.sh`: pinned Godot into `.tools/` (add `--templates` to export)
- `scripts/run-tests.sh`: headless tests; run before and after every change, must pass
- `scripts/export-linux.sh`: builds `build/linux/emberdeep.x86_64`
- `.tools/godot --path game`: run the game

## Rules of the codebase

- **Only `GameState` changes game state**, through `handle_intent()` (players) and
  `apply_gm_response()` (GM). UI and network code never mutate state directly.
- **The GM is untrusted input.** New GM actions need: a schema entry in `GameMaster.build_schema()`,
  validation and clamping in `GameState._apply_gm_action()`, a line in `gm_system.md`, and a test.
- **All randomness goes through `Dice` or `DungeonGenerator.rng_for()`**, never `randi()`
  in game logic, so seeds reproduce games.
- Rules content belongs in `game/data/` (JSON), not in code. Mark SRD-derived data and keep
  `docs/LEGAL.md` true. Never use the "D&D" trademark in names or UI.
- New intents must check that the sender owns the hero.
- Keep docs in step with code: if behavior in a doc changes, update the doc in the same commit.
- Static typing in GDScript where the type is known (`var x: int`, `-> Dictionary`).
