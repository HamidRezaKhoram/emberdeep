class_name Presenter
extends RefCounted
## Plays GameState's events back over time, so the game reads like a tabletop turn
## instead of a teleport. The rules have already resolved; this only decides what the
## screen shows and when. Pure logic (no nodes): MapView draws from it, AudioDirector
## plays sounds from `played`, tests drive it with fake time. See docs/EVENTS.md.
##
## Responsiveness rules:
## - Events play strictly in order, so a monster's step never shows before the hit that
##   caused it. A player's input during playback is applied to the rules at once and its
##   animation simply queues: nothing is dropped or blocked (the input buffer).
## - When more than CATCH_UP_AFTER events are waiting, playback speeds up, so the screen
##   never falls far behind the game.
## - Idle (nothing queued), every token snaps to the true state, so the view can't drift.

## An event finished playing (sound, rumble and UI hang off this, in sync with the picture).
signal played(ev: Dictionary)

## Seconds each event type holds the queue. Types not listed play instantly.
const DURATIONS := {
	"moved": 0.09,
	"attack": 0.18,
	"monster_die": 0.22,
	"hero_down": 0.2,
	"hero_die": 0.3,
	"woke": 0.14,
	"lost_track": 0.1,
	"death_save": 0.25,
}
const CATCH_UP_AFTER := 6
const FLOATER_SECONDS := 0.9

var queue: Array = []
## actor id -> Vector2 in tile units (fractional while moving)
var visual: Dictionary = {}
## actor id -> seconds of hit flash left
var flashes: Dictionary = {}
## [{pos: Vector2 (tiles), text, color: Color, t: seconds left}]
var floaters: Array = []
## dead monster id -> {pos: Vector2i, name, key, alpha}: drawn until its death has played
var ghosts: Dictionary = {}
## actor id -> Vector2 extra offset in tiles (attack lunge)
var offsets: Dictionary = {}
## camera shake left, seconds
var shake := 0.0
## 1 = normal; debug slow motion sets 0.25 to inspect animations
var time_scale := 1.0

var _current: Dictionary = {}
var _stale := true   # the true state may have changed since the last reconcile
var _t := 0.0
var _dur := 0.0
var _from := Vector2.ZERO


func push(ev: Dictionary) -> void:
	if ev.get("type") == "reset":
		clear()
		return
	if ev.get("type") == "monster_die":
		# the rules removed the monster already; keep drawing it until its death plays
		ghosts[ev["actor"]] = {"pos": ev["pos"], "name": ev.get("name", ""), "key": ev.get("key", ""), "alpha": 1.0}
	queue.append(ev)
	_stale = true


## The rules state changed (also without events, e.g. a snapshot): re-sync when idle.
func mark_stale() -> void:
	_stale = true


func clear() -> void:
	queue.clear()
	visual.clear()
	flashes.clear()
	floaters.clear()
	ghosts.clear()
	offsets.clear()
	_current = {}
	shake = 0.0


func busy() -> bool:
	return not queue.is_empty() or not _current.is_empty()


## Something is still moving on screen (redraw every frame while true).
func animating() -> bool:
	return busy() or not floaters.is_empty() or not flashes.is_empty() or shake > 0.0


## Advances playback. `truth` returns {actor id: Vector2i}, where every token really
## is now; it is only called when idle and something changed, not every frame.
func advance(delta: float, truth: Callable) -> void:
	delta *= time_scale
	_tick_effects(delta)
	var speed := 1.0 + maxf(0.0, float(queue.size() - CATCH_UP_AFTER)) * 0.5
	var budget := delta * speed
	while true:
		if _current.is_empty():
			if queue.is_empty():
				_reconcile(truth)
				return
			_begin(queue.pop_front())
		var step := minf(budget, _dur - _t)
		_t += step
		budget -= step
		_animate(_current, 1.0 if _dur <= 0.0 else _t / _dur)
		if _t < _dur:
			return
		var done := _current
		_finish(done)
		_current = {}
		played.emit(done)
		if budget <= 0.0 and not queue.is_empty() and float(DURATIONS.get(queue[0].get("type"), 0.0)) > 0.0:
			return


## Where to draw an actor this frame, in tiles, or null when it shouldn't be drawn yet
## (it exists in the rules but its arrival hasn't played).
func position_of(id: String, truth_pos: Vector2i):
	if visual.has(id):
		return visual[id] + offsets.get(id, Vector2.ZERO)
	if not busy():
		return Vector2(truth_pos)
	return null


func _begin(ev: Dictionary) -> void:
	_current = ev
	_t = 0.0
	_dur = float(DURATIONS.get(ev.get("type"), 0.0))
	match ev.get("type"):
		"moved":
			_from = visual.get(ev["actor"], Vector2(ev["from"]))
		"spawned":
			visual[ev["actor"]] = Vector2(ev["pos"])
		"attack":
			if not visual.has(ev["attacker"]) or not visual.has(ev["target"]):
				_dur = 0.0   # one side isn't on screen yet: nothing to show


func _animate(ev: Dictionary, k: float) -> void:
	match ev.get("type"):
		"moved":
			var e := 1.0 - (1.0 - k) * (1.0 - k)   # ease out
			visual[ev["actor"]] = _from.lerp(Vector2(ev["to"]), e)
		"attack":
			if visual.has(ev["attacker"]) and visual.has(ev["target"]):
				var dir: Vector2 = (visual[ev["target"]] - visual[ev["attacker"]]).normalized()
				offsets[ev["attacker"]] = dir * 0.3 * sin(k * PI)   # lunge and return
		"monster_die":
			if ghosts.has(ev["actor"]):
				ghosts[ev["actor"]]["alpha"] = 1.0 - k


func _finish(ev: Dictionary) -> void:
	match ev.get("type"):
		"moved":
			visual[ev["actor"]] = Vector2(ev["to"])
		"attack":
			offsets.erase(ev["attacker"])
			var at: Vector2 = visual.get(ev["target"], Vector2.ZERO)
			if ev["hit"]:
				flashes[ev["target"]] = 0.25
				var text := ("CRIT %d" if ev["crit"] else "%d") % int(ev["damage"])
				_float({"pos": at, "text": text, "color": Color("ff6b5a") if ev["crit"] else Color("ffd0c8"), "t": FLOATER_SECONDS})
				if ev["crit"]:
					shake = 0.18
			else:
				_float({"pos": at, "text": "miss", "color": Color("b8b8c8"), "t": FLOATER_SECONDS})
		"monster_die":
			ghosts.erase(ev["actor"])
			visual.erase(ev["actor"])
		"woke":
			if visual.has(ev["actor"]):
				_float({"pos": visual[ev["actor"]], "text": "!", "color": Color("ffe066"), "t": FLOATER_SECONDS})
		"lost_track":
			if visual.has(ev["actor"]):
				_float({"pos": visual[ev["actor"]], "text": "?", "color": Color("9aa0b0"), "t": FLOATER_SECONDS})
		"hero_down", "hero_die":
			flashes[ev["actor"]] = 0.35
		"death_save":
			if visual.has(ev["actor"]):
				_float({"pos": visual[ev["actor"]], "text": "save %d" % int(ev["natural"]), "color": Color("9be07a") if ev["success"] else Color("ff9f8a"), "t": FLOATER_SECONDS})


## Adds a floating label; labels on the same tile stack upward instead of overlapping.
func _float(f: Dictionary) -> void:
	var stack := 0
	for other in floaters:
		if Vector2(other["pos"]).distance_to(Vector2(f["pos"])) < 0.5:
			stack += 1
	f["stack"] = stack
	floaters.append(f)


func _tick_effects(delta: float) -> void:
	for id in flashes.keys():
		flashes[id] -= delta
		if flashes[id] <= 0.0:
			flashes.erase(id)
	for f in floaters:
		f["t"] -= delta
	floaters = floaters.filter(func(f): return f["t"] > 0.0)
	shake = maxf(0.0, shake - delta)


func _reconcile(truth_fn: Callable) -> void:
	if not _stale:
		return
	_stale = false
	var truth: Dictionary = truth_fn.call()
	for id in visual.keys():
		if not truth.has(id):
			visual.erase(id)
	for id in truth:
		visual[id] = Vector2(truth[id])
	offsets.clear()
	ghosts.clear()
