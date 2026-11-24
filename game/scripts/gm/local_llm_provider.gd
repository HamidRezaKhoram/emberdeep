class_name LocalLLMProvider
extends GMProvider
## A model running on the host machine (or the LAN), through the OpenAI-compatible
## chat completions endpoint that Ollama, llama.cpp's llama-server and LM Studio all
## serve. JSON-schema constrained output keeps small models on the rails.
## Default: Ollama at http://127.0.0.1:11434. See docs/AI_GAME_MASTER.md.

var url := "http://127.0.0.1:11434/v1/chat/completions"
var model := "llama3.1:8b"


func display_name() -> String:
	return "Local LLM (%s)" % model


func request_turn(system_prompt: String, messages: Array, schema: Dictionary, _event: Dictionary) -> void:
	var msgs: Array = [{"role": "system", "content": system_prompt}]
	msgs.append_array(messages)
	var body := {
		"model": model,
		"messages": msgs,
		"stream": false,
		"response_format": {"type": "json_schema", "json_schema": {"name": "gm_turn", "strict": true, "schema": schema}},
	}
	_post(url, PackedStringArray(["content-type: application/json"]), body)


func _handle_response(code: int, text: String) -> void:
	var data = JSON.parse_string(text)
	if code != 200 or typeof(data) != TYPE_DICTIONARY or data.get("choices", []).is_empty():
		_finish_error("HTTP %d: %s" % [code, text.left(300)])
		return
	_finish_json(str(data["choices"][0].get("message", {}).get("content", "")))
