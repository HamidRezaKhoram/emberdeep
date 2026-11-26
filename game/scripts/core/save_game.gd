class_name SaveGame
extends RefCounted
## Save files: user://saves/<slot>.sav. See docs/SAVES.md.
##
## - Versioned: `format` is this file layout's version. Older formats are migrated
##   step by step in _migrate(); newer ones (from a later game) are refused.
## - The map is not stored. It is rebuilt from the seed and the doors opened, then
##   checked against a hash, so a save made with other dungeon rules (another
##   generator_version) is refused instead of loading a wrong map.
## - Safe to share: Godot's binary Variant format, read with objects disallowed, so a
##   save file can hold data but never code. Compressed.
## - Written to a temporary file, then renamed: a crash mid-save can't destroy the old save.

const FORMAT := 1
const DIR := "user://saves/"
const EXT := ".sav"
const QUICK := "quicksave"


static func path_for(slot: String) -> String:
	return DIR + slot.validate_filename() + EXT


static func exists(slot: String) -> bool:
	return FileAccess.file_exists(path_for(slot))


## Saves the current game. `extra` holds things outside the rules (the GM's
## conversation history). Returns "" or an error.
static func write(slot: String, extra: Dictionary = {}) -> String:
	if GameState.dungeon == null or GameState.player_order.is_empty():
		return "no game to save"
	DirAccess.make_dir_recursive_absolute(DIR)
	var data := {
		"format": FORMAT,
		"game_version": str(ProjectSettings.get_setting("application/config/version", "0")),
		"generator_version": GameData.dungeon.generator_version,
		"data_fingerprint": GameData.fingerprint,
		"saved_at": Time.get_datetime_string_from_system(true),
		"state": GameState.to_save(),
		"extra": extra,
	}
	var path := path_for(slot)
	var tmp := path + ".tmp"
	var f := FileAccess.open_compressed(tmp, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return "can't write %s (%s)" % [tmp, error_string(FileAccess.get_open_error())]
	f.store_var(data, false)
	f.close()
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		return "can't replace %s (%s)" % [path, error_string(err)]
	return ""


## Reads and checks a save without touching the game.
## Returns {error: String, warnings: Array[String], data: Dictionary}.
static func read(slot: String) -> Dictionary:
	var out := {"error": "", "warnings": [] as Array[String], "data": {}}
	var path := path_for(slot)
	if not FileAccess.file_exists(path):
		out["error"] = "no save named '%s'" % slot
		return out
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		out["error"] = "can't open %s" % path
		return out
	var data = f.get_var(false)   # false: never decode objects
	f.close()
	return check(data)


## Version and shape checks (used by read(), and by tests on hand-made data).
static func check(data) -> Dictionary:
	var out := {"error": "", "warnings": [] as Array[String], "data": {}}
	if typeof(data) != TYPE_DICTIONARY or typeof(data.get("format")) != TYPE_INT:
		out["error"] = "not an Emberdeep save, or the file is damaged"
		return out
	if int(data["format"]) > FORMAT:
		out["error"] = "this save is from a newer version of the game (format %d, this game reads up to %d)" % [data["format"], FORMAT]
		return out
	data = _migrate(data)
	if int(data.get("generator_version", -1)) != GameData.dungeon.generator_version:
		out["error"] = "this save was made with dungeon generator v%s; this game uses v%d, so its map can't be rebuilt" % [
			str(data.get("generator_version", "?")), GameData.dungeon.generator_version]
		return out
	if typeof(data.get("state")) != TYPE_DICTIONARY:
		out["error"] = "the save has no game state"
		return out
	for key in ["players", "monsters", "gm_spawned", "init_order"]:
		if typeof(data["state"].get(key)) != TYPE_DICTIONARY:
			out["error"] = "the save's '%s' is damaged" % key
			return out
	for key in ["opened_doors", "player_order", "items", "initiative", "log"]:
		if typeof(data["state"].get(key)) != TYPE_ARRAY:
			out["error"] = "the save's '%s' is damaged" % key
			return out
	if str(data.get("data_fingerprint", "")) != GameData.fingerprint:
		out["warnings"].append("The game's rules data changed since this save was made; numbers may play differently.")
	out["data"] = data
	return out


## Reads a save and loads it into the game. Returns {error, warnings, extra}.
static func load_slot(slot: String) -> Dictionary:
	var r := read(slot)
	if r["error"] != "":
		return {"error": r["error"], "warnings": r["warnings"], "extra": {}}
	var err := GameState.load_save(r["data"]["state"])
	for w in r["warnings"]:
		GameState.add_log("system", w)
	return {"error": err, "warnings": r["warnings"], "extra": r["data"].get("extra", {})}


## Upgrades older save layouts one format at a time. Add a case per format bump:
##   1: (current)
static func _migrate(data: Dictionary) -> Dictionary:
	while int(data["format"]) < FORMAT:
		match int(data["format"]):
			_:
				break
	return data
