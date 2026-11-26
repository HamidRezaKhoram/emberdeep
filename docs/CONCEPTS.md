# Concepts explained, with examples from Emberdeep

Companion to [LEARNING.md](LEARNING.md). Each section says what the concept is, why it matters
here, and points at real code in this repo. Read a section, then open the file it names.

---

## 1. GDScript, Godot's language

GDScript looks like Python: indentation (tabs) instead of braces, `func` instead of `def`, no semicolons.
Unlike Python, it is built into the engine and knows about engine types like `Vector2i` and `Node`.

### Variables and types

```gdscript
var hp = 10            # dynamic: any type
var hp: int = 10       # typed: the editor and the engine check it
var hp := 10           # typed by inference: := means "use the type of the value"
const SPEED_TILES := 6 # never changes
```

Types catch mistakes before you run the game and make autocomplete work. The repo's rule
is to type everything you can (`CLAUDE.md`).

Types you'll see constantly:

| Type | What | Example in the repo |
|---|---|---|
| `int`, `float`, `bool`, `String` | the basics | `var round_num: int = 0` |
| `Vector2i` | a pair of integers, a grid position | `hero["pos"]`, `Vector2i.UP` is `(0, -1)` |
| `Rect2i` | a rectangle on the grid | a room's `rect` |
| `Array` | a list | `initiative`, a list of actor ids in turn order |
| `Dictionary` | key → value map | every hero, monster and room is a Dictionary |

### Dictionaries are the game's data

Heroes are not classes here. They're dictionaries:

```gdscript
var hero: Dictionary = players[actor_id]
hero["hp"] = maxi(0, int(hero["hp"]) - dmg)
var dc := int(a.get("dc", 10))       # .get(key, default) never crashes on a missing key
```

That's why you see `int(...)` and `str(...)` wrapped around reads: a dictionary value has no fixed
type, so the code converts it to the type it expects. Dictionaries also turn into JSON easily,
which matters for snapshots, saves and the AI.

### Functions

```gdscript
static func ability_modifier(score: int) -> int:
	return floori((score - 10) / 2.0)
```

- `-> int` is the return type; `-> void` returns nothing.
- `static` means you call it on the class, `Rules.ability_modifier(16)`, without creating an object.
- A leading `_` (`_intent_move`) is a convention for "private, only this file calls it".
- `##` comments above a function are doc comments; the editor shows them as help.

### Classes

Every `.gd` file *is* a class.

```gdscript
class_name Dice          # gives the file a global name you can use anywhere
extends RefCounted       # what it inherits from
```

- `extends RefCounted` makes a plain object, freed automatically when nothing references it
  (`Dice`, `Rules`, `DungeonGenerator`).
- `extends Node` makes something that can live in the scene tree and get engine callbacks
  (`GameMaster`, the providers).
- `extends` also works for your own classes: `class_name OfflineProvider` / `extends GMProvider`.
  The child overrides `request_turn()`; the rest comes from the parent. This is how three AI
  backends share one interface.

### Control flow

```gdscript
match kind:                    # like switch
	"move": ...
	"end_turn": ...

for id in initiative: ...      # loop over an array
for i in 4: ...                # 0, 1, 2, 3

initiative.sort_custom(func(a, b): return rolls[a] > rolls[b])   # a lambda (inline function)
```

**Read in the repo:** `core/dice.gd` and `core/rules.gd`. Together they cover almost all of the above.

---

## 2. How Godot is put together

### Nodes and the scene tree

A Godot game is a **tree of nodes**. Each node does one job: `Camera2D` follows something,
`Label` shows text, `HTTPRequest` makes web calls. A **scene** is a saved tree of nodes (a `.tscn` file)
you can reuse.

Emberdeep's tree at runtime, roughly:

```
root
├── GameState      (autoload)
├── Net            (autoload)
└── Main           (scenes/main.tscn, script main.gd)
    ├── MapView    (Node2D, draws the dungeon)
    │   └── Camera2D
    ├── CanvasLayer (UI on top of the map)
    │   ├── menu…
    │   └── HUD: status Label, log RichTextLabel, LineEdit
    └── GameMaster
        ├── provider (e.g. LocalLLMProvider)
        │   └── HTTPRequest
        └── OfflineProvider (fallback)
```

Most Godot tutorials build these trees by dragging nodes in the editor. This project builds
them **in code** (`Node.new()` then `add_child()`), see `main.gd` `_ready()`. Same result,
different style; don't be thrown when tutorials look different.

### Lifecycle callbacks

Godot calls these functions on your node at the right moments. You just define them:

| Function | Called when | Used in |
|---|---|---|
| `_init()` | the object is created | `Dice._init(seed)` |
| `_ready()` | the node and its children entered the tree | `main.gd` builds the UI here |
| `_process(delta)` | every frame; `delta` = seconds since last frame | `map_view.gd` slides the camera |
| `_draw()` | after `queue_redraw()` asks for it | `map_view.gd` draws tiles and tokens |
| `_unhandled_input(event)` | a key or click nothing else used | `main.gd` turns keys into intents |

### Signals

A **signal** is a message an object sends without knowing who's listening (the observer pattern).

```gdscript
# game_state.gd: declare and emit
signal changed
signal log_added(entry: Dictionary)
...
changed.emit()

# main.gd: subscribe
GameState.changed.connect(_on_state_changed)
GameState.log_added.connect(_on_log)

# network.gd: another subscriber to the same signal
GameState.changed.connect(func(): _dirty = true)
```

When the state changes, the HUD redraws *and* the network marks a snapshot to send, but
`GameState` never mentions either of them. That's the point: game logic doesn't depend on UI or networking.

Godot's own nodes have signals too: `HTTPRequest.request_completed`, `Button.pressed`,
`multiplayer.server_disconnected`.

### Autoloads (singletons)

An **autoload** is a node Godot creates at startup and keeps for the whole game, reachable by
name from any script. Emberdeep has two, listed in `project.godot`:

```ini
[autoload]
GameState="*res://scripts/core/game_state.gd"
Net="*res://scripts/net/network.gd"
```

So any script can write `GameState.players` or `Net.send_intent(...)`. Use autoloads sparingly:
they're global state. Here they're justified because there's exactly one game and one network connection.

### `res://` and `user://`

- `res://` is the project folder (`game/`). Read-only in an exported game.
- `user://` is a per-user writable folder (settings, saves). On a Mac:
  `~/Library/Application Support/Godot/app_userdata/Emberdeep/`.

---

## 3. The fifth-edition rules

Everything here is in the free [SRD 5.2.1](https://www.dndbeyond.com/srd); `rules.gd` is the code version.

### Ability scores and modifiers

Six abilities: Strength, Dexterity, Constitution, Intelligence, Wisdom, Charisma. Each has a
**score** (usually 8-18) and a **modifier**, which is what you actually add to rolls:

```
modifier = floor((score - 10) / 2)       8 → -1   10 → +0   14 → +2   16 → +3   18 → +4
```

### Proficiency bonus

A bonus for things your character is trained in (weapons, skills, some saves). It grows with level:
+2 at levels 1-4, +3 at 5-8, +4 at 9-12, and so on. `Rules.proficiency_bonus(level)`.

### The d20 test, the core mechanic

Almost everything uncertain is: **roll a d20, add a modifier, compare with a target number.**
Meet or beat it and you succeed. There are three kinds:

| Kind | When | Target | Example |
|---|---|---|---|
| **Ability check** | you *try* something | a DC (Difficulty Class) the GM sets: 10 easy, 15 medium, 20 hard | force a stuck door: Strength check, DC 15 |
| **Saving throw** | you *resist* something | a DC set by the effect | dodge a fire trap: Dexterity save, DC 13 |
| **Attack roll** | you attack | the target's **AC** (Armor Class) | longsword vs goblin: d20 + attack bonus vs AC 15 |

Under the 2024 rules, natural 20s and 1s matter **only on attack rolls**: a 20 always hits and is a
**critical hit** (roll the damage dice twice), a 1 always misses. `rules.gd` follows this.

**Advantage / disadvantage:** roll two d20s and keep the higher (advantage) or lower
(disadvantage). They cancel out if you have both. `Dice.d20(mode)` already does it; nothing calls it with a mode yet.

### Combat

1. **Initiative:** everyone rolls d20 + Dexterity modifier. Highest goes first. (`_start_combat()`)
2. **On your turn:** move up to your speed (30 ft = 6 squares of 5 ft) and take one action, usually an attack.
3. **Damage:** roll the weapon's dice plus modifier (`"1d8+3"`) and subtract from HP.
4. **0 HP:** a monster dies; a hero falls **unconscious** and starts making **death saving throws**:
   d20 each turn, 10+ is a success, 3 successes = stable, 3 failures = dead, a natural 20 = back up
   with 1 HP. The game doesn't do death saves yet (it's an M1 roadmap item), which is why heroes just stay at 0.

### Monster stat blocks

A monster's numbers: AC, HP (as dice, e.g. `2d8+4`), speed, attack bonus, damage, and a
**CR** (Challenge Rating, roughly how dangerous). The game uses CR as a budget when filling rooms
(`_populate_room()`). See `data/srd/monsters.json`.

---

## 4. The codebase's core ideas

These are design decisions. Understanding *why* each exists matters more than the code.

### One source of truth

Only `GameState` changes game state. The UI reads state and redraws; it never sets `hero["hp"]`.
If two places could change HP, they'd eventually disagree, and in multiplayer every machine would
show something different.

### Intents

Players don't change the world, they send an **intent**: a request, as a small dictionary.

```gdscript
# main.gd: a key press becomes an intent
Net.send_intent({"type": "move", "dir": Vector2i.UP, "actor": _acting_id()})

# network.gd: on the host, handle it right away; on a client, send it to the host (peer 1)
func send_intent(intent: Dictionary) -> void:
	if is_authority():
		GameState.handle_intent(local_peer_id(), intent)
	else:
		_rpc_intent.rpc_id(1, intent)

# game_state.gd: the host checks it before acting
if int(hero["owner"]) != sender:
	return            # you can't move someone else's hero
```

The neat result: single-player, hot-seat and LAN all use **the same code path**. Single-player
is just "I'm the host and the only player".

### Determinism (seeded randomness)

A computer's "random" numbers come from a formula started by a **seed**. Same seed, same sequence.
Emberdeep routes every roll through `Dice` or `DungeonGenerator.rng_for()`:

```gdscript
func rng_for(key: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash("%d|%s" % [world_seed, key])    # e.g. key = "door:12,-4"
	return r
```

Each door gets its own random stream from (world seed, door position). So the room behind
a door is always the same, no matter which doors you opened first. That gives you:

- **Tests** that can assert exact results.
- **Saves** that only need the seed and the list of opened doors to rebuild the whole map.
- **Bug reports** you can replay: "seed 42, open the north door, crash".

One stray `randi()` breaks all three, which is why `CLAUDE.md` forbids it.

### Tests

`game/tests/test_main.gd` is a scene that runs checks and quits with exit code 0 (pass) or 1 (fail).
`scripts/run-tests.sh` runs it without a window (`--headless`). CI runs it on every push.

```gdscript
check(Dice.parse("3d7").is_empty(), "reject d7")
```

Habit to build: run tests before you change anything (so you know they passed), and after.

### The AI is untrusted input

The model's reply is treated like input from a stranger: parsed, then every action is checked.

```gdscript
var dc := clampi(int(a.get("dc", 10)), 5, 30)         # no DC 999
if not monster_table.has(key) or rid < 0: return       # no invented monsters
count = mini(count, MAX_GM_SPAWNS_PER_ROOM - ...)      # no infinite spawns
```

The worst a broken or "creative" model can do is write odd narration. It can't kill a hero,
fudge a roll or crash the game. That's design pillar 2, "Fair dice" ([DESIGN.md](DESIGN.md)).

### Data over code

Monsters live in `data/srd/monsters.json`, the GM prompt in `data/prompts/gm_system.md`.
Adding a monster is editing a file, not writing code. Spells, items and classes should follow the same pattern.

---

## 5. Game-programming skills

### Grids

The dungeon is a grid of tiles keyed by `Vector2i`. Things you'll do constantly:

- **Neighbours:** `pos + Vector2i.UP` etc. (`DungeonGenerator.DIRS`). Four directions today.
- **Manhattan distance:** `abs(dx) + abs(dy)`, the number of steps when you can't move diagonally (`_manhattan()`).
- **Tile → pixels:** `Vector2(p * TILE)`, where `TILE = 24` (`map_view.gd` `_px()`).

### Pathfinding (A\*)

Monsters currently move greedily: each step, go to whichever neighbour is closest to the hero.
That gets stuck behind any wall between them.

**A\*** finds the actual shortest path. It explores outward from the start, always expanding the
square with the lowest *(steps so far + estimated steps left)*. The estimate (a "heuristic") is
the Manhattan distance. Red Blob Games' [interactive introduction](https://www.redblobgames.com/pathfinding/a-star/introduction.html)
is the best explanation anywhere.

You don't have to write it: Godot has `AStarGrid2D`.

```gdscript
var astar := AStarGrid2D.new()
astar.region = Rect2i(-50, -50, 100, 100)
astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
astar.update()
astar.set_point_solid(wall_pos, true)          # for each wall
var path := astar.get_id_path(monster_pos, hero_pos)   # Array of Vector2i
```

You'll also need it for click-to-move (M2) and for line of sight with ranged attacks (M1).

### Procedural generation

Making content with an algorithm instead of by hand. The classic dungeon techniques:

| Technique | Idea | Good for |
|---|---|---|
| **BSP** | split a rectangle in two, repeatedly, put a room in each piece | tidy room-and-corridor levels |
| **Cellular automata** | random noise, then "a wall with 5+ wall neighbours stays a wall", repeated | caves |
| **Drunkard's walk** | a digger wanders randomly, carving floor | winding tunnels |
| **Wave function collapse** | place tiles so every neighbour pair is allowed | set pieces from example tiles |
| **Accretion** (Emberdeep) | add rooms one at a time to the edge of what exists | growing the map as you explore |

The first four need the whole level's bounds up front. Emberdeep wants the map to exist only
where you've been, so it uses accretion: each unexplored door is a promise, and opening it tries
up to 8 corridor + room layouts that fit in empty space ([MAP_GENERATION.md](MAP_GENERATION.md)).
The others can still be used *inside* a room, e.g. cellular automata for a cave room.

### Drawing with `_draw()`

`map_view.gd` draws everything with shape calls:

```gdscript
func _draw() -> void:
	for p in dungeon.revealed:
		draw_rect(Rect2(_px(p), Vector2(TILE, TILE)), COLORS[t])
	draw_circle(center, TILE * 0.4, hero_color)
```

Godot doesn't call `_draw()` every frame. It runs once, the result is cached, and it runs again only
after `queue_redraw()`. `main.gd` calls that whenever `GameState.changed` fires. Simple, and fine
for a few hundred tiles.

### `TileMapLayer` (for real art, M2)

A node that draws a grid of images from a **TileSet** (a sprite sheet cut into tiles):

```gdscript
tile_layer.set_cell(Vector2i(3, 5), source_id, Vector2i(0, 0))   # grid pos, which sheet, which tile in it
```

TileSets support **terrains** (autotiling: pick the right wall corner automatically) and
per-tile collision. Tutorials older than Godot 4.3 use the deprecated `TileMap` node; use `TileMapLayer`.

### UI text with BBCode

The narration log is a `RichTextLabel`, which understands BBCode tags:

```gdscript
log_label.append_text("[color=#f0d9a0][i]%s[/i][/color]\n" % text)   # GM text: warm italics
```

Note the line before it: `text.replace("[", "[lb]")`. That escapes `[` so a player (or the AI)
can't type `[color=red]` and inject formatting. Same idea as escaping HTML on a website.

---

## 6. The AI side

### HTTP requests in Godot

`HTTPRequest` is a node: you call `request()`, and later it emits `request_completed`
with the result. It doesn't block the game while waiting.

```gdscript
# gm_provider.gd
_http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
...
func _on_http_done(result, code, _headers, body):
	_handle_response(code, body.get_string_from_utf8())
```

Every provider shares this; each just builds a different `body` and reads a different reply shape.

### Chat APIs: system prompt and messages

Language models are called with:

- a **system prompt**: standing instructions (`data/prompts/gm_system.md`: "you are the GM, the engine rolls dice, describe only listed creatures…")
- a list of **messages**: alternating `user` and `assistant` turns, the conversation so far

Models have no memory between calls. Each request has to carry everything the model needs.
Emberdeep sends the last 24 messages plus a fresh `STATE: {...}` block with the facts that matter now
(party HP, current room, creatures). Old turns get dropped; the facts survive in STATE.

### Structured outputs (forcing JSON)

If you ask a model "reply in JSON", it usually does, but not always. **Structured outputs**
make the server constrain generation to a JSON Schema, so the reply always parses.

```gdscript
# game_master.gd build_schema(), simplified
"type": {"type": "string", "enum": ["ability_check", "spawn_monster", "place_item", "none"]},
"monster": {"type": "string", "enum": monster_keys},    # filled from monsters.json at runtime
```

The `enum` means the model literally can't name a monster the engine doesn't have.
Structured outputs guarantee the *shape*; the engine's validation (section 4) still checks the *values*.

### Running a model locally with Ollama

[Ollama](https://ollama.com) downloads and runs open models on your machine and serves them at
`http://127.0.0.1:11434` with the same API shape as OpenAI's (`/v1/chat/completions`), so one
provider (`local_llm_provider.gd`) works with Ollama, llama.cpp and LM Studio.

```bash
ollama pull llama3.1:8b
```

Then pick "Local LLM" in the game menu. An 8B model runs fine on an Apple Silicon Mac. It's free and
private, but it follows rules less reliably than a large hosted model like Claude. Watch it invent
creatures or decide outcomes itself; that's exactly what the prompt and validation guard against.

### Why the engine owns the facts

Research the repo cites ([RESEARCH.md](RESEARCH.md#2-the-ai-game-master)) found that language models
are bad at tracking game state over a long session, and hallucinate less when the relevant facts
are given to them each turn. So the split is:

| Engine (code) | AI (model) |
|---|---|
| map, HP, positions, every dice roll | descriptions, voices, motives |
| decides what's *true* | decides how it *feels*, and when to ask for a roll |

Keep this split in mind for every AI feature you add.
