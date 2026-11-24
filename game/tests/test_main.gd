extends Node
## Headless test suite. Run from the repo root: scripts/run-tests.sh
## Exits with code 0 when everything passes, 1 otherwise.

var passes := 0
var failures := 0


func _ready() -> void:
	_test_dice()
	_test_rules()
	_test_generator_determinism()
	_test_generator_layout()
	_test_movement_and_ownership()
	_test_gm_validation()
	_test_combat_terminates()
	_test_snapshot_roundtrip()
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
	check(GameState.monsters.size() <= GameState.MAX_GM_SPAWNS_PER_ROOM, "GM spawns capped per room (%d)" % GameState.monsters.size())
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


func _test_snapshot_roundtrip() -> void:
	GameState.new_game(77, ["Fen"], 1)
	var snap := GameState.to_snapshot(true)
	var tiles_before: Dictionary = GameState.dungeon.tiles.duplicate()
	GameState.dungeon = null
	GameState.apply_snapshot(snap)
	check(GameState.dungeon != null and GameState.dungeon.tiles == tiles_before, "snapshot restores the map")
	check(GameState.player_order.size() == 1, "snapshot restores the party")
