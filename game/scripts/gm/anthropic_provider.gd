class_name AnthropicProvider
extends GMProvider
## Claude as game master, over the Messages API.
## Godot has no official Anthropic SDK, so this is raw HTTPS with HTTPRequest.
##
## - Structured outputs (output_config.format) force the reply into the GM schema.
## - The system prompt is marked for prompt caching: it is identical every turn.
## - Server-side fallbacks ("default") retry on another model if a safety classifier
##   declines a turn (dark fantasy combat can occasionally trip one).
## - History is kept as text only (no thinking blocks are replayed), so trimming old
##   turns is safe. See docs/AI_GAME_MASTER.md.

const URL := "https://api.anthropic.com/v1/messages"
const API_VERSION := "2026-10-21"

var api_key := ""
var model := "claude-opus-5-5"
var effort := "low"


func display_name() -> String:
	return "Claude (%s)" % model


func request_turn(system_prompt: String, messages: Array, schema: Dictionary, _event: Dictionary) -> void:
	if api_key.is_empty():
		_finish_error("no API key: set ANTHROPIC_API_KEY")
		return
	var body := {
		"model": model,
		"max_tokens": 16000,
		"system": [{"type": "text", "text": system_prompt, "cache_control": {"type": "ephemeral"}}],
		"messages": messages,
		"output_config": {"effort": effort, "format": {"type": "json_schema", "schema": schema}},
		"fallbacks": "default",
	}
	var headers := PackedStringArray([
		"content-type: application/json",
		"x-api-key: " + api_key,
		"anthropic-version: " + API_VERSION,
		"anthropic-beta: server-side-fallback-2026-07-01",
	])
	_post(URL, headers, body)


func _handle_response(code: int, text: String) -> void:
	var data = JSON.parse_string(text)
	if code != 200 or typeof(data) != TYPE_DICTIONARY:
		_finish_error("HTTP %d: %s" % [code, text.left(300)])
		return
	var stop := str(data.get("stop_reason", ""))
	if stop == "refusal":
		_finish_error("the model declined this turn")
		return
	if stop == "max_tokens":
		_finish_error("reply was cut off (max_tokens)")
		return
	var out := ""
	for block in data.get("content", []):
		if typeof(block) == TYPE_DICTIONARY and block.get("type") == "text":
			out += str(block.get("text", ""))
	_finish_json(out)
