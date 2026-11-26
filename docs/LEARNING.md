# Learning plan: from zero to contributing to Emberdeep

Eight units. Each one has **read** (the material), **do** (an exercise in this codebase) and a
**check** (you're ready to move on when you can do it without notes). Plan on about 3-5 hours per unit.
Setup is in [GETTING_STARTED.md](GETTING_STARTED.md); do that first.
Each concept is explained, with examples from this code, in [CONCEPTS.md](CONCEPTS.md).

Work on a branch for the exercises (`git switch -c learning`) so you can throw them away.
Run `scripts/run-tests.sh` after every change.

---

## Unit 1: Programming in GDScript

**Read / do**
- [Learn GDScript From Zero](https://gdquest.github.io/learn-gdscript/) (GDQuest, free, ~10 h, runs in the browser).
  Skip lessons you already know from other languages; the point is GDScript's syntax.
- [GDScript reference](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html):
  variables, functions, `match`, `for`, arrays, dictionaries, lambdas, `class_name`, `extends`.
- [Static typing in GDScript](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/static_typing.html).
  This repo uses it everywhere (`var x: int`, `-> Dictionary`).

**Do:** read `game/scripts/core/dice.gd` and `rules.gd` line by line. For every line, say out loud what it does.

**Check:** you can explain `Dice.parse("2d6+3")`, including what the regex captures, and why
`Rules.damage()` doubles the dice but not the modifier on a crit.

## Unit 2: How Godot thinks (nodes, scenes, signals)

**Read**
- [Step by step](https://docs.godotengine.org/en/stable/getting_started/step_by_step/index.html):
  nodes and scenes, instancing, scripting languages, first script, player input, **signals**.
- [Singletons (autoload)](https://docs.godotengine.org/en/stable/tutorials/scripting/singletons_autoload.html).

**Do:** build the official [Your first 2D game](https://docs.godotengine.org/en/stable/getting_started/first_2d_game/index.html)
("Dodge the Creeps") in a separate folder, outside this repo. Finish it.

**Then, in Emberdeep:** open `game/project.godot` in the Godot app. Find the two autoloads
(Project → Project Settings → Globals). In `main.gd`, find where it connects to
`GameState.changed` and `GameState.log_added`, and follow what happens when each fires.

**Check:** you can explain why `GameState` emits `changed` instead of calling the HUD directly.
(Answer: the state doesn't know who is listening: the HUD, the map, and the network code all react.)

## Unit 3: Tests and determinism (your safety net)

**Read**
- [Random number generation](https://docs.godotengine.org/en/stable/tutorials/math/random_number_generation.html)
  (seeds, `RandomNumberGenerator`).
- [Command line tutorial](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html)
  (`--headless`, `--path`): this is how `run-tests.sh` works.
- `game/tests/test_main.gd`, the whole file.

**Do**
1. Break `Rules.ability_modifier()` on purpose (e.g. drop the `floori`), run the tests, read the failure, revert.
2. Write a new test: a level-5 hero has proficiency bonus +3, and level 9 has +4.
3. Write a test that the same seed gives the same three `d20()` rolls twice in a row.

**Check:** you can say why the rules forbid `randi()` in game logic (`CLAUDE.md`).

## Unit 4: Fifth-edition rules (what you're implementing)

**Read:** [SRD 5.2.1](https://www.dndbeyond.com/srd), free and CC-BY-4.0:
- "Playing the Game": d20 tests, advantage/disadvantage, proficiency, ability checks, saving throws.
- "Combat": initiative, turns, actions, attack rolls, damage, dropping to 0 HP, death saving throws.
- The Fighter class page (the only class in the game today).
- A few monster stat blocks (Giant Rat, Goblin Warrior, Skeleton, Zombie).

**Do:** compare every number in `game/data/srd/monsters.json` with the SRD. It says
"PLACEHOLDER" today, so this is real work the roadmap needs (M1: verified stat blocks). Write down every mismatch.

**Check:** you can explain the difference between an ability check, a saving throw and an attack roll,
and what a natural 20 does in each under the 2024 rules (see the comment in `rules.gd`).

## Unit 5: The game loop in `game_state.gd`

This is the heart of the game (617 lines). Read it in this order:

1. `handle_intent()`: every player action enters here; note the ownership check.
2. `_intent_move()`: moving, attacking by walking into a monster, opening doors.
3. `_start_combat()` → `_advance_turn()` → `_monster_turn()` → `_check_combat_over()`.
4. `_remove_from_initiative()`: subtle; the commit "Fix turn order when an actor leaves initiative" shows why.
5. `_populate_room()` and `_spawn_monster()`.

**Do (pick two)**
- Monsters walk toward the hero greedily with Manhattan distance (`_monster_turn`) and get stuck behind
  walls. Read Red Blob Games' [Introduction to A*](https://www.redblobgames.com/pathfinding/a-star/introduction.html),
  then try Godot's built-in [`AStarGrid2D`](https://docs.godotengine.org/en/stable/classes/class_astargrid2d.html).
- Add a "dodge" or "dash" option on a hero's turn.
- Make the log say how many squares of movement are left after each step.

**Check:** draw the combat turn cycle on paper, from "door opens" to "The fight is over".

## Unit 6: Procedural generation (`dungeon_generator.gd`)

**Read**
- [MAP_GENERATION.md](MAP_GENERATION.md), then the generator itself (225 lines).
- Red Blob Games, [Grids and graphs](https://www.redblobgames.com/pathfinding/grids/graphs.html).
- [RogueBasin](https://www.roguebasin.com/) articles on dungeon generation, cellular automata and BSP, for background.

**Do**
1. Add a room kind (for example "armory") to `ROOM_KINDS` and a line in `offline_provider.gd`.
2. Make some rooms round or L-shaped (roadmap item: room shapes). Keep the "no overlap" and
   "always reachable" tests passing.

**Check:** you can explain why the generator uses `rng_for("door:x,y")` instead of one global RNG.
(Answer: the room behind a door must be the same no matter what order doors are opened in, which saves depend on.)

## Unit 7: Drawing and UI

**Read**
- [Custom drawing in 2D](https://docs.godotengine.org/en/stable/tutorials/2d/custom_drawing_in_2d.html): `_draw()`, `queue_redraw()`. Used by `map_view.gd`.
- [BBCode in RichTextLabel](https://docs.godotengine.org/en/stable/tutorials/ui/bbcode_in_richtextlabel.html): the narration log.
- [Using TileMaps](https://docs.godotengine.org/en/stable/tutorials/2d/using_tilemaps.html) and
  [Using TileSets](https://docs.godotengine.org/en/stable/tutorials/2d/using_tilesets.html). These are needed for M2 art.
  Older tutorials use the deprecated `TileMap` node; this project needs `TileMapLayer` (Godot 4.3+).

**Do**
1. In `map_view.gd`, draw a small HP bar under each monster.
2. Show a damage number that fades out over a second (a `Label` plus a `Tween`).
3. Stretch goal: draw the floor with a `TileMapLayer` and a free tileset, for example
   [Kenney's](https://kenney.nl/assets) (CC0). Keep the colored-square drawing for everything else.

**Check:** you know when the map gets redrawn, and why.

## Unit 8: The AI game master

**Read**
- [AI_GAME_MASTER.md](AI_GAME_MASTER.md) and `game/data/prompts/gm_system.md`.
- `game_master.gd` (`build_schema()`), `gm_provider.gd`, then the three providers.
- [Making HTTP requests](https://docs.godotengine.org/en/stable/tutorials/networking/http_request_class.html) in Godot.
- [Ollama structured outputs](https://docs.ollama.com/capabilities/structured-outputs): what the local provider relies on.
- The Claude API docs on [structured outputs](https://docs.claude.com/en/docs/build-with-claude/structured-outputs)
  and [prompt caching](https://docs.claude.com/en/docs/build-with-claude/prompt-caching): what the Claude provider relies on.
- The papers listed in [RESEARCH.md](RESEARCH.md#sources) under "AI game master". Start with CALYPSO and FIREBALL.

**Do**
1. Install [Ollama](https://ollama.com), run `ollama pull llama3.1:8b`, pick "Local LLM" in the menu and play a few rooms.
   Type odd things into the GM box. Note when the model breaks the rules.
2. **First real feature: advantage/disadvantage on ability checks.** It touches every layer, and
   `CLAUDE.md` lists the steps: a schema field in `build_schema()`, validation in `_apply_gm_action()`,
   a line in `gm_system.md`, and a test. `Dice.d20(mode)` already supports it.

**Check:** you can explain why the GM is treated as "untrusted input", and what the worst
thing a broken model reply can do.

---

## Later, when you need them

| Topic | Material | When |
|---|---|---|
| Networking | [High-level multiplayer](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html), then `network.gd` and [NETWORKING.md](NETWORKING.md) | Before touching LAN or Steam (M3) |
| Steam | [GodotSteam docs](https://godotsteam.com/) | M3 |
| Saving | [Saving games](https://docs.godotengine.org/en/stable/tutorials/io/saving_games.html) | M1 save/load |
| Game design | *A Theory of Fun* (Koster); *The Art of Game Design* (Schell) | Any time |
| Roguelike design | [RogueBasin](https://www.roguebasin.com/), Brian Bucklew's and Josh Ge's talks on procedural generation | Unit 6 onward |
| Community | [Godot forum](https://forum.godotengine.org/), r/godot, the Godot Discord | When stuck |

## Suggested pace

| Week | Units |
|---|---|
| 1 | 1 and 2 (finish "Dodge the Creeps") |
| 2 | 3 and 4 |
| 3 | 5 |
| 4 | 6 and 7 |
| 5 | 8, ending with your first real feature as a pull request |
