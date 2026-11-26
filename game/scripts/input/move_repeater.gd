class_name MoveRepeater
extends RefCounted
## Held-direction auto-repeat, run by the game clock instead of the OS key repeat,
## so it feels the same on every machine and works for controllers (which have no
## key repeat). A press moves at once; holding moves again after `delay`, then every
## `interval`. Pure logic: feed it presses, releases and time; it returns directions.

var delay := 0.22
var interval := 0.11
var _dir := Vector2i.ZERO
var _timer := 0.0


func _init(delay_s: float = 0.22, interval_s: float = 0.11) -> void:
	delay = maxf(delay_s, 0.01)
	interval = maxf(interval_s, 0.01)


## A direction was just pressed: it takes over, and fires once right now.
func press(dir: Vector2i) -> Vector2i:
	_dir = dir
	_timer = delay
	return dir


## The held direction was released. Releasing another direction changes nothing.
func release(dir: Vector2i) -> void:
	if dir == _dir:
		_dir = Vector2i.ZERO


func held() -> Vector2i:
	return _dir


## Advances time while `still_held` (is the direction's action still down?).
## Returns the direction when a repeat is due, else ZERO. At most one step per call,
## so a frame hitch never fires a burst of moves.
func tick(delta: float, still_held: bool) -> Vector2i:
	if _dir == Vector2i.ZERO:
		return Vector2i.ZERO
	if not still_held:
		_dir = Vector2i.ZERO
		return Vector2i.ZERO
	_timer -= delta
	if _timer > 0.0:
		return Vector2i.ZERO
	_timer = maxf(_timer + interval, interval * 0.5)
	return _dir
