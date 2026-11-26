extends Node2D
## Top-down view of the dungeon, drawn with plain shapes so the skeleton needs no
## art. Swap for a TileMapLayer + pixel tileset later (docs/ROADMAP.md, milestone 2).

const TILE := 24
const COLORS := {
	DungeonGenerator.Tile.FLOOR: Color("3a3442"),
	DungeonGenerator.Tile.WALL: Color("6b6276"),
	DungeonGenerator.Tile.DOOR_UNEXPLORED: Color("c9a25a"),
	DungeonGenerator.Tile.DOOR_OPEN: Color("7a5c33"),
	DungeonGenerator.Tile.RUBBLE: Color("4b4450"),
}
const HERO_COLORS := [Color("5ab0e8"), Color("8be07a"), Color("e87adf"), Color("e8d35a"), Color("7ae8d8"), Color("f0a060")]

var focus_id := ""
var camera: Camera2D


func _ready() -> void:
	camera = Camera2D.new()
	camera.offset = Vector2(210, 0)  # the HUD covers the right 420 px
	add_child(camera)
	camera.make_current()


func _process(_delta: float) -> void:
	if GameState.players.has(focus_id):
		var target := _px(GameState.players[focus_id]["pos"]) + Vector2(TILE, TILE) / 2
		camera.position = camera.position.lerp(target, 0.2)


func _draw() -> void:
	var dungeon: DungeonGenerator = GameState.dungeon
	if dungeon == null:
		return
	for p in dungeon.revealed:
		var t := dungeon.get_tile(p)
		if COLORS.has(t):
			draw_rect(Rect2(_px(p), Vector2(TILE, TILE)), COLORS[t])
	var font := ThemeDB.fallback_font
	for it in GameState.items:
		draw_circle(_px(it["pos"]) + Vector2(TILE, TILE) / 2, 4, Color("ffd36b"))
	var active := GameState.current_actor()
	for id in GameState.monsters:
		var m: Dictionary = GameState.monsters[id]
		var r := Rect2(_px(m["pos"]) + Vector2(3, 3), Vector2(TILE - 6, TILE - 6))
		draw_rect(r, Color("c0392b") if m.get("awake", true) else Color("6e2a22"))  # sleeping: dimmer
		draw_string(font, _px(m["pos"]) + Vector2(0, TILE - 6), str(m["name"]).left(1), HORIZONTAL_ALIGNMENT_CENTER, TILE, 14, Color.WHITE)
		if id == active:
			draw_rect(r.grow(2), Color.YELLOW, false, 2.0)
	for id in GameState.player_order:
		var h: Dictionary = GameState.players[id]
		var c: Color = HERO_COLORS[int(h["color"]) % HERO_COLORS.size()]
		if h.get("dead", false):
			c = Color("2a2a2a")
		elif int(h["hp"]) <= 0:
			c = c.darkened(0.6)
		var center := _px(h["pos"]) + Vector2(TILE, TILE) / 2
		draw_circle(center, TILE * 0.4, c)
		draw_string(font, _px(h["pos"]) + Vector2(0, TILE - 6), str(h["name"]).left(1), HORIZONTAL_ALIGNMENT_CENTER, TILE, 14, Color.BLACK)
		if id == active:
			draw_arc(center, TILE * 0.55, 0, TAU, 24, Color.YELLOW, 2.0)
		elif id == focus_id:
			draw_arc(center, TILE * 0.55, 0, TAU, 24, Color.WHITE, 1.0)


func _px(p: Vector2i) -> Vector2:
	return Vector2(p * TILE)
