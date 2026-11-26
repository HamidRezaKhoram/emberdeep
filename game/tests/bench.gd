extends Node
## Performance budgets: grows a big dungeon, times the hot paths and fails (exit 1)
## when one is over its budget in budgets.json. Run: scripts/bench.sh
## The point is to catch cost that grows with the size of the world.

var budgets: Dictionary
var failures := 0


func _ready() -> void:
	budgets = JSON.parse_string(FileAccess.get_file_as_string("res://tests/budgets.json"))
	GameState.debug_enabled = false
	GameState.new_game(4242, ["Ann", "Bob"], 1)
	var hid: String = GameState.player_order[0]
	var d: DungeonGenerator = GameState.dungeon

	# grow the map, filling rooms like play does
	var opened := 0
	var t := Time.get_ticks_usec()
	while d.rooms.size() < int(budgets["rooms"]) and not d.doors.is_empty():
		var keys: Array = d.doors.keys()
		keys.sort()
		var room := d.open_door(keys[0])
		if not room.is_empty():
			GameState._populate_room(room)
		opened += 1
	report("open_door_ms", _ms(t) / maxi(opened, 1), "per door, %d doors" % opened)
	# make sure there are enough sleeping monsters spread around
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var i := 0
	while GameState.monsters.size() < int(budgets["monsters"]) and i < 5000:
		GameState._spawn_monster("giant_rat", d.rooms[1 + rng.randi() % (d.rooms.size() - 1)], rng, false)
		i += 1
	var far: Vector2i = d.rooms[-1]["center"]

	t = Time.get_ticks_usec()
	for k in 10000:
		d.room_at(far)
	report("room_at_ms", _ms(t) / 10000.0, "")
	t = Time.get_ticks_usec()
	for k in 10000:
		GameState.monster_at(far)
	report("monster_at_ms", _ms(t) / 10000.0, "")
	t = Time.get_ticks_usec()
	for k in 100:
		GameState._update_awareness()
	report("awareness_ms", _ms(t) / 100.0, "%d monsters in the dungeon" % GameState.monsters.size())

	# a hero step while exploring (the most frequent input)
	var hero: Dictionary = GameState.players[hid]
	t = Time.get_ticks_usec()
	var steps := 0
	for k in 50:
		for dir in DungeonGenerator.DIRS:
			var q: Vector2i = hero["pos"] + dir
			if d.get_tile(q) == DungeonGenerator.Tile.FLOOR and GameState.mode == "explore":
				GameState.handle_intent(1, {"type": "move", "dir": dir, "actor": hid})
				steps += 1
				break
	report("hero_step_ms", _ms(t) / maxi(steps, 1), "%d steps" % steps)

	# a full round of a 20-monster fight (every monster pathfinds and acts)
	GameState.new_game(77, ["Cy"], 1)
	d = GameState.dungeon
	for k in 60:
		if d.doors.is_empty():
			break
		var keys: Array = d.doors.keys()
		keys.sort()
		d.open_door(keys[0])
	hid = GameState.player_order[0]
	GameState.players[hid]["hp"] = 100000
	GameState.players[hid]["max_hp"] = 100000
	for k in 20:
		GameState._spawn_monster("goblin", d.rooms[1 + k % (d.rooms.size() - 1)], rng, true)
	GameState._update_awareness()
	t = Time.get_ticks_usec()
	var rounds := 0
	for k in 5:
		if GameState.mode != "combat":
			break
		GameState.handle_intent(1, {"type": "end_turn", "actor": hid})
		rounds += 1
	report("fight_round_ms", _ms(t) / maxi(rounds, 1), "%d monsters, %d rounds" % [GameState.initiative.size() - 1, rounds])

	# saves and network snapshots at the big size
	GameState.new_game(4242, ["Ann", "Bob"], 1)
	d = GameState.dungeon
	while d.rooms.size() < int(budgets["rooms"]) and not d.doors.is_empty():
		var keys: Array = d.doors.keys()
		keys.sort()
		var room := d.open_door(keys[0])
		if not room.is_empty():
			GameState._populate_room(room)
	t = Time.get_ticks_usec()
	var err := SaveGame.write("bench")
	report("save_write_ms", _ms(t), err)
	var before := GameState.state_hash()
	t = Time.get_ticks_usec()
	var r := SaveGame.load_slot("bench")
	report("save_load_ms", _ms(t), "identical" if GameState.state_hash() == before else "MISMATCH " + str(r["error"]))
	DirAccess.remove_absolute(SaveGame.path_for("bench"))
	report("snapshot_kb_no_map", var_to_bytes(GameState.to_snapshot(false, -1)).size() / 1024.0, "%d monsters" % GameState.monsters.size())

	# drawing the map: a full repaint (loading a game) and one door opening at 300 rooms
	var mv = load("res://scripts/world/map_view.gd").new()
	add_child(mv)
	t = Time.get_ticks_usec()
	mv.refresh()
	report("map_full_paint_ms", _ms(t), "%d tiles" % d.revealed.size())
	t = Time.get_ticks_usec()
	var painted := 0
	for k in 20:
		if d.doors.is_empty():
			break
		var keys: Array = d.doors.keys()
		keys.sort()
		d.open_door(keys[0])
		mv.refresh()
		painted += 1
	report("map_door_paint_ms", _ms(t) / maxi(painted, 1), "per door, incl. generation")
	GameState.game_event.disconnect(mv.presenter.push)
	mv.free()

	print("\nbench: %d over budget" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func report(key: String, value: float, note: String) -> void:
	var budget := float(budgets[key])
	var ok := value <= budget
	if not ok:
		failures += 1
	print("%s %-20s %10.4f  (budget %s)  %s" % ["ok  " if ok else "OVER", key, value, str(budget), note])


func _ms(start_usec: int) -> float:
	return (Time.get_ticks_usec() - start_usec) / 1000.0
