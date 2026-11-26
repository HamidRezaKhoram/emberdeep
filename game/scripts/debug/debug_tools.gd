class_name DebugTools
extends CanvasLayer
## Developer tools, added by main.gd in debug builds only (never in exported release
## builds). Commands that change the game go through GameState.handle_intent as
## "debug" intents, so they are recorded and replays still reproduce. See docs/DEBUG.md.

const REFRESH := 0.25        # seconds between overlay updates
const HASH_EVERY := 2.0      # the state hash is costlier; refresh it less often

var map_view: Node            # for the Presenter (queue length, slow motion)
var acting_id: Callable       # -> String, the hero commands apply to
var reload_assets: Callable   # forgets loaded art and sound so edited files show up
var _label := Label.new()
var _clock := 0.0
var _hash_clock := 0.0
var _hash := ""
var _spawn_index := 0


func _ready() -> void:
	layer = 50
	_label.position = Vector2(8, 8)
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color("e8f0ff"))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	_label.visible = "--overlay" in OS.get_cmdline_user_args()
	add_child(_label)
	GameState.debug_enabled = true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_overlay"):
		_label.visible = not _label.visible
		_clock = REFRESH
	elif event.is_action_pressed("debug_spawn"):
		var keys: Array = GameData.monsters.keys()
		run("/spawn %s" % keys[_spawn_index % keys.size()])
		_spawn_index += 1
	elif event.is_action_pressed("debug_heal"):
		run("/heal")
	elif event.is_action_pressed("debug_clear"):
		run("/clear")
	elif event.is_action_pressed("debug_slowmo"):
		run("/slowmo")
	elif event.is_action_pressed("debug_reload"):
		run("/reload")
	else:
		return
	get_viewport().set_input_as_handled()


## Runs a "/command" typed in the GM box or bound to a key. Returns false if `text`
## isn't a debug command (so it goes to the GM as usual).
func run(text: String) -> bool:
	if not text.begins_with("/"):
		return false
	var words := text.strip_edges().trim_prefix("/").split(" ", false)
	if words.is_empty():
		return true
	var actor: String = acting_id.call()
	match words[0]:
		"spawn":
			var key := words[1] if words.size() > 1 else str(GameData.monsters.keys()[0])
			var n := words[2].to_int() if words.size() > 2 else 1
			Net.send_intent({"type": "debug", "op": "spawn", "key": key, "count": n, "actor": actor})
		"heal":
			Net.send_intent({"type": "debug", "op": "heal", "actor": actor})
		"clear":
			Net.send_intent({"type": "debug", "op": "clear", "actor": actor})
		"slowmo":
			var pr: Presenter = map_view.presenter
			pr.time_scale = 0.25 if pr.time_scale == 1.0 else 1.0
			GameState.add_log("system", "[debug] animation speed x%.2f" % pr.time_scale)
		"reload":
			var errs := GameData.load_all()
			var input_errs := InputBindings.apply(Settings.load_config())
			if reload_assets.is_valid():
				reload_assets.call()
			GameState.add_log("system", "[debug] data, art and sound reloaded: %d errors%s" % [errs.size() + input_errs.size(), "" if errs.is_empty() else " (" + "; ".join(errs) + ")"])
		"hash":
			GameState.add_log("system", "[debug] state hash %s" % GameState.state_hash())
		_:
			GameState.add_log("system", "[debug] commands: /spawn <monster> [count], /heal, /clear, /slowmo, /reload, /hash. Keys: F1 overlay, F2 spawn, F3 heal, F4 clear, F7 slow motion, F8 reload")
	return true


func _process(delta: float) -> void:
	if not _label.visible:
		return
	_clock += delta
	_hash_clock += delta
	if _clock < REFRESH:
		return
	_clock = 0.0
	if _hash_clock >= HASH_EVERY and GameState.dice != null:
		_hash_clock = 0.0
		_hash = GameState.state_hash().left(12)
	var d: DungeonGenerator = GameState.dungeon
	var pr: Presenter = map_view.presenter
	_label.text = "\n".join([
		"Emberdeep %s   %d fps   %.1f ms/frame   %.0f MB" % [ProjectSettings.get_setting("application/config/version", "?"),
			Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0],
		"seed %d   rooms %d   tiles %d   doors left %d" % [GameState.world_seed, d.rooms.size() if d else 0, d.tiles.size() if d else 0, d.doors.size() if d else 0],
		"monsters %d (awake %d)   mode %s round %d   initiative %d" % [GameState.monsters.size(), GameState._awake_ids.size(), GameState.mode, GameState.round_num, GameState.initiative.size()],
		"events %d   queued %d   speed x%.2f   inputs recorded %d" % [GameState.event_seq, pr.queue.size(), pr.time_scale, GameState.recording.get("inputs", []).size()],
		"data errors %d   hash %s" % [GameData.errors.size(), _hash],
	])
