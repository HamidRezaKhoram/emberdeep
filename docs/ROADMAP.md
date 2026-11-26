# Roadmap

Each milestone ends with something playable. Tick items as they land.

## M0: Skeleton (this commit)

- [x] Godot 4.6 project, Linux export preset, build/test scripts, CI
- [x] Seeded dice, SRD core math (modifiers, checks, attacks, damage)
- [x] Door-driven dungeon growth with fog of war
- [x] Host-authoritative GameState: intents, exploration, initiative combat, monster AI
- [x] AI GM: structured JSON turns, validated actions, offline / local LLM / Claude providers
- [x] Hot-seat (1-4 heroes) and LAN host/join with broadcast discovery
- [x] Headless tests: dice, rules, generator determinism and layout, ownership, GM validation, combat ends, snapshots
- [x] First run on a real machine (Fedora, Intel UHD 630): tests pass, debug build runs, smoke bot plays a delve

## M1: A real session (vertical slice)

- [ ] Character creation: 4 SRD classes (Fighter, Rogue, Cleric, Wizard), species, background, standard array
- [ ] Skills + proficiency in checks; GM can ask for a *skill* (Perception, Stealth, Athletics...)
- [ ] Advantage / disadvantage; the GM may grant it with a reason
- [x] Death saving throws, Stabilize (Wisdom (Medicine) DC 10)
- [ ] Healing potions usable
- [x] Local encounters: creatures sleep until seen, chase along real paths (bounded A*), lose track when cut off
- [x] Initiative ties by Dexterity; creatures can join a fight in progress
- [x] Replay test: same seed + same inputs = identical game, with state invariants checked every step
- [ ] Ranged attacks with line of sight; opportunity attacks
- [ ] Short and long rests; Hit Dice
- [ ] Save / load (seed + opened doors + entities + log + GM summary)
- [ ] Rolling "story so far" summary and world memory for the GM
- [ ] Settings screen: provider, model, effort, local URL; privacy note
- [ ] Verified SRD 5.2.1 stat blocks for ~20 low-CR monsters

## M2: Looks and feels like a game

- [ ] Pixel-art tileset in TileMapLayer, autotiled walls, light radius, remembered tiles
- [x] Event stream + Presenter: sliding tokens, attack lunges, hit flashes, damage/miss popups, crit shake, catch-up playback ([EVENTS.md](EVENTS.md))
- [x] Audio hook: SFX per event, explore/combat music crossfade, ambience per room kind, volume settings
- [ ] Token sprites, dice roll animation
- [ ] Streaming narration (typewriter as tokens arrive)
- [ ] Sound: ambience per room kind, combat SFX
- [x] Controller support, rebindable actions, game-clock move repeat, UI scale ([INPUT.md](INPUT.md))
- [ ] Mouse click-to-move with path preview
- [ ] Character sheet and inventory panels

## M3: Friends

- [ ] GodotSteam lobbies + Steam `MultiplayerPeer` (see NETWORKING.md)
- [ ] Reconnect, spectators, chat between players (not to the GM)
- [ ] Remote Play Together tested on Linux and Steam Deck
- [ ] Delta snapshots

## M4: Depth

- [ ] Spells (curated SRD subset), conditions, monster special abilities
- [ ] Regions and themes by depth, stairs between levels, locked/trapped/secret doors
- [ ] GM plot hooks on doors; NPCs with memory and dialogue mode; quests
- [ ] XP and levels 1-5; loot tables; shops at a surface camp
- [ ] GM eval harness (recorded fixtures + checks per provider/model)
- [ ] In-engine local inference option (llama.cpp GDExtension, model shipped beside the binary)

## M5: Release

- [ ] Steam page, credits screen with the SRD attribution, store assets
- [ ] AppImage / Flatpak / Steam depot for Linux; Windows build
- [ ] Performance pass on low-end hardware (Steam Deck)
