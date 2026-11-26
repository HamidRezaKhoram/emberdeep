extends Node2D
## Top-down view of the dungeon. Art comes from res://art/ by file name (docs/ASSETS.md);
## anything without a file is drawn as the plain colored shape, so art can be added one
## file at a time. Layers, bottom to top:
## - tiles: a TileMapLayer. Only the tiles a door opening changed (and their neighbours,
##   for wall autotiling) are repainted, so the cost doesn't grow with the map.
## - tokens: heroes, monsters, items and effects, redrawn every frame only while the
##   Presenter is animating, and only those inside the camera's view.
## Positions come from the Presenter (animated), not straight from GameState.

const TILE := 32
const ART_DIR := "res://art/"
const TILE_NAMES := {
	DungeonGenerator.Tile.FLOOR: "floor",
	DungeonGenerator.Tile.WALL: "wall",
	DungeonGenerator.Tile.DOOR_UNEXPLORED: "door_closed",
	DungeonGenerator.Tile.DOOR_OPEN: "door_open",
	DungeonGenerator.Tile.RUBBLE: "rubble",
}
const COLORS := {   # fallbacks when there's no file
	DungeonGenerator.Tile.FLOOR: Color("3a3442"),
	DungeonGenerator.Tile.WALL: Color("6b6276"),
	DungeonGenerator.Tile.DOOR_UNEXPLORED: Color("c9a25a"),
	DungeonGenerator.Tile.DOOR_OPEN: Color("7a5c33"),
	DungeonGenerator.Tile.RUBBLE: Color("4b4450"),
}
## Tiles a wall joins up with when choosing its autotile piece.
const JOINS_WALLS := [DungeonGenerator.Tile.WALL, DungeonGenerator.Tile.DOOR_UNEXPLORED,
	DungeonGenerator.Tile.DOOR_OPEN, DungeonGenerator.Tile.RUBBLE]
## Autotile mask bits: a wall's neighbour in this direction is wall-like.
const MASK_DIRS := [[Vector2i.UP, 1], [Vector2i.RIGHT, 2], [Vector2i.DOWN, 4], [Vector2i.LEFT, 8]]
const NEIGHBOURS_8 := [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0),
	Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]
const HERO_COLORS := [Color("5ab0e8"), Color("8be07a"), Color("e87adf"), Color("e8d35a"), Color("7ae8d8"), Color("f0a060")]
const CAMERA_SHARPNESS := 12.0   # higher = camera catches up faster; frame-rate independent
const FLASH_MONSTER := Color(2.5, 2.5, 2.5)   # modulate above 1 brightens a sprite
const FLASH_HERO := Color(2.2, 0.6, 0.5)

var presenter := Presenter.new()
var art := AssetLibrary.new(ART_DIR)
var focus_id := ""
var camera: Camera2D
## Width of the HUD covering the right of the screen; the camera centers on what's left.
var hud_width := 420:
	set(v):
		hud_width = v
		if camera:
			camera.offset = Vector2(v / 2.0, 0)

var tile_layer := TileMapLayer.new()
var _tokens := _TokenLayer.new()
var _sources: Dictionary = {}    # Texture2D instance id -> TileSet source id
var _fallbacks: Dictionary = {}  # Tile -> generated flat-color texture
var _drawn_dungeon: DungeonGenerator
var _clock := 0.0


func _ready() -> void:
	_reset_tileset()
	_tokens.view = self
	add_child(tile_layer)
	add_child(_tokens)
	camera = Camera2D.new()
	camera.offset = Vector2(hud_width / 2.0, 0)
	add_child(camera)
	camera.make_current()
	GameState.game_event.connect(presenter.push)


## Call when GameState changed: redraws what depends on it.
func refresh() -> void:
	presenter.mark_stale()
	_update_tiles()
	_tokens.queue_redraw()


## Forgets every loaded file and redraws (debug F8: see new or edited art at once).
func reload_art() -> void:
	art.clear()
	_reset_tileset()
	_drawn_dungeon = null
	refresh()


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


# --- tiles ------------------------------------------------------------------

func _update_tiles() -> void:
	var d: DungeonGenerator = GameState.dungeon
	if d == null:
		tile_layer.clear()
		_drawn_dungeon = null
		return
	var changed: Array[Vector2i] = []
	var everything := d.take_changes(changed)
	if everything or d != _drawn_dungeon:
		_drawn_dungeon = d
		tile_layer.clear()
		for p in d.revealed:
			_paint(d, p)
		return
	# a changed tile can change its neighbours' wall pieces too
	var todo := {}
	for p in changed:
		todo[p] = true
		for dir in DungeonGenerator.DIRS:
			todo[p + dir] = true
	for p in todo:
		_paint(d, p)


func _paint(d: DungeonGenerator, p: Vector2i) -> void:
	var t := d.get_tile(p)
	if not d.revealed.has(p) or not TILE_NAMES.has(t):
		tile_layer.erase_cell(p)
		return
	var cell := cell_for(d, p)
	tile_layer.set_cell(p, cell[0], cell[1])


## [source id, atlas coords] for the tile at p: the region's art, else the default art,
## else the flat-color fallback. Walls use the 4x4 autotile sheet when there is one.
func cell_for(d: DungeonGenerator, p: Vector2i) -> Array:
	var t := d.get_tile(p)
	var name: String = TILE_NAMES[t]
	var region := _region_at(d, p)
	if t == DungeonGenerator.Tile.WALL:
		var sheets := art.first_textures(_tile_stems(region, "wall_autotile"))
		if not sheets.is_empty():
			var sheet: Texture2D = sheets[AssetLibrary.pick_variant(sheets.size(), p, d.world_seed)]
			var src := _source_for(sheet)
			if src >= 0 and sheet.get_width() >= TILE * 4 and sheet.get_height() >= TILE * 4:
				var m := wall_mask(d, p)
				return [src, Vector2i(m % 4, m / 4)]
	var variants := art.first_textures(_tile_stems(region, name))
	if not variants.is_empty():
		var src := _source_for(variants[AssetLibrary.pick_variant(variants.size(), p, d.world_seed)])
		if src >= 0:
			return [src, Vector2i.ZERO]
	return [_source_for(_fallback(t)), Vector2i.ZERO]


## Which neighbours of the wall at p are wall-like: up 1, right 2, down 4, left 8.
## The autotile sheet's piece for mask m is at column m % 4, row m / 4.
static func wall_mask(d: DungeonGenerator, p: Vector2i) -> int:
	var m := 0
	for pair in MASK_DIRS:
		if d.get_tile(p + pair[0]) in JOINS_WALLS:
			m |= int(pair[1])
	return m


static func _tile_stems(region: String, name: String) -> Array:
	if region == "":
		return ["tiles/" + name]
	return ["regions/%s/tiles/%s" % [region, name], "tiles/" + name]


## The region of the room at p, or of a room next to it (walls and doors belong to the
## room they border). "" until rooms have regions (docs/CONTENT_PLAN.md, regions.json).
static func _region_at(d: DungeonGenerator, p: Vector2i) -> String:
	var rid := d.room_at(p)
	if rid < 0:
		for n in NEIGHBOURS_8:
			rid = d.room_at(p + n)
			if rid >= 0:
				break
	if rid < 0:
		return ""
	return str(d.rooms[rid].get("region", ""))


func _reset_tileset() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	tile_layer.tile_set = ts
	_sources.clear()


## The TileSet source for a texture, added the first time it's used. Every whole
## TILE x TILE cell of the texture becomes a tile. -1 if the image is too small.
func _source_for(tex: Texture2D) -> int:
	var key := tex.get_instance_id()
	if _sources.has(key):
		return _sources[key]
	if tex.get_width() < TILE or tex.get_height() < TILE:
		push_warning("art: %s is %dx%d, smaller than one %dpx tile" % [tex.get_meta("source_path", tex.resource_path), tex.get_width(), tex.get_height(), TILE])
		_sources[key] = -1
		return -1
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(TILE, TILE)
	for x in tex.get_width() / TILE:
		for y in tex.get_height() / TILE:
			src.create_tile(Vector2i(x, y))
	var id := tile_layer.tile_set.add_source(src)
	_sources[key] = id
	return id


func _fallback(t: int) -> Texture2D:
	if not _fallbacks.has(t):
		var img := Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
		img.fill(COLORS[t])
		_fallbacks[t] = ImageTexture.create_from_image(img)
	return _fallbacks[t]


# --- tokens -----------------------------------------------------------------

## A monster's sprite, or null: art/monsters/<key>.png (variants picked per creature).
func monster_texture(key: String, id: String) -> Texture2D:
	var v := art.textures("monsters/" + key)
	return null if v.is_empty() else v[posmod(hash(id), v.size())]


## A hero's sprite and whether to tint it: hero_<class>.png as drawn, else the grey
## hero.png tinted with the player's color. [null, false] if neither exists.
func hero_texture(cls: String) -> Array:
	var v := art.textures("tokens/hero_" + cls.to_lower().replace(" ", "_"))
	if not v.is_empty():
		return [v[0], false]
	v = art.textures("tokens/hero")
	return [null, false] if v.is_empty() else [v[0], true]


func item_texture(item_name: String) -> Texture2D:
	var v := art.first_textures(["items/" + item_name.to_lower().replace(" ", "_"), "items/item"])
	return null if v.is_empty() else v[0]


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
				var tex: Texture2D = view.item_texture(str(it["name"]))
				if tex:
					_draw_sprite(tex, Vector2(it["pos"]), Color.WHITE)
				else:
					draw_circle(Vector2(it["pos"] * TILE) + half, 5, Color("ffd36b"))
		var active := GameState.current_actor()
		for id in GameState.monsters:
			var m: Dictionary = GameState.monsters[id]
			if not area.has_point(m["pos"]):
				continue
			var at = pr.position_of(id, m["pos"])
			if at != null:
				_draw_monster(at, id, str(m["key"]), str(m["name"]), m.get("awake", true), pr.flashes.has(id), id == active, 1.0, font)
		for id in pr.ghosts:
			var g: Dictionary = pr.ghosts[id]
			_draw_monster(pr.visual.get(id, Vector2(g["pos"])), id, str(g.get("key", "")), str(g["name"]), true, false, false, float(g["alpha"]), font)
		for id in GameState.player_order:
			var h: Dictionary = GameState.players[id]
			var at = pr.position_of(id, h["pos"])
			if at == null:
				continue
			_draw_hero(at, id, h, pr.flashes.has(id), id == active, font)
		for f in pr.floaters:
			var rise := (Presenter.FLOATER_SECONDS - float(f["t"])) * 18.0 + int(f.get("stack", 0)) * 14.0
			var col: Color = f["color"]
			col.a = clampf(float(f["t"]) / 0.3, 0.0, 1.0)
			draw_string(font, Vector2(f["pos"]) * TILE + Vector2(-TILE, -4 - rise), str(f["text"]), HORIZONTAL_ALIGNMENT_CENTER, TILE * 3, 15, col)

	func _draw_sprite(tex: Texture2D, at: Vector2, modulate_color: Color) -> void:
		draw_texture_rect(tex, Rect2(at * TILE, Vector2(TILE, TILE)), false, modulate_color)

	func _draw_hero(at: Vector2, id: String, h: Dictionary, flash: bool, active: bool, font: Font) -> void:
		var c: Color = HERO_COLORS[int(h["color"]) % HERO_COLORS.size()]
		var dead: bool = h.get("dead", false)
		var down := int(h["hp"]) <= 0
		var center: Vector2 = at * TILE + Vector2(TILE, TILE) / 2
		var sprite: Array = view.hero_texture(str(h.get("class", "")))
		if sprite[0] != null:
			var mod: Color = c if sprite[1] else Color.WHITE
			if dead:
				mod = Color(0.25, 0.25, 0.25)
			elif down:
				mod = mod.darkened(0.6)
			if flash:
				mod = FLASH_HERO
			_draw_sprite(sprite[0], at, mod)
		else:
			if dead:
				c = Color("2a2a2a")
			elif down:
				c = c.darkened(0.6)
			if flash:
				c = Color("ff5040")
			draw_circle(center, TILE * 0.4, c)
			draw_string(font, at * TILE + Vector2(0, TILE - 9), str(h["name"]).left(1), HORIZONTAL_ALIGNMENT_CENTER, TILE, 16, Color.BLACK)
		if active:
			draw_arc(center, TILE * 0.55, 0, TAU, 24, Color.YELLOW, 2.0)
		elif id == view.focus_id:
			draw_arc(center, TILE * 0.55, 0, TAU, 24, Color.WHITE, 1.0)

	func _draw_monster(at: Vector2, id: String, key: String, name: String, awake: bool, flash: bool, active: bool, alpha: float, font: Font) -> void:
		var r := Rect2(at * TILE + Vector2(4, 4), Vector2(TILE - 8, TILE - 8))
		var tex: Texture2D = view.monster_texture(key, id) if key != "" else null
		if tex:
			var mod := Color.WHITE if awake else Color(0.55, 0.55, 0.6)   # sleeping: dimmer
			if flash:
				mod = FLASH_MONSTER
			mod.a = alpha
			_draw_sprite(tex, at, mod)
		else:
			var c := Color("c0392b") if awake else Color("6e2a22")
			if flash:
				c = Color.WHITE
			c.a = alpha
			draw_rect(r, c)
			draw_string(font, at * TILE + Vector2(0, TILE - 9), name.left(1), HORIZONTAL_ALIGNMENT_CENTER, TILE, 16, Color(1, 1, 1, alpha))
		if active:
			draw_rect(Rect2(at * TILE, Vector2(TILE, TILE)).grow(-1), Color.YELLOW, false, 2.0)
