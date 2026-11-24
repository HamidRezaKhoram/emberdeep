# Research notes

Research done on 2026-11-23, before the skeleton was written. Each section ends with
the decision it led to. Sources are at the bottom; numbers and versions are as of that date.

## 1. Engine and language

**What we need:** a 2D top-down (or 3/4 "semi-2D") view, a turn-based grid game, a lot of
UI text (narration log, character sheets), HTTP calls to an LLM, LAN multiplayer, and a
single native Linux executable. One developer, indie budget.

| Option | For | Against |
|---|---|---|
| **Godot 4 (GDScript)** | Free, MIT. Strong 2D: TileMapLayer, Camera2D, a full UI toolkit (RichTextLabel with BBCode is ideal for a narration log). Built-in high-level multiplayer (ENet) with RPCs. HTTPRequest built in. One-command headless export to a Linux x86_64 binary with the data embedded. Big community; the largest share of indie 2D projects. Local-LLM plugins exist (NobodyWho, godot-llama-cpp) on llama.cpp. | GDScript is dynamically typed at heart (we use static types where it helps). Export templates are a large download. |
| Bevy (Rust) | Fast, ECS, everything is code. | Pre-1.0 with breaking changes between versions, no editor, UI and text layout are still the weak spot: the opposite of what a text-heavy RPG needs. |
| LÖVE 2D (Lua) | Tiny, quick to start. | No editor, no UI toolkit, no networking layer beyond raw sockets; everything an RPG needs is DIY. |
| Unity / C# | Mature. | Licensing churn, heavy for a 2D grid game. |
| Python + pygame / Raylib | Easy. | Packaging a native executable is fiddly; no UI toolkit. |

Version: Godot **4.6** is the current stable line (4.6.3 is the latest patch; 4.5 is in
partial support; 4.7 is in beta). The Godot project recommends the latest stable for new projects.

**Decision: Godot 4.6, GDScript, GL Compatibility renderer** (runs on older GPUs and
integrated graphics; we draw 2D only). Pin the exact version in `scripts/fetch-godot.sh`.
C# is possible later but needs the .NET build of Godot; GDScript keeps the toolchain one binary.

## 2. The AI game master

What published work and hobby projects agree on:

- **LLMs are bad at tracking game state.** A D&D dialogue study reached only 58% joint
  accuracy on game state tracking with a fine-tuned model and concluded that extra machinery
  is needed beyond the model. The FIREBALL dataset exists because real play needs ground-truth
  structured state alongside the narration.
- **Keep canonical state outside the model** and give it only the relevant slice each turn.
  Hobby AI-DM projects converge on structured JSON state plus rolling summaries plus recent turns.
- **Constraining generation cuts hallucination.** A 2026 study of LLM-driven detective games
  measured hallucinations (defined as violations of the game's logic and state) at 17.8% for
  an LLM-only design versus 6.3% when the relevant facts were retrieved from a structured tree
  and injected into the prompt. Their framing fits us: a GM "hallucination" is contradicting the game state.
- **Models ignore tool results** sometimes (CALYPSO saw a model invent a roll instead of using
  the real one) and tend to paraphrase stat blocks instead of making the scene interesting.
  Fix: the engine rolls and the prompt says so plainly; the prompt asks for motives and sensory detail.

**Decisions:**

1. The **engine is authoritative**: map, HP, positions, dice, combat. The GM narrates and *proposes*.
2. The GM answers every event with **one structured JSON object** (`narration` + `actions[]`),
   enforced with JSON-schema structured outputs (Claude: `output_config.format`; local servers:
   `response_format: json_schema`). Actions are a small closed set (ability check, spawn monster,
   place item) that the engine **validates** (known monsters only, DC clamped 5-30, spawn budget per room).
3. **Dice are rolled by the engine**, and results go back to the GM as a new event.
4. Each request carries a **compact STATE block** (party, current room facts, recent log), not the
   whole world. Older turns are dropped; a rolling summary is on the roadmap.
5. **Providers are pluggable**: offline (no AI), local model, Claude.

### Local vs cloud models

The game is meant to run **locally or on a LAN**, so local models are first-class:

- **Ollama**, **llama.cpp's llama-server** and **LM Studio** all serve an OpenAI-compatible
  `/v1/chat/completions` endpoint, and Ollama documents JSON-schema structured outputs through it
  (complex schemas need bigger models and run slower). One provider class covers all three.
- **In-engine inference** (NobodyWho, a llama.cpp GDExtension) is possible later. Caveat from its
  docs: llama.cpp needs the GGUF model as a real file, not inside Godot's .pck, so models ship
  beside the executable. We start with an external server because it keeps the game binary small
  and lets the host pick any model. Only the **host** needs a model; clients just receive state.
- **Claude** (Messages API) for the best GM quality when online. Godot has no Anthropic SDK, so raw
  HTTPS; defaults: model `claude-opus-5-5`, effort `low` for fast turns, structured outputs,
  prompt caching on the fixed system prompt, server-side refusal fallback.

## 3. Map generation "as you go"

Classic techniques: **BSP** (recursive splits, then rooms in the leaves), **cellular automata**
(caves), **drunkard's walk**, **wave function collapse** (tile adjacency rules; slows as rules
grow, and needs a connectivity repair pass), and room-and-corridor accretion. Roguelikes since
*Rogue* generate at runtime, but almost all generate a **whole level up front**; we found no
standard recipe for growing the map *while* the player explores.

BSP and whole-level WFC need the full bounds in advance, which fights "grow forever". **Room
accretion** fits: each unexplored door is a promise; opening it lays out a corridor and a room
there, if it fits, and adds new doors. The map is never bigger than what has been explored, and
the GM sees each room the moment it exists.

**Decision:** door-driven room accretion, seeded by (world seed, door position) so it is
deterministic. Later: themed regions, special rooms from the GM's plot hooks, WFC or cellular
automata *inside* rooms for caves and set pieces. Details in [MAP_GENERATION.md](MAP_GENERATION.md).

## 4. Multiplayer: local and Steam/LAN

- **Godot high-level multiplayer** abstracts the transport behind `MultiplayerPeer`. ENet is UDP;
  LAN discovery is done separately with a `PacketPeerUDP` broadcast beacon (broadcast must be
  explicitly enabled; the usual pattern is a separate discovery port).
- **Steam:** GodotSteam is the maintained Steamworks integration (lobbies, P2P, a
  `SteamMultiplayerPeer`) with prebuilt Godot 4.6 binaries/GDExtension. The older
  expressobits `steam-multiplayer-peer` plugin is paused and points to GodotSteam. GodotSteam's
  newer releases changed networking APIs to Steam IDs, so pin a version.
- **Steam Remote Play Together** streams a *local* multiplayer game to friends; only the host owns
  the game. It targets shared-screen / local co-op games and works with Linux hosts. So
  **hot-seat play on one screen gets online play for free** through Steam, with no netcode.

**Decision:** host-authoritative design from day one. Players send *intents*; the host runs
GameState and the GM and broadcasts snapshots. Three ways to play, same code path:
1. one computer, 1-4 heroes hot-seat (works with Remote Play Together),
2. LAN via ENet + broadcast discovery (in the skeleton),
3. Steam lobbies via GodotSteam (roadmap; swaps only the `MultiplayerPeer`).
Details in [NETWORKING.md](NETWORKING.md).

## 5. Rules content and legal

- The **SRD 5.2.1** (the 2024 fifth-edition core rules) is published under **CC-BY-4.0**. Use is
  free, commercial use included, as long as we give the attribution statement. The license can't be revoked.
- Only the SRD is covered. "Dungeons & Dragons" / "D&D", the logos, and non-SRD content
  (named settings, iconic monsters left out of the SRD) are **not**. So the game has its own name
  (Emberdeep) and describes itself as "compatible with fifth edition", with the attribution in
  [LEGAL.md](LEGAL.md).

**Decision:** implement mechanics from the SRD 5.2.1, keep monster/spell data in `game/data/srd/`
with attribution, never use the trademark in the product name or branding.

## Sources

Engine
- [Godot 4.6 release page](https://godotengine.org/releases/4.6/)
- [Godot 4.6.3 maintenance release](https://godotengine.org/article/maintenance-release-godot-4-6-3/)
- [Godot 4.5.2 release (support policy)](https://godotengine.org/article/maintenance-release-godot-4-5-2/)
- [LÖVE vs Godot comparison](https://generalistprogrammer.com/comparisons/love2d-vs-godot)
- [Bevy vs Godot comparison](https://sugggest.com/compare/bevy-game-engine-vs-godot-engine)
- [Why Godot? (indie devlog)](https://squeakypig.itch.io/unicopia/devlog/694333/why-godot)

AI game master
- [Dungeons and Dragons as a Dialog Challenge for AI (EMNLP 2022)](https://aclanthology.org/2022.emnlp-main.637.pdf)
- [FIREBALL: D&D actual-play with structured game state](https://arxiv.org/pdf/2305.01528)
- [CALYPSO: LLMs as Dungeon Master's Assistants](https://www.researchgate.net/publication/374523345_CALYPSO_LLMs_as_Dungeon_Master's_Assistants)
- [Narrative reliability in LLM detective games via structured knowledge trees](https://arxiv.org/pdf/2609.23043)
- [AI dungeon master with layered memory (hobby project)](https://github.com/ahmadcheema007-boop/ai-dungeon-master)
- [AI DM with Gemini, state-derivation pattern (blog)](https://dev.to/doubledare704/i-built-an-ai-dungeon-master-with-gemini-to-automate-my-dd-campaigns-16ji)
- [Ollama structured outputs](https://docs.ollama.com/capabilities/structured-outputs)
- [Ollama OpenAI compatibility](https://docs.ollama.com/API/openai-compatibility)
- [NobodyWho: local LLMs in Godot](https://nobodywho-ooo.github.io/nobodywho)
- [Running local LLMs in Godot (forum)](https://forum.godotengine.org/t/running-local-llms-in-godot/94392)
- [godot-llama-cpp](https://github.com/hazelnutcloud/godot-llama-cpp)

Map generation
- [Procedural generation methods compared (SBGames 2020)](https://www.sbgames.org/proceedings2020/ComputacaoShort/207911.pdf)
- [WFC roguelike levels, University of Tartu thesis](https://ims.ut.ee/www-public2/at/2024/bsc/june/atprog-bakalaureuset55-loti.05.029-Johannes_Voldemar_Langsepp-text-20240520.pdf)
- [Procedural content generation book chapter (TU Delft)](https://pure.tudelft.nl/ws/files/45041707/chapter03.Online.pdf)
- [mapgen crate (BSP, CA, drunkard, WFC)](https://docs.rs/crate/mapgen/0.4.0/)

Networking
- [GodotSteam](https://github.com/GodotSteam/GodotSteam)
- [steam-multiplayer-peer (paused)](https://github.com/expressobits/steam-multiplayer-peer)
- [ENetMultiplayerPeer docs](https://docs.godotengine.org/en/4.2/classes/class_enetmultiplayerpeer.html)
- [PacketPeerUDP docs](https://docs.godotengine.org/ja/4.3/classes/class_packetpeerudp.html)
- [LAN broadcast discovery demo](https://store.godotengine.org/asset/lucas-campos-achcar/godot-network-broadcast-discovery-demo/)
- [Server browser on ENet (forum)](https://forum.godotengine.org/t/implement-server-browser-on-top-of-enetmultiplayerpeer-infrastructure/119831)
- [Remote Play Together on Linux](https://gamingonlinux.com/2019/10/remote-play-together-should-now-work-properly-on-linux-with-a-new-steam-beta-update)
- [Remote Play Together "Invite Anyone"](https://www.gamingonlinux.com/2021/02/valve-launch-a-beta-for-remote-play-together-invite-anyone-no-steam-account-needed)

Legal
- [SRD 5.2.1 (D&D Beyond)](https://dndbeyond.com/srd)
- [Wizards: Systems Reference Document](https://DnD.wizards.com/resources/systems-reference-document)
- [Creator FAQ](https://www.dndbeyond.com/creator-faq)
- [SRD 5.2.1 legal page (markdown mirror)](https://nemo-illusionist.github.io/ttrpg_srd_markdown/en/dnd/srd-5.2/00_Legal)
- [PC Gamer: core rules released under Creative Commons](https://www.pcgamer.com/games/board-games/the-core-of-the-new-dungeons-and-dragons-rules-have-been-released-into-the-creative-commons-so-you-can-use-them-when-you-publish-your-own-d-and-d-material)
