class_name Replay
extends RefCounted
## Replay files: how a game started plus every input to the rules, in order
## (GameState.recording). Running one reproduces the game exactly, which turns a bug
## report into a file. See docs/SAVES.md.
##
##   godot --headless --path game -- --replay=<file>          check it reproduces
##   godot --path game -- --replay=<file> --watch             watch it play

const DIR := "user://replays/"
const EXT := ".replay"
const FORMAT := 1


## Writes the current recording, with the hash it should reproduce. Returns the path or "".
static func save(path: String = "") -> String:
	if GameState.recording.is_empty():
		return ""
	if path.is_empty():
		DirAccess.make_dir_recursive_absolute(DIR)
		path = DIR + Time.get_datetime_string_from_system(true).replace(":", "-") + EXT
	var data := GameState.recording.duplicate(true)
	data["format"] = FORMAT
	data["final_hash"] = GameState.state_hash()
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return ""
	f.store_var(data, false)
	f.close()
	return path


static func read(path: String) -> Dictionary:
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	var data = f.get_var(false)   # never decode objects
	f.close()
	return data if typeof(data) == TYPE_DICTIONARY else {}


## Starts the game the recording starts from. Returns "" or an error.
static func begin(rec: Dictionary) -> String:
	if typeof(rec.get("start")) != TYPE_DICTIONARY or typeof(rec.get("inputs")) != TYPE_ARRAY:
		return "not a replay file"
	if int(rec.get("format", 0)) > FORMAT:
		return "replay from a newer version of the game"
	var start: Dictionary = rec["start"]
	GameState.debug_enabled = bool(start.get("debug", false))   # replay debug commands only if they were allowed
	if int(start.get("generator_version", -1)) != GameData.dungeon.generator_version:
		return "replay made with dungeon generator v%s, this game uses v%d" % [str(start.get("generator_version")), GameData.dungeon.generator_version]
	match start.get("kind"):
		"new":
			GameState.new_game(int(start["seed"]), start["heroes"], int(start.get("owner", 1)))
		"save":
			var err := GameState.load_save(start["save"], 1)
			if err != "":
				return err
		_:
			return "unknown replay start"
	return ""


## Applies one recorded input.
static func step(op: Array) -> void:
	match str(op[0]):
		"intent":
			GameState.handle_intent(int(op[1]), op[2])
		"gm":
			GameState.apply_gm_response(op[1], op[2])
		"join":
			GameState.add_player(str(op[1]), int(op[2]))
		"leave":
			GameState.remove_players_of(int(op[1]))


## Runs a whole recording. Returns {error, hash, matches, inputs, data_changed}.
static func run(rec: Dictionary) -> Dictionary:
	var err := begin(rec)
	if err != "":
		return {"error": err, "hash": "", "matches": false, "inputs": 0, "data_changed": false}
	for op in rec["inputs"]:
		step(op)
	var h := GameState.state_hash()
	return {
		"error": "", "hash": h, "matches": h == str(rec.get("final_hash", h)), "inputs": rec["inputs"].size(),
		"data_changed": str(rec["start"].get("data_fingerprint", "")) != GameData.fingerprint,
	}
