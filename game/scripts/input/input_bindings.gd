class_name InputBindings
extends RefCounted
## Registers the game's input actions in Godot's InputMap from data/input/bindings.json,
## then applies the player's overrides from settings.cfg ([input] section). Gameplay
## code only ever asks about actions ("end_turn"), never about keys, so keyboard,
## controller and remapped controls all take the same path. See docs/INPUT.md.

const DEFAULTS_PATH := "res://data/input/bindings.json"
const MOVES := {"move_up": Vector2i.UP, "move_down": Vector2i.DOWN, "move_left": Vector2i.LEFT, "move_right": Vector2i.RIGHT}
const DEADZONE := 0.5
const JOY_BUTTONS := {
	"a": JOY_BUTTON_A, "b": JOY_BUTTON_B, "x": JOY_BUTTON_X, "y": JOY_BUTTON_Y,
	"back": JOY_BUTTON_BACK, "start": JOY_BUTTON_START,
	"left_shoulder": JOY_BUTTON_LEFT_SHOULDER, "right_shoulder": JOY_BUTTON_RIGHT_SHOULDER,
	"left_stick": JOY_BUTTON_LEFT_STICK, "right_stick": JOY_BUTTON_RIGHT_STICK,
	"dpad_up": JOY_BUTTON_DPAD_UP, "dpad_down": JOY_BUTTON_DPAD_DOWN,
	"dpad_left": JOY_BUTTON_DPAD_LEFT, "dpad_right": JOY_BUTTON_DPAD_RIGHT,
}
const JOY_AXES := {"left_x": JOY_AXIS_LEFT_X, "left_y": JOY_AXIS_LEFT_Y, "right_x": JOY_AXIS_RIGHT_X, "right_y": JOY_AXIS_RIGHT_Y}

## action -> human label, in file order
static var labels: Dictionary = {}
## action -> the binding strings in effect (defaults or the player's override)
static var bindings: Dictionary = {}


## Registers every action. Returns problems found ("action: binding: what is wrong");
## a bad binding is skipped, the rest of the action still works.
static func apply(cfg: ConfigFile = null) -> Array[String]:
	var errors: Array[String] = []
	labels.clear()
	bindings.clear()
	var data = JSON.parse_string(FileAccess.get_file_as_string(DEFAULTS_PATH))
	if typeof(data) != TYPE_DICTIONARY or typeof(data.get("actions")) != TYPE_DICTIONARY:
		errors.append("%s: missing or not valid JSON" % DEFAULTS_PATH)
		return errors
	for action in data["actions"]:
		var spec: Dictionary = data["actions"][action]
		labels[action] = str(spec.get("label", action))
		var list: Array = spec.get("bind", [])
		if cfg and cfg.has_section_key("input", action):
			list = str(cfg.get_value("input", action)).split(",", false)
		var strings: Array[String] = []
		for b in list:
			strings.append(str(b).strip_edges())
		bindings[action] = strings
		if InputMap.has_action(action):
			InputMap.erase_action(action)
		InputMap.add_action(action, DEADZONE)
		for b in strings:
			var ev := parse(b)
			if ev == null:
				errors.append("%s: '%s' is not a binding (see docs/INPUT.md)" % [action, b])
			else:
				InputMap.action_add_event(action, ev)
	for e in errors:
		push_warning("Input: " + e)
	return errors


## "key:W", "joy_button:a", "joy_axis:left_y-" -> an InputEvent, or null.
static func parse(binding: String) -> InputEvent:
	var parts := binding.split(":", true, 1)
	if parts.size() != 2:
		return null
	var kind := parts[0].strip_edges().to_lower()
	var value := parts[1].strip_edges()
	match kind:
		"key":
			var code := OS.find_keycode_from_string(value)
			if code == KEY_NONE:
				return null
			var k := InputEventKey.new()
			# InputMap matches keycode when set, else physical_keycode: so letters get
			# only the physical code (layout-independent), other keys only the keycode.
			if _is_letter(value):
				k.physical_keycode = code
			else:
				k.keycode = code
			return k
		"joy_button":
			var b := InputEventJoypadButton.new()
			if JOY_BUTTONS.has(value.to_lower()):
				b.button_index = JOY_BUTTONS[value.to_lower()]
			elif value.is_valid_int() and value.to_int() >= 0 and value.to_int() < JOY_BUTTON_SDL_MAX:
				b.button_index = value.to_int()
			else:
				return null
			return b
		"joy_axis":
			var sign := value.right(1)
			var axis := value.left(-1).to_lower()
			if (sign != "+" and sign != "-") or not JOY_AXES.has(axis):
				return null
			var m := InputEventJoypadMotion.new()
			m.axis = JOY_AXES[axis]
			m.axis_value = 1.0 if sign == "+" else -1.0
			return m
	return null


## Letters are bound by physical position, so WASD stays WASD on AZERTY layouts.
static func _is_letter(name: String) -> bool:
	return name.length() == 1 and name.to_upper() >= "A" and name.to_upper() <= "Z"


## "W / Up / D-pad up": the bindings of an action as players read them.
static func describe(action: String) -> String:
	var out: Array[String] = []
	for b in bindings.get(action, []):
		var parts: PackedStringArray = str(b).split(":", true, 1)
		if parts.size() != 2:
			continue
		match parts[0]:
			"key": out.append(parts[1])
			"joy_button": out.append("pad " + parts[1].replace("_", " "))
			"joy_axis": out.append("stick " + parts[1].replace("_", " "))
	return " / ".join(out)


## Short help text for the HUD, keyboard bindings only (the first of each action).
static func help_text() -> String:
	var first := func(action: String) -> String:
		for b in bindings.get(action, []):
			if str(b).begins_with("key:"):
				return str(b).trim_prefix("key:")
		return "?"
	return "Move: %s/%s/%s/%s  Attack or help: walk into them\n%s: end turn  %s: switch hero  %s: talk  %s: leave text box" % [
		first.call("move_up"), first.call("move_left"), first.call("move_down"), first.call("move_right"),
		first.call("end_turn"), first.call("switch_hero"), first.call("talk"), first.call("cancel")]
