# Map generation

## How it works now: door-driven room accretion

1. The **start room** (7x6, "entrance hall") is carved at the origin with one unexplored door
   on each wall.
2. An **unexplored door** is a promise. Its record holds the room it belongs to and the
   direction it faces.
3. When a hero steps on it, `open_door(p)` seeds an RNG from `hash(world_seed | "door:x,y")`
   and tries up to 8 layouts: a corridor of 1-4 tiles, then a room 4-9 deep and 4-8 wide,
   shifted sideways at random. The last 4 tries use small rooms with a 1-tile corridor.
4. A layout **fits** if the room plus its wall ring, and the corridor plus its side walls, are
   all empty (`VOID`). So rooms never overlap and always have walls between them.
5. If one fits: carve corridor and room, make both ends `DOOR_OPEN`, pick a room kind, and
   add new unexplored doors on the other three walls (60% each, 40% past depth 6).
   If nothing fits: the door becomes `RUBBLE`.
6. **Frontier guarantee:** if no unexplored door is left anywhere, one is punched into the newest
   room that has space. The dungeon never seals itself.
7. The engine **populates** the room (`GameState._populate_room`, seeded by room id): 45% chance
   of a monster group within a depth-based CR budget, 30% chance of an item.
8. The GM gets the room's facts and describes it.

Properties (covered by `game/tests/test_main.gd`): deterministic per seed and door order, no
overlapping rooms, every room reachable from the start, at least one unexplored door left.

## Why not BSP / WFC for the whole level

They need the level's bounds up front. We want the map to exist only where the party has
been, and to let the GM influence what comes next. Accretion gives that for free.
See [RESEARCH.md](RESEARCH.md#3-map-generation-as-you-go).

## Roadmap

1. **Room shapes:** L-shapes, circles, pillared halls, caves via cellular automata inside the
   room's footprint, WFC set pieces from hand-made tiles.
2. **Regions and themes:** depth bands (sewers → crypts → caverns → ruined city) that change
   tiles, room kinds, monster tables and the GM's tone.
3. **Loops:** sometimes join a new room to a nearby existing one (a second door) so the map is
   not a pure tree. Needs a check for corridor paths through void.
4. **GM hooks:** the GM can tag an unexplored door with a theme ("smells of incense"); the
   generator uses it to pick the room kind and contents.
5. **Stairs:** a "down" room that starts a new level with a new seed offset; levels unload
   when the party leaves.
6. **Doors as gameplay:** locked (check or key), trapped, secret (Perception check reveals).
7. **Art:** replace shape drawing with a TileMapLayer + autotiled walls; light radius and
   remembered-but-not-visible tiles for fog of war.

## Saves

Because the room behind a door depends only on (seed, door position), a save needs only the
seed and `opened_doors` in order to rebuild the map exactly. Monsters, items and heroes are
saved separately. (Changing the generator breaks old saves, so version the generator.)
