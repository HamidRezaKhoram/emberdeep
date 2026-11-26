# Assets: how art and sound get into the game

Drop a file with the right name in the right folder and the game uses it. No code, no
settings, no Godot editor needed. A file that's missing is drawn as today's colored shape (art)
or is silent (sound), so you can add things one file at a time.
[CONTENT_PLAN.md](CONTENT_PLAN.md) covers *making* the content; this page is the exact contract.

## Folders and names

```
game/art/
  tiles/floor.png  floor_2.png  floor_3.png     variants, picked per tile
  tiles/wall.png   wall_2.png                   plain walls (used if there is no autotile sheet)
  tiles/wall_autotile.png                       4x4 sheet of wall pieces (below); wins over wall.png
  tiles/door_closed.png  door_open.png  rubble.png
  regions/<region id>/tiles/...                 same names; overrides tiles/ in that region's rooms
  tokens/hero.png                               greyscale; tinted with each player's color
  tokens/hero_<class>.png                       e.g. hero_fighter.png; drawn as is, no tint
  monsters/<monster key>.png                    key from data/srd/monsters.json (giant_rat, goblin …)
  items/item.png  items/<item name>.png         name lower-case, spaces as _ ("old_coin.png")
game/audio/
  sfx/<sound>.wav|ogg                           names: CONTENT_PLAN.md "Integration contract: audio"
  music/explore.ogg  combat.ogg  defeat.ogg
  ambience/<room kind>.ogg                      spaces as _ ("well_room.ogg")
```

- **Size:** tiles and tokens are **32×32 px** PNGs. Bigger images use their top-left 32×32
  (or, for the autotile sheet, a grid of 32×32 pieces). Smaller ones are refused with a warning.
- **Variants:** `name.png`, `name_2.png`, `name_3.png` … up to `_9`, numbered **without gaps**
  (a missing `_2` hides `_3`). Tiles pick a variant from their position and the map's seed, so a
  tile always looks the same. Monsters pick one per creature. Sounds pick at random each time.
- **Most specific wins:** region art over default art; `hero_<class>` over `hero`;
  `monster_hit_<key>` over `monster_hit`; `items/<name>` over `items/item`.

## Wall autotiles

`tiles/wall_autotile.png` is **128×128**: 16 pieces of 32×32 in a 4×4 grid. Each wall picks
the piece that matches which of its four neighbours are also wall-like (wall, door or rubble):

| bit | neighbour |
|---|---|
| 1 | up |
| 2 | right |
| 4 | down |
| 8 | left |

Add up the bits of the neighbours that are walls; that's the piece number *m*, found at
column `m % 4`, row `m / 4` (counting from 0, top-left). For example:

```
 0: alone        1: up           2: right        3: up+right
 4: down         5: up+down      6: right+down   7: up+right+down
 8: left         9: up+left     10: left+right  11: up+left+right
12: down+left   13: up+down+left 14: left+right+down 15: all four
```

A horizontal wall run is piece 10, a vertical one piece 5, a room's top-left corner piece 6.
Variants work here too (`wall_autotile_2.png`). Draw doors as whole tiles: they replace the wall.

## Seeing your changes

- Running from the source folder (`"$GODOT" --path game`, or the editor), files are read
  straight from disk: no import step.
- In a running debug game press **F8**: data, art and sound are reloaded, so you can edit a PNG,
  save it, press F8 and see it.
- Exported builds use Godot's imported copies. Open the project in the Godot editor once (or run
  `scripts/run-tests.sh`, which imports) before exporting, so new files are included.

## How it works (for code)

- `AssetLibrary` (`scripts/view/asset_library.gd`): finds files by stem, collects variants,
  caches results including misses, `clear()` for reloads, `pick_variant()` for stable choices.
  In editor builds it reads raw files; in exports, imported resources.
- `MapView` (`scripts/world/map_view.gd`): draws tiles in a `TileMapLayer`. Each texture becomes
  a `TileSet` source the first time it's used. When a door opens, only the changed tiles and their
  neighbours are repainted (`DungeonGenerator.take_changes()`), so the cost doesn't grow with the
  map. Tokens are drawn with the same library, falling back to shapes.
- `AudioDirector` loads sounds through its own `AssetLibrary` rooted at `res://audio/`.
- Tests write PNGs to `user://` and check variants, region overrides, autotile pieces, fallbacks,
  and that repainting only the changes gives the same map as a full repaint.
