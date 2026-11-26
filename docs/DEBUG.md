# Debug tools

Available in **debug builds only**: running from the editor, `"$GODOT" --path game`, or a
`--export-debug` build. Release exports don't include them, and the rules ignore debug commands
unless `GameState.debug_enabled` is on.

## Keys

| Key | What |
|---|---|
| F1 | Stats overlay: version, FPS, frame time, memory, seed, rooms/tiles/doors, monsters (awake), mode, initiative, events, animation queue, inputs recorded, data errors, state hash |
| F2 | Spawn an awake monster in your room (cycles through the monster list) |
| F3 | Heal the whole party (also revives the dead) |
| F4 | Remove every awake monster, ending the fight |
| F7 | Slow motion (x0.25) for animations, to tune timing |
| F8 | Reload `game/data/` and the key bindings without restarting |
| F12 | Save a replay (works in every build; see [SAVES.md](SAVES.md)) |

## Commands

Type these in the GM text box (Enter):

| Command | What |
|---|---|
| `/spawn <monster> [count]` | e.g. `/spawn orc 3`, in your room |
| `/heal`, `/clear` | as F3, F4 |
| `/slowmo`, `/reload` | as F7, F8 |
| `/hash` | print the state hash (compare two machines or two runs) |
| `/help` | list commands |

## Launch flags

Put these after `--`, e.g. `"$GODOT" --path game -- --play --seed=42 --heroes=2 --overlay`.

| Flag | What |
|---|---|
| `--play` | skip the menu: start a local game at once |
| `--seed=N`, `--heroes=N` | with `--play` |
| `--overlay` | start with the F1 overlay on (handy for performance screenshots) |
| `--smoke [--steps=N] [--shot=file.png] [--record=file.replay]` | a bot plays through real key events |
| `--replay=file [--watch]` | verify or watch a replay |

## Rules for debug commands

Commands that change the game (spawn, heal, clear) are **inputs like any other**: they go through
`GameState.handle_intent` as `{type: "debug", op: ...}`. So:
- they're recorded, and replays reproduce them (the replay remembers that debug was allowed);
- they keep every invariant (indexes, initiative, combat start and end);
- only the host's own player (peer 1) can send them, so LAN guests can't cheat in a debug host.

View-only tools (overlay, slow motion, reload) don't touch the rules.

Adding a command: handle a new `op` in `GameState._intent_debug()`, add a `/word` in
`DebugTools.run()`, and optionally a key in `data/input/bindings.json` (`"debug": true`).
