class_name Pathfinder
extends RefCounted
## A* on the 4-connected tile grid, with a cap on how many tiles it may expand.
##
## The dungeon has no fixed bounds and keeps growing, so this never builds a grid of
## the whole map (as AStarGrid2D would). The cap keeps every search's cost the same
## however big the map gets: a creature that can't find a route within it gives up,
## which is also how it "loses track" of the party (see GameState._monster_turn).
##
## Deterministic: ties are broken by insertion order, so seeds still reproduce games.

const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]


## Shortest path from `start` to `goal`, not including `start`, ending with `goal`.
## `passable(p: Vector2i) -> bool` says which tiles may be entered; `goal` is always
## enterable (it is usually the tile of the creature being chased).
## Returns [] when start == goal, or when no path is found within `max_expanded` tiles.
static func find_path(start: Vector2i, goal: Vector2i, passable: Callable, max_expanded: int = 512) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if start == goal:
		return path
	var came_from := {start: start}
	var cost := {start: 0}
	var heap := _Heap.new()
	heap.push(_dist(start, goal), 0, start)
	var expanded := 0
	while not heap.is_empty():
		var p: Vector2i = heap.pop()
		if p == goal:
			while p != start:
				path.append(p)
				p = came_from[p]
			path.reverse()
			return path
		expanded += 1
		if expanded > max_expanded:
			break
		var g: int = cost[p] + 1
		for d in DIRS:
			var q := p + d
			if q != goal and not passable.call(q):
				continue
			if cost.has(q) and cost[q] <= g:
				continue
			cost[q] = g
			came_from[q] = p
			heap.push(g + _dist(q, goal), _dist(q, goal), q)
	return path


static func _dist(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## Binary min-heap ordered by (f, h, insertion order). Stale entries (a tile pushed
## again with a lower cost) are allowed; the cheaper copy always pops first.
class _Heap:
	var _keys: Array = []   # [f, h, seq]
	var _vals: Array[Vector2i] = []
	var _seq := 0

	func is_empty() -> bool:
		return _vals.is_empty()

	func push(f: int, h: int, v: Vector2i) -> void:
		_keys.append([f, h, _seq])
		_vals.append(v)
		_seq += 1
		var i := _vals.size() - 1
		while i > 0:
			var parent := (i - 1) >> 1
			if not _less(i, parent):
				break
			_swap(i, parent)
			i = parent

	func pop() -> Vector2i:
		var top: Vector2i = _vals[0]
		var last := _vals.size() - 1
		_swap(0, last)
		_keys.pop_back()
		_vals.pop_back()
		var i := 0
		var n := _vals.size()
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var m := i
			if l < n and _less(l, m):
				m = l
			if r < n and _less(r, m):
				m = r
			if m == i:
				break
			_swap(i, m)
			i = m
		return top

	func _less(a: int, b: int) -> bool:
		var ka: Array = _keys[a]
		var kb: Array = _keys[b]
		if ka[0] != kb[0]:
			return ka[0] < kb[0]
		if ka[1] != kb[1]:
			return ka[1] < kb[1]
		return ka[2] < kb[2]

	func _swap(a: int, b: int) -> void:
		var tk = _keys[a]
		_keys[a] = _keys[b]
		_keys[b] = tk
		var tv := _vals[a]
		_vals[a] = _vals[b]
		_vals[b] = tv
