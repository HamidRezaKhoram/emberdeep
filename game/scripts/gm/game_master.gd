class_name GameMaster
extends Node
## Runs on the host only. Turns game events into GM requests, one at a time, and
## hands each structured reply to GameState, which validates and applies it.
## See docs/AI_GAME_MASTER.md for the prompt, schema and context strategy.

const MAX_HISTORY := 24            # messages kept (12 exchanges); older turns are dropped
const PROMPT_PATH := "res://data/prompts/gm_system.md"

var provider: GMProvider
var fallback: OfflineProvider
var system_prompt := ""
var history: Array = []            # [{role, content: String}], alternating, user first
var queue: Array = []              # pending events
var busy := false
var _current: Dictionary = {}
var _using_fallback := false


func setup(p: GMProvider) -> void:
	provider = p
	add_child(provider)
	provider.completed.connect(_on_completed)
	fallback = OfflineProvider.new()
	add_child(fallback)
	fallback.completed.connect(_on_completed)
	system_prompt = FileAccess.get_file_as_string(PROMPT_PATH)
	GameState.gm_event.connect(_on_gm_event)
	GameState.add_log("system", "Game master: %s." % provider.display_name())


func build_schema() -> Dictionary:
	var monster_keys: Array = [""]
	monster_keys.append_array(GameState.monster_table.keys())
	var ability_keys: Array = [""]
	ability_keys.append_array(Rules.ABILITIES)
	return {
		"type": "object",
		"additionalProperties": false,
		"required": ["narration", "actions"],
		"properties": {
			"narration": {"type": "string", "description": "What the players see, hear and feel. 1-4 sentences, second person."},
			"actions": {
				"type": "array",
				"description": "Requests for the engine. Use an empty array when nothing mechanical happens.",
				"items": {
					"type": "object",
					"additionalProperties": false,
					"required": ["type", "ability", "dc", "monster", "count", "item", "reason"],
					"properties": {
						"type": {"type": "string", "enum": ["ability_check", "spawn_monster", "place_item", "none"]},
						"ability": {"type": "string", "enum": ability_keys},
						"dc": {"type": "integer"},
						"monster": {"type": "string", "enum": monster_keys},
						"count": {"type": "integer"},
						"item": {"type": "string"},
						"reason": {"type": "string"},
					},
				},
			},
		},
	}


func _on_gm_event(event: Dictionary) -> void:
	queue.append(event)
	_pump()


func _pump() -> void:
	if busy or queue.is_empty():
		return
	_current = queue.pop_front()
	busy = true
	_using_fallback = false
	var state := JSON.stringify(GameState.summary_for_gm(str(_current.get("actor", ""))))
	var msg := "STATE: %s\n\nEVENT (%s): %s" % [state, _current.get("kind", ""), _current.get("text", "")]
	history.append({"role": "user", "content": msg})
	_trim_history()
	provider.request_turn(system_prompt, history, build_schema(), _current)


func _on_completed(result: Dictionary) -> void:
	if not busy:
		return
	if result.get("ok", false):
		if not _using_fallback:  # the failed turn's user message was already removed
			history.append({"role": "assistant", "content": str(result["raw"])})
		GameState.apply_gm_response(result["data"], _current)
	else:
		history.pop_back()  # keep the history alternating user/assistant
		if not _using_fallback:
			GameState.add_log("system", "(GM unavailable: %s)" % result.get("error", "unknown error"))
			_using_fallback = true
			fallback.request_turn(system_prompt, [], {}, _current)
			return
	busy = false
	_pump()


## Drops the oldest exchanges. Because we only send text (no thinking blocks),
## dropping whole leading turns is safe; it does reset the prompt cache after the
## system prompt. Roadmap: replace with a rolling "story so far" summary.
func _trim_history() -> void:
	while history.size() > MAX_HISTORY:
		history.pop_front()
		history.pop_front()
