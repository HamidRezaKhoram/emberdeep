class_name DungeonGenerator
extends RefCounted
## Grows the dungeon one room at a time, when a hero opens an unexplored door.
##
## Deterministic: the room behind a door depends only on (world_seed, door position),
## so the same seed plus the same doors opened gives the same map. That keeps saves
## tiny (seed + list of opened doors) and lets peers rebuild the map if needed.
## See docs/MAP_GENERATION.md for the design and the planned upgrades.

enum Tile { VOID = 0, FLOOR = 1, WALL = 2, DOOR_UNEXPLORED = 3, DOOR_OPEN = 4, RUBBLE = 5 }

const DIRS := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

var world_seed: int
var tiles: Dictionary = {}      # Vector2i -> Tile
var revealed: Dictionary = {}   # Vector2i -> true (fog of war: what the party has seen)
var rooms: Array = []           # [{id, rect: Rect2i, depth, kind, center, entry}]
var doors: Dictionary = {}      # unexplored door Vector2i -> {room: id, dir: Vector2i}
var opened_doors: Array = []    # Vector2i, in the order they were opened (for saves)
var _room_of: Dictionary = {}   # floor Vector2i -> room id. Index for room_at(); rebuilt, never sent.


func _init(seed_value: int = 1) -> void:
	world_seed = seed_value
	GameData.ensure_loaded()


func rng_for(key: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash("%d|%s" % [world_seed, key])
	return r


func get_tile(p: Vector2i) -> int:
	return int(tiles.get(p, Tile.VOID))


## Heroes may step here (stepping on an unexplored door opens it).
func is_walkable(p: Vector2i) -> bool:
	var t := get_tile(p)
	return t == Tile.FLOOR or t == Tile.DOOR_OPEN or t == Tile.DOOR_UNEXPLORED


## Monsters stay on explored ground.
func is_open_floor(p: Vector2i) -> bool:
	var t := get_tile(p)
	return t == Tile.FLOOR or t == Tile.DOOR_OPEN


## Creatures and light pass through these.
func is_transparent(p: Vector2i) -> bool:
	var t := get_tile(p)
	return t == Tile.FLOOR or t == Tile.DOOR_OPEN


## The room whose floor contains p, or -1 (corridors, walls, doors). O(1).
func room_at(p: Vector2i) -> int:
	return int(_room_of.get(p, -1))


## True when nothing opaque lies strictly between a and b. Symmetric: a sees b
## exactly when b sees a (a line is traced both ways and either clear line counts).
func has_line_of_sight(a: Vector2i, b: Vector2i) -> bool:
	return _ray_clear(a, b) or _ray_clear(b, a)


func _ray_clear(a: Vector2i, b: Vector2i) -> bool:
	# Bresenham's line; the end points themselves may be opaque (a creature in a doorway).
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx + dy
	var p := a
	while true:
		if p != a and p != b and not is_transparent(p):
			return false
		if p == b:
			return true
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			p.x += sx
		if e2 <= dx:
			err += dx
			p.y += sy
	return true


func room_floor_tiles(room: Dictionary) -> Array:
	var out: Array = []
	var rect: Rect2i = room["rect"]
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			out.append(Vector2i(x, y))
	return out


func unexplored_door_count() -> int:
	return doors.size()


func create_start_room() -> Dictionary:
	var rng := rng_for("start")
	var rules := GameData.dungeon
	var room := _carve_room(rules.start_rect, 0, rules.start_kind)
	for d in DIRS:
		_add_door_on_wall(room, d, rng)
	return room


## Opens the unexplored door at p and builds what lies behind it.
## Returns the new room, or {} if there was no room to build (the door becomes rubble).
func open_door(p: Vector2i) -> Dictionary:
	if get_tile(p) != Tile.DOOR_UNEXPLORED or not doors.has(p):
		return {}
	var info: Dictionary = doors[p]
	var d: Vector2i = info["dir"]
	var parent: Dictionary = rooms[int(info["room"])]
	var rng := rng_for("door:%d,%d" % [p.x, p.y])
	var rules := GameData.dungeon
	for attempt in rules.max_attempts:
		var length := rng.randi_range(rules.corridor_length.x, rules.corridor_length.y)
		var along := rng.randi_range(rules.room_depth.x, rules.room_depth.y)
		var across := rng.randi_range(rules.room_width.x, rules.room_width.y)
		if attempt >= rules.shrink_after:
			length = rules.corridor_length.x
			along = rng.randi_range(rules.small_room.x, rules.small_room.y)
			across = rng.randi_range(rules.small_room.x, rules.small_room.y)
		var offset := rng.randi_range(0, across - 1)
		var plan := _plan(p, d, length, along, across, offset)
		if _fits(plan):
			opened_doors.append(p)
			return _build(p, d, plan, parent, rng)
	tiles[p] = Tile.RUBBLE
	doors.erase(p)
	opened_doors.append(p)
	_ensure_frontier(rng)
	return {}


func to_dict() -> Dictionary:
	return {"seed": world_seed, "tiles": tiles, "revealed": revealed, "rooms": rooms, "doors": doors}


func from_dict(data: Dictionary) -> void:
	world_seed = int(data.get("seed", world_seed))
	tiles = data.get("tiles", {})
	revealed = data.get("revealed", {})
	rooms = data.get("rooms", [])
	doors = data.get("doors", {})
	_room_of.clear()
	for room in rooms:
		_index_room(room)


func _index_room(room: Dictionary) -> void:
	var rect: Rect2i = room["rect"]
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			_room_of[Vector2i(x, y)] = int(room["id"])


# --- internals -------------------------------------------------------------

func _carve_room(rect: Rect2i, depth: int, kind: String) -> Dictionary:
	var room := {
		"id": rooms.size(), "rect": rect, "depth": depth, "kind": kind,
		"center": rect.position + rect.size / 2, "entry": Vector2i.ZERO,
	}
	for x in range(rect.position.x - 1, rect.end.x + 1):
		for y in range(rect.position.y - 1, rect.end.y + 1):
			var p := Vector2i(x, y)
			if rect.has_point(p):
				tiles[p] = Tile.FLOOR
			elif get_tile(p) == Tile.VOID:
				tiles[p] = Tile.WALL
			revealed[p] = true
	rooms.append(room)
	_index_room(room)
	return room


func _add_door_on_wall(room: Dictionary, d: Vector2i, rng: RandomNumberGenerator) -> bool:
	var rect: Rect2i = room["rect"]
	var p := Vector2i.ZERO
	if d == Vector2i.UP:
		p = Vector2i(rng.randi_range(rect.position.x, rect.end.x - 1), rect.position.y - 1)
	elif d == Vector2i.DOWN:
		p = Vector2i(rng.randi_range(rect.position.x, rect.end.x - 1), rect.end.y)
	elif d == Vector2i.LEFT:
		p = Vector2i(rect.position.x - 1, rng.randi_range(rect.position.y, rect.end.y - 1))
	else:
		p = Vector2i(rect.end.x, rng.randi_range(rect.position.y, rect.end.y - 1))
	if get_tile(p) != Tile.WALL or get_tile(p + d) != Tile.VOID:
		return false
	tiles[p] = Tile.DOOR_UNEXPLORED
	doors[p] = {"room": room["id"], "dir": d}
	return true


## Lays out a corridor of `length` tiles from the door, then a room whose entrance
## faces back down the corridor. `along` is the room's depth in direction d,
## `across` its width, `offset` shifts it sideways.
func _plan(p: Vector2i, d: Vector2i, length: int, along: int, across: int, offset: int) -> Dictionary:
	var perp := Vector2i(absi(d.y), absi(d.x))
	var corridor: Array = []
	for i in range(1, length + 1):
		corridor.append(p + d * i)
	var entry: Vector2i = p + d * (length + 1)
	var c1: Vector2i = entry + d + perp * (-offset)
	var c2: Vector2i = entry + d * along + perp * (across - 1 - offset)
	var lo := Vector2i(mini(c1.x, c2.x), mini(c1.y, c2.y))
	var hi := Vector2i(maxi(c1.x, c2.x), maxi(c1.y, c2.y))
	return {"corridor": corridor, "entry": entry, "rect": Rect2i(lo, hi - lo + Vector2i.ONE), "perp": perp}


func _fits(plan: Dictionary) -> bool:
	var rect: Rect2i = plan["rect"]
	var grown: Rect2i = rect.grow(1)
	for x in range(grown.position.x, grown.end.x):
		for y in range(grown.position.y, grown.end.y):
			if get_tile(Vector2i(x, y)) != Tile.VOID:
				return false
	var perp: Vector2i = plan["perp"]
	for c in plan["corridor"]:
		for q in [c, c + perp, c - perp]:
			if get_tile(q) != Tile.VOID:
				return false
	return true


func _build(p: Vector2i, d: Vector2i, plan: Dictionary, parent: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var perp: Vector2i = plan["perp"]
	for c in plan["corridor"]:
		tiles[c] = Tile.FLOOR
		revealed[c] = true
		for side in [c + perp, c - perp]:
			if get_tile(side) == Tile.VOID:
				tiles[side] = Tile.WALL
			revealed[side] = true
	tiles[p] = Tile.DOOR_OPEN
	doors.erase(p)
	var depth: int = int(parent["depth"]) + 1
	var rules := GameData.dungeon
	var kind: String = rules.room_kinds[rng.randi() % rules.room_kinds.size()]
	var room := _carve_room(plan["rect"], depth, kind)
	var entry: Vector2i = plan["entry"]
	tiles[entry] = Tile.DOOR_OPEN
	room["entry"] = entry
	var exit_chance := rules.exit_chance if depth < rules.deep_after else rules.exit_chance_deep
	for nd in DIRS:
		if nd == -d:
			continue
		if rng.randf() < exit_chance:
			_add_door_on_wall(room, nd, rng)
	_ensure_frontier(rng)
	return room


## Never let the dungeon close itself off: if no unexplored door is left,
## punch one into the newest room that has space for it.
func _ensure_frontier(rng: RandomNumberGenerator) -> void:
	if not doors.is_empty():
		return
	for i in range(rooms.size() - 1, -1, -1):
		for d in DIRS:
			for _try in 4:
				if _add_door_on_wall(rooms[i], d, rng):
					return
