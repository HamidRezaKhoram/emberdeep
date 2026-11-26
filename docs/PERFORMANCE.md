# Performance

The dungeon has no size limit, so the rule is: **the cost of one action must not grow with the
size of the world.** See "Scaling rules" in [ARCHITECTURE.md](ARCHITECTURE.md) for how the code
keeps to that: indexes for lookups, work only near the heroes, capped searches, cached drawing.

## Budgets

`scripts/bench.sh` grows a 300-room dungeon with 300 creatures, times the hot paths, and fails when
one goes over its budget in `game/tests/budgets.json`. CI runs it on every push.

| Measure | Budget | Measured (Apple Silicon laptop, 2026-11-25) |
|---|---|---|
| open a door (generate + fill the room) | 2 ms | 0.07 ms |
| `room_at`, `monster_at` | 0.01 ms | 0.0002 ms |
| awareness check (who wakes up) | 1 ms | 0.08 ms |
| a hero's step while exploring | 2 ms | 0.10 ms |
| a full round of a 20-monster fight | 10 ms | 1.9 ms |
| save write / load, 300 rooms | 400 / 800 ms | 11 / 28 ms |
| network snapshot without the map | 200 KB | 122 KB |
| draw the whole map (loading a game), 21k tiles | 1000 ms | 103 ms |
| repaint after a door opens (incl. generating it) | 2 ms | 0.08 ms |

Budgets are set well above the measured values so a slower CI machine passes. A regression that
changes how cost scales (an O(n) scan in a hot path) still blows through them. Tighten budgets
as the game matures; never loosen one to make a change pass without understanding why.

The 16.6 ms frame (60 fps) is the real limit: anything that runs in one frame, such as a whole
monster round, must stay well under it. That's why monsters beyond `chase_range` (balance.json)
don't run a path search at all: it cut a 20-monster round from 17 ms to 2 ms.

## Watching it in play

Press **F1** in a debug build for FPS, frame time and memory ([DEBUG.md](DEBUG.md)). For a deeper
look, run from the Godot editor and use the Debugger → Profiler and Monitors tabs.

## Targets

- 60 fps on a Steam Deck and on integrated graphics (Intel UHD 630 class), at 300+ rooms.
- No frame over 33 ms during play, including a big monster round or opening a door.

## Known next steps

- Network snapshots still send every monster on each change (122 KB at 300); switch to deltas
  of what changed (roadmap M3).
- The tile layer draws every revealed tile in one cached batch; move to `TileMapLayer` chunks
  when the art arrives.
