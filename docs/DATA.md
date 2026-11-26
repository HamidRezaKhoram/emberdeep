# Game data

Every rules number and piece of content lives in `game/data/`, not in code. Code reads it through
`GameData` (`game/scripts/core/game_data.gd`) as typed values, such as `GameData.balance.sight_tiles`.
To tune the game, edit a file; no code changes needed.

| File | What | Notes |
|---|---|---|
| `data/rules/balance.json` | speed, sight range, how fast creatures lose track, GM limits, encounter and item odds, CR budget by depth | safe to tune freely |
| `data/rules/dungeon.json` | room and corridor sizes, exit odds, room kinds, start room | **changes the map a seed makes**: bump `generator_version` |
| `data/rules/heroes.json` | character classes (one Fighter for now) | SRD 5.2.1 derived |
| `data/rules/items.json` | flavor item names | |
| `data/srd/monsters.json` | monster stat blocks | SRD 5.2.1 derived; placeholders until checked |
| `data/prompts/gm_system.md` | the AI game master's instructions | |

Keys starting with `_` (like `_note`) are comments and are ignored.

## Validation

`GameData.load_all()` checks every value: type, whole number vs fraction, allowed range, dice
expressions (`1d8+2`), required keys and sections, and repeated monster keys. Each problem is
reported as `file: key: what is wrong`, for example:

```
res://data/rules/balance.json: sight_tiles: expected a whole number, got 2.5
res://data/srd/monsters.json: monsters[3]: hp: 'lots' is not a dice expression like 1d8+2
```

A bad value falls back to a safe default (or is clamped into range), so the game still runs,
and the error is printed. The test suite fails if the shipped files have any error.

## Fingerprint

`GameData.fingerprint` is a SHA-256 of all data files. Saves and replays record it, so a game is
only reproduced against the rules it was played with.

## Adding a new tunable

1. Add the key to the JSON file, with a `_note` if it isn't obvious.
2. Add a typed field to the matching class in `game_data.gd` (`Balance`, `DungeonRules`, …) and
   read it with `r.int_()`, `r.float_()`, `r.dice()`, etc., giving a default and a range.
3. Use `GameData.<section>.<field>` in code. Never copy the number into a constant.
4. Add a check to `_test_game_data()` if the validation is new.
