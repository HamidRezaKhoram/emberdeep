# Saves and replays

## Saves

**F5** quick-saves, **F9** quick-loads, and the menu's **Continue** button loads the quick save.
Files go to `user://saves/<slot>.sav` (macOS: `~/Library/Application Support/Godot/app_userdata/Emberdeep/saves/`).

What's stored (`GameState.to_save()`): seed, the doors opened (in order), heroes, monsters, items,
mode, initiative, log, id counters, the dice's RNG state, and the AI game master's conversation.
**The map isn't stored.** It's rebuilt from the seed and the opened doors (the generator is
deterministic), then checked against a hash of the saved map.

The test suite proves that loading a save and playing on gives exactly the same game as never
having stopped.

### Versioning

| Field | Meaning | On mismatch |
|---|---|---|
| `format` | layout of the save file (`SaveGame.FORMAT`) | older: migrated step by step in `SaveGame._migrate()`; newer: refused ("from a newer version") |
| `generator_version` | the dungeon rules (`data/rules/dungeon.json`) | refused: the map can't be rebuilt |
| `map_hash` | SHA-256 of every tile | refused if the rebuilt map differs |
| `data_fingerprint` | SHA-256 of all `game/data/` files | loads, with a warning in the log (balance changed) |
| `game_version` | `application/config/version` in `project.godot` | informational |

**When you change the save layout:** bump `SaveGame.FORMAT`, add a migration step from the old
format, and add a test that loads an old-format save.
**When you change dungeon generation:** bump `generator_version` in `dungeon.json`.

### Safety

- Saves use Godot's binary Variant format, read with objects **disallowed**, so a save file
  someone sends you can hold data but never run code. Exact types survive (ints stay ints,
  `Vector2i` stays `Vector2i`), unlike JSON.
- Writes go to a `.tmp` file that is then renamed over the old save, so a crash mid-save never
  destroys the previous one.
- A save that fails a check is refused before anything in the running game changes.
- LAN: only the host can save. Loading is local only; every hero becomes the local player's.

## Replays

The game records how it started (new game with a seed, or a save) and **every input to the
rules**, in order: player intents, applied AI game master replies, players joining or leaving.
That's `GameState.recording`. Since the rules are deterministic, replaying the inputs reproduces
the game exactly. The AI's replies are recorded, so its randomness doesn't matter.

- **F12** saves the current game's replay to `user://replays/<date>.replay` and prints the path.
  Attach it to a bug report.
- Check that a replay reproduces (exit code 0 if it does):
  ```bash
  "$GODOT" --headless --path game -- --replay=path/to/file.replay
  ```
- Watch it play:
  ```bash
  "$GODOT" --path game -- --replay=path/to/file.replay --watch
  ```
- The smoke bot can record one: `-- --smoke --record=out.replay`.

A replay stores the hash of the final state, so a mismatch means the rules' behavior changed
(intended or a bug). It also records the generator version and data fingerprint, and reports when
the data has changed since it was recorded.
