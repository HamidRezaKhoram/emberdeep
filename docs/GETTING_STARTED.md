# Getting started: learning path for Emberdeep (macOS)

A personal on-ramp: what to install, what to learn, and what to read in this repo, in order.

## 0. Where the project stands

- M0 skeleton is done: ~2,200 lines of GDScript, Godot 4.6.3, colored squares for art, one
  Fighter, six monsters, AI GM with offline / local LLM / Claude providers, hot-seat + LAN.
- Research and engine choice are already in [RESEARCH.md](RESEARCH.md). No need to redo it.
- Next milestone is **M1: a real session** ([ROADMAP.md](ROADMAP.md)).

## 1. Get it running on a Mac

All scripts now work on macOS. `scripts/fetch-godot.sh` would put Godot in `.tools/`, but this
checkout is in iCloud Drive, so Godot is installed outside it and found through `GODOT`:

Installed and verified on 2026-11-25 (Apple Silicon, macOS 15): 355 tests pass, smoke bot plays.

1. **Godot 4.6.3 stable** (macOS universal, SHA-512 checked against the official release) lives at
   `~/Applications/Godot 4.6.3.app`. It is kept outside iCloud Drive on purpose: syncing a `.app`
   wastes space and can break its code signature.
   - Use 4.6.3, not Homebrew's `godot` cask (that is 4.7.x). Opening the project in 4.7 rewrites
     project files and would drift from what CI tests.
2. Point the scripts at it (add to `~/.zshrc` to keep it):
   ```bash
   export GODOT="$HOME/Applications/Godot 4.6.3.app/Contents/MacOS/Godot"
   ```
3. Run the tests (needs GNU `timeout`, already installed via Homebrew coreutils):
   ```bash
   scripts/run-tests.sh
   ```
4. Play from source: `"$GODOT" --path game`, or open `game/project.godot` in the Godot app and press F5.
5. Watch the bot play a seeded game and save a screenshot to `build/smoke.png`:
   ```bash
   scripts/smoke.sh
   ```

## 2. Learn Godot + GDScript (about a week of evenings)

The full curriculum, with exercises in this codebase, is in [LEARNING.md](LEARNING.md). The short version:

Do these in order; the official docs are the best resource.

1. **Getting Started → Step by step** (nodes, scenes, scripts, signals):
   https://docs.godotengine.org/en/stable/getting_started/step_by_step/index.html
2. **Your first 2D game** ("Dodge the Creeps"): build it once, end to end.
   https://docs.godotengine.org/en/stable/getting_started/first_2d_game/
3. **GDScript reference** — focus on static typing, `class_name`, signals, `Dictionary`/`Array`.
4. Then skim the docs for the pieces Emberdeep uses:
   | Concept | Where it appears here |
   |---|---|
   | Autoloads (singletons) | `GameState`, `Net` in `project.godot` |
   | Signals | `GameState.changed`, `log_added`, `gm_event` |
   | `_draw()` custom drawing | `world/map_view.gd` |
   | `RandomNumberGenerator` with seeds | `core/dice.gd`, `DungeonGenerator.rng_for()` |
   | `HTTPRequest` | `gm/gm_provider.gd` |
   | High-level multiplayer / RPCs | `net/network.gd` |
   | `RichTextLabel` + BBCode | narration log in `main.gd` |
   | `TileMapLayer` (for M2 art) | not used yet |

Note the skeleton builds its UI **in code** (`main.gd`), not in scenes. That's unusual for
Godot tutorials; it's a deliberate shortcut ([ARCHITECTURE.md](ARCHITECTURE.md#known-shortcuts-fine-for-a-skeleton-fix-as-we-grow)).

## 3. Read the codebase in this order

Smallest and purest first, so each file builds on the last.

1. [`CLAUDE.md`](../CLAUDE.md) — the house rules (only `GameState` mutates state, GM is untrusted, all randomness via `Dice`).
2. [ARCHITECTURE.md](ARCHITECTURE.md) — the diagram and state shapes.
3. `game/scripts/core/dice.gd` (65 lines) — seeded dice, `NdM+K` parser.
4. `game/scripts/core/rules.gd` (50 lines) — SRD math: modifiers, checks, attacks, crits.
5. `game/tests/test_main.gd` — shows how every system is *meant* to behave. Run it, break something, run it again.
6. `game/scripts/world/dungeon_generator.gd` + [MAP_GENERATION.md](MAP_GENERATION.md) — door-driven room accretion.
7. `game/scripts/core/game_state.gd` (617 lines, the heart) — read `handle_intent` → `_intent_move` → `_start_combat` / `_advance_turn` → `_populate_room` → `_apply_gm_action`.
8. `game/scripts/gm/` + [AI_GAME_MASTER.md](AI_GAME_MASTER.md) + `game/data/prompts/gm_system.md` — the JSON contract with the model.
9. `game/scripts/main.gd` — input → intents, HUD.
10. `game/scripts/net/network.gd` + [NETWORKING.md](NETWORKING.md) — last; you won't touch it for a while.

## 4. Learn the rules you're implementing

- **SRD 5.2.1** (free, CC-BY-4.0): https://www.dndbeyond.com/srd — read "Playing the Game"
  (d20 tests, combat) and the Fighter/Rogue/Cleric/Wizard class pages before M1.
- Keep [LEGAL.md](LEGAL.md) in mind: SRD content only, never the trademark.

## 5. First tasks to build confidence (small → bigger)

1. Change a constant (e.g. `SPEED_TILES`) and watch tests/gameplay change. Revert.
2. Add a monster to `game/data/srd/monsters.json` (check its stats against the SRD) — pure data, no code.
3. Add a room kind + offline line (`ROOM_KINDS` in the generator, `ROOM_LINES` in `offline_provider.gd`).
4. Add **advantage/disadvantage** to checks — `Dice.d20(mode)` already supports it; wire it through
   (M1 item, touches rules + GM schema + validation + test, so it teaches the full GM-action checklist in `CLAUDE.md`).
5. Then pick a real M1 item: skills & proficiency, or death saving throws.

Rule of thumb from `CLAUDE.md`: run `scripts/run-tests.sh` before and after every change.
