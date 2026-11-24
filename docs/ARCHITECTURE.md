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
5. **Data over code.** Monsters, prompts (and later spells, items, classes) are files in `game/data/`.

## Files

| Path | Role |
|---|---|
| `game/scripts/core/game_state.gd` | Autoload `GameState`. Heroes, monsters, items, modes, initiative, log. Intent handling, combat, room population, GM action validation, snapshots. |
| `game/scripts/core/dice.gd` | `Dice`: seeded roller, `NdM+K` parser, d20 with advantage. |
| `game/scripts/core/rules.gd` | `Rules`: SRD math (modifiers, checks, attacks, damage). Pure functions. |
| `game/scripts/core/settings.gd` | `Settings`: `user://settings.cfg`, API key from env. |
| `game/scripts/world/dungeon_generator.gd` | `DungeonGenerator`: door-driven room accretion, fog of war. |
| `game/scripts/world/map_view.gd` | Draws revealed tiles and tokens; camera follows the acting hero. |
| `game/scripts/net/network.gd` | Autoload `Net`: ENet host/join, intents, snapshots, LAN beacon. |
| `game/scripts/gm/game_master.gd` | `GameMaster`: event queue, prompt + history, schema, provider fallback. |
| `game/scripts/gm/*_provider.gd` | `GMProvider` base + Anthropic, local OpenAI-compatible, offline. |
| `game/scripts/main.gd` | Menu and HUD, built in code; keyboard input → intents. |
| `game/data/srd/monsters.json` | Stat blocks (placeholders until checked against SRD 5.2.1). |
| `game/data/prompts/gm_system.md` | The GM system prompt. |
| `game/tests/` | Headless test scene (`scripts/run-tests.sh`). |

## State shapes

Hero: `{id, name, owner, class, level, abilities{str..cha}, hp, max_hp, ac, attack_bonus,
damage, weapon, pos: Vector2i, moves_left, has_action, inventory[], color}`

Monster: `{id, key, name, pos, hp, max_hp, ac, attack_bonus, damage, speed, dex, awake, room}`

Room: `{id, rect: Rect2i, depth, kind, center, entry}`

Intent: `{type: "move"|"end_turn"|"say", actor: hero id, dir?: Vector2i, text?: String}`

GM event: `{kind: "room_revealed"|"player_action"|"check_result"|"combat_over", text, actor, chain}`

## Known shortcuts (fine for a skeleton, fix as we grow)

- Snapshots send the whole state; the map only when it changed. Switch to deltas when rooms number in the hundreds.
- UI is built in code. Move to scenes and a Theme once the layout settles.
- `room_at()` is a linear scan. Use a spatial index (tile → room id) when it shows up in a profile.
- No save/load yet. Plan: seed + `opened_doors` + heroes + monsters + log + GM summary, as JSON in `user://saves/`.
