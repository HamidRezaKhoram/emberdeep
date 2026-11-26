# Content plan: art, music, sound and story

How to make Emberdeep's content, and the **integration contract**: the folders, file names and
formats the code will look for. If you follow the contract, new files show up in the game with
no code changes. **The hooks are built** (Phase D); the exact rules are in [ASSETS.md](ASSETS.md).

Start with **story**, because it decides the look and the sound. Then art and audio can go in parallel.

---

## 1. Story

### What to write

Keep it short and usable. The AI game master reads it, so write facts and tone, not prose.

1. **One-page pitch:** what Emberdeep *is* (the place), why people go down, what's at the bottom.
   One paragraph each.
2. **Regions by depth.** The design doc already suggests sewers → crypts → caverns → ruined city.
   For each region: name, depth range, mood in three words, who lives there, what it looked like
   before it fell, two or three secrets.
3. **Factions:** two to four groups that want something down there, and how each treats the heroes.
4. **Named NPCs:** five to ten, each with a want, a fear and a way of speaking.
5. **Room kinds:** the game has `chamber, hall, shrine, crypt, storeroom, cavern, library, barracks,
   well room, kennel`. Give each one a line or two of description per region, and add new kinds.
6. **Monsters' roles:** why each of `giant_rat, goblin, skeleton, zombie, wolf, orc` is down there.
7. **Tone rules for the GM:** what's in bounds and what isn't (the current prompt says grim,
   mysterious, small moments of warmth and humor).

### Legal limits (from [LEGAL.md](LEGAL.md))

- Mechanics come from the SRD 5.2.1. Settings, gods, named characters and monsters must be **your own**.
- Never use "D&D", "Dungeons & Dragons", or any named setting from those books.
- If a monster isn't in the SRD 5.2.1, design your own instead.

### Workflow

1. Write freely in `docs/story/STORY_BIBLE.md`, which is for humans.
2. When a part settles, copy its facts into the data files below. That's what the game reads.
3. Playtest with a Local LLM or Claude as GM, and see whether the narration matches your tone.
   Adjust the bible, not just the prompt.

### Integration contract: story

| File | Format | Used by |
|---|---|---|
| `docs/story/STORY_BIBLE.md` | free Markdown | you, and contributors |
| `game/data/lore/world.md` | short Markdown, about 300-600 words: the facts every GM turn should know | appended to the GM system prompt |
| `game/data/lore/regions.json` | see below | the generator (which region you're in), GM STATE, art and audio choice |
| `game/data/lore/rooms.json` | `{"<region>": {"<room kind>": ["description", ...]}}` | the offline storyteller, and hints to the GM |
| `game/data/lore/npcs.json` | `[{"id", "name", "region", "want", "fear", "voice"}]` | GM STATE when the party is in that region |

```json
// regions.json
[
  {
    "id": "sewers",
    "name": "The Drowned Ways",
    "depth": [0, 4],
    "mood": "damp, echoing, rotten",
    "room_kinds": ["chamber", "storeroom", "well room", "kennel"],
    "monsters": ["giant_rat", "zombie"],
    "music": "sewers",
    "ambience": "drip"
  }
]
```

Keep IDs lowercase with underscores (`ruined_city`). Code, art and audio files all use these IDs.

---

## 2. Art

### Specs (decided)

- **Tile size: 32×32 px**, drawn at 1× (one texture pixel = one screen pixel at 1280×720).
- **PNG**, RGBA, transparent background where nothing is drawn.
- **Nearest-neighbour filtering** is already set in `project.godot`, so pixels stay crisp.
- **One palette** for the whole game, about 16-32 colors. Make it first, as `game/art/palette.png`.
  Every texture uses only those colors, which is what makes art by different hands look like one game.
- **Light comes from the top-left.** Highlights go on top/left edges, shadows on bottom/right.

### Tools (free unless noted)

| Tool | Notes |
|---|---|
| [Aseprite](https://www.aseprite.org/) | the standard pixel-art editor; about $20, or free if you compile it from source |
| [LibreSprite](https://libresprite.github.io/) | free fork of an older Aseprite |
| [Pixelorama](https://pixelorama.org/) | free, made in Godot itself |
| [Lospec palette list](https://lospec.com/palette-list) | thousands of free palettes to start from |

### Order to make things in

Each step gives you something visible in the game.

1. **Palette.**
2. **Floor, wall, door (closed), door (open), rubble.** That's the whole dungeon today.
3. **Hero token**, drawn in greys so the game can tint it per player (keep the current 6 hero colors readable).
4. **Six monster tokens**, one per monster key.
5. **Item icon** (a generic one is enough to start).
6. **Floor and wall variants** (2-4 each) so rooms don't look tiled.
7. **Region tile sets:** a different floor and wall look per region.
8. **Wall autotiles:** a 16-piece "match sides" sheet, `tiles/wall_autotile.png` (128×128), so walls connect properly.
   The piece order is in [ASSETS.md](ASSETS.md#wall-autotiles).
   Godot's `TileMapLayer` terrains pick the right piece automatically.
9. **UI:** panel frame, buttons, portraits, a d20 for the roll animation.

### Integration contract: art

```
game/art/
  palette.png
  tiles/
    floor.png  floor_2.png  floor_3.png      # numbered = variants
    wall.png   wall_2.png
    wall_autotile.png                        # 4x4 sheet of joined wall pieces (optional)
    door_closed.png  door_open.png  rubble.png
  regions/<region id>/tiles/...              # same names; overrides tiles/ in that region
  tokens/
    hero.png                                  # greyscale, tinted in game
    hero_<class>.png                          # optional, e.g. hero_fighter.png
  monsters/<monster key>.png                  # giant_rat.png, goblin.png, skeleton.png ...
  items/item.png  items/<item name>.png      # e.g. old_coin.png
  ui/...                                      # not used yet (UI theme comes later)
```

Rules the code follows (built; details in [ASSETS.md](ASSETS.md)):

- A file that's missing falls back to the colored shape drawn today, so you can add art one file at a time.
- `name_2.png`, `name_3.png` … are variants. The game picks one per tile with the map's seed, so a tile looks the same every time you see it.
- Monster file names must match the `key` in `game/data/srd/monsters.json`.
- Region folders override the defaults for rooms in that region.

### Licensing

If you use any art you didn't make (for example a CC0 pack from [Kenney](https://kenney.nl/assets)
or [OpenGameArt](https://opengameart.org/)), add it to `CREDITS.md` with the author, link and license.
CC0 and CC-BY are fine; avoid "non-commercial" (NC) licenses if you might ever sell the game.

---

## 3. Music and sound

### Three layers

| Layer | What | Format |
|---|---|---|
| **Music** | one loop per region, plus combat, victory and defeat stings | OGG Vorbis, 44.1 kHz, stereo, loops seamlessly |
| **Ambience** | a quiet background bed per room kind or region: dripping, wind, distant chanting | OGG Vorbis, looping |
| **SFX** | short one-shots tied to game events | WAV, 16-bit, 44.1 kHz, mono |

OGG is compressed and streams well for long files. WAV has no decode delay, which matters for
short sounds that must feel instant.

### Tools (free)

| Tool | Use |
|---|---|
| [jsfxr](https://sfxr.me/) | retro sound effects in the browser, in seconds |
| [Audacity](https://www.audacityteam.org/) | record, trim, fade, normalize, export WAV/OGG |
| [BeepBox](https://www.beepbox.co/) | chiptune music in the browser |
| [LMMS](https://lmms.io/) | full music production, free |
| [Bosca Ceoil Blue](https://github.com/YuriSizov/boscaceoil-blue) | simple music maker for beginners, built with Godot |
| [Freesound](https://freesound.org/) | recorded sounds; check each file's license |

### Order

1. **SFX for what happens most:** footstep, door opens, attack hit, attack miss, critical hit, monster dies, hero down.
2. **One exploration loop and one combat loop.** The game crossfades between them.
3. **Ambience** for two or three room kinds.
4. **Region music**, stings, the rest of the SFX, and UI clicks.

### Loudness

So nothing needs fixing in code:

- Normalize SFX peaks to about **-6 dB**, and music to about **-14 LUFS** (Audacity: Effect → Loudness Normalization).
- Ambience should sit well under the music: about **-24 LUFS**.
- Loops: cut at zero crossings and check the loop point in Audacity. In Godot, looping is a checkbox on the imported file.
- Trim silence from the start of SFX. Silence at the start makes a sound feel late.

### Integration contract: audio

The core plan (Phase B) makes the game report every event. The audio hook plays the file named after it.

```
game/audio/
  sfx/<event>.wav          # variants: <event>_2.wav, <event>_3.wav … picked at random
  ambience/<room kind>.ogg # or ambience/<region id>.ogg
  music/explore.ogg  music/combat.ogg
  music/<region id>.ogg  music/<region id>_combat.ogg
  music/victory.ogg  music/defeat.ogg
```

| Event name | When |
|---|---|
| `step` | a hero moves one square |
| `door_open` | an unexplored door opens |
| `door_blocked` | a door turns out to be rubble |
| `combat_start` / `combat_end` | a fight begins or ends |
| `turn_start` | it's a hero's turn |
| `attack_hit` / `attack_miss` / `attack_crit` | a hero attacks |
| `monster_hit` / `monster_miss` | a monster attacks |
| `monster_die` | a monster falls |
| `hero_down` | a hero drops to 0 HP |
| `death_save_success` / `death_save_fail` | death saves (after Phase A) |
| `check_success` / `check_fail` | an ability check the GM asked for |
| `pickup` | an item is picked up |
| `hero_die` | a hero dies after 3 failed death saves |
| `woke` / `lost_track` | a monster notices you / gives up |
| `stabilized` / `revived` | a dying hero is stable / back on their feet |
| `gm_speak` | GM narration arrives (a soft page-turn or quill sound) |
| `ui_click` / `ui_confirm` | menus |

The full, current list is in [EVENTS.md](EVENTS.md); `AudioDirector.sound_for()` is the mapping.
**This hook is built:** drop files in and they play.

Rules the code follows:

- A missing file means silence, so you can add sounds one at a time.
- Separate volume sliders for **Music**, **SFX** and **Ambience** (Godot audio buses).
- Music crossfades over about one second when you switch between exploring and combat, or move to another region.
- Monster-specific sounds are optional: `sfx/monster_hit_<monster key>.wav` wins over `monster_hit.wav` if it exists.

---

## 4. Integration timeline

What you can do now, and when the game starts using it.

| You (content) | Me (code) | Result |
|---|---|---|
| Story pitch, regions, palette | Core Phase A: gameplay fixes | nothing visible yet; the plan is set |
| First tiles and tokens, first SFX | Core Phase B: event stream + smooth animation | events are named and ready for sound |
| Monsters, variants, two music loops | Core Phase D: art loader, `TileMapLayer`, audio manager (**done**) | **your files appear in the game**; F8 reloads them |
| `world.md`, `regions.json`, `rooms.json` | regions in the generator, lore in GM STATE | the GM speaks in your world's voice, and regions change the look and music |
| Wall autotiles, region tile sets, UI | terrain autotiling, region overrides, UI theme | it looks like a finished game |

## 5. A first month for content

| Week | Story | Art | Audio |
|---|---|---|---|
| 1 | pitch, regions list, tone rules | palette, floor, wall | footstep, door, hit, miss (jsfxr) |
| 2 | region details, factions | doors, rubble, hero token | crit, monster die, hero down |
| 3 | NPCs, room descriptions for region 1 | six monster tokens | exploration loop |
| 4 | `world.md` + `regions.json` for region 1 | variants, item icon | combat loop, one ambience |

Keep everything in git. Commit small: "art: floor and wall", "story: region list".
