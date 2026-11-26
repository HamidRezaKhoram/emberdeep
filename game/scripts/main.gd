extends Node
## Entry scene. Builds the menu and the in-game HUD in code so the skeleton's .tscn
## files stay trivial; move these into real scenes as the UI grows.

const MapViewScript := preload("res://scripts/world/map_view.gd")
const PROVIDERS := ["offline", "local", "claude"]

var cfg: ConfigFile
var gm: GameMaster
var map_view: Node2D
var in_game := false
var controlled_id := ""
var repeater: MoveRepeater
var audio: AudioDirector
var ui_scale := 1.0

# menu widgets
var menu: Control
var name_edit: LineEdit
var heroes_spin: SpinBox
var seed_edit: LineEdit
var provider_option: OptionButton
var ip_edit: LineEdit
var lan_list: ItemList
var menu_status: Label

# HUD widgets
var hud: Control
var status_label: Label
var log_label: RichTextLabel
var input_line: LineEdit
var help_label: Label

const HUD_WIDTH := 420


func _ready() -> void:
	cfg = Settings.load_config()
	InputBindings.apply(cfg)
	repeater = MoveRepeater.new(float(cfg.get_value("controls", "move_repeat_delay")), float(cfg.get_value("controls", "move_repeat_interval")))
	ui_scale = Settings.ui_scale(cfg)
	map_view = MapViewScript.new()
	map_view.visible = false
	add_child(map_view)
	audio = AudioDirector.new()
	add_child(audio)
	audio.apply_volumes(cfg)
	map_view.presenter.played.connect(audio.on_played)
	GameState.log_added.connect(audio.on_log)
	var ui := CanvasLayer.new()
	add_child(ui)
	_build_menu(ui)
	_build_hud(ui)
	_apply_ui_scale()
	GameState.log_added.connect(_on_log)
	GameState.changed.connect(_on_state_changed)
	Net.status.connect(func(t): menu_status.text = t)
	Net.lan_game_found.connect(_on_lan_found)
	Net.joined.connect(_show_game)
	Net.start_discovery()
	if "--smoke" in OS.get_cmdline_user_args():
		_run_smoke.call_deferred()


# --- menu ------------------------------------------------------------------------

func _build_menu(ui: CanvasLayer) -> void:
	menu = CenterContainer.new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(menu)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(460 * ui_scale, 0)
	box.add_theme_constant_override("separation", 8)
	menu.add_child(box)

	var title := Label.new()
	title.text = "EMBERDEEP"
	title.add_theme_font_size_override("font_size", roundi(40 * ui_scale))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	name_edit = _labeled(box, "Your name", LineEdit.new())
	name_edit.text = str(cfg.get_value("player", "name"))
	heroes_spin = _labeled(box, "Heroes on this screen (hot-seat)", SpinBox.new())
	heroes_spin.min_value = 1
	heroes_spin.max_value = 4
	heroes_spin.value = 1
	seed_edit = _labeled(box, "World seed (blank = random)", LineEdit.new())
	provider_option = _labeled(box, "Game master", OptionButton.new())
	provider_option.add_item("Offline storyteller (no AI)")
	provider_option.add_item("Local LLM (Ollama / llama.cpp / LM Studio)")
	provider_option.add_item("Claude API (needs ANTHROPIC_API_KEY)")
	provider_option.select(maxi(0, PROVIDERS.find(str(cfg.get_value("gm", "provider")))))

	_button(box, "Play on this computer", _start_local)
	_button(box, "Host a LAN game", _host_lan)
	box.add_child(HSeparator.new())
	ip_edit = _labeled(box, "Join by address", LineEdit.new())
	ip_edit.placeholder_text = "192.168.1.20"
	_button(box, "Join", func(): _join(ip_edit.text.strip_edges()))
	var found := Label.new()
	found.text = "Games on your network (double-click to join):"
	box.add_child(found)
	lan_list = ItemList.new()
	lan_list.custom_minimum_size = Vector2(0, 90)
	lan_list.item_activated.connect(func(i): _join(str(lan_list.get_item_metadata(i))))
	box.add_child(lan_list)
	menu_status = Label.new()
	menu_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(menu_status)


func _labeled(parent: Control, text: String, control: Control) -> Control:
	var l := Label.new()
	l.text = text
	parent.add_child(l)
	parent.add_child(control)
	return control


func _button(parent: Control, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)


func _save_menu_choices() -> void:
	cfg.set_value("player", "name", name_edit.text.strip_edges())
	cfg.set_value("gm", "provider", PROVIDERS[provider_option.selected])
	Settings.save_config(cfg)


func _start_local() -> void:
	_save_menu_choices()
	var names: Array = [name_edit.text]
	for i in range(1, int(heroes_spin.value)):
		names.append("Companion %d" % (i + 1))
	_start_gm()
	GameState.new_game(seed_edit.text.to_int(), names, 1)
	_show_game()


func _host_lan() -> void:
	_save_menu_choices()
	if Net.host(name_edit.text) != OK:
		return
	_start_gm()
	GameState.new_game(seed_edit.text.to_int(), [name_edit.text], 1)
	_show_game()


func _join(address: String) -> void:
	if address.is_empty():
		return
	_save_menu_choices()
	Net.join(address, name_edit.text)


func _on_lan_found(info: Dictionary) -> void:
	var ip := str(info["ip"])
	for i in lan_list.item_count:
		if str(lan_list.get_item_metadata(i)) == ip:
			return
	var idx := lan_list.add_item("%s's game (%d heroes) - %s" % [info.get("name", "?"), int(info.get("players", 0)), ip])
	lan_list.set_item_metadata(idx, ip)


## The GM lives on the host. Clients never create one.
func _start_gm() -> void:
	if gm:
		GameState.gm_event.disconnect(gm._on_gm_event)
		gm.queue_free()
	gm = GameMaster.new()
	add_child(gm)
	gm.setup(_make_provider())


func _make_provider() -> GMProvider:
	match PROVIDERS[provider_option.selected]:
		"local":
			var p := LocalLLMProvider.new()
			p.url = str(cfg.get_value("gm", "local_url"))
			p.model = str(cfg.get_value("gm", "local_model"))
			return p
		"claude":
			var key := Settings.claude_api_key(cfg)
			if key.is_empty():
				GameState.add_log("system", "No ANTHROPIC_API_KEY found; using the offline storyteller.")
				return OfflineProvider.new()
			var p := AnthropicProvider.new()
			p.api_key = key
			p.model = str(cfg.get_value("gm", "claude_model"))
			p.effort = str(cfg.get_value("gm", "claude_effort"))
			return p
	return OfflineProvider.new()


# --- HUD -------------------------------------------------------------------------

func _build_hud(ui: CanvasLayer) -> void:
	hud = PanelContainer.new()
	hud.anchor_left = 1.0
	hud.anchor_right = 1.0
	hud.anchor_bottom = 1.0
	hud.offset_left = -HUD_WIDTH
	hud.visible = false
	ui.add_child(hud)
	var box := VBoxContainer.new()
	hud.add_child(box)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status_label)
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(log_label)
	input_line = LineEdit.new()
	input_line.placeholder_text = "Enter: tell the GM what you do or say"
	input_line.text_submitted.connect(_on_say)
	box.add_child(input_line)
	help_label = Label.new()
	help_label.text = InputBindings.help_text()
	help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(help_label)


## One theme for every menu and HUD control: text size and panel width follow the
## player's ui scale. The map is not scaled (it has its own camera).
func _apply_ui_scale() -> void:
	var theme := Theme.new()
	theme.default_font_size = roundi(16 * ui_scale)
	menu.theme = theme
	hud.theme = theme
	help_label.add_theme_font_size_override("font_size", roundi(12 * ui_scale))
	var width := roundi(HUD_WIDTH * ui_scale)
	hud.offset_left = -width
	map_view.hud_width = width


func _show_game() -> void:
	in_game = true
	menu.visible = false
	hud.visible = true
	map_view.visible = true
	controlled_id = ""
	for id in GameState.player_order:
		if int(GameState.players[id]["owner"]) == Net.local_peer_id():
			controlled_id = id
			break
	_on_state_changed()


func _unhandled_input(event: InputEvent) -> void:
	if not in_game:
		return
	if input_line.has_focus():
		if event.is_action_pressed("cancel"):
			input_line.release_focus()
			get_viewport().set_input_as_handled()
		return
	for action in InputBindings.MOVES:
		if event.is_action_released(action):
			repeater.release(InputBindings.MOVES[action])
		elif event.is_action_pressed(action):
			# moves fire on the press itself (no waiting for the next frame); holding
			# repeats on the game's clock in _process
			_send_move(repeater.press(InputBindings.MOVES[action]))
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("end_turn"):
		Net.send_intent({"type": "end_turn", "actor": _acting_id()})
	elif event.is_action_pressed("switch_hero"):
		_cycle_hero()
	elif event.is_action_pressed("talk"):
		input_line.grab_focus.call_deferred()   # deferred: the same key must not also submit the box
	elif event.is_action_pressed("restart") and GameState.game_over and not Net.is_online():
		_start_local()
	else:
		return
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not in_game or input_line.has_focus():
		return
	var held := repeater.held()
	if held == Vector2i.ZERO:
		return
	var action := ""
	for a in InputBindings.MOVES:
		if InputBindings.MOVES[a] == held:
			action = a
	_send_move(repeater.tick(delta, Input.is_action_pressed(action)))


func _send_move(dir: Vector2i) -> void:
	if dir != Vector2i.ZERO:
		Net.send_intent({"type": "move", "dir": dir, "actor": _acting_id()})


## In combat, hot-seat players automatically control whoever's turn it is.
func _acting_id() -> String:
	var cur := GameState.current_actor()
	if GameState.players.has(cur) and int(GameState.players[cur]["owner"]) == Net.local_peer_id():
		return cur
	# a downed hero can't act: hand control to one of ours who is still standing
	if GameState.players.has(controlled_id) and int(GameState.players[controlled_id]["hp"]) <= 0:
		for id in GameState.player_order:
			if int(GameState.players[id]["owner"]) == Net.local_peer_id() and int(GameState.players[id]["hp"]) > 0:
				controlled_id = id
				break
	return controlled_id


func _cycle_hero() -> void:
	var mine: Array = GameState.player_order.filter(func(id): return int(GameState.players[id]["owner"]) == Net.local_peer_id())
	if mine.is_empty():
		return
	controlled_id = mine[(mine.find(controlled_id) + 1) % mine.size()]
	_on_state_changed()


func _on_say(text: String) -> void:
	input_line.clear()
	input_line.release_focus()
	if not text.strip_edges().is_empty():
		Net.send_intent({"type": "say", "text": text, "actor": _acting_id()})


func _on_state_changed() -> void:
	if not in_game:
		return
	map_view.focus_id = _acting_id()
	audio.focus_id = map_view.focus_id
	map_view.refresh()
	var lines: Array = []
	for id in GameState.player_order:
		var h: Dictionary = GameState.players[id]
		var marker := ">" if id == _acting_id() else " "
		var cond := GameState.hero_condition(h)
		lines.append("%s %s  HP %d/%d  AC %d%s" % [marker, h["name"], h["hp"], h["max_hp"], h["ac"], "" if cond == "ok" else "  (" + cond + ")"])
	var header := "Exploring" if GameState.mode == "explore" else "COMBAT, round %d" % GameState.round_num
	var cur := GameState.current_actor()
	if GameState.players.has(cur):
		var h: Dictionary = GameState.players[cur]
		header += ": %s's turn (%d moves%s)" % [h["name"], h["moves_left"], ", attack ready" if h["has_action"] else ""]
	status_label.text = header + "\n" + "\n".join(lines)


func _on_log(entry: Dictionary) -> void:
	var text := str(entry["text"]).replace("[", "[lb]")
	match str(entry["kind"]):
		"gm": log_label.append_text("[color=#f0d9a0][i]%s[/i][/color]\n\n" % text)
		"player": log_label.append_text("[color=#8fd3ff]%s[/color]\n" % text)
		"roll": log_label.append_text("[color=#9be07a]%s[/color]\n" % text)
		"combat": log_label.append_text("[color=#ff9f8a]%s[/color]\n" % text)
		_: log_label.append_text("[color=#a9a3b3]%s[/color]\n" % text)


# --- dev smoke run -----------------------------------------------------------------

## `emberdeep.x86_64 -- --smoke [--shot=/path/to.png] [--steps=N]`
## Starts a seeded 2-hero hot-seat game and plays it by sending real key events
## through the input pipeline (walks to the nearest unexplored door, fights what it
## meets), then saves a screenshot, prints a summary and quits. A seed for playtest bots.
func _run_smoke() -> void:
	var shot := "user://smoke.png"
	var steps := 400
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot = a.trim_prefix("--shot=")
		elif a.begins_with("--steps="):
			steps = a.trim_prefix("--steps=").to_int()
	seed_edit.text = "4242"
	heroes_spin.value = 2
	provider_option.select(0)
	_start_local()
	var keys := {Vector2i.UP: KEY_W, Vector2i.DOWN: KEY_S, Vector2i.LEFT: KEY_A, Vector2i.RIGHT: KEY_D}
	for i in steps:
		if GameState.game_over:
			break
		var d := _smoke_next_step()
		_smoke_press(keys[d] if d != Vector2i.ZERO else KEY_SPACE)
		await get_tree().process_frame
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png(shot)
	var hp: Array = []
	for id in GameState.player_order:
		hp.append("%s %d/%d" % [GameState.players[id]["name"], GameState.players[id]["hp"], GameState.players[id]["max_hp"]])
	print("SMOKE rooms=%d unexplored_doors=%d monsters=%d mode=%s game_over=%s log=%d heroes=[%s] shot=%s" % [
		GameState.dungeon.rooms.size(), GameState.dungeon.doors.size(), GameState.monsters.size(),
		GameState.mode, GameState.game_over, GameState.log_seq, ", ".join(hp), ProjectSettings.globalize_path(shot)])
	get_tree().quit()


func _smoke_press(key: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()   # like a real keyboard: logical and physical code
		ev.keycode = key
		ev.physical_keycode = key
		ev.pressed = pressed
		Input.parse_input_event(ev)


## First step of a shortest path to a goal (a foe to hit in combat, else an unexplored
## door), or ZERO for "end turn".
func _smoke_next_step() -> Vector2i:
	var id := _acting_id()
	if not GameState.players.has(id):
		return Vector2i.ZERO
	var hero: Dictionary = GameState.players[id]
	var start: Vector2i = hero["pos"]
	var combat := GameState.mode == "combat"
	if combat:
		for d in DungeonGenerator.DIRS:
			if hero["has_action"] and not GameState.monster_at(start + d).is_empty():
				return d
		if int(hero["moves_left"]) <= 0:
			return Vector2i.ZERO
	var first := {start: Vector2i.ZERO}
	var queue: Array = [start]
	while not queue.is_empty():
		var p: Vector2i = queue.pop_front()
		var goal := false
		if combat:
			for d in DungeonGenerator.DIRS:
				if not GameState.monster_at(p + d).is_empty():
					goal = true
		else:
			goal = GameState.dungeon.get_tile(p) == DungeonGenerator.Tile.DOOR_UNEXPLORED
		if goal and p != start:
			return first[p]
		if GameState.dungeon.get_tile(p) == DungeonGenerator.Tile.DOOR_UNEXPLORED:
			continue
		for d in DungeonGenerator.DIRS:
			var q: Vector2i = p + d
			if first.has(q) or not GameState.dungeon.is_walkable(q):
				continue
			if not GameState.player_at(q).is_empty() or not GameState.monster_at(q).is_empty():
				continue
			first[q] = d if p == start else first[p]
			queue.append(q)
	return Vector2i.ZERO
