extends Node
## Headless test suite. Run from the repo root: scripts/run-tests.sh
## Exits with code 0 when everything passes, 1 otherwise.

var passes := 0
var failures := 0


func _ready() -> void:
	_test_game_data()
	_test_input_bindings()
	_test_move_repeater()
	_test_dice()
	_test_rules()
	_test_generator_determinism()
	_test_generator_layout()
	_test_movement_and_ownership()
	_test_gm_validation()
	_test_combat_terminates()
	_test_kill_keeps_turn()
	_test_snapshot_roundtrip()
	_test_pathfinder()
	_test_line_of_sight()
	_test_room_index()
	_test_encounters_are_local()
	_test_lose_track_ends_combat()
	_test_many_monsters_in_initiative()
	_test_initiative_ties()
	_test_death_saves()
	_test_stabilize()
	_test_replay_determinism()
	_test_event_stream_complete()
	_test_presenter_playback()
	_test_sound_mapping()
	print("\n%d passed, %d failed" % [passes, failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(cond: bool, what: String) -> void:
	if cond:
		passes += 1
	else:
		failures += 1
		printerr("FAIL: " + what)


func _test_dice() -> void:
	check(Dice.parse("2d6+3") == {"count": 2, "sides": 6, "modifier": 3}, "parse 2d6+3")
	check(Dice.parse("d20") == {"count": 1, "sides": 20, "modifier": 0}, "parse d20")
	check(Dice.parse("1d8 - 1")["modifier"] == -1, "parse negative modifier")
	check(Dice.parse("3d7").is_empty(), "reject d7")
	check(Dice.parse("banana").is_empty(), "reject garbage")
	var d := Dice.new(99)
	var lo := 999
	var hi := -999
	for i in 500:
		var t: int = d.roll("2d6+1")["total"]
		lo = mini(lo, t)
		hi = maxi(hi, t)
	check(lo >= 3 and hi <= 13, "2d6+1 stays in 3..13 (got %d..%d)" % [lo, hi])
	var a := Dice.new(5)
	var b := Dice.new(5)
	check(a.roll("4d20")["rolls"] == b.roll("4d20")["rolls"], "same seed, same rolls")


func _test_rules() -> void:
	check(Rules.ability_modifier(10) == 0, "mod(10) = 0")
	check(Rules.ability_modifier(15) == 2, "mod(15) = +2")
	check(Rules.ability_modifier(8) == -1, "mod(8) = -1")
	check(Rules.ability_modifier(1) == -5, "mod(1) = -5")
	check(Rules.proficiency_bonus(1) == 2 and Rules.proficiency_bonus(5) == 3 and Rules.proficiency_bonus(17) == 6, "proficiency bonus")
	var d := Dice.new(1)
	for i in 300:
		var r := Rules.attack_roll(d, 0, 30)
		if r["natural"] == 20:
			check(r["hit"] and r["crit"], "natural 20 always hits")
		elif r["natural"] == 1:
			check(not r["hit"], "natural 1 always misses")
		else:
			check(not r["hit"], "cannot hit AC 30 with +0 except on a 20")


func _open_doors(gen: DungeonGenerator, n: int) -> void:
	for i in n:
		if gen.doors.is_empty():
			return
		var keys: Array = gen.doors.keys()
		keys.sort()
		gen.open_door(keys[0])


func _test_generator_determinism() -> void:
	var a := DungeonGenerator.new(7)
	var b := DungeonGenerator.new(7)
	a.create_start_room()
	b.create_start_room()
	_open_doors(a, 25)
	_open_doors(b, 25)
	check(a.tiles == b.tiles, "same seed + same doors = same map")
	var c := DungeonGenerator.new(8)
	c.create_start_room()
	_open_doors(c, 25)
	check(a.tiles != c.tiles, "different seed = different map")


func _test_generator_layout() -> void:
	for s in [1, 2, 3, 42, 1234]:
		var g := DungeonGenerator.new(s)
		g.create_start_room()
		_open_doors(g, 40)
		check(g.rooms.size() > 5, "seed %d grew more than 5 rooms (%d)" % [s, g.rooms.size()])
		var overlap := false
		for i in g.rooms.size():
			for j in range(i + 1, g.rooms.size()):
				var ri: Rect2i = g.rooms[i]["rect"]
				var rj: Rect2i = g.rooms[j]["rect"]
				if ri.intersects(rj):
					overlap = true
		check(not overlap, "seed %d: no overlapping rooms" % s)
		check(not g.doors.is_empty(), "seed %d: an unexplored door always remains" % s)
		# every room is reachable from the start room
		var start: Vector2i = g.rooms[0]["center"]
		var seen := {start: true}
		var frontier: Array = [start]
		while not frontier.is_empty():
			var p: Vector2i = frontier.pop_back()
			for d in DungeonGenerator.DIRS:
				var q: Vector2i = p + d
				if not seen.has(q) and g.is_walkable(q):
					seen[q] = true
					frontier.append(q)
		var unreachable := 0
		for room in g.rooms:
			if not seen.has(room["center"]):
				unreachable += 1
		check(unreachable == 0, "seed %d: all rooms reachable (%d unreachable)" % [s, unreachable])


func _test_movement_and_ownership() -> void:
	GameState.new_game(123, ["Ava", "Bo"], 1)
	check(GameState.player_order.size() == 2, "two heroes")
	var id: String = GameState.player_order[0]
	var start: Vector2i = GameState.players[id]["pos"]
	var moved := false
	for d in DungeonGenerator.DIRS:
		var q: Vector2i = start + d
		if GameState.dungeon.get_tile(q) == DungeonGenerator.Tile.FLOOR and GameState.player_at(q).is_empty():
			GameState.handle_intent(2, {"type": "move", "dir": d, "actor": id})
			check(GameState.players[id]["pos"] == start, "a peer cannot move a hero it does not own")
			GameState.handle_intent(1, {"type": "move", "dir": d, "actor": id})
			check(GameState.players[id]["pos"] == q, "owner can move hero")
			moved = true
			break
	check(moved, "found a floor tile to move onto")
	GameState.handle_intent(1, {"type": "move", "dir": Vector2i(1, 1), "actor": id})
	check(GameState.players[id]["pos"] != start + Vector2i(1, 1) or not moved, "diagonal / malformed moves rejected")


func _test_gm_validation() -> void:
	GameState.new_game(321, ["Cy"], 1)
	var id: String = GameState.player_order[0]
	var ev := {"kind": "player_action", "text": "", "actor": id, "chain": 0}
	var blank := {"type": "none", "ability": "", "dc": 0, "monster": "", "count": 0, "item": "", "reason": ""}
	var bad := blank.duplicate()
	bad["type"] = "spawn_monster"
	bad["monster"] = "ancient_red_dragon"
	bad["count"] = 9
	GameState.apply_gm_response({"narration": "A roar!", "actions": [bad]}, ev)
	check(GameState.monsters.is_empty(), "GM cannot spawn monsters outside the table")
	check(GameState.log_entries.back()["kind"] == "gm", "narration is logged")
	var good := blank.duplicate()
	good["type"] = "spawn_monster"
	good["monster"] = "goblin"
	good["count"] = 9
	GameState.apply_gm_response({"narration": "", "actions": [good, good]}, ev)
	check(GameState.monsters.size() <= GameData.balance.gm_max_spawns_per_room, "GM spawns capped per room (%d)" % GameState.monsters.size())
	check(GameState.monsters.size() > 0 and GameState.mode == "combat", "a GM spawn starts combat")
	var before := GameState.log_entries.size()
	var chk := blank.duplicate()
	chk["type"] = "ability_check"
	chk["ability"] = "dex"
	chk["dc"] = 99
	GameState.apply_gm_response({"narration": "", "actions": [chk]}, ev)
	var last: Dictionary = GameState.log_entries.back()
	check(GameState.log_entries.size() == before + 1 and last["kind"] == "roll", "ability check is rolled by the engine")
	check("DC 30" in str(last["text"]), "DC is clamped to 30")
	GameState.apply_gm_response({"narration": 42, "actions": "not a list"}, ev)
	check(true, "malformed GM reply does not crash")


func _test_combat_terminates() -> void:
	for s in [11, 12, 13]:
		GameState.new_game(s, ["Dee", "Eli"], 1)
		var ev := {"kind": "player_action", "text": "", "actor": GameState.player_order[0], "chain": 0}
		GameState.apply_gm_response({"narration": "", "actions": [{"type": "spawn_monster", "ability": "", "dc": 0, "monster": "goblin", "count": 2, "item": "", "reason": ""}]}, ev)
		var steps := 0
		while GameState.mode == "combat" and not GameState.game_over and steps < 2000:
			steps += 1
			var cur := GameState.current_actor()
			var hero: Dictionary = GameState.players[cur]
			var attacked := false
			for d in DungeonGenerator.DIRS:
				if hero["has_action"] and not GameState.monster_at(hero["pos"] + d).is_empty():
					GameState.handle_intent(1, {"type": "move", "dir": d, "actor": cur})
					attacked = true
					break
			if not attacked and GameState.current_actor() == cur:
				GameState.handle_intent(1, {"type": "end_turn", "actor": cur})
		check(steps < 2000, "seed %d: combat ends (%d steps, %s)" % [s, steps, "party lost" if GameState.game_over else "party won"])


## Regression: killing a monster that acts earlier in initiative used to hand the
## turn to the next monster without it acting, stalling combat.
func _test_kill_keeps_turn() -> void:
	GameState.new_game(55, ["Gil"], 1)
	var hid: String = GameState.player_order[0]
	var hero: Dictionary = GameState.players[hid]
	var ev := {"kind": "player_action", "text": "", "actor": hid, "chain": 0}
	GameState.apply_gm_response({"narration": "", "actions": [{"type": "spawn_monster", "ability": "", "dc": 0, "monster": "zombie", "count": 2, "item": "", "reason": ""}]}, ev)
	var mids: Array = GameState.monsters.keys()
	check(mids.size() == 2, "two zombies spawned")
	if mids.size() != 2:
		return
	var victim: Dictionary = GameState.monsters[mids[0]]
	# put the victim next to the hero, before the hero in initiative, and make it easy to kill
	var spot := Vector2i.ZERO
	for d in DungeonGenerator.DIRS:
		var q: Vector2i = hero["pos"] + d
		if GameState.dungeon.is_open_floor(q) and GameState.monster_at(q).is_empty():
			spot = d
			break
	check(spot != Vector2i.ZERO, "free tile next to hero")
	GameState.move_monster(mids[0], hero["pos"] + spot)
	victim["hp"] = 1
	victim["ac"] = -50
	GameState.initiative = [mids[0], hid, mids[1]]
	GameState.turn_index = 1
	for _try in 20:
		if not GameState.monsters.has(mids[0]):
			break
		hero["has_action"] = true
		GameState.handle_intent(1, {"type": "move", "dir": spot, "actor": hid})
	check(not GameState.monsters.has(mids[0]), "victim died")
	check(GameState.current_actor() == hid, "still the hero's turn after the kill (got %s)" % GameState.current_actor())


func _test_snapshot_roundtrip() -> void:
	GameState.new_game(77, ["Fen"], 1)
	var snap := GameState.to_snapshot(true)
	var tiles_before: Dictionary = GameState.dungeon.tiles.duplicate()
	GameState.dungeon = null
	GameState.apply_snapshot(snap)
	check(GameState.dungeon != null and GameState.dungeon.tiles == tiles_before, "snapshot restores the map")
	check(GameState.player_order.size() == 1, "snapshot restores the party")


# --- Phase A: pathfinding, awareness, death saves, replay ----------------------------

## A 10x5 field with a wall at x=5 that has one gap at the bottom.
func _field_passable(p: Vector2i) -> bool:
	if p.x < 0 or p.y < 0 or p.x > 9 or p.y > 4:
		return false
	return not (p.x == 5 and p.y < 4)


func _test_pathfinder() -> void:
	var path := Pathfinder.find_path(Vector2i(0, 0), Vector2i(9, 0), _field_passable)
	check(path.size() == 17, "A* detours through the gap: 17 steps (got %d)" % path.size())
	check(not path.is_empty() and path[-1] == Vector2i(9, 0), "path ends at the goal")
	var ok := true
	var prev := Vector2i(0, 0)
	for p in path:
		if absi(p.x - prev.x) + absi(p.y - prev.y) != 1 or not _field_passable(p):
			ok = false
		prev = p
	check(ok, "every step is one tile and passable")
	check(path == Pathfinder.find_path(Vector2i(0, 0), Vector2i(9, 0), _field_passable), "A* is deterministic")
	var sealed := func(p: Vector2i) -> bool: return _field_passable(p) and p != Vector2i(5, 4)
	check(Pathfinder.find_path(Vector2i(0, 0), Vector2i(9, 0), sealed).is_empty(), "no path through a sealed wall")
	check(Pathfinder.find_path(Vector2i(0, 0), Vector2i(9, 0), _field_passable, 5).is_empty(), "search stops at its budget")
	check(Pathfinder.find_path(Vector2i(2, 2), Vector2i(2, 2), _field_passable).is_empty(), "start == goal: empty path")


func _test_line_of_sight() -> void:
	var g := DungeonGenerator.new(1)
	for x in 10:
		for y in 5:
			g.tiles[Vector2i(x, y)] = DungeonGenerator.Tile.FLOOR
	for y in 4:
		g.tiles[Vector2i(5, y)] = DungeonGenerator.Tile.WALL
	check(g.has_line_of_sight(Vector2i(0, 4), Vector2i(9, 4)), "clear row: can see")
	check(not g.has_line_of_sight(Vector2i(0, 1), Vector2i(9, 1)), "wall in the way: cannot see")
	check(g.has_line_of_sight(Vector2i(1, 0), Vector2i(4, 3)) == g.has_line_of_sight(Vector2i(4, 3), Vector2i(1, 0)), "line of sight is symmetric")


func _test_room_index() -> void:
	var g := DungeonGenerator.new(9)
	g.create_start_room()
	_open_doors(g, 30)
	var g2 := DungeonGenerator.new(9)
	g2.from_dict(g.to_dict())
	var mismatches := 0
	for p in g.tiles:
		var scan := -1
		for room in g.rooms:
			if (room["rect"] as Rect2i).has_point(p):
				scan = int(room["id"])
		if g.room_at(p) != scan or g2.room_at(p) != scan:
			mismatches += 1
	check(mismatches == 0, "room index matches a full scan, also after from_dict (%d mismatches)" % mismatches)


## The farthest room from the start, for placing creatures out of sight.
func _far_room() -> Dictionary:
	var start: Vector2i = GameState.dungeon.rooms[0]["center"]
	var best: Dictionary = {}
	var best_d := -1
	for room in GameState.dungeon.rooms:
		var c: Vector2i = room["center"]
		var dist := absi(c.x - start.x) + absi(c.y - start.y)
		if dist > best_d:
			best = room
			best_d = dist
	return best


func _grow(n: int) -> void:
	for i in n:
		if GameState.dungeon.doors.is_empty():
			return
		var keys: Array = GameState.dungeon.doors.keys()
		keys.sort()
		GameState.dungeon.open_door(keys[0])


## Steps the first hero onto any free floor tile next to it.
func _step_somewhere(id: String) -> void:
	var p: Vector2i = GameState.players[id]["pos"]
	for d in DungeonGenerator.DIRS:
		var q: Vector2i = p + d
		if GameState.dungeon.get_tile(q) == DungeonGenerator.Tile.FLOOR and GameState.player_at(q).is_empty() and GameState.monster_at(q).is_empty():
			GameState.handle_intent(1, {"type": "move", "dir": d, "actor": id})
			return


func _test_encounters_are_local() -> void:
	GameState.new_game(404, ["Ira"], 1)
	var hid: String = GameState.player_order[0]
	_grow(30)
	var far := _far_room()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	check(GameState._spawn_monster("goblin", far, rng, false), "spawned a sleeping goblin far away")
	_step_somewhere(hid)
	check(GameState.mode == "explore", "a sleeping creature out of sight does not start a fight")
	check(GameState._spawn_monster("giant_rat", GameState.dungeon.rooms[0], rng, false), "spawned a sleeping rat in the hero's room")
	_step_somewhere(hid)
	check(GameState.mode == "combat", "a creature in the hero's room wakes and starts a fight")
	var far_in_fight := false
	for id in GameState.initiative:
		if GameState.monsters.has(id) and int(GameState.monsters[id]["room"]) == int(far["id"]):
			far_in_fight = true
	check(not far_in_fight, "the far goblin stays out of the fight")
	check(GameState.initiative.size() == 2, "initiative = the hero and the rat (got %d)" % GameState.initiative.size())


## An awake creature with no route to the party gives up, and the fight ends.
func _test_lose_track_ends_combat() -> void:
	GameState.new_game(505, ["Jo"], 1)
	var hid: String = GameState.player_order[0]
	var pocket := Vector2i(400, 400)
	GameState.dungeon.tiles[pocket] = DungeonGenerator.Tile.FLOOR
	var fake_room := {"id": -7, "rect": Rect2i(pocket, Vector2i.ONE), "entry": Vector2i.ZERO}
	var rng := RandomNumberGenerator.new()
	check(GameState._spawn_monster("orc", fake_room, rng, true), "spawned an awake orc in a sealed pocket")
	GameState._update_awareness()
	check(GameState.mode == "combat", "an awake creature starts a fight")
	for i in 6:
		if GameState.mode != "combat":
			break
		GameState.handle_intent(1, {"type": "end_turn", "actor": hid})
	check(GameState.mode == "explore", "the orc loses track and the fight ends")
	check(GameState.monsters.size() == 1 and not GameState.monsters.values()[0]["awake"], "the orc is asleep again")


## Initiative used to stop after 64 entries; big fights must still reach a hero's turn.
func _test_many_monsters_in_initiative() -> void:
	GameState.new_game(606, ["Kai"], 1)
	var hid: String = GameState.player_order[0]
	var rng := RandomNumberGenerator.new()
	for i in 100:
		var p := Vector2i(1000 + i * 3, 1000)
		GameState.dungeon.tiles[p] = DungeonGenerator.Tile.FLOOR
		GameState._spawn_monster("giant_rat", {"id": -100 - i, "rect": Rect2i(p, Vector2i.ONE), "entry": Vector2i.ZERO}, rng, true)
	var t0 := Time.get_ticks_msec()
	GameState._update_awareness()
	check(GameState.mode == "combat" and GameState.initiative.size() == 101, "101 actors in initiative")
	check(GameState.current_actor() == hid, "the hero gets a turn despite 100 monsters")
	for i in 4:
		if GameState.mode != "combat":
			break
		GameState.handle_intent(1, {"type": "end_turn", "actor": hid})
	check(GameState.mode == "explore", "all 100 lose track and the fight ends")
	check(Time.get_ticks_msec() - t0 < 2000, "100-monster fight resolves in under 2 s (%d ms)" % (Time.get_ticks_msec() - t0))


func _test_initiative_ties() -> void:
	GameState.new_game(707, ["Lu", "Mo"], 1)
	var a: String = GameState.player_order[0]
	var b: String = GameState.player_order[1]
	GameState._init_order = {a: [12, 10], b: [12, 16], "m50": [12, 16], "m7": [15, 8]}
	var ids: Array = [a, "m50", b, "m7"]
	ids.sort_custom(GameState._goes_before)
	check(ids == ["m7", b, "m50", a], "initiative: total, then Dexterity, then heroes first (got %s)" % str(ids))
	GameState._init_order.clear()


## Checks every death-save outcome against an independent roll of the same die.
func _test_death_saves() -> void:
	GameState.new_game(808, ["Nia"], 1)
	var hero: Dictionary = GameState.players[GameState.player_order[0]]
	var seen := {}
	for s in range(1, 200):
		GameState.dice = Dice.new(s)
		var twin := Dice.new(s)
		hero["hp"] = 0
		hero["death_successes"] = 0
		hero["death_failures"] = 0
		hero["stable"] = false
		hero["dead"] = false
		var n := int(twin.d20()["natural"])
		GameState._death_save(hero)
		var ok := true
		if n == 20:
			ok = hero["hp"] == 1 and hero["death_failures"] == 0
			seen["20"] = true
		elif n == 1:
			ok = hero["death_failures"] == 2
			seen["1"] = true
		elif n >= 10:
			ok = hero["death_successes"] == 1 and hero["hp"] == 0
			seen["hi"] = true
		else:
			ok = hero["death_failures"] == 1
			seen["lo"] = true
		if not ok:
			check(false, "death save with natural %d (seed %d)" % [n, s])
			return
		# play it out: always resolved within 4 more saves
		var rolls := 1
		while GameState.is_dying(hero) and rolls < 6:
			GameState._death_save(hero)
			rolls += 1
		if GameState.is_dying(hero):
			check(false, "death saves resolve within 5 rolls (seed %d)" % s)
			return
		if hero["dead"] and int(hero["death_failures"]) < 3:
			check(false, "dead only after 3 failures (seed %d)" % s)
			return
	check(seen.size() == 4, "saw natural 1, 20, a success and a failure (%s)" % str(seen.keys()))
	check(true, "death saves follow the SRD over 199 seeds")


func _test_stabilize() -> void:
	GameState.new_game(909, ["Oz", "Pia"], 1)
	var a: Dictionary = GameState.players[GameState.player_order[0]]
	var b: Dictionary = GameState.players[GameState.player_order[1]]
	var dir := Vector2i.ZERO
	for d in DungeonGenerator.DIRS:
		if GameState.dungeon.get_tile(a["pos"] + d) == DungeonGenerator.Tile.FLOOR:
			dir = d
			break
	b["pos"] = a["pos"] + dir
	b["hp"] = 0
	var start: Vector2i = a["pos"]
	for i in 50:
		if not GameState.is_dying(b):
			break
		GameState.handle_intent(1, {"type": "move", "dir": dir, "actor": a["id"]})
	check(a["pos"] == start, "tending a dying ally does not step onto them")
	check(int(b["hp"]) == 1 and not b["stable"], "stabilized out of combat, the ally comes to with 1 HP")


# --- replay: same seed + same inputs = same game -------------------------------------

func _test_replay_determinism() -> void:
	for s in [3, 17, 4242, 90001]:
		var first := _bot_game(s, 300)
		var invariant_err: String = first["error"]
		check(invariant_err.is_empty(), "seed %d: invariants hold every step (%s)" % [s, invariant_err])
		check(int(first["rooms"]) >= 3, "seed %d: the bot explored (%d rooms)" % [s, first["rooms"]])
		var second := _bot_game(s, 300)
		check(first["hash"] == second["hash"], "seed %d: replay gives the identical final state" % s)


## Plays a seeded 2-hero game through handle_intent only (no UI): walk to doors,
## fight what wakes up, tend dying allies. Returns {hash, rooms, error}.
func _bot_game(seed_value: int, steps: int) -> Dictionary:
	GameState.new_game(seed_value, ["Ann", "Bob"], 1)
	var err := ""
	for i in steps:
		if GameState.game_over:
			break
		var id := _bot_actor()
		if id.is_empty():
			break
		var d := _bot_step(id)
		if d == Vector2i.ZERO:
			if GameState.mode != "combat":
				break
			GameState.handle_intent(1, {"type": "end_turn", "actor": id})
		else:
			GameState.handle_intent(1, {"type": "move", "dir": d, "actor": id})
		if err.is_empty():
			err = _invariant_error()
			if not err.is_empty():
				err = "step %d: %s" % [i, err]
	return {"hash": _state_hash(), "rooms": GameState.dungeon.rooms.size(), "error": err}


func _bot_actor() -> String:
	if GameState.mode == "combat":
		var cur := GameState.current_actor()
		return cur if GameState.players.has(cur) else ""
	var alive := GameState.living_players()
	return alive[0] if not alive.is_empty() else ""


func _bot_step(id: String) -> Vector2i:
	var hero: Dictionary = GameState.players[id]
	var start: Vector2i = hero["pos"]
	var combat := GameState.mode == "combat"
	var can_act: bool = hero["has_action"] or not combat
	for d in DungeonGenerator.DIRS:
		var q: Vector2i = start + d
		if can_act and (not GameState.monster_at(q).is_empty() or not GameState._dying_ally_at(q).is_empty()):
			return d
	if combat and int(hero["moves_left"]) <= 0:
		return Vector2i.ZERO
	var first := {start: Vector2i.ZERO}
	var queue: Array = [start]
	while not queue.is_empty():
		var p: Vector2i = queue.pop_front()
		if p != start:
			var goal := false
			for d in DungeonGenerator.DIRS:
				if not GameState._dying_ally_at(p + d).is_empty() or (combat and not GameState.monster_at(p + d).is_empty()):
					goal = true
			if not combat and GameState.dungeon.get_tile(p) == DungeonGenerator.Tile.DOOR_UNEXPLORED:
				goal = true
			if goal:
				return first[p]
		if GameState.dungeon.get_tile(p) == DungeonGenerator.Tile.DOOR_UNEXPLORED:
			continue
		for d in DungeonGenerator.DIRS:
			var q: Vector2i = p + d
			if first.has(q) or not GameState.dungeon.is_walkable(q):
				continue
			if not GameState.player_at(q).is_empty() or not GameState.monster_at(q).is_empty() or not GameState._dying_ally_at(q).is_empty():
				continue
			first[q] = d if p == start else first[p]
			queue.append(q)
	return Vector2i.ZERO


## Rules that must hold after every input. Returns "" or what broke.
func _invariant_error() -> String:
	var gs := GameState
	if gs._monster_at_tile.size() != gs.monsters.size():
		return "tile index has %d entries for %d monsters" % [gs._monster_at_tile.size(), gs.monsters.size()]
	var awake := 0
	for id in gs.monsters:
		var m: Dictionary = gs.monsters[id]
		if gs._monster_at_tile.get(m["pos"]) != id:
			return "tile index wrong for %s" % id
		if m["awake"] != gs._awake_ids.has(id):
			return "awake index wrong for %s" % id
		if m["awake"]:
			awake += 1
			if gs.mode == "combat" and not gs.initiative.has(id):
				return "awake %s is not in initiative" % id
		elif gs.initiative.has(id):
			return "sleeping %s is in initiative" % id
		if not gs.player_at(m["pos"]).is_empty():
			return "%s shares a tile with a hero" % id
	if gs.mode == "explore" and (awake > 0 or not gs.initiative.is_empty()) and not gs.game_over:
		return "exploring with %d awake monsters" % awake
	if gs.mode == "combat":
		if gs.turn_index < 0 or gs.turn_index >= gs.initiative.size():
			return "turn_index %d out of range" % gs.turn_index
		for id in gs.initiative:
			if not gs.players.has(id) and not gs.monsters.has(id):
				return "initiative holds unknown %s" % id
	var tiles := {}
	for id in gs.player_order:
		var h: Dictionary = gs.players[id]
		if int(h["hp"]) < 0 or int(h["hp"]) > int(h["max_hp"]):
			return "%s has %d HP" % [id, h["hp"]]
		if h["dead"] and int(h["hp"]) != 0:
			return "%s is dead with HP" % id
		if int(h["hp"]) > 0:
			if tiles.has(h["pos"]):
				return "two heroes on one tile"
			tiles[h["pos"]] = true
	return ""


## Hash of everything that defines the game. map_version and log sequence numbers
## are left out on purpose: they count up across games so network clients can tell
## new data from old, so they differ between two runs of the same game.
func _state_hash() -> String:
	var snap := GameState.to_snapshot(true)
	snap.erase("map_version")
	var texts: Array = []
	for e in GameState.log_entries:
		texts.append([e["kind"], e["text"]])
	snap["log"] = texts
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(var_to_bytes([snap, GameState.dice.rng.state]))
	return ctx.finish().hex_encode()


# --- data files ----------------------------------------------------------------------

func _test_game_data() -> void:
	var errs := GameData.load_all()
	check(errs.is_empty(), "shipped data files load without errors %s" % str(errs))
	check(GameData.monsters.size() >= 6 and GameData.monsters.has("goblin"), "monsters loaded")
	check(GameData.hero_class("fighter").hp == 11, "fighter class loaded")
	check(GameData.fingerprint.length() == 64, "data fingerprint is a SHA-256")
	# the validator reports precise problems and falls back to safe values
	var bad: Array[String] = []
	var b := GameData.Balance.new(GameData._Reader.new({"speed_tiles": "fast", "sight_tiles": 2.5, "path_budget": 1}, "test.json", bad))
	check(b.speed_tiles == 6 and b.sight_tiles == 8 and b.path_budget == 16, "bad values fall back to defaults or clamp")
	var joined := "\n".join(bad)
	check("speed_tiles: expected a number" in joined, "reports a wrong type")
	check("sight_tiles: expected a whole number" in joined, "reports a fraction where a whole number is needed")
	check("path_budget: 1 is outside" in joined, "reports an out-of-range value")
	check("gm: missing" in joined, "reports a missing section")
	var bad2: Array[String] = []
	var m := GameData.MonsterSpec.new(GameData._Reader.new({"key": "x", "hp": "lots", "damage": "2d7"}, "m.json", bad2))
	check(m.hp == "1d6" and m.damage == "1d4", "bad dice fall back")
	check(bad2.size() >= 2 and "hp: 'lots' is not a dice expression" in "\n".join(bad2), "reports bad dice")


# --- input ---------------------------------------------------------------------------

func _test_input_bindings() -> void:
	var errs := InputBindings.apply(null)
	check(errs.is_empty(), "default bindings load without errors %s" % str(errs))
	for action in ["move_up", "move_down", "move_left", "move_right", "end_turn", "switch_hero", "talk", "cancel", "restart"]:
		check(InputMap.has_action(action) and InputMap.action_get_events(action).size() >= 2, "%s has keyboard and controller bindings" % action)
	var w := InputBindings.parse("key:W") as InputEventKey
	check(w != null and w.physical_keycode == KEY_W and w.keycode == KEY_NONE, "letters bind by physical key")
	var sp := InputBindings.parse("key:Space") as InputEventKey
	check(sp != null and sp.keycode == KEY_SPACE, "named keys bind by keycode")
	var pad := InputBindings.parse("joy_button:dpad_up") as InputEventJoypadButton
	check(pad != null and pad.button_index == JOY_BUTTON_DPAD_UP, "controller buttons by name")
	var ax := InputBindings.parse("joy_axis:left_y-") as InputEventJoypadMotion
	check(ax != null and ax.axis == JOY_AXIS_LEFT_Y and ax.axis_value < 0, "stick directions")
	for bad in ["key:NotAKey", "joy_button:z", "joy_axis:left_y", "nonsense", "joy_button:99"]:
		check(InputBindings.parse(bad) == null, "rejects '%s'" % bad)
	# a real key event reaches the action
	var ev := InputEventKey.new()
	ev.keycode = KEY_W
	ev.physical_keycode = KEY_W
	ev.pressed = true
	check(ev.is_action_pressed("move_up"), "pressing W triggers move_up")
	# the player's override replaces the defaults for that action only
	var cfg := ConfigFile.new()
	cfg.set_value("input", "end_turn", "key:Enter, joy_button:start")
	cfg.set_value("input", "talk", "key:Bogus")
	errs = InputBindings.apply(cfg)
	check(errs.size() == 1 and "talk" in errs[0], "a bad override is reported (%s)" % str(errs))
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	check(enter.is_action_pressed("end_turn") and not space.is_action_pressed("end_turn"), "override rebinds end_turn to Enter")
	check(InputBindings.describe("end_turn") == "Enter / pad start", "describe() reads bindings for players (%s)" % InputBindings.describe("end_turn"))
	InputBindings.apply(null)


func _test_move_repeater() -> void:
	var r := MoveRepeater.new(0.2, 0.1)
	check(r.press(Vector2i.UP) == Vector2i.UP, "a press moves at once")
	check(r.tick(0.15, true) == Vector2i.ZERO, "no repeat before the delay")
	check(r.tick(0.06, true) == Vector2i.UP, "repeats after the delay")
	check(r.tick(0.05, true) == Vector2i.ZERO and r.tick(0.06, true) == Vector2i.UP, "then every interval")
	check(r.tick(5.0, true) == Vector2i.UP and r.tick(0.01, true) == Vector2i.ZERO, "a frame hitch fires one step, not a burst")
	r.press(Vector2i.LEFT)
	r.release(Vector2i.UP)
	check(r.held() == Vector2i.LEFT, "releasing an old direction keeps the new one")
	check(r.tick(1.0, false) == Vector2i.ZERO and r.held() == Vector2i.ZERO, "letting go stops the repeat")


# --- events and presentation ---------------------------------------------------------

## Rebuilding every token's position from the event stream alone must land exactly
## where the rules put it: the presentation can't drift from the game.
func _test_event_stream_complete() -> void:
	for s in [3, 4242]:
		var pos := {}
		var dead := {}
		var seqs: Array = []
		var on_event := func(ev: Dictionary) -> void:
			seqs.append(ev["seq"])
			match ev["type"]:
				"reset":
					pos.clear()
					dead.clear()
				"spawned":
					pos[ev["actor"]] = ev["pos"]
				"moved":
					pos[ev["actor"]] = ev["to"]
				"monster_die":
					dead[ev["actor"]] = true
					pos.erase(ev["actor"])
		GameState.game_event.connect(on_event)
		var result := _bot_game(s, 300)
		GameState.game_event.disconnect(on_event)
		var wrong := 0
		for id in GameState.players:
			if pos.get(id) != GameState.players[id]["pos"]:
				wrong += 1
		for id in GameState.monsters:
			if pos.get(id) != GameState.monsters[id]["pos"]:
				wrong += 1
		var extra := pos.size() - GameState.players.size() - GameState.monsters.size()
		check(wrong == 0 and extra == 0, "seed %d: events alone reproduce every position (%d wrong, %d extra)" % [s, wrong, extra])
		var ordered := true
		for i in range(1, seqs.size()):
			if int(seqs[i]) != int(seqs[i - 1]) + 1:
				ordered = false
		check(ordered and seqs.size() > 50, "seed %d: event seq numbers are gapless (%d events)" % [s, seqs.size()])
		check(result["error"].is_empty(), "seed %d: still no invariant errors" % s)


func _test_presenter_playback() -> void:
	var pr := Presenter.new()
	var truth := {"h1": Vector2i(3, 0), "m1": Vector2i(5, 0)}
	var tf := func() -> Dictionary: return truth
	pr.push({"seq": 1, "type": "spawned", "actor": "h1", "pos": Vector2i(0, 0)})
	pr.push({"seq": 2, "type": "spawned", "actor": "m1", "pos": Vector2i(5, 0)})
	for i in 3:
		pr.push({"seq": 3 + i, "type": "moved", "actor": "h1", "from": Vector2i(i, 0), "to": Vector2i(i + 1, 0)})
	var played: Array = []
	pr.played.connect(func(ev): played.append(ev["seq"]))
	pr.advance(0.0, tf)
	check(pr.visual["h1"] == Vector2(0, 0), "a move doesn't show before time passes")
	pr.advance(0.045, tf)
	var mid: Vector2 = pr.visual["h1"]
	check(mid.x > 0.0 and mid.x < 1.0, "mid-move the token is between tiles (%s)" % str(mid))
	for i in 20:
		pr.advance(0.05, tf)
	check(pr.visual["h1"] == Vector2(3, 0) and not pr.busy(), "playback ends where the rules are")
	check(played == [1, 2, 3, 4, 5], "events play in order (%s)" % str(played))
	# a long queue catches up: 30 moves (2.7 s at normal speed) finish well under that
	for i in 30:
		pr.push({"seq": 10 + i, "type": "moved", "actor": "m1", "from": Vector2i(5, i), "to": Vector2i(5, i + 1)})
	truth["m1"] = Vector2i(5, 30)
	var t := 0.0
	while pr.busy() and t < 5.0:
		pr.advance(1.0 / 60.0, tf)
		t += 1.0 / 60.0
	check(t < 1.5, "a backlog of 30 moves catches up in %.2f s (< 1.5 s)" % t)
	# kills keep the dead monster on screen until its death plays
	pr.push({"seq": 50, "type": "attack", "attacker": "h1", "target": "m1", "hit": true, "crit": true, "damage": 9, "natural": 20})
	pr.push({"seq": 51, "type": "monster_die", "actor": "m1", "key": "orc", "name": "Orc", "pos": Vector2i(5, 30)})
	truth.erase("m1")
	check(pr.ghosts.has("m1"), "a dying monster is kept as a ghost")
	for i in 30:
		pr.advance(0.05, tf)
	check(not pr.ghosts.has("m1") and not pr.visual.has("m1"), "the ghost is gone after its death plays")
	check(pr.floaters.is_empty() or pr.floaters[0]["text"] == "CRIT 9", "a crit shows its damage")
	pr.push({"seq": 60, "type": "reset"})
	check(pr.visual.is_empty() and not pr.busy(), "reset clears the view")


func _test_sound_mapping() -> void:
	var hit := {"type": "attack", "hit": true, "crit": false, "damage": 5}
	check(AudioDirector.sound_for(hit, true) == ["attack_hit"], "hero hit")
	var crit := {"type": "attack", "hit": true, "crit": true, "damage": 9}
	check(AudioDirector.sound_for(crit, true) == ["attack_crit", "attack_hit"], "crit falls back to hit")
	var mhit := {"type": "attack", "hit": true, "crit": false, "attacker_key": "goblin"}
	check(AudioDirector.sound_for(mhit, false) == ["monster_hit_goblin", "monster_hit"], "monster-specific sound first")
	check(AudioDirector.sound_for({"type": "moved"}, false).is_empty(), "monsters' steps are silent")
	check(AudioDirector.sound_for({"type": "moved"}, true) == ["step"], "heroes' steps")
	check(AudioDirector.sound_for({"type": "death_save", "success": false}, true) == ["death_save_fail"], "death save sounds")
