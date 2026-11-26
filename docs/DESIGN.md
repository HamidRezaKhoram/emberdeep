# Game design

## Pitch

A tabletop-style dungeon crawl for 1-6 friends on one couch or one network. An AI game
master describes every room, voices every creature and asks for rolls; the dungeon itself is
built room by room as you open doors, so no two delves are alike and the map never ends
before your curiosity does. Rules follow the fifth-edition SRD 5.2.1, so tabletop players
already know how to play.

## Pillars

1. **It feels like a real table.** Free-text "I try to..." always gets an answer. The GM asks
   for checks, creatures talk and lie, consequences stick.
2. **Fair dice.** The engine owns every number. The AI can't fudge rolls, invent HP, or kill a
   hero by narration. Players can trust the game.
3. **The unknown behind every door.** The map grows as you explore; the GM learns what's in
   a room the moment the party does.
4. **Friends first.** Hot-seat on one screen, LAN, or Steam. One host runs the world and the GM.

## Core loop

```
explore (free movement) -> open a door -> engine builds the room + rolls contents
   -> GM narrates -> players talk / act / poke things -> GM asks for checks -> engine rolls
   -> monsters?  -> combat (initiative, turns) -> loot, rest, deeper
```

- **Exploration mode:** each hero moves freely. Typing in the box sends "what I say or do"
  to the GM. Stepping on a gold door opens it.
- **Who notices whom:** creatures placed in a room start asleep. One wakes when a conscious
  hero is in its room, or within 8 squares (40 ft) with line of sight, or when it is attacked.
  Creatures the GM adds (an alarm) arrive awake. Only awake creatures fight, so a fight is
  local: the rest of the dungeon stays where it is.
- **Combat mode:** starts when a creature wakes. Initiative = d20 + DEX modifier; ties go to the
  higher Dexterity score, then heroes before monsters. A creature that wakes mid-fight joins at
  its place in the order. On your turn: move up to 6 squares (30 ft) and take one action: attack
  (walk into a foe) or tend a dying ally (walk into them). Space ends the turn.
- **Monsters** chase the nearest hero they can reach, along a real path (A*). A creature that
  has had no route to the party for 2 of its turns loses track, goes back to sleep and leaves
  the fight. The fight ends when no creature is awake.
- **Dropping to 0 HP:** the hero is dying. At the start of each of their turns they roll a death
  saving throw (d20: 10+ success, natural 1 = two failures, natural 20 = back up with 1 HP).
  Three successes: stable. Three failures: dead. An ally can walk into a dying hero to stabilize
  them with a DC 10 Wisdom (Medicine) check (their action in combat; retry freely outside it).
  *Simplification until rests exist:* a stable hero comes to with 1 HP once no fight is going on
  (the rules say 1d4 hours). The delve ends when no hero is conscious.
- **Depth:** each room's depth is its distance in doors from the entrance. Encounter budget grows
  with depth (see `_populate_room` in `game_state.gd`).

## Rules scope (SRD 5.2.1)

Skeleton today: ability scores and modifiers, proficiency bonus, d20 tests, ability checks
with DCs, attack rolls (natural 20 crits, natural 1 misses), damage dice with crits doubling the
dice, AC, HP, initiative (Dexterity breaks ties), speed in 5-ft squares, death saving throws,
stabilizing (Wisdom (Medicine) DC 10). One pregenerated level-1 Fighter.

Next, in order (see [ROADMAP.md](ROADMAP.md)): character creation (species, background,
classes: Fighter, Rogue, Cleric, Wizard first), skills and proficiency, advantage/disadvantage
from conditions, healing potions, short/long rests, opportunity attacks, ranged attacks
and cover, spells (a curated SRD subset), conditions, XP and levels 1-5, equipment and
potions, stealth and surprise.

Keep rules **data-driven**: stat blocks, spells and items live in `game/data/srd/*.json` so
content grows without code changes.

## The AI game master's job

| The engine does | The GM does |
|---|---|
| Builds rooms, places creatures and loot by rule | Describes rooms, gives creatures motives |
| Rolls every die, applies damage | Decides *when* a check is needed and its DC |
| Runs initiative, movement, attacks | Narrates hits, deaths and aftermath |
| Enforces budgets (spawns, DCs) | Proposes a reinforcement or a clue item, rarely |
| Keeps the record (log, state) | Keeps the story consistent with that record |

The GM may only change the world through the action list in its reply; see
[AI_GAME_MASTER.md](AI_GAME_MASTER.md).

## Presentation

- Top-down 2D grid, 24 px tiles today (colored shapes). Target: 16x16 or 32x32 pixel-art
  tileset in a TileMapLayer with fog of war; optional 3/4 "semi-2D" wall faces later.
- Right-hand panel: party status, narration log (GM text in warm italics, rolls in green,
  combat in red), and a text box for talking to the GM.
- Later: character sheets, portraits, dice animation, ambient sound per room kind, a
  "story so far" journal written by the GM.

## Content and tone

Dark fantasy with warmth and humor; violence at tabletop level, not gore. The GM prompt sets
tone in `game/data/prompts/gm_system.md`. Player text goes only to the GM provider the host chose;
with Local LLM or Offline, nothing leaves the host machine.

## Open questions

- Party size cap: 4 hot-seat feels right; 6 over LAN?
- Should the GM be able to *end* a fight (creatures surrender/flee) through an action?
- Persistent world between sessions (campaign mode) or single delves (roguelite)? Leaning: both,
  with a campaign save that stores seed + opened doors + story summary.
- How much should players see of the GM's "plans"? A visible quest log is likely helpful.
