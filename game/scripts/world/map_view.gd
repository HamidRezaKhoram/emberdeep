extends Node2D
## Top-down view of the dungeon, drawn with plain shapes so the skeleton needs no
## art (docs/CONTENT_PLAN.md covers the art hooks). Two layers:
## - tiles: redrawn only when the map changes (opening a door), however long the map;
## - tokens: heroes, monsters, items and effects, redrawn every frame only while the
##   Presenter is animating, and only those inside the camera's view.
## Positions come from the Presenter (animated), not straight from GameState.

const TILE := 24
const COLORS := {
	DungeonGenerator.Tile.FLOOR: Color("3a3442"),
	DungeonGenerator.Tile.WALL: Color("6b6276"),
	DungeonGenerator.Tile.DOOR_UNEXPLORED: Color("c9a25a"),
	DungeonGenerator.Tile.DOOR_OPEN: Color("7a5c33"),
	DungeonGenerator.Tile.RUBBLE: Color("4b4450"),
}
const HERO_COLORS := [Color("5ab0e8"), Color("8be07a"), Color("e87adf"), Color("e8d35a"), Color("7ae8d8"), Color("f0a060")]
const CAMERA_SHARPNESS := 12.0   # higher = camera catches up faster; frame-rate independent

var presenter := Presenter.new()
var focus_id := ""
var camera: Camera2D
## Width of the HUD covering the right of the screen; the camera centers on what's left.
var hud_width := 420:
	set(v):
		hud_width = v
		if camera:
			camera.offset = Vector2(v / 2.0, 0)

var _tiles := _TileLayer.new()
var _tokens := _TokenLayer.new()
var _drawn_map_version := -1
var _drawn_dungeon: DungeonGenerator
var _clock := 0.0


func _ready() -> void:
	_tiles.view = self
	_tokens.view = self
	add_child(_tiles)
	add_child(_tokens)
	camera = Camera2D.new()
	camera.offset = Vector2(hud_width / 2.0, 0)
	add_child(camera)
	camera.make_current()
	GameState.game_event.connect(presenter.push)


## Call when GameState changed: redraws what depends on it.
func refresh() -> void:
	presenter.mark_stale()
	if GameState.map_version != _drawn_map_version or GameState.dungeon != _drawn_dungeon:
		_drawn_map_version = GameState.map_version
		_drawn_dungeon = GameState.dungeon
		_tiles.queue_redraw()
	_tokens.queue_redraw()


func _process(delta: float) -> void:
	_clock += delta
	var was_animating := presenter.animating()
	presenter.advance(delta, _truth)
	if was_animating or presenter.animating():
		_tokens.queue_redraw()
	if GameState.players.has(focus_id):
		var at = presenter.position_of(focus_id, GameState.players[focus_id]["pos"])
		if at != null:
			var target: Vector2 = at * TILE + Vector2(TILE, TILE) / 2
			camera.position = camera.position.lerp(target, 1.0 - exp(-CAMERA_SHARPNESS * delta))
	var base := Vector2(hud_width / 2.0, 0)
	if presenter.shake > 0.0:
		# view-only wobble from the clock, never from the game's dice
		camera.offset = base + Vector2(sin(_clock * 93.0), cos(_clock * 71.0)) * presenter.shake * 24.0
	else:
		camera.offset = base


func _truth() -> Dictionary:
	var t := {}
	for id in GameState.players:
		t[id] = GameState.players[id]["pos"]
	for id in GameState.monsters:
		t[id] = GameState.monsters[id]["pos"]
	return t


## The part of the world the camera shows, in tiles, with a margin.
func visible_tiles() -> Rect2i:
	var size := get_viewport_rect().size / camera.zoom
	var top_left := camera.get_screen_center_position() - size / 2
	var r := Rect2i(Vector2i((top_left / TILE).floor()) - Vector2i(2, 2), Vector2i((size / TILE).ceil()) + Vector2i(4, 4))
	return r


static func px(p: Vector2) -> Vector2:
	return p * TILE


class _TileLayer:
	extends Node2D
	var view

	func _draw() -> void:
		var dungeon: DungeonGenerator = GameState.dungeon
		if dungeon == null:
			return
		for p in dungeon.revealed:
			var t := dungeon.get_tile(p)
			if COLORS.has(t):
				draw_rect(Rect2(Vector2(p * TILE), Vector2(TILE, TILE)), COLORS[t])


class _TokenLayer:
	extends Node2D
	var view

	func _draw() -> void:
		if GameState.dungeon == null:
			return
		var pr: Presenter = view.presenter
		var area: Rect2i = view.visible_tiles()
		var font := ThemeDB.fallback_font
		var half := Vector2(TILE, TILE) / 2
		for it in GameState.items:
			if area.has_point(it["pos"]):
				draw_circle(Vector2(it["pos"] * TILE) + half, 4, Color("ffd36b"))
		var active := GameState.current_actor()
		for id in GameState.monsters:
			var m: Dictionary = GameState.monsters[id]
			if not area.has_point(m["pos"]):
				continue
			var at = pr.position_of(id, m["pos"])
			if at != null:
				_draw_monster(at, str(m["name"]), m.get("awake", true), pr.flashes.has(id), id == active, 1.0, font)
		for id in pr.ghosts:
			var g: Dictionary = pr.ghosts[id]
			_draw_monster(pr.visual.get(id, Vector2(g["pos"])), str(g["name"]), true, false, false, float(g["alpha"]), font)
		for id in GameState.player_order:
			var h: Dictionary = GameState.players[id]
			var at = pr.position_of(id, h["pos"])
			if at == null:
				continue
			var c: Color = HERO_COLORS[int(h["color"]) % HERO_COLORS.size()]
			if h.get("dead", false):
				c = Color("2a2a2a")
			elif int(h["hp"]) <= 0:
				c = c.darkened(0.6)
			if pr.flashes.has(id):
				c = Color("ff5040")
			var center: Vector2 = at * TILE + half
			draw_circle(center, TILE * 0.4, c)
			draw_string(font, at * TILE + Vector2(0, TILE - 6), str(h["name"]).left(1), HORIZONTAL_ALIGNMENT_CENTER, TILE, 14, Color.BLACK)
			if id == active:
				draw_arc(center, TILE * 0.55, 0, TAU, 24, Color.YELLOW, 2.0)
			elif id == view.focus_id:
				draw_arc(center, TILE * 0.55, 0, TAU, 24, Color.WHITE, 1.0)
		for f in pr.floaters:
			var rise := (Presenter.FLOATER_SECONDS - float(f["t"])) * 18.0 + int(f.get("stack", 0)) * 14.0
			var col: Color = f["color"]
			col.a = clampf(float(f["t"]) / 0.3, 0.0, 1.0)
			draw_string(font, Vector2(f["pos"]) * TILE + Vector2(-TILE, -4 - rise), str(f["text"]), HORIZONTAL_ALIGNMENT_CENTER, TILE * 3, 15, col)

	func _draw_monster(at: Vector2, name: String, awake: bool, flash: bool, active: bool, alpha: float, font: Font) -> void:
		var r := Rect2(at * TILE + Vector2(3, 3), Vector2(TILE - 6, TILE - 6))
		var c := Color("c0392b") if awake else Color("6e2a22")   # sleeping: dimmer
		if flash:
			c = Color.WHITE
		c.a = alpha
		draw_rect(r, c)
		draw_string(font, at * TILE + Vector2(0, TILE - 6), name.left(1), HORIZONTAL_ALIGNMENT_CENTER, TILE, 14, Color(1, 1, 1, alpha))
		if active:
			draw_rect(r.grow(2), Color.YELLOW, false, 2.0)
