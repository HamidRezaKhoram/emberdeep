class_name Settings
extends RefCounted
## Player settings in user://settings.cfg (on Linux: ~/.local/share/godot/app_userdata/Emberdeep/).
## The Claude API key is read from the ANTHROPIC_API_KEY environment variable first;
## a key saved in the file is stored as plain text, so the env var is preferred.

const PATH := "user://settings.cfg"

const DEFAULTS := {
	"player": {"name": "Adventurer"},
	"controls": {
		"move_repeat_delay": 0.22,      # seconds before a held move repeats
		"move_repeat_interval": 0.11,   # seconds between repeats while held
	},
	"audio": {                          # volumes, 0.0 to 1.0
		"master": 1.0,
		"music": 0.8,
		"sfx": 1.0,
		"ambience": 0.7,
	},
	"ui": {
		"scale": 1.0,                   # text and HUD size, 0.75 to 2.0 (e.g. 1.25 on a Steam Deck)
	},
	# [input] holds optional per-action overrides, e.g. end_turn="key:Enter, joy_button:a"
	# (defaults: data/input/bindings.json, formats: docs/INPUT.md)
	"gm": {
		"provider": "offline",            # offline | local | claude
		"claude_model": "claude-opus-5-5",
		"claude_effort": "low",           # low keeps narration snappy; raise for richer GMing
		"claude_api_key": "",
		"local_url": "http://127.0.0.1:11434/v1/chat/completions",  # Ollama; llama-server and LM Studio work too
		"local_model": "llama3.1:8b",
	},
}


static func load_config() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(PATH)  # a missing file is fine: defaults fill in below
	for section in DEFAULTS:
		for key in DEFAULTS[section]:
			if not cfg.has_section_key(section, key):
				cfg.set_value(section, key, DEFAULTS[section][key])
	return cfg


static func ui_scale(cfg: ConfigFile) -> float:
	return clampf(float(cfg.get_value("ui", "scale", 1.0)), 0.75, 2.0)


static func save_config(cfg: ConfigFile) -> void:
	cfg.save(PATH)


static func claude_api_key(cfg: ConfigFile) -> String:
	var env := OS.get_environment("ANTHROPIC_API_KEY")
	if not env.is_empty():
		return env
	return str(cfg.get_value("gm", "claude_api_key", ""))
