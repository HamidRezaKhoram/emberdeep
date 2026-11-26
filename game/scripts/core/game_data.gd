class_name GameData
extends RefCounted
## Every rules number and piece of content the engine uses, loaded from game/data/
## and checked once at startup. Code reads typed fields (GameData.balance.sight_tiles),
## never raw JSON, so a typo in a data file is reported with its file and key
## instead of failing somewhere in the middle of a game. See docs/DATA.md.
##
## Loads lazily on first use; load_all() re-reads the files (debug builds bind it to F5).

const BALANCE_PATH := "res://data/rules/balance.json"
const DUNGEON_PATH := "res://data/rules/dungeon.json"
const HEROES_PATH := "res://data/rules/heroes.json"
const ITEMS_PATH := "res://data/rules/items.json"
const MONSTERS_PATH := "res://data/srd/monsters.json"
const ALL_PATHS: Array[String] = [BALANCE_PATH, DUNGEON_PATH, HEROES_PATH, ITEMS_PATH, MONSTERS_PATH]

static var balance: Balance
static var dungeon: DungeonRules
static var classes: Dictionary = {}        # class id -> HeroClass
static var default_class := ""
static var monsters: Dictionary = {}       # monster key -> MonsterSpec, in file order
static var flavor_items: Array[String] = []
## Problems found by the last load, as "file: key: what is wrong". Empty when all is well.
static var errors: Array[String] = []
## SHA-256 of every data file. Saves and replays record it, so a game is only
## replayed against the rules it was played with.
static var fingerprint := ""
static var _loaded := false


static func ensure_loaded() -> void:
	if not _loaded:
		load_all()


## Re-reads every data file. Returns the problems found (also in `errors`).
## On errors, the values that did parse are still used, with defaults for the rest.
static func load_all() -> Array[String]:
	errors = []
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var raw := {}
	for path in ALL_PATHS:
		var text := FileAccess.get_file_as_string(path)
		ctx.update(text.to_utf8_buffer())
		var data = JSON.parse_string(text)
		if typeof(data) != TYPE_DICTIONARY:
			errors.append("%s: not a JSON object (missing file or syntax error)" % path)
			data = {}
		raw[path] = data
	fingerprint = ctx.finish().hex_encode()
	balance = Balance.new(_Reader.new(raw[BALANCE_PATH], BALANCE_PATH, errors))
	dungeon = DungeonRules.new(_Reader.new(raw[DUNGEON_PATH], DUNGEON_PATH, errors))
	_load_heroes(_Reader.new(raw[HEROES_PATH], HEROES_PATH, errors))
	_load_items(_Reader.new(raw[ITEMS_PATH], ITEMS_PATH, errors))
	_load_monsters(_Reader.new(raw[MONSTERS_PATH], MONSTERS_PATH, errors))
	for e in errors:
		push_error("Game data: " + e)
	_loaded = true
	return errors


static func hero_class(id: String) -> HeroClass:
	ensure_loaded()
	return classes.get(id, classes.get(default_class))


static func monster(key: String) -> MonsterSpec:
	ensure_loaded()
	return monsters.get(key)


static func _load_heroes(r: _Reader) -> void:
	classes.clear()
	var section := r.child("classes")
	for id in section.keys():
		classes[id] = HeroClass.new(section.child(id))
	default_class = r.str_("default_class", "fighter")
	if not classes.has(default_class):
		r.fail("default_class", "'%s' is not one of the classes" % default_class)
		if classes.is_empty():
			classes[default_class] = HeroClass.new(_Reader.new({}, r.path + ": classes." + default_class, errors))


static func _load_items(r: _Reader) -> void:
	flavor_items = r.strings("flavor_items", ["something"])


static func _load_monsters(r: _Reader) -> void:
	monsters.clear()
	var list: Array = r.array("monsters")
	for i in list.size():
		var spec := MonsterSpec.new(_Reader.new(list[i], "%s: monsters[%d]" % [r.path, i], errors))
		if spec.key.is_empty() or monsters.has(spec.key):
			errors.append("%s: monsters[%d]: key '%s' is empty or repeated" % [r.path, i, spec.key])
			continue
		monsters[spec.key] = spec


# --- typed rules -----------------------------------------------------------------

class Balance:
	var speed_tiles: int
	var sight_tiles: int
	var lose_track_turns: int
	var path_budget: int
	var chase_range: int     # beyond this grid distance a creature doesn't even search for a path
	var stabilize_dc: int
	var max_log: int
	var gm_max_spawns_per_room: int
	var gm_max_actions_per_turn: int
	var gm_max_chain: int
	var gm_dc_min: int
	var gm_dc_max: int
	var gm_max_spawn_count: int
	var monster_chance: float
	var item_chance: float
	var cr_budget_base: float
	var cr_budget_per_depth: float
	var max_group: int

	func _init(r: _Reader) -> void:
		speed_tiles = r.int_("speed_tiles", 6, 1, 40)
		sight_tiles = r.int_("sight_tiles", 8, 1, 40)
		lose_track_turns = r.int_("lose_track_turns", 2, 1, 20)
		path_budget = r.int_("path_budget", 512, 16, 100000)
		chase_range = r.int_("chase_range", 30, 2, 1000)
		stabilize_dc = r.int_("stabilize_dc", 10, 1, 30)
		max_log = r.int_("max_log", 200, 10, 10000)
		var gm := r.child("gm")
		gm_max_spawns_per_room = gm.int_("max_spawns_per_room", 3, 0, 20)
		gm_max_actions_per_turn = gm.int_("max_actions_per_turn", 4, 0, 20)
		gm_max_chain = gm.int_("max_chain", 2, 0, 10)
		gm_dc_min = gm.int_("dc_min", 5, 1, 30)
		gm_dc_max = gm.int_("dc_max", 30, gm_dc_min, 40)
		gm_max_spawn_count = gm.int_("max_spawn_count", 3, 1, 20)
		var enc := r.child("encounters")
		monster_chance = enc.float_("monster_chance", 0.45, 0.0, 1.0)
		item_chance = enc.float_("item_chance", 0.3, 0.0, 1.0)
		cr_budget_base = enc.float_("cr_budget_base", 0.25, 0.0, 30.0)
		cr_budget_per_depth = enc.float_("cr_budget_per_depth", 0.125, 0.0, 30.0)
		max_group = enc.int_("max_group", 4, 1, 20)


class DungeonRules:
	var generator_version: int
	var start_rect: Rect2i
	var start_kind: String
	var max_attempts: int
	var shrink_after: int
	var corridor_length: Vector2i   # x = min, y = max (inclusive)
	var room_depth: Vector2i
	var room_width: Vector2i
	var small_room: Vector2i
	var exit_chance: float
	var exit_chance_deep: float
	var deep_after: int
	var room_kinds: Array[String]

	func _init(r: _Reader) -> void:
		generator_version = r.int_("generator_version", 1, 1, 1000000)
		var start := r.child("start_room")
		start_rect = Rect2i(start.vec2i("position", Vector2i(-3, -3)), start.vec2i("size", Vector2i(7, 6), 3, 30))
		start_kind = start.str_("kind", "entrance hall")
		max_attempts = r.int_("max_attempts", 8, 1, 100)
		shrink_after = r.int_("shrink_after", 4, 0, max_attempts)
		corridor_length = r.range_("corridor_length", Vector2i(1, 4), 1, 30)
		room_depth = r.range_("room_depth", Vector2i(4, 9), 2, 60)
		room_width = r.range_("room_width", Vector2i(4, 8), 2, 60)
		small_room = r.range_("small_room", Vector2i(3, 4), 2, 60)
		exit_chance = r.float_("exit_chance", 0.6, 0.0, 1.0)
		exit_chance_deep = r.float_("exit_chance_deep", 0.4, 0.0, 1.0)
		deep_after = r.int_("deep_after", 6, 0, 1000)
		room_kinds = r.strings("room_kinds", ["chamber"])


class HeroClass:
	var name: String
	var level: int
	var abilities: Dictionary = {}   # "str".."cha" -> score
	var hp: int
	var ac: int
	var attack_bonus: int
	var damage: String
	var weapon: String

	func _init(r: _Reader) -> void:
		name = r.str_("name", "Adventurer")
		level = r.int_("level", 1, 1, 20)
		var ab := r.child("abilities")
		for a in Rules.ABILITIES:
			abilities[a] = ab.int_(a, 10, 1, 30)
		hp = r.int_("hp", 10, 1, 1000)
		ac = r.int_("ac", 10, 0, 40)
		attack_bonus = r.int_("attack_bonus", 0, -10, 30)
		damage = r.dice("damage", "1d4")
		weapon = r.str_("weapon", "fists")


class MonsterSpec:
	var key: String
	var name: String
	var cr: float
	var ac: int
	var hp: String          # dice expression, rolled per creature
	var speed: int          # 5-ft squares
	var dex: int
	var attack_bonus: int
	var damage: String

	func _init(r: _Reader) -> void:
		key = r.str_("key", "")
		name = r.str_("name", key.capitalize())
		cr = r.float_("cr", 0.0, 0.0, 30.0)
		ac = r.int_("ac", 10, 0, 40)
		hp = r.dice("hp", "1d6")
		speed = r.int_("speed", 6, 0, 40)
		dex = r.int_("dex", 10, 1, 30)
		attack_bonus = r.int_("attack_bonus", 0, -10, 30)
		damage = r.dice("damage", "1d4")


# --- validation -----------------------------------------------------------------

## Reads typed values out of one JSON object, recording a precise error and
## returning the default for anything missing, mistyped or out of range.
class _Reader:
	var data: Dictionary
	var path: String
	var errors: Array[String]   # shared with GameData.errors (Arrays are passed by reference)

	func _init(d, where: String, errs: Array[String]) -> void:
		data = d if typeof(d) == TYPE_DICTIONARY else {}
		path = where
		errors = errs
		if typeof(d) != TYPE_DICTIONARY:
			fail("", "expected an object")

	func fail(key: String, what: String) -> void:
		errors.append("%s: %s%s" % [path, key + ": " if key != "" else "", what])

	func keys() -> Array:
		return data.keys().filter(func(k): return not str(k).begins_with("_"))

	func child(key: String) -> _Reader:
		if not data.has(key):
			fail(key, "missing")
			return _Reader.new({}, path + "." + key, errors)
		return _Reader.new(data[key], path + "." + key, errors)

	func _num(key: String):
		if not data.has(key):
			fail(key, "missing")
			return null
		var v = data[key]
		if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
			fail(key, "expected a number, got %s" % type_string(typeof(v)))
			return null
		return v

	func int_(key: String, default: int, lo: int, hi: int) -> int:
		var v = _num(key)
		if v == null:
			return default
		if float(v) != floorf(float(v)):
			fail(key, "expected a whole number, got %s" % str(v))
			return default
		if int(v) < lo or int(v) > hi:
			fail(key, "%d is outside %d..%d" % [int(v), lo, hi])
			return clampi(int(v), lo, hi)
		return int(v)

	func float_(key: String, default: float, lo: float, hi: float) -> float:
		var v = _num(key)
		if v == null:
			return default
		if float(v) < lo or float(v) > hi:
			fail(key, "%s is outside %s..%s" % [str(v), str(lo), str(hi)])
			return clampf(float(v), lo, hi)
		return float(v)

	func str_(key: String, default: String) -> String:
		if not data.has(key) or typeof(data[key]) != TYPE_STRING:
			fail(key, "expected text")
			return default
		return data[key]

	func dice(key: String, default: String) -> String:
		var s := str_(key, default)
		if Dice.parse(s).is_empty():
			fail(key, "'%s' is not a dice expression like 1d8+2" % s)
			return default
		return s

	func array(key: String) -> Array:
		if not data.has(key) or typeof(data[key]) != TYPE_ARRAY:
			fail(key, "expected a list")
			return []
		return data[key]

	func strings(key: String, default: Array[String]) -> Array[String]:
		var out: Array[String] = []
		for v in array(key):
			if typeof(v) == TYPE_STRING and not v.is_empty():
				out.append(v)
			else:
				fail(key, "every entry must be non-empty text")
		if out.is_empty():
			fail(key, "must not be empty")
			return default
		return out

	func vec2i(key: String, default: Vector2i, lo: int = -1000000, hi: int = 1000000) -> Vector2i:
		var a := array(key)
		if a.size() != 2 or typeof(a[0]) not in [TYPE_INT, TYPE_FLOAT] or typeof(a[1]) not in [TYPE_INT, TYPE_FLOAT]:
			fail(key, "expected [x, y]")
			return default
		var v := Vector2i(int(a[0]), int(a[1]))
		if v.x < lo or v.y < lo or v.x > hi or v.y > hi:
			fail(key, "%s is outside %d..%d" % [str(v), lo, hi])
			return default
		return v

	## [min, max], inclusive, min <= max.
	func range_(key: String, default: Vector2i, lo: int, hi: int) -> Vector2i:
		var v := vec2i(key, default, lo, hi)
		if v.x > v.y:
			fail(key, "min %d is above max %d" % [v.x, v.y])
			return default
		return v
