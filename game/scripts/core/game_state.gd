extends Node
## Canonical game state (autoload "GameState").
##
## Host-authoritative: only the host (or a single-player game) changes state, and
## only through handle_intent() for player input and apply_gm_response() for the
## AI game master. Clients receive snapshots from Net and redraw. The GM never owns
## state: it proposes actions, the engine validates them and rolls the dice.
## See docs/ARCHITECTURE.md.

signal changed                          # any state change: redraw UI, broadcast to peers
signal log_added(entry: Dictionary)     # {seq, kind, text}; kind: system | gm | player | roll | combat
signal gm_event(event: Dictionary)      # host only: {kind, text, actor, chain}

const SPEED_TILES := 6          # 30 ft at 5 ft per square
const MAX_LOG := 200
const MAX_GM_SPAWNS_PER_ROOM := 3
const MAX_GM_ACTIONS_PER_TURN := 4
const MAX_GM_CHAIN := 2         # how many follow-up GM calls one event may cause
const FLAVOR_ITEMS := [
	"a pouch of tarnished coins", "a potion of healing", "a rusted key",
	"a torn map fragment", "a silver holy symbol", "a coil of hempen rope",
]

var world_seed: int = 0
var dice: Dice
var dungeon: DungeonGenerator
var monster_table: Dictionary = {}   # key -> stat block (data/srd/monsters.json)
var players: Dictionary = {}         # hero id -> hero
var player_order: Array = []
var monsters: Dictionary = {}        # monster id -> monster
var items: Array = []                # [{id, name, pos}]
var mode: String = "explore"         # explore | combat
var initiative: Array = []           # actor ids, highest first
var turn_index: int = 0
var round_num: int = 0
var game_over: bool = false
var map_version: int = 0
var log_entries: Array = []
var log_seq: int = 0
var _next_id: int = 1
var _gm_spawned: Dictionary = {}     # room id -> monsters the GM added there


func _ready() -> void:
	monster_table = _load_monsters()


# --- setup -----------------------------------------------------------------

func new_game(seed_value: int, hero_names: Array, owner_peer: int = 1) -> void:
	world_seed = seed_value if seed_value != 0 else randi_range(1, 2000000000)
	dice = Dice.new(world_seed)
	dungeon = DungeonGenerator.new(world_seed)
	if monster_table.is_empty():
		monster_table = _load_monsters()
	players.clear()
	player_order.clear()
	monsters.clear()
	items.clear()
	initiative.clear()
	log_entries.clear()
	_gm_spawned.clear()
	mode = "explore"
	turn_index = 0
	round_num = 0
	game_over = false
	_next_id = 1
	var start := dungeon.create_start_room()
	map_version += 1
	for n in hero_names:
		add_player(str(n), owner_peer)
	add_log("system", "A new delve begins (seed %d). Arrow keys or WASD to move, Enter to speak to the GM." % world_seed)
	if not player_order.is_empty():
		gm_event.emit({"kind": "room_revealed", "text": _describe_room(start), "actor": player_order[0], "chain": 0})
	changed.emit()


func add_player(hero_name: String, owner_peer: int) -> String:
	var id := "h%d" % _next_id
	_next_id += 1
	var hero := {
		"id": id, "name": hero_name.strip_edges().left(24), "owner": owner_peer,
		"class": "Fighter", "level": 1,
		"abilities": {"str": 15, "dex": 14, "con": 13, "int": 10, "wis": 12, "cha": 8},
		"hp": 11, "max_hp": 11, "ac": 16, "attack_bonus": 4, "damage": "1d8+2", "weapon": "longsword",
		"pos": Vector2i.ZERO, "moves_left": SPEED_TILES, "has_action": true,
		"inventory": [], "color": player_order.size(),
	}
	if hero["name"] == "":
		hero["name"] = "Hero %d" % (player_order.size() + 1)
	hero["pos"] = _free_tile_near(dungeon.rooms[0]["center"] if dungeon and not dungeon.rooms.is_empty() else Vector2i.ZERO)
	players[id] = hero
	player_order.append(id)
	if mode == "combat":
		initiative.append(id)
	add_log("system", "%s joins the party." % hero["name"])
	changed.emit()
	return id


func remove_players_of(owner_peer: int) -> void:
	for id in player_order.duplicate():
		if int(players[id]["owner"]) == owner_peer:
			add_log("system", "%s leaves the party." % players[id]["name"])
			players.erase(id)
			player_order.erase(id)
			initiative.erase(id)
	if mode == "combat" and not initiative.is_empty():
		turn_index = turn_index % initiative.size()
	changed.emit()


# --- player input ------------------------------------------------------------

## The only entry point for player input. `sender` is the network peer that sent
## it (1 = the host / a local game); a peer may only act for heroes it owns.
func handle_intent(sender: int, intent: Dictionary) -> void:
	var actor_id := str(intent.get("actor", ""))
	if not players.has(actor_id):
		return
	var hero: Dictionary = players[actor_id]
	if int(hero["owner"]) != sender:
		return
	var kind := str(intent.get("type", ""))
	if game_over and kind != "say":
		return
	match kind:
		"move":
			var d := _parse_dir(intent.get("dir"))
			if d != Vector2i.ZERO:
				_intent_move(hero, d)
		"end_turn":
			if mode == "combat" and current_actor() == actor_id:
				_advance_turn()
		"say":
			var text := str(intent.get("text", "")).strip_edges().left(400)
			if not text.is_empty():
				add_log("player", "%s: %s" % [hero["name"], text])
				gm_event.emit({"kind": "player_action", "text": "%s says/does: %s" % [hero["name"], text], "actor": actor_id, "chain": 0})
	changed.emit()


func current_actor() -> String:
	if mode != "combat" or initiative.is_empty():
		return ""
	return str(initiative[turn_index % initiative.size()])


func monster_at(p: Vector2i) -> String:
	for id in monsters:
		if monsters[id]["pos"] == p:
			return id
	return ""


func player_at(p: Vector2i) -> String:
	for id in players:
		if players[id]["pos"] == p and int(players[id]["hp"]) > 0:
			return id
	return ""


func living_players() -> Array:
	return player_order.filter(func(id): return int(players[id]["hp"]) > 0)


# --- AI game master ------------------------------------------------------------

## Applies one structured GM reply ({narration, actions[]}). Everything is validated
## here: unknown monsters, out-of-range DCs and over-budget spawns are dropped.
func apply_gm_response(data: Dictionary, event: Dictionary) -> void:
	var narration := str(data.get("narration", "")).strip_edges()
	if not narration.is_empty():
		add_log("gm", narration.left(1500))
	var actions = data.get("actions", [])
	if typeof(actions) == TYPE_ARRAY:
		var applied := 0
		for a in actions:
			if applied >= MAX_GM_ACTIONS_PER_TURN:
				break
			if typeof(a) == TYPE_DICTIONARY:
				_apply_gm_action(a, event)
				applied += 1
	changed.emit()


## Compact view of the world for the GM prompt: only what the GM needs this turn.
func summary_for_gm(actor_id: String) -> Dictionary:
	var party: Array = []
	for id in player_order:
		var h: Dictionary = players[id]
		party.append({"id": id, "name": h["name"], "class": h["class"], "level": h["level"], "hp": "%d/%d" % [h["hp"], h["max_hp"]]})
	var room_info := {}
	if players.has(actor_id):
		var rid := dungeon.room_at(players[actor_id]["pos"])
		if rid >= 0:
			room_info = _room_facts(dungeon.rooms[rid])
		else:
			room_info = {"location": "a narrow corridor"}
	var recent: Array = []
	for e in log_entries.slice(maxi(0, log_entries.size() - 8)):
		recent.append("[%s] %s" % [e["kind"], e["text"]])
	return {
		"mode": mode, "round": round_num, "acting_hero": actor_id, "party": party,
		"location": room_info, "allowed_monsters": monster_table.keys(), "recent_log": recent,
	}


# --- network snapshots ----------------------------------------------------------

func to_snapshot(include_map: bool) -> Dictionary:
	var s := {
		"seed": world_seed, "players": players, "player_order": player_order, "monsters": monsters,
		"items": items, "mode": mode, "initiative": initiative, "turn_index": turn_index,
		"round": round_num, "game_over": game_over, "map_version": map_version,
		"log": log_entries.slice(maxi(0, log_entries.size() - 60)),
	}
	if include_map:
		s["map"] = dungeon.to_dict()
	return s


func apply_snapshot(s: Dictionary) -> void:
	world_seed = int(s.get("seed", world_seed))
	players = s.get("players", {})
	player_order = s.get("player_order", [])
	monsters = s.get("monsters", {})
	items = s.get("items", [])
	mode = str(s.get("mode", "explore"))
	initiative = s.get("initiative", [])
	turn_index = int(s.get("turn_index", 0))
	round_num = int(s.get("round", 0))
	game_over = bool(s.get("game_over", false))
	if s.has("map"):
		dungeon = DungeonGenerator.new(world_seed)
		dungeon.from_dict(s["map"])
		map_version = int(s.get("map_version", 0))
	for e in s.get("log", []):
		if int(e["seq"]) > log_seq:
			log_seq = int(e["seq"])
			log_entries.append(e)
			log_added.emit(e)
	changed.emit()


func add_log(kind: String, text: String) -> void:
	log_seq += 1
	var entry := {"seq": log_seq, "kind": kind, "text": text}
	log_entries.append(entry)
	if log_entries.size() > MAX_LOG:
		log_entries.pop_front()
	log_added.emit(entry)


# --- movement and combat ---------------------------------------------------------

func _intent_move(hero: Dictionary, d: Vector2i) -> void:
	if int(hero["hp"]) <= 0:
		return
	if mode == "combat" and current_actor() != hero["id"]:
		return
	var target: Vector2i = hero["pos"] + d
	var mid := monster_at(target)
	if not mid.is_empty():
		if mode == "combat" and not hero["has_action"]:
			add_log("system", "%s has already attacked this turn (Space ends the turn)." % hero["name"])
			return
		_hero_attacks(hero, monsters[mid])
		if mode == "combat":
			hero["has_action"] = false
			_maybe_auto_end(hero)
		return
	if mode == "combat" and int(hero["moves_left"]) <= 0:
		return
	if dungeon.get_tile(target) == DungeonGenerator.Tile.DOOR_UNEXPLORED:
		var room := dungeon.open_door(target)
		map_version += 1
		if room.is_empty():
			add_log("system", "Rubble blocks this doorway.")
			return
		_populate_room(room)
		add_log("system", "%s opens a door: %s." % [hero["name"], room["kind"]])
		gm_event.emit({"kind": "room_revealed", "text": _describe_room(room), "actor": hero["id"], "chain": 0})
	if not dungeon.is_walkable(target) or not player_at(target).is_empty():
		return
	hero["pos"] = target
	_pick_up_items(hero)
	if mode == "combat":
		hero["moves_left"] = int(hero["moves_left"]) - 1
		_maybe_auto_end(hero)
	elif _any_monster_awake():
		_start_combat()


func _hero_attacks(hero: Dictionary, m: Dictionary) -> void:
	var r := Rules.attack_roll(dice, int(hero["attack_bonus"]), int(m["ac"]))
	if r["hit"]:
		var dmg := Rules.damage(dice, str(hero["damage"]), r["crit"])
		m["hp"] = int(m["hp"]) - dmg
		add_log("combat", "%s %s the %s with a %s: %d damage (rolled %d, total %d vs AC %d)." % [
			hero["name"], "CRITS" if r["crit"] else "hits", m["name"], hero["weapon"], dmg, r["natural"], r["total"], m["ac"]])
	else:
		add_log("combat", "%s misses the %s (rolled %d, total %d vs AC %d)." % [hero["name"], m["name"], r["natural"], r["total"], m["ac"]])
	if int(m["hp"]) <= 0:
		add_log("combat", "The %s falls." % m["name"])
		monsters.erase(m["id"])
		initiative.erase(m["id"])
		if not initiative.is_empty():
			turn_index = turn_index % initiative.size()
		if mode == "explore" and _any_monster_awake():
			_start_combat()
		_check_combat_over()


func _monster_attacks(m: Dictionary, hero: Dictionary) -> void:
	var r := Rules.attack_roll(dice, int(m["attack_bonus"]), int(hero["ac"]))
	if r["hit"]:
		var dmg := Rules.damage(dice, str(m["damage"]), r["crit"])
		hero["hp"] = maxi(0, int(hero["hp"]) - dmg)
		add_log("combat", "The %s hits %s for %d damage (rolled %d)." % [m["name"], hero["name"], dmg, r["natural"]])
		if int(hero["hp"]) == 0:
			add_log("combat", "%s drops, unconscious!" % hero["name"])
	else:
		add_log("combat", "The %s misses %s (rolled %d)." % [m["name"], hero["name"], r["natural"]])


func _start_combat() -> void:
	mode = "combat"
	round_num = 1
	var rolls := {}
	for id in living_players():
		rolls[id] = dice.roll_die(20) + Rules.ability_modifier(int(players[id]["abilities"]["dex"]))
	for id in monsters:
		if monsters[id]["awake"]:
			rolls[id] = dice.roll_die(20) + Rules.ability_modifier(int(monsters[id]["dex"]))
	initiative = rolls.keys()
	initiative.sort_custom(func(a, b): return rolls[a] > rolls[b])
	var names: Array = []
	for id in initiative:
		names.append("%s (%d)" % [_actor_name(id), rolls[id]])
	add_log("combat", "Roll for initiative! " + ", ".join(names))
	turn_index = -1
	_advance_turn()


func _advance_turn() -> void:
	for _guard in 64:
		if _check_combat_over() or game_over:
			return
		turn_index += 1
		if turn_index >= initiative.size():
			turn_index = 0
			round_num += 1
		var id := str(initiative[turn_index])
		if players.has(id):
			var hero: Dictionary = players[id]
			if int(hero["hp"]) <= 0:
				continue
			hero["moves_left"] = SPEED_TILES
			hero["has_action"] = true
			add_log("system", "Round %d: %s's turn (move %d, attack by walking into a foe, Space to end)." % [round_num, hero["name"], SPEED_TILES])
			return
		if monsters.has(id):
			_monster_turn(monsters[id])


func _maybe_auto_end(hero: Dictionary) -> void:
	if int(hero["moves_left"]) <= 0 and not hero["has_action"]:
		_advance_turn()


func _monster_turn(m: Dictionary) -> void:
	var target := _nearest_living_player(m["pos"])
	if target.is_empty():
		return
	var steps := int(m["speed"])
	while steps > 0 and _manhattan(m["pos"], players[target]["pos"]) > 1:
		var best: Vector2i = m["pos"]
		var best_dist := _manhattan(m["pos"], players[target]["pos"])
		for d in DungeonGenerator.DIRS:
			var q: Vector2i = m["pos"] + d
			if dungeon.is_open_floor(q) and monster_at(q).is_empty() and player_at(q).is_empty():
				var dist := _manhattan(q, players[target]["pos"])
				if dist < best_dist:
					best = q
					best_dist = dist
		if best == m["pos"]:
			break
		m["pos"] = best
		steps -= 1
	if _manhattan(m["pos"], players[target]["pos"]) == 1:
		_monster_attacks(m, players[target])
	if living_players().is_empty():
		game_over = true
		add_log("system", "The party has fallen. Press R to start a new delve.")


func _check_combat_over() -> bool:
	if mode != "combat":
		return false
	if not _any_monster_awake():
		mode = "explore"
		initiative.clear()
		add_log("combat", "The fight is over.")
		gm_event.emit({"kind": "combat_over", "text": "The party won the fight.", "actor": living_players()[0] if not living_players().is_empty() else "", "chain": 0})
		return true
	return false


func _any_monster_awake() -> bool:
	for id in monsters:
		if monsters[id]["awake"]:
			return true
	return false


# --- room contents ---------------------------------------------------------------

## The engine, not the GM, rolls what a new room holds, so balance stays in code.
## The GM gets these facts and narrates them (and may add a little, within budget).
func _populate_room(room: Dictionary) -> void:
	var rng := dungeon.rng_for("contents:%d" % room["id"])
	var depth := int(room["depth"])
	if rng.randf() < 0.45:
		var budget := 0.25 + 0.125 * depth
		var options: Array = monster_table.keys().filter(func(k): return float(monster_table[k]["cr"]) <= budget)
		if not options.is_empty():
			var key: String = options[rng.randi() % options.size()]
			var count := rng.randi_range(1, clampi(1 + (depth >> 1), 1, 4))
			for i in count:
				_spawn_monster(key, room, rng)
	if rng.randf() < 0.3:
		_place_item(FLAVOR_ITEMS[rng.randi() % FLAVOR_ITEMS.size()], room, rng)


func _spawn_monster(key: String, room: Dictionary, rng: RandomNumberGenerator) -> bool:
	var spec: Dictionary = monster_table[key]
	var p := _random_free_tile(room, rng)
	if p == Vector2i(-99999, -99999):
		return false
	var id := "m%d" % _next_id
	_next_id += 1
	var hp := maxi(1, int(dice.roll(str(spec["hp"]))["total"]))
	monsters[id] = {
		"id": id, "key": key, "name": spec["name"], "pos": p, "hp": hp, "max_hp": hp,
		"ac": spec["ac"], "attack_bonus": spec["attack_bonus"], "damage": spec["damage"],
		"speed": spec["speed"], "dex": spec["dex"], "awake": true, "room": room["id"],
	}
	if mode == "combat":
		initiative.append(id)
	return true


func _place_item(item_name: String, room: Dictionary, rng: RandomNumberGenerator) -> void:
	var p := _random_free_tile(room, rng)
	if p != Vector2i(-99999, -99999):
		items.append({"id": "i%d" % _next_id, "name": item_name, "pos": p})
		_next_id += 1


func _pick_up_items(hero: Dictionary) -> void:
	for it in items.duplicate():
		if it["pos"] == hero["pos"]:
			hero["inventory"].append(it["name"])
			items.erase(it)
			add_log("system", "%s picks up %s." % [hero["name"], it["name"]])


func _apply_gm_action(a: Dictionary, event: Dictionary) -> void:
	var actor_id := str(event.get("actor", ""))
	if not players.has(actor_id):
		var alive := living_players()
		if alive.is_empty():
			return
		actor_id = alive[0]
	var hero: Dictionary = players[actor_id]
	var chain := int(event.get("chain", 0))
	match str(a.get("type", "none")):
		"ability_check":
			var ab := str(a.get("ability", ""))
			if not (ab in Rules.ABILITIES):
				return
			var dc := clampi(int(a.get("dc", 10)), 5, 30)
			var mod := Rules.ability_modifier(int(hero["abilities"][ab]))
			var r := Rules.ability_check(dice, mod, dc)
			var text := "%s makes a %s check (DC %d) for \"%s\": rolled %d%+d = %d, %s." % [
				hero["name"], Rules.ABILITY_NAMES[ab], dc, str(a.get("reason", "")).left(80),
				r["natural"], mod, r["total"], "SUCCESS" if r["success"] else "FAILURE"]
			add_log("roll", text)
			if chain < MAX_GM_CHAIN:
				gm_event.emit({"kind": "check_result", "text": text, "actor": actor_id, "chain": chain + 1})
		"spawn_monster":
			var key := str(a.get("monster", ""))
			var rid := dungeon.room_at(hero["pos"])
			if not monster_table.has(key) or rid < 0:
				return
			var count := clampi(int(a.get("count", 1)), 1, MAX_GM_SPAWNS_PER_ROOM)
			count = mini(count, MAX_GM_SPAWNS_PER_ROOM - int(_gm_spawned.get(rid, 0)))
			var rng := dungeon.rng_for("gm-spawn:%d:%d" % [rid, log_seq])
			var spawned := 0
			for i in count:
				if _spawn_monster(key, dungeon.rooms[rid], rng):
					spawned += 1
			_gm_spawned[rid] = int(_gm_spawned.get(rid, 0)) + spawned
			if spawned > 0 and mode == "explore":
				_start_combat()
		"place_item":
			var item_name := str(a.get("item", "")).strip_edges().left(48)
			var rid := dungeon.room_at(hero["pos"])
			if item_name.is_empty() or rid < 0:
				return
			_place_item(item_name, dungeon.rooms[rid], dungeon.rng_for("gm-item:%d:%d" % [rid, log_seq]))


# --- helpers ---------------------------------------------------------------------

func _room_facts(room: Dictionary) -> Dictionary:
	var rect: Rect2i = room["rect"]
	var here: Array = []
	for id in monsters:
		if int(monsters[id]["room"]) == int(room["id"]):
			here.append("%s (%s)" % [monsters[id]["name"], _hp_state(monsters[id])])
	var stuff: Array = []
	for it in items:
		if rect.has_point(it["pos"]):
			stuff.append(it["name"])
	var exits := 0
	for p in dungeon.doors:
		if int(dungeon.doors[p]["room"]) == int(room["id"]):
			exits += 1
	return {
		"room_id": room["id"], "kind": room["kind"], "depth": room["depth"],
		"size_ft": "%dx%d" % [rect.size.x * 5, rect.size.y * 5],
		"creatures": here, "items": stuff, "unexplored_exits": exits,
	}


func _describe_room(room: Dictionary) -> String:
	return "A new area is revealed: " + JSON.stringify(_room_facts(room))


func _hp_state(m: Dictionary) -> String:
	var frac := float(m["hp"]) / float(maxi(1, int(m["max_hp"])))
	return "unhurt" if frac >= 1.0 else ("wounded" if frac > 0.5 else "badly wounded")


func _actor_name(id: String) -> String:
	if players.has(id):
		return players[id]["name"]
	if monsters.has(id):
		return monsters[id]["name"]
	return id


func _nearest_living_player(from: Vector2i) -> String:
	var best := ""
	var best_d := 1 << 30
	for id in living_players():
		var d := _manhattan(from, players[id]["pos"])
		if d < best_d:
			best = id
			best_d = d
	return best


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func _parse_dir(v) -> Vector2i:
	if typeof(v) != TYPE_VECTOR2I:
		return Vector2i.ZERO
	var d: Vector2i = v
	return d if absi(d.x) + absi(d.y) == 1 else Vector2i.ZERO


func _random_free_tile(room: Dictionary, rng: RandomNumberGenerator) -> Vector2i:
	var cells := dungeon.room_floor_tiles(room)
	var entry: Vector2i = room["entry"]
	for _try in 30:
		var p: Vector2i = cells[rng.randi() % cells.size()]
		if _manhattan(p, entry) > 1 and monster_at(p).is_empty() and player_at(p).is_empty():
			return p
	return Vector2i(-99999, -99999)


func _free_tile_near(center: Vector2i) -> Vector2i:
	for r in range(0, 6):
		for x in range(-r, r + 1):
			for y in range(-r, r + 1):
				var p := center + Vector2i(x, y)
				if dungeon and dungeon.get_tile(p) == DungeonGenerator.Tile.FLOOR and player_at(p).is_empty():
					return p
	return center


func _load_monsters() -> Dictionary:
	var out := {}
	var text := FileAccess.get_file_as_string("res://data/srd/monsters.json")
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Could not read data/srd/monsters.json")
		return out
	for m in data.get("monsters", []):
		out[str(m["key"])] = m
	return out
