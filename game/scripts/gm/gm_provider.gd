class_name GMProvider
extends Node
## Base class for AI game master backends. A provider takes the system prompt, the
## conversation so far and a JSON schema, and answers with one structured turn:
## {narration: String, actions: Array}. See docs/AI_GAME_MASTER.md.

## result: {ok: bool, data: Dictionary, raw: String, error: String}
signal completed(result: Dictionary)

var _http: HTTPRequest


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 120.0
	add_child(_http)
	_http.request_completed.connect(_on_http_done)


func display_name() -> String:
	return "provider"


## messages: [{role: "user"|"assistant", content: String}], alternating, user first.
## event: the game event being answered (the offline provider uses it directly).
func request_turn(_system_prompt: String, _messages: Array, _schema: Dictionary, _event: Dictionary) -> void:
	_finish_error("request_turn() not implemented")


func _post(url: String, headers: PackedStringArray, body: Dictionary) -> void:
	var err := _http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		_finish_error("request could not start (error %d)" % err)


func _on_http_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_finish_error("network error %d" % result)
		return
	_handle_response(code, body.get_string_from_utf8())


func _handle_response(_code: int, _text: String) -> void:
	_finish_error("_handle_response() not implemented")


## Parses the model's JSON text. Models are constrained by the schema, but the
## engine still treats the reply as untrusted input (GameState validates actions).
func _finish_json(raw: String) -> void:
	var data = JSON.parse_string(raw)
	if typeof(data) != TYPE_DICTIONARY:
		_finish_error("reply was not a JSON object")
		return
	call_deferred("_emit", {"ok": true, "data": data, "raw": raw, "error": ""})


func _finish_error(message: String) -> void:
	call_deferred("_emit", {"ok": false, "data": {}, "raw": "", "error": message})


func _emit(result: Dictionary) -> void:
	completed.emit(result)
