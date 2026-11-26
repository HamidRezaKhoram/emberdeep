# Emberdeep

A top-down, tabletop-style dungeon crawl where an **AI game master** narrates, voices
creatures and calls for rolls, and the **dungeon is built room by room as you open doors**.
Rules follow the fifth-edition **SRD 5.2.1**. Play solo, hot-seat on one screen, or with
friends over **LAN** (Steam lobbies planned). Built with **Godot 4.6** for a native Linux executable.

> Status: **skeleton (M0).** Everything below runs, but it is bare: colored squares for art,
> one pregenerated Fighter, six monsters. See [docs/ROADMAP.md](docs/ROADMAP.md).

## Quick start (Linux)

```bash
scripts/fetch-godot.sh            # downloads the pinned Godot 4.6.3 editor into .tools/
scripts/run-tests.sh              # headless test suite
.tools/godot --path game          # play from source
scripts/smoke.sh                  # bot plays a seeded game in a window, saves build/smoke.png
```

Build the executable:

```bash
scripts/fetch-godot.sh --templates   # once: export templates (~1 GB)
scripts/export-linux.sh              # -> build/linux/emberdeep.x86_64 (single file)
```

Dev (debug) build: `.tools/godot --headless --path game --export-debug Linux "$PWD/build/linux/emberdeep-dev.x86_64"`.
Any build accepts `-- --smoke [--shot=out.png] [--steps=N]` for the bot run.

Or open `game/` in the Godot 4.6 editor.

## Choosing a game master

| Menu option | Needs | Data leaves your machine? |
|---|---|---|
| Offline storyteller | nothing | no |
| Local LLM | [Ollama](https://ollama.com) (`ollama pull llama3.1:8b`), llama.cpp `llama-server`, or LM Studio, on the host | no |
| Claude API | `export ANTHROPIC_API_KEY=...` on the host | yes, to Anthropic |

Only the host needs a model or a key. Settings live in
`~/.local/share/godot/app_userdata/Emberdeep/settings.cfg` (`local_url`, `local_model`,
`claude_model`, `claude_effort`).

## Controls

Arrows / WASD or D-pad / stick move · walk into a monster to attack, or into a dying ally to help ·
Space (A) ends your combat turn · Tab (X) switches hero (hot-seat) · Enter (Y) talks to the GM ·
Esc (B) leaves the text box · F5 / F9 quick save / load · F12 saves a replay for bug reports.
All rebindable: [docs/INPUT.md](docs/INPUT.md). Saves and replays: [docs/SAVES.md](docs/SAVES.md).
Gold squares are unexplored doors.

## How it fits together

- The **engine is the source of truth**: map, HP, dice, combat. The AI GM only narrates and
  proposes a few validated actions (ask for an ability check, add a monster, place an item).
- The **host** runs the game state and the GM; everyone else sends intents and gets snapshots.
- The **map** grows deterministically from the seed and the doors you open.

Docs:
[Research](docs/RESEARCH.md) ·
[Design](docs/DESIGN.md) ·
[Architecture](docs/ARCHITECTURE.md) ·
[AI game master](docs/AI_GAME_MASTER.md) ·
[Map generation](docs/MAP_GENERATION.md) ·
[Networking](docs/NETWORKING.md) ·
[Roadmap](docs/ROADMAP.md) ·
[Legal](docs/LEGAL.md)

## Repository layout

```
game/                  Godot project (open this in the editor)
  scripts/core/        GameState (autoload), Dice, Rules, Settings
  scripts/world/       DungeonGenerator, map view
  scripts/gm/          GameMaster + providers (offline, local LLM, Claude)
  scripts/net/         Net (autoload): LAN host/join, discovery
  data/srd/            rules data (monster stat blocks)
  data/prompts/        GM system prompt
  tests/               headless test scene
scripts/               fetch-godot, run-tests, export-linux
docs/                  research, design and planning
```

## Legal

Emberdeep is not affiliated with or endorsed by Wizards of the Coast.

This work includes material from the System Reference Document 5.2.1 ("SRD 5.2.1") by Wizards
of the Coast LLC, available at https://www.dndbeyond.com/srd. The SRD 5.2.1 is licensed under the
Creative Commons Attribution 4.0 International License, available at
https://creativecommons.org/licenses/by/4.0/legalcode.

Code: MIT, see [LICENSE](LICENSE).
