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
## One atomic thing that happened, in order: {seq, type, ...}. The rules resolve
## instantly; the presentation (animation, sound) plays these back at its own pace.
## Types and fields: docs/EVENTS.md. Clients get them inside snapshots.
signal game_event(ev: Dictionary)

const NO_TILE := Vector2i(-99999, -99999)
# Every rules and balance number lives in game/data/ (GameData), not here.

var world_seed: int = 0
var dice: Dice
var dungeon: DungeonGenerator
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
var event_seq: int = 0               # like log_seq: keeps counting across games, so clients can tell new from old
var recent_events: Array = []        # the last MAX_EVENTS events, for snapshots
const MAX_EVENTS := 256
var _next_id: int = 1
var _gm_spawned: Dictionary = {}     # room id -> monsters the GM added there
var _gm_actions: int = 0             # GM actions applied this game; seeds GM placement RNGs
# Indexes, so lookups stay O(1) however many creatures the dungeon holds.
# Derived from `monsters`: kept in step by _place_monster/_remove_monster/_wake/_sleep
# and rebuilt by _rebuild_indexes() after a snapshot. Never sent over the network.
var _monster_at_tile: Dictionary = {}  # Vector2i -> monster id
var _awake_ids: Dictionary = {}        # monster id -> true
var _init_order: Dictionary = {}       # actor id -> [initiative total, dex score], combat only


func _ready() -> void:
	GameData.ensure_loaded()


# --- setup -----------------------------------------------------------------

func new_game(seed_value: int, hero_names: Array, owner_peer: int = 1) -> void:
	world_seed = seed_value if seed_value != 0 else randi_range(1, 2000000000)
	dice = Dice.new(world_seed)
	dungeon = DungeonGenerator.new(world_seed)
	GameData.ensure_loaded()
	players.clear()
	player_order.clear()
	monsters.clear()
	items.clear()
	initiative.clear()
	log_entries.clear()
	recent_events.clear()
	_emit("reset", {})
	_gm_spawned.clear()
	_gm_actions = 0
	_monster_at_tile.clear()
	_awake_ids.clear()
	_init_order.clear()
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
	var cls := GameData.hero_class(GameData.default_class)
	var hero := {
		"id": id, "name": hero_name.strip_edges().left(24), "owner": owner_peer,
		"class": cls.name, "level": cls.level, "abilities": cls.abilities.duplicate(),
		"hp": cls.hp, "max_hp": cls.hp, "ac": cls.ac, "attack_bonus": cls.attack_bonus,
		"damage": cls.damage, "weapon": cls.weapon,
		"pos": Vector2i.ZERO, "moves_left": GameData.balance.speed_tiles, "has_action": true,
		"inventory": [], "color": player_order.size(),
		# at 0 HP: dying until 3 successes (stable) or 3 failures (dead); see _death_save()
		"death_successes": 0, "death_failures": 0, "stable": false, "dead": false,
	}
	if hero["name"] == "":
		hero["name"] = "Hero %d" % (player_order.size() + 1)
	hero["pos"] = _free_tile_near(dungeon.rooms[0]["center"] if dungeon and not dungeon.rooms.is_empty() else Vector2i.ZERO)
	players[id] = hero
	player_order.append(id)
	_emit("spawned", {"actor": id, "pos": hero["pos"]})
	if mode == "combat":
		_join_initiative(id)
	add_log("system", "%s joins the party." % hero["name"])
	changed.emit()
	return id


func remove_players_of(owner_peer: int) -> void:
	for id in player_order.duplicate():
		if int(players[id]["owner"]) == owner_peer:
			add_log("system", "%s leaves the party." % players[id]["name"])
			players.erase(id)
			player_order.erase(id)
			_remove_from_initiative(id)
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


## The monster standing on p, or "". O(1) through the tile index.
func monster_at(p: Vector2i) -> String:
	return str(_monster_at_tile.get(p, ""))


## A conscious hero standing on p, or "". Heroes are few (at most 6), so a scan is fine.
func player_at(p: Vector2i) -> String:
	for id in players:
		if players[id]["pos"] == p and int(players[id]["hp"]) > 0:
			return id
	return ""


func living_players() -> Array:
	return player_order.filter(func(id): return int(players[id]["hp"]) > 0)


## A hero at 0 HP who is neither stable nor dead.
func is_dying(hero: Dictionary) -> bool:
	return int(hero["hp"]) <= 0 and not hero.get("stable", false) and not hero.get("dead", false)


## Moves a monster and keeps the tile index in step. Tests use it too.
func move_monster(id: String, p: Vector2i) -> void:
	var m: Dictionary = monsters[id]
	var from: Vector2i = m["pos"]
	if _monster_at_tile.get(from) == id:
		_monster_at_tile.erase(from)
	m["pos"] = p
	_monster_at_tile[p] = id
	_emit("moved", {"actor": id, "from": from, "to": p})


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
			if applied >= GameData.balance.gm_max_actions_per_turn:
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
		party.append({"id": id, "name": h["name"], "class": h["class"], "level": h["level"], "hp": "%d/%d" % [h["hp"], h["max_hp"]], "condition": hero_condition(h)})
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
		"location": room_info, "allowed_monsters": GameData.monsters.keys(), "recent_log": recent,
	}


# --- network snapshots ----------------------------------------------------------

## include_map: send the dungeon too (only when map_version changed).
## events_after: send the events with a higher seq (what clients haven't seen); -1 = none.
func to_snapshot(include_map: bool, events_after: int = -1) -> Dictionary:
	var s := {
		"seed": world_seed, "players": players, "player_order": player_order, "monsters": monsters,
		"items": items, "mode": mode, "initiative": initiative, "turn_index": turn_index,
		"round": round_num, "game_over": game_over, "map_version": map_version,
		"log": log_entries.slice(maxi(0, log_entries.size() - 60)),
	}
	if include_map:
		s["map"] = dungeon.to_dict()
	if events_after >= 0:
		s["events"] = recent_events.filter(func(e): return int(e["seq"]) > events_after)
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
	_rebuild_indexes()
	for ev in s.get("events", []):
		if int(ev["seq"]) > event_seq:
			event_seq = int(ev["seq"])
			game_event.emit(ev)
	for e in s.get("log", []):
		if int(e["seq"]) > log_seq:
			log_seq = int(e["seq"])
			log_entries.append(e)
			log_added.emit(e)
	changed.emit()


func _rebuild_indexes() -> void:
	_monster_at_tile.clear()
	_awake_ids.clear()
	for id in monsters:
		_monster_at_tile[monsters[id]["pos"]] = id
		if monsters[id].get("awake", false):
			_awake_ids[id] = true


## "ok", "dying (2 successes, 1 failure)", "stable", or "dead": for the HUD and the GM.
func hero_condition(h: Dictionary) -> String:
	if h.get("dead", false):
		return "dead"
	if int(h["hp"]) > 0:
		return "ok"
	if h.get("stable", false):
		return "unconscious, stable"
	return "dying (%d successes, %d failures)" % [int(h.get("death_successes", 0)), int(h.get("death_failures", 0))]


func _emit(type: String, data: Dictionary) -> void:
	event_seq += 1
	data["seq"] = event_seq
	data["type"] = type
	recent_events.append(data)
	if recent_events.size() > MAX_EVENTS:
		recent_events.pop_front()
	game_event.emit(data)


func add_log(kind: String, text: String) -> void:
	log_seq += 1
	var entry := {"seq": log_seq, "kind": kind, "text": text}
	log_entries.append(entry)
	if log_entries.size() > GameData.balance.max_log:
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
		if monsters.has(mid):
			_wake(mid, "is attacked")   # a sleeping creature you hit wakes up
		if mode == "combat":
			hero["has_action"] = false
		_update_awareness()
		if mode == "combat":
			_maybe_auto_end(hero)
		return
	var ally := _dying_ally_at(target)
	if not ally.is_empty():
		_try_stabilize(hero, players[ally])
		return
	if mode == "combat" and int(hero["moves_left"]) <= 0:
		return
	if dungeon.get_tile(target) == DungeonGenerator.Tile.DOOR_UNEXPLORED:
		var room := dungeon.open_door(target)
		map_version += 1
		if room.is_empty():
			add_log("system", "Rubble blocks this doorway.")
			_emit("door_blocked", {"actor": hero["id"], "pos": target})
			return
		_populate_room(room)
		add_log("system", "%s opens a door: %s." % [hero["name"], room["kind"]])
		_emit("door_open", {"actor": hero["id"], "pos": target, "room": room["id"], "kind": room["kind"]})
		gm_event.emit({"kind": "room_revealed", "text": _describe_room(room), "actor": hero["id"], "chain": 0})
	if not dungeon.is_walkable(target) or not player_at(target).is_empty():
		return
	var from: Vector2i = hero["pos"]
	hero["pos"] = target
	_emit("moved", {"actor": hero["id"], "from": from, "to": target})
	_pick_up_items(hero)
	if mode == "combat":
		hero["moves_left"] = int(hero["moves_left"]) - 1
	_update_awareness()
	if mode == "combat" and current_actor() == hero["id"]:
		_maybe_auto_end(hero)


func _hero_attacks(hero: Dictionary, m: Dictionary) -> void:
	var r := Rules.attack_roll(dice, int(hero["attack_bonus"]), int(m["ac"]))
	var dmg := 0
	if r["hit"]:
		dmg = Rules.damage(dice, str(hero["damage"]), r["crit"])
		m["hp"] = int(m["hp"]) - dmg
		add_log("combat", "%s %s the %s with a %s: %d damage (rolled %d, total %d vs AC %d)." % [
			hero["name"], "CRITS" if r["crit"] else "hits", m["name"], hero["weapon"], dmg, r["natural"], r["total"], m["ac"]])
	else:
		add_log("combat", "%s misses the %s (rolled %d, total %d vs AC %d)." % [hero["name"], m["name"], r["natural"], r["total"], m["ac"]])
	_emit("attack", {"attacker": hero["id"], "target": m["id"], "hit": r["hit"], "crit": r["crit"], "damage": dmg, "natural": r["natural"]})
	if int(m["hp"]) <= 0:
		add_log("combat", "The %s falls." % m["name"])
		_emit("monster_die", {"actor": m["id"], "key": m["key"], "name": m["name"], "pos": m["pos"]})
		_remove_monster(str(m["id"]))
		_check_combat_over()


func _monster_attacks(m: Dictionary, hero: Dictionary) -> void:
	var r := Rules.attack_roll(dice, int(m["attack_bonus"]), int(hero["ac"]))
	var dmg := 0
	if r["hit"]:
		dmg = Rules.damage(dice, str(m["damage"]), r["crit"])
	_emit("attack", {"attacker": m["id"], "attacker_key": m["key"], "target": hero["id"], "hit": r["hit"], "crit": r["crit"], "damage": dmg, "natural": r["natural"]})
	if r["hit"]:
		hero["hp"] = maxi(0, int(hero["hp"]) - dmg)
		add_log("combat", "The %s hits %s for %d damage (rolled %d)." % [m["name"], hero["name"], dmg, r["natural"]])
		if int(hero["hp"]) == 0:
			_emit("hero_down", {"actor": hero["id"]})
			hero["death_successes"] = 0
			hero["death_failures"] = 0
			hero["stable"] = false
			add_log("combat", "%s drops, unconscious and dying!" % hero["name"])
	else:
		add_log("combat", "The %s misses %s (rolled %d)." % [m["name"], hero["name"], r["natural"]])


## Initiative: d20 + Dexterity modifier. Ties go to the higher Dexterity score,
## then to whoever was listed first (heroes in party order, then monsters by id).
func _start_combat() -> void:
	mode = "combat"
	round_num = 1
	_emit("combat_start", {})
	_init_order.clear()
	var ids: Array = []
	for id in player_order:
		if not players[id].get("dead", false):
			ids.append(id)
	for id in _sorted_awake_ids():
		ids.append(id)
	for id in ids:
		_roll_initiative(id)
	initiative = ids
	initiative.sort_custom(_goes_before)
	var names: Array = []
	for id in initiative:
		names.append("%s (%d)" % [_actor_name(id), _init_order[id][0]])
	add_log("combat", "Roll for initiative! " + ", ".join(names))
	turn_index = -1
	_advance_turn()


func _roll_initiative(id: String) -> void:
	var dex := int(players[id]["abilities"]["dex"]) if players.has(id) else int(monsters[id]["dex"])
	_init_order[id] = [dice.roll_die(20) + Rules.ability_modifier(dex), dex]


func _goes_before(a: String, b: String) -> bool:
	var ka: Array = _init_order[a]
	var kb: Array = _init_order[b]
	if ka[0] != kb[0]:
		return ka[0] > kb[0]
	if ka[1] != kb[1]:
		return ka[1] > kb[1]
	return _actor_rank(a) < _actor_rank(b)


## Stable order for ties: heroes by party order first, then monsters by spawn number.
func _actor_rank(id: String) -> int:
	if players.has(id):
		return player_order.find(id)
	return 1000 + id.trim_prefix("m").to_int()


## Adds an actor to a fight in progress, at its place in the initiative order.
## Inserting before the current actor shifts the pointer, so the turn doesn't jump.
func _join_initiative(id: String) -> void:
	if initiative.has(id):
		return
	_roll_initiative(id)
	var idx := initiative.size()
	for i in initiative.size():
		if _goes_before(id, str(initiative[i])):
			idx = i
			break
	initiative.insert(idx, id)
	if idx <= turn_index:
		turn_index += 1
	add_log("combat", "%s joins the fight (initiative %d)." % [_actor_name(id), _init_order[id][0]])


func _advance_turn() -> void:
	# Each actor gets at most a few passes; the cap only guards against bugs.
	var guard := initiative.size() * 3 + 3
	while guard > 0:
		guard -= 1
		if _check_combat_over() or game_over:
			return
		turn_index += 1
		if turn_index >= initiative.size():
			turn_index = 0
			round_num += 1
		var id := str(initiative[turn_index])
		if players.has(id):
			var hero: Dictionary = players[id]
			if hero.get("dead", false) or (int(hero["hp"]) <= 0 and hero.get("stable", false)):
				continue
			if int(hero["hp"]) <= 0:
				_death_save(hero)
				if int(hero["hp"]) <= 0:
					continue   # still down: the turn passes on
			hero["moves_left"] = GameData.balance.speed_tiles
			hero["has_action"] = true
			_emit("turn_start", {"actor": id, "round": round_num})
			add_log("system", "Round %d: %s's turn (move %d, attack by walking into a foe, Space to end)." % [round_num, hero["name"], hero["moves_left"]])
			return
		if monsters.has(id):
			_monster_turn(monsters[id])
			if game_over:
				return
			if monsters.has(id) and not monsters[id]["awake"]:
				# it lost track of the party during its turn: drop it from the fight here,
				# without _remove_from_initiative(), which would re-enter this loop
				initiative.remove_at(turn_index)
				_init_order.erase(id)
				turn_index -= 1


## Removing an actor must not shift whose turn it is: entries before the current
## one move the pointer back by one; removing the current actor passes the turn on.
func _remove_from_initiative(id: String) -> void:
	_init_order.erase(id)
	var idx := initiative.find(id)
	if idx < 0:
		return
	var was_current := mode == "combat" and idx == turn_index
	initiative.remove_at(idx)
	if idx < turn_index:
		turn_index -= 1
	if initiative.is_empty():
		turn_index = 0
	elif was_current:
		turn_index -= 1
		_advance_turn()


func _maybe_auto_end(hero: Dictionary) -> void:
	if int(hero["moves_left"]) <= 0 and not hero["has_action"]:
		_advance_turn()


## A creature's turn: find a route to the nearest conscious hero (bounded A*),
## walk up to its speed along it, attack if adjacent. A creature that has had no
## route for LOSE_TRACK_TURNS turns in a row gives up and goes back to sleep.
func _monster_turn(m: Dictionary) -> void:
	var chase := _find_chase(m)
	if chase.is_empty():
		m["lost_turns"] = int(m.get("lost_turns", 0)) + 1
		if int(m["lost_turns"]) >= GameData.balance.lose_track_turns:
			add_log("combat", "The %s loses track of you." % m["name"])
			_emit("lost_track", {"actor": m["id"]})
			_sleep(str(m["id"]))
		return
	m["lost_turns"] = 0
	var target: Dictionary = players[chase["target"]]
	var path: Array = chase["path"]
	var steps := int(m["speed"])
	var i := 0
	while steps > 0 and _manhattan(m["pos"], target["pos"]) > 1 and i < path.size() - 1:
		var next: Vector2i = path[i]
		if not monster_at(next).is_empty() or not player_at(next).is_empty():
			break   # someone stepped into the way since the path was planned
		move_monster(str(m["id"]), next)
		i += 1
		steps -= 1
	if _manhattan(m["pos"], target["pos"]) == 1:
		_monster_attacks(m, target)
	if living_players().is_empty():
		game_over = true
		add_log("system", "The party has fallen. Press R to start a new delve.")
		_emit("party_fallen", {})


## {target: hero id, path: Array[Vector2i]} for the nearest hero this creature can
## reach, or {} if none is reachable within PATH_BUDGET. Heroes are tried nearest
## first (by grid distance), so usually only one search runs.
func _find_chase(m: Dictionary) -> Dictionary:
	var from: Vector2i = m["pos"]
	var heroes := living_players()
	heroes.sort_custom(func(a, b):
		var da := _manhattan(from, players[a]["pos"])
		var db := _manhattan(from, players[b]["pos"])
		return da < db if da != db else player_order.find(a) < player_order.find(b))
	for hid in heroes:
		var goal: Vector2i = players[hid]["pos"]
		if _manhattan(from, goal) == 1:
			return {"target": hid, "path": [goal]}
		var path := Pathfinder.find_path(from, goal, _monster_can_enter, GameData.balance.path_budget)
		if not path.is_empty():
			return {"target": hid, "path": path}
	return {}


func _monster_can_enter(p: Vector2i) -> bool:
	return dungeon.is_open_floor(p) and monster_at(p).is_empty() and player_at(p).is_empty()


func _check_combat_over() -> bool:
	if mode != "combat":
		return false
	if not _any_monster_awake():
		mode = "explore"
		initiative.clear()
		_init_order.clear()
		add_log("combat", "The fight is over.")
		_emit("combat_end", {})
		_recover_stable_heroes()
		gm_event.emit({"kind": "combat_over", "text": "The party won the fight.", "actor": living_players()[0] if not living_players().is_empty() else "", "chain": 0})
		return true
	return false


func _any_monster_awake() -> bool:
	return not _awake_ids.is_empty()


func _sorted_awake_ids() -> Array:
	var ids: Array = _awake_ids.keys()
	ids.sort_custom(func(a, b): return _actor_rank(a) < _actor_rank(b))
	return ids


# --- awareness: who notices whom ---------------------------------------------------

## Wakes sleeping creatures that a conscious hero can now see: in the same room, or
## within SIGHT_TILES with line of sight. Only tiles near heroes are checked, so the
## cost does not grow with the number of creatures in the dungeon.
## Starts a fight if anything is awake while exploring.
func _update_awareness() -> void:
	var sight := GameData.balance.sight_tiles
	for hid in living_players():
		var hp: Vector2i = players[hid]["pos"]
		var hroom := dungeon.room_at(hp)
		for x in range(hp.x - sight, hp.x + sight + 1):
			for y in range(hp.y - sight, hp.y + sight + 1):
				var p := Vector2i(x, y)
				var mid := str(_monster_at_tile.get(p, ""))
				if mid.is_empty() or _awake_ids.has(mid):
					continue
				var same_room := hroom >= 0 and int(monsters[mid]["room"]) == hroom
				if same_room or (_manhattan(hp, p) <= sight and dungeon.has_line_of_sight(hp, p)):
					_wake(mid, "notices %s" % players[hid]["name"])
	if mode == "explore" and _any_monster_awake() and not game_over:
		_start_combat()


func _wake(id: String, why: String) -> void:
	if _awake_ids.has(id):
		return
	var m: Dictionary = monsters[id]
	m["awake"] = true
	m["lost_turns"] = 0
	_awake_ids[id] = true
	add_log("combat", "The %s %s!" % [m["name"], why])
	_emit("woke", {"actor": id})
	if mode == "combat":
		_join_initiative(id)


func _sleep(id: String) -> void:
	monsters[id]["awake"] = false
	_awake_ids.erase(id)


# --- dying, death saves and stabilizing (SRD 5.2.1) ---------------------------------

## At the start of a dying hero's turn: d20, no modifiers. 10+ is a success, 9 or
## lower a failure, a natural 1 counts as two failures, a natural 20 brings the hero
## back with 1 HP. Three successes: stable. Three failures: dead.
func _death_save(hero: Dictionary) -> void:
	var n := int(dice.d20()["natural"])
	_emit("death_save", {"actor": hero["id"], "natural": n, "success": n >= 10})
	if n == 20:
		_revive(hero, 1)
		add_log("roll", "%s rolls a death saving throw: natural 20! They regain consciousness with 1 HP." % hero["name"])
		return
	if n == 1:
		hero["death_failures"] = int(hero["death_failures"]) + 2
	elif n >= 10:
		hero["death_successes"] = int(hero["death_successes"]) + 1
	else:
		hero["death_failures"] = int(hero["death_failures"]) + 1
	add_log("roll", "%s rolls a death saving throw: %d (%s). Successes %d, failures %d." % [
		hero["name"], n, "success" if n >= 10 else "failure", mini(hero["death_successes"], 3), mini(hero["death_failures"], 3)])
	if int(hero["death_failures"]) >= 3:
		hero["dead"] = true
		add_log("combat", "%s dies." % hero["name"])
		_emit("hero_die", {"actor": hero["id"]})
	elif int(hero["death_successes"]) >= 3:
		hero["stable"] = true
		add_log("combat", "%s is stable, but unconscious." % hero["name"])
		_emit("stabilized", {"actor": hero["id"]})


func _dying_ally_at(p: Vector2i) -> String:
	for id in player_order:
		if players[id]["pos"] == p and is_dying(players[id]):
			return id
	return ""


## Walking into a dying ally: a DC 10 Wisdom (Medicine) check to stabilize them.
## Uses the hero's action in combat; outside combat it can be retried.
func _try_stabilize(hero: Dictionary, ally: Dictionary) -> void:
	if mode == "combat":
		if not hero["has_action"]:
			add_log("system", "%s has already used their action this turn." % hero["name"])
			return
		hero["has_action"] = false
	var mod := Rules.ability_modifier(int(hero["abilities"]["wis"]))
	var dc := GameData.balance.stabilize_dc
	var r := Rules.ability_check(dice, mod, dc)
	_emit("check_success" if r["success"] else "check_fail", {"actor": hero["id"], "ability": "wis", "target": ally["id"]})
	add_log("roll", "%s tends to %s: Wisdom (Medicine) check, rolled %d%+d = %d vs DC %d, %s." % [
		hero["name"], ally["name"], r["natural"], mod, r["total"], dc, "SUCCESS" if r["success"] else "FAILURE"])
	if r["success"]:
		ally["stable"] = true
		add_log("combat", "%s is stable." % ally["name"])
		_emit("stabilized", {"actor": ally["id"]})
		if mode == "explore":
			_recover_stable_heroes()
	if mode == "combat":
		_maybe_auto_end(hero)


## Simplification until rests exist: a stable hero wakes with 1 HP once no fight is
## going on (the rules say after 1d4 hours; there is no clock to wait on yet).
func _recover_stable_heroes() -> void:
	for id in player_order:
		var h: Dictionary = players[id]
		if int(h["hp"]) <= 0 and h.get("stable", false) and not h.get("dead", false):
			_revive(h, 1)
			add_log("system", "%s comes to with 1 HP." % h["name"])


func _revive(hero: Dictionary, hp: int) -> void:
	hero["hp"] = clampi(hp, 1, int(hero["max_hp"]))
	_emit("revived", {"actor": hero["id"]})
	hero["death_successes"] = 0
	hero["death_failures"] = 0
	hero["stable"] = false


# --- room contents ---------------------------------------------------------------

## The engine, not the GM, rolls what a new room holds, so balance stays in code.
## The GM gets these facts and narrates them (and may add a little, within budget).
func _populate_room(room: Dictionary) -> void:
	var rng := dungeon.rng_for("contents:%d" % room["id"])
	var depth := int(room["depth"])
	var b := GameData.balance
	if rng.randf() < b.monster_chance:
		var budget := b.cr_budget_base + b.cr_budget_per_depth * depth
		var options: Array = GameData.monsters.keys().filter(func(k): return GameData.monsters[k].cr <= budget)
		if not options.is_empty():
			var key: String = options[rng.randi() % options.size()]
			var count := rng.randi_range(1, clampi(1 + (depth >> 1), 1, b.max_group))
			for i in count:
				_spawn_monster(key, room, rng, false)   # asleep until a hero sees it
	if rng.randf() < b.item_chance:
		_place_item(GameData.flavor_items[rng.randi() % GameData.flavor_items.size()], room, rng)


## Places a creature in a room. `awake` creatures join (or start) the fight at once;
## sleeping ones wait until a hero sees them (_update_awareness).
func _spawn_monster(key: String, room: Dictionary, rng: RandomNumberGenerator, awake: bool) -> bool:
	var spec := GameData.monster(key)
	var p := _random_free_tile(room, rng)
	if p == NO_TILE:
		return false
	var id := "m%d" % _next_id
	_next_id += 1
	var hp := maxi(1, int(dice.roll(spec.hp)["total"]))
	monsters[id] = {
		"id": id, "key": key, "name": spec.name, "pos": p, "hp": hp, "max_hp": hp,
		"ac": spec.ac, "attack_bonus": spec.attack_bonus, "damage": spec.damage,
		"speed": spec.speed, "dex": spec.dex, "awake": false, "room": room["id"], "lost_turns": 0,
	}
	_monster_at_tile[p] = id
	_emit("spawned", {"actor": id, "key": key, "pos": p})
	if awake:
		monsters[id]["awake"] = true
		_awake_ids[id] = true
		if mode == "combat":
			_join_initiative(id)
	return true


func _remove_monster(id: String) -> void:
	var m: Dictionary = monsters[id]
	if _monster_at_tile.get(m["pos"]) == id:
		_monster_at_tile.erase(m["pos"])
	_awake_ids.erase(id)
	monsters.erase(id)
	_remove_from_initiative(id)


func _place_item(item_name: String, room: Dictionary, rng: RandomNumberGenerator) -> void:
	var p := _random_free_tile(room, rng)
	if p != NO_TILE:
		items.append({"id": "i%d" % _next_id, "name": item_name, "pos": p})
		_next_id += 1


func _pick_up_items(hero: Dictionary) -> void:
	for it in items.duplicate():
		if it["pos"] == hero["pos"]:
			hero["inventory"].append(it["name"])
			items.erase(it)
			add_log("system", "%s picks up %s." % [hero["name"], it["name"]])
			_emit("pickup", {"actor": hero["id"], "item": it["name"], "pos": it["pos"]})


func _apply_gm_action(a: Dictionary, event: Dictionary) -> void:
	var actor_id := str(event.get("actor", ""))
	if not players.has(actor_id):
		var alive := living_players()
		if alive.is_empty():
			return
		actor_id = alive[0]
	var hero: Dictionary = players[actor_id]
	var chain := int(event.get("chain", 0))
	# Per-game counter, not log_seq: log_seq keeps counting across games (clients
	# rely on that), so seeding from it would make GM placements differ on replay.
	_gm_actions += 1
	match str(a.get("type", "none")):
		"ability_check":
			var ab := str(a.get("ability", ""))
			if not (ab in Rules.ABILITIES):
				return
			var dc := clampi(int(a.get("dc", 10)), GameData.balance.gm_dc_min, GameData.balance.gm_dc_max)
			var mod := Rules.ability_modifier(int(hero["abilities"][ab]))
			var r := Rules.ability_check(dice, mod, dc)
			var text := "%s makes a %s check (DC %d) for \"%s\": rolled %d%+d = %d, %s." % [
				hero["name"], Rules.ABILITY_NAMES[ab], dc, str(a.get("reason", "")).left(80),
				r["natural"], mod, r["total"], "SUCCESS" if r["success"] else "FAILURE"]
			add_log("roll", text)
			_emit("check_success" if r["success"] else "check_fail", {"actor": actor_id, "ability": ab})
			if chain < GameData.balance.gm_max_chain:
				gm_event.emit({"kind": "check_result", "text": text, "actor": actor_id, "chain": chain + 1})
		"spawn_monster":
			var key := str(a.get("monster", ""))
			var rid := dungeon.room_at(hero["pos"])
			if not GameData.monsters.has(key) or rid < 0:
				return
			var count := clampi(int(a.get("count", 1)), 1, GameData.balance.gm_max_spawn_count)
			count = mini(count, GameData.balance.gm_max_spawns_per_room - int(_gm_spawned.get(rid, 0)))
			var rng := dungeon.rng_for("gm-spawn:%d:%d" % [rid, _gm_actions])
			var spawned := 0
			for i in count:
				if _spawn_monster(key, dungeon.rooms[rid], rng, true):   # an alarm: they come ready
					spawned += 1
			_gm_spawned[rid] = int(_gm_spawned.get(rid, 0)) + spawned
			if spawned > 0 and mode == "explore":
				_start_combat()
		"place_item":
			var item_name := str(a.get("item", "")).strip_edges().left(48)
			var rid := dungeon.room_at(hero["pos"])
			if item_name.is_empty() or rid < 0:
				return
			_place_item(item_name, dungeon.rooms[rid], dungeon.rng_for("gm-item:%d:%d" % [rid, _gm_actions]))


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
	return NO_TILE


func _free_tile_near(center: Vector2i) -> Vector2i:
	for r in range(0, 6):
		for x in range(-r, r + 1):
			for y in range(-r, r + 1):
				var p := center + Vector2i(x, y)
				if dungeon and dungeon.get_tile(p) == DungeonGenerator.Tile.FLOOR and player_at(p).is_empty():
					return p
	return center
