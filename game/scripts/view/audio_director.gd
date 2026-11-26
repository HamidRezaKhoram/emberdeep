class_name AudioDirector
extends Node
## Plays sound for what the Presenter shows, in sync with the animation. Files are
## found by name under res://audio/ (docs/CONTENT_PLAN.md, "Integration contract:
## audio"); a missing file is silence, so sounds can be added one at a time.
##
##   audio/sfx/<event>.wav|ogg        variants: <event>_2, _3 … picked at random
##   audio/music/explore.ogg, combat.ogg, victory.ogg, defeat.ogg   crossfaded
##   audio/ambience/<room kind>.ogg   follows the room the focused hero is in

const SFX_DIR := "res://audio/sfx/"
const MUSIC_DIR := "res://audio/music/"
const AMBIENCE_DIR := "res://audio/ambience/"
const EXTENSIONS := ["wav", "ogg"]
const MAX_VARIANTS := 9
const VOICES := 8                 # sound effects that can overlap
const CROSSFADE := 1.0            # seconds
const BUSES := ["Music", "SFX", "Ambience"]

var focus_id := ""                # the hero whose room sets the ambience
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _music: Array[AudioStreamPlayer] = []   # two players, for crossfades
var _music_track := ""
var _ambience: Array[AudioStreamPlayer] = []
var _ambience_track := ""
var _cache: Dictionary = {}       # path stem -> Array of AudioStream ([] = no file)
var _rng := RandomNumberGenerator.new()   # picks variants; view-only, never the game's dice


func _ready() -> void:
	for bus in BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
	for i in VOICES:
		_voices.append(_player("SFX"))
	for i in 2:
		_music.append(_player("Music"))
		_ambience.append(_player("Ambience"))
	_rng.randomize()


func apply_volumes(cfg: ConfigFile) -> void:
	_set_volume("Master", float(cfg.get_value("audio", "master", 1.0)))
	_set_volume("Music", float(cfg.get_value("audio", "music", 0.8)))
	_set_volume("SFX", float(cfg.get_value("audio", "sfx", 1.0)))
	_set_volume("Ambience", float(cfg.get_value("audio", "ambience", 0.7)))


## Connect to Presenter.played.
func on_played(ev: Dictionary) -> void:
	play_sfx(sound_for(ev, GameState.players.has(str(ev.get("actor", ev.get("attacker", ""))))))
	match ev.get("type"):
		"reset", "combat_end":
			_play_music("explore")
		"combat_start":
			_play_music("combat")
		"party_fallen":
			_play_music("defeat")
		"moved", "spawned":
			if ev.get("actor") == focus_id:
				_update_ambience()


## GM narration arriving (connect to GameState.log_added).
func on_log(entry: Dictionary) -> void:
	if entry.get("kind") == "gm":
		play_sfx(["gm_speak"])


## Which sound files an event may play, most specific first. `by_hero`: the actor (or
## attacker) is a hero. Pure function, so the mapping is testable and documented here.
static func sound_for(ev: Dictionary, by_hero: bool) -> Array[String]:
	var out: Array[String] = []
	match ev.get("type"):
		"moved":
			if by_hero:
				out.append("step")
		"attack":
			if by_hero:
				out.append("attack_crit" if ev["crit"] else ("attack_hit" if ev["hit"] else "attack_miss"))
				if ev["crit"]:
					out.append("attack_hit")
			else:
				var key := str(ev.get("attacker_key", ""))
				var name := "monster_hit" if ev["hit"] else "monster_miss"
				if key != "":
					out.append("%s_%s" % [name, key])
				out.append(name)
		"monster_die":
			if ev.get("key", "") != "":
				out.append("monster_die_%s" % ev["key"])
			out.append("monster_die")
		"death_save":
			out.append("death_save_success" if ev["success"] else "death_save_fail")
		"turn_start":
			if by_hero:
				out.append("turn_start")
		"door_open", "door_blocked", "combat_start", "combat_end", "hero_down", "hero_die", \
		"check_success", "check_fail", "pickup", "woke", "lost_track", "stabilized", "revived":
			out.append(str(ev["type"]))
	return out


## Plays the first of `names` that has a file. Returns the name played, or "".
func play_sfx(names: Array[String]) -> String:
	for n in names:
		var streams := _streams(SFX_DIR + n)
		if streams.is_empty():
			continue
		var p := _voices[_next_voice]
		_next_voice = (_next_voice + 1) % _voices.size()
		p.stream = streams[_rng.randi() % streams.size()]
		p.play()
		return n
	return ""


## Every variant of a sound: stem.wav/ogg, stem_2…stem_9. Cached, including misses.
func _streams(stem: String) -> Array:
	if _cache.has(stem):
		return _cache[stem]
	var out: Array = []
	for i in MAX_VARIANTS:
		var s := stem if i == 0 else "%s_%d" % [stem, i + 1]
		for ext in EXTENSIONS:
			var path := "%s.%s" % [s, ext]
			if ResourceLoader.exists(path):
				out.append(load(path))
				break
	_cache[stem] = out
	return out


func _play_music(track: String) -> void:
	if track == _music_track:
		return
	_music_track = track
	_crossfade(_music, _streams(MUSIC_DIR + track))


func _update_ambience() -> void:
	if not GameState.players.has(focus_id) or GameState.dungeon == null:
		return
	var rid := GameState.dungeon.room_at(GameState.players[focus_id]["pos"])
	if rid < 0:
		return   # corridors keep the last room's ambience
	var kind := str(GameState.dungeon.rooms[rid]["kind"]).replace(" ", "_")
	if kind == _ambience_track:
		return
	_ambience_track = kind
	_crossfade(_ambience, _streams(AMBIENCE_DIR + kind))


## Fades the playing one of a pair out and the other in with `streams` (or to silence).
func _crossfade(pair: Array[AudioStreamPlayer], streams: Array) -> void:
	var out := pair[0] if pair[0].playing else pair[1]
	var into := pair[1] if out == pair[0] else pair[0]
	if not out.playing and streams.is_empty():
		return   # silence to silence: nothing to fade
	var tw := create_tween().set_parallel(true)
	if out.playing:
		tw.tween_property(out, "volume_db", -60.0, CROSSFADE)
		tw.chain().tween_callback(out.stop)
	if not streams.is_empty():
		into.stream = streams[_rng.randi() % streams.size()]
		into.volume_db = -60.0
		into.play()
		tw.tween_property(into, "volume_db", 0.0, CROSSFADE)


func _player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


func _set_volume(bus: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(clampf(linear, 0.0, 1.0)))
