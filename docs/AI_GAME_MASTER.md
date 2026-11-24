# The AI game master

## Contract

Every GM turn is: **one event in, one JSON object out.**

Request (built in `game_master.gd`):
- System prompt: `game/data/prompts/gm_system.md`, identical every turn (cacheable).
- History: alternating user/assistant text, last 24 messages.
- New user message: `STATE: {json}` + `EVENT (kind): text`.

Reply schema (enforced by the provider's structured-output mode, then validated by the engine):

```json
{
  "narration": "string, 1-4 sentences, second person",
  "actions": [
    {"type": "ability_check|spawn_monster|place_item|none",
     "ability": "|str|dex|con|int|wis|cha", "dc": 0, "monster": "|<allowed key>",
     "count": 0, "item": "", "reason": ""}
  ]
}
```

Every action object has every field (simpler for small local models and for strict schemas).
The `monster` enum is filled from `data/srd/monsters.json` at runtime, so the model can't name
a creature the engine doesn't know.

## Events

| kind | when | GM should |
|---|---|---|
| `room_revealed` | a door opened, room built and populated | describe it; mention every listed creature and item |
| `player_action` | a player typed in the box | answer as the world; ask for a check if uncertain |
| `check_result` | the engine rolled a check the GM asked for | narrate the consequence |
| `combat_over` | last awake monster fell | brief aftermath |

`chain` counts follow-ups so a check → result → check loop stops after 2 (`MAX_GM_CHAIN`).

## Validation (in `GameState._apply_gm_action`)

- Max 4 actions per reply.
- `ability_check`: ability must be one of the six; DC clamped to 5-30; rolled by the engine
  with the acting hero's modifier; result logged and sent back as `check_result`.
- `spawn_monster`: key must be in the table; count clamped 1-3; at most 3 GM spawns per room in
  total; only inside a room (not corridors); starts combat.
- `place_item`: name trimmed to 48 chars; placed on a free tile; flavor only for now.
- Anything else is ignored.

## Providers

| Provider | File | Notes |
|---|---|---|
| Offline storyteller | `offline_provider.gd` | No network. Canned room text. Also the automatic fallback when a provider fails. |
| Local LLM | `local_llm_provider.gd` | OpenAI-compatible `/v1/chat/completions` with `response_format: json_schema`. Works with Ollama (default `http://127.0.0.1:11434`), llama.cpp `llama-server`, LM Studio. Set `local_url` / `local_model` in `user://settings.cfg`. |
| Claude | `anthropic_provider.gd` | Messages API over raw HTTPS (no Godot SDK). `claude-opus-5-5`, `output_config.effort: "low"` (raise to `medium` for richer play), `output_config.format` JSON schema, `cache_control` on the system prompt, `fallbacks: "default"` with the `server-side-fallback-2026-07-01` beta for refusals, checks `stop_reason` for `refusal` and `max_tokens`. Key from `ANTHROPIC_API_KEY`. |

Only the **host** runs a provider. Clients never need a model or a key.

### Running a local model

```bash
# Ollama
ollama pull llama3.1:8b        # or any instruct model that handles JSON well
ollama serve                   # listens on 127.0.0.1:11434
# then pick "Local LLM" in the menu
```

Small models (7-8B) handle the narration and simple actions; they are worse at knowing when
*not* to act. Watch for: describing creatures that aren't in the room, deciding outcomes
instead of asking for checks. The prompt and the engine's validation both push against this.

## Context strategy

- **Now:** fixed system prompt + last 12 exchanges + a fresh STATE block each turn. STATE carries
  the facts that matter (party HP, the acting hero's room, creatures, items, recent log), so
  dropping old turns loses flavor, not facts.
- **Claude specifics:** history is plain text only (we don't replay thinking blocks), so dropping
  leading turns is safe with preserved-thinking checks. The system prompt is cached; trimming
  history resets the cache after it, which is cheap at this size.
- **Next:** a rolling "story so far" summary (written by the GM every N turns, kept in STATE),
  and a small **world memory** of named NPCs, factions, clues and promises keyed by room id, so the
  GM can be reminded of what it invented. Retrieve by current room and recent entities, as the
  structured-knowledge research suggests ([RESEARCH.md](RESEARCH.md#2-the-ai-game-master)).

## Ideas for later

- **GM-authored rooms:** let the GM attach a `theme` or `plot_hook` to unexplored doors
  ("the door with claw marks") that biases what the generator builds behind them.
- **NPC dialogue mode** with per-NPC memory.
- **Session recap** at the end: the GM writes a journal entry.
- **Eval harness:** a set of recorded STATE+EVENT fixtures and checks ("mentions every creature",
  "never states HP", "asks for a check on risky actions") run against each provider/model.
- **Latency:** stream narration token-by-token into the log (SSE for Claude, `stream: true` for local).
