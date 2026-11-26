# Emberdeep: notes for AI assistants and contributors

Godot 4.6 / GDScript, 2D top-down, AI game master, procedurally grown dungeon, SRD 5.2.1 rules,
host-authoritative multiplayer (hot-seat, LAN, later Steam). Read `docs/ARCHITECTURE.md` first.

## Commands

- `scripts/fetch-godot.sh`: pinned Godot into `.tools/` (add `--templates` to export)
- `scripts/run-tests.sh`: headless tests; run before and after every change, must pass
- `scripts/bench.sh`: performance budgets on a 300-room dungeon (`docs/PERFORMANCE.md`); must pass
- `scripts/export-linux.sh`: builds `build/linux/emberdeep.x86_64`
- `.tools/godot --path game`: run the game
- `scripts/smoke.sh`: a bot plays a seeded 2-hero game through real key events in a window,
  saves `build/smoke.png` and prints a summary; use it to check UI/gameplay changes for real
- `.tools/godot --path game -- --play --seed=42 --overlay`: straight into a game with the debug overlay
  (debug tools and flags: `docs/DEBUG.md`; saves and replays: `docs/SAVES.md`)

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
- **Every change to game state goes through an input** (`handle_intent`, `apply_gm_response`,
  `add_player`, `remove_players_of`) so it is recorded and replays reproduce. Debug commands too.
- **Emit an event** (`_emit`) wherever state changes something the player sees (`docs/EVENTS.md`).
- **Never set `monster["pos"]` directly**: use `move_monster()`; indexes must stay in step.
- **Balance numbers live in `game/data/`** (`docs/DATA.md`), never as constants in code.
- **Changing dungeon generation?** Bump `generator_version` in `data/rules/dungeon.json`.
  **Changing the save layout?** Bump `SaveGame.FORMAT` and add a migration (`docs/SAVES.md`).
- **Art and sound are found by file name** through `AssetLibrary` (`docs/ASSETS.md`); every
  lookup needs a fallback (shape or silence). Don't create art or audio content: the owner makes it.
