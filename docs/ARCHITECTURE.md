# Architecture

```
                 HOST (or single-player machine)                              CLIENTS
 ┌──────────────────────────────────────────────────────────────┐      ┌──────────────────┐
 │  input ──► Net.send_intent ──► GameState.handle_intent ◄──────┼──────┤ Net._rpc_intent  │
 │                                    │   (validates owner,       │      │                  │
 │                                    │    rules, dice)           │      │                  │
 │                     DungeonGenerator◄─┤ open_door             │      │                  │
 │                                    │                           │      │                  │
 │                         gm_event ──┼──► GameMaster ──► GMProvider ──► Claude / local LLM / offline
 │                                    │        ▲                  │      │                  │
 │       GameState.apply_gm_response ◄┼────────┘ JSON {narration, │      │                  │
 │          (validates every action)  │                 actions}  │      │                  │
 │                                    ▼                           │      │                  │
 │                        changed ──► Net._process ──snapshot─────┼─────►│ apply_snapshot   │
 │                           └──► main.gd HUD + map_view redraw   │      │  └► HUD + map    │
 └──────────────────────────────────────────────────────────────┘      └──────────────────┘
```

## Principles

1. **One source of truth.** `GameState` (autoload) on the host. Clients never change it;
   they send intents and render snapshots.
2. **Everything is an intent.** Local keyboard, hot-seat, LAN peers all go through
   `Net.send_intent()` → `GameState.handle_intent(sender, intent)`. The sender's peer id must
   own the hero. This is why single-player and multiplayer share one code path.
3. **The AI is an untrusted input.** Its reply is parsed, then every action is validated like a
   player intent. A broken or hostile reply can at worst produce odd narration.
4. **Determinism.** Dice and generation are seeded. The map behind a door depends only on
   (seed, door position). Tests rely on this; so will saves and replays.
5. **Data over code.** Every rules number, monster, class, item and prompt is a file in `game/data/`,
   loaded and validated by `GameData` ([DATA.md](DATA.md)). Code holds no balance constants.
6. **Rules resolve, the view replays.** `GameState` resolves every action instantly and emits
   ordered events; the `Presenter` decides when the player *sees* them. Rules never wait on
   animation, and animation can't change the rules ([EVENTS.md](EVENTS.md)).

## Files

| Path | Role |
|---|---|
| `game/scripts/core/game_state.gd` | Autoload `GameState`. Heroes, monsters, items, modes, initiative, log. Intent handling, combat, room population, GM action validation, snapshots. |
| `game/scripts/core/game_data.gd` | `GameData`: loads and validates every file in `game/data/` into typed rules (balance, dungeon, classes, monsters, items); data fingerprint. See [DATA.md](DATA.md). |
| `game/scripts/core/dice.gd` | `Dice`: seeded roller, `NdM+K` parser, d20 with advantage. |
| `game/scripts/core/rules.gd` | `Rules`: SRD math (modifiers, checks, attacks, damage). Pure functions. |
| `game/scripts/core/save_game.gd` | `SaveGame`: versioned save files, checks, migrations. See [SAVES.md](SAVES.md). |
| `game/scripts/core/replay.gd` | `Replay`: write, read, run and verify recordings of every input. |
| `game/scripts/core/settings.gd` | `Settings`: `user://settings.cfg`, API key from env. |
| `game/scripts/world/dungeon_generator.gd` | `DungeonGenerator`: door-driven room accretion, fog of war, line of sight, O(1) `room_at()` through a tile → room index. |
| `game/scripts/world/pathfinder.gd` | `Pathfinder`: A* on the tile grid with a cap on tiles expanded, so cost doesn't grow with the map. Deterministic tie-breaking. |
| `game/scripts/world/map_view.gd` | Two layers: tiles in a `TileMapLayer` (only tiles a door opening changed are repainted, autotiled walls, art by file name) and tokens (sprites or shapes, animated, culled to the camera). Frame-rate-independent camera. See [ASSETS.md](ASSETS.md). |
| `game/scripts/debug/debug_tools.gd` | `DebugTools` (debug builds only): F1 overlay, spawn/heal/clear as recorded debug intents, slow motion, data hot reload, `/commands`. See [DEBUG.md](DEBUG.md). |
| `game/scripts/view/presenter.gd` | `Presenter`: plays `GameState.game_event`s back over time (slides, lunges, flashes, floating numbers), catches up when behind, snaps to the truth when idle. See [EVENTS.md](EVENTS.md). |
| `game/scripts/view/asset_library.gd` | `AssetLibrary`: finds art and sound files by name, variants, region overrides, cached; reads raw files in editor builds so new files need no import. |
| `game/scripts/view/audio_director.gd` | `AudioDirector`: sound effects on played events, music crossfade (explore/combat), ambience by room kind; files by name, missing = silent. |
| `game/scripts/net/network.gd` | Autoload `Net`: ENet host/join, intents, snapshots, LAN beacon. |
| `game/scripts/gm/game_master.gd` | `GameMaster`: event queue, prompt + history, schema, provider fallback. |
| `game/scripts/gm/*_provider.gd` | `GMProvider` base + Anthropic, local OpenAI-compatible, offline. |
| `game/scripts/main.gd` | Menu and HUD, built in code; input actions → intents. |
| `game/scripts/input/` | `InputBindings` (actions from `data/input/bindings.json` + player overrides), `MoveRepeater` (held-move repeat on the game clock). See [INPUT.md](INPUT.md). |
| `game/data/rules/*.json` | Balance, dungeon generation, hero classes, items. |
| `game/data/srd/monsters.json` | Stat blocks (placeholders until checked against SRD 5.2.1). |
| `game/data/prompts/gm_system.md` | The GM system prompt. |
| `game/tests/` | Headless test scene (`scripts/run-tests.sh`). |

## State shapes

Hero: `{id, name, owner, class, level, abilities{str..cha}, hp, max_hp, ac, attack_bonus,
damage, weapon, pos: Vector2i, moves_left, has_action, inventory[], color,
death_successes, death_failures, stable, dead}`

Monster: `{id, key, name, pos, hp, max_hp, ac, attack_bonus, damage, speed, dex, awake, room, lost_turns}`

## Scaling rules

The dungeon has no size limit, so per-action costs must not grow with it:

- **Indexes for lookups.** `GameState._monster_at_tile` (tile → monster) and `_awake_ids`, and
  `DungeonGenerator._room_of` (tile → room) make `monster_at()` and `room_at()` O(1). They are
  derived data: kept in step by the functions that move, spawn, remove, wake and sleep creatures
  (`move_monster`, `_spawn_monster`, `_remove_monster`, `_wake`, `_sleep`), rebuilt after a
  snapshot, and never sent over the network. Never assign `monster["pos"]` directly.
- **Local work only.** Awareness scans the tiles around each hero, not every creature.
  Path searches stop after `PATH_BUDGET` tiles. Only awake creatures enter initiative.
- **Measured** at 300 rooms / 21k tiles / 300 creatures: opening a door 0.06 ms, `room_at` and
  `monster_at` 0.2 µs each.

Room: `{id, rect: Rect2i, depth, kind, center, entry}`

Intent: `{type: "move"|"end_turn"|"say", actor: hero id, dir?: Vector2i, text?: String}`

GM event: `{kind: "room_revealed"|"player_action"|"check_result"|"combat_over", text, actor, chain}`

## Known shortcuts (fine for a skeleton, fix as we grow)

- Snapshots send the whole state; the map only when it changed. Switch to deltas when rooms number in the hundreds.
- UI is built in code. Move to scenes and a Theme once the layout settles.
- The map view redraws every revealed tile on each change; move to `TileMapLayer` (chunked, cached).
