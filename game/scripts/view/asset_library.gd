class_name AssetLibrary
extends RefCounted
## Finds art and sound files by name, so content can be added one file at a time with
## no code changes (docs/CONTENT_PLAN.md has the folder layout; docs/ASSETS.md the rules).
##
## - `stem` is a path without extension under `root`, e.g. "tiles/floor".
## - Variants: stem, stem_2, stem_3 … stem_9 (stops at the first gap).
## - A missing file gives an empty list; callers fall back to drawing shapes or silence.
## - Results are cached, misses included, so per-frame lookups cost one dictionary read.
##   `clear()` forgets everything (the F8 debug reload).
##
## Loading: in editor builds (running from the source folder) files are read straight
## from disk, so new or changed files show up without an import step and F8 reloads them.
## Exported games load Godot's imported copies (the raw files aren't in the export).

const MAX_VARIANTS := 9
const IMAGE_EXTENSIONS: Array[String] = ["png"]
const SOUND_EXTENSIONS: Array[String] = ["wav", "ogg"]

var root: String
## Read raw files from disk instead of imported resources. Default: editor builds only.
var live: bool
var _cache: Dictionary = {}   # "kind:stem" -> Array


func _init(root_dir: String, live_files: bool = OS.has_feature("editor")) -> void:
	root = root_dir if root_dir.ends_with("/") else root_dir + "/"
	live = live_files


func clear() -> void:
	_cache.clear()


## Every variant of an image, in order. [] if there is none.
func textures(stem: String) -> Array:
	return _lookup("tex", stem, IMAGE_EXTENSIONS)


## Every variant of a sound, in order. [] if there is none.
func sounds(stem: String) -> Array:
	return _lookup("snd", stem, SOUND_EXTENSIONS)


## The first stem in `stems` that has any variants, as its variant list; [] if none do.
## Use for "most specific first" lookups (region override, then default).
func first_textures(stems: Array) -> Array:
	for s in stems:
		var t := textures(str(s))
		if not t.is_empty():
			return t
	return []


## Which of `count` variants a tile shows. Depends only on the position and the map's
## seed, so a tile looks the same every time it's drawn, on every machine.
## View-only: never use this for game rules (those go through Dice).
static func pick_variant(count: int, p: Vector2i, seed_value: int) -> int:
	if count <= 1:
		return 0
	# integer hash (xorshift-multiply); stable across platforms, unlike hash() of a string
	var h := (p.x * 73856093) ^ (p.y * 19349663) ^ (seed_value * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return posmod(h, count)


func _lookup(kind: String, stem: String, exts: Array[String]) -> Array:
	var key := kind + ":" + stem
	if _cache.has(key):
		return _cache[key]
	var out: Array = []
	for i in MAX_VARIANTS:
		var s := stem if i == 0 else "%s_%d" % [stem, i + 1]
		var res: Resource = null
		for ext in exts:
			res = _load(root + s + "." + ext, ext)
			if res != null:
				break
		if res == null:
			break   # variants are numbered without gaps
		out.append(res)
	_cache[key] = out
	return out


func _load(path: String, ext: String) -> Resource:
	if live:
		if not FileAccess.file_exists(path):
			return null
		return _load_raw(path, ext)
	# Exported (or forced): imported resources only. Checking for the .import file
	# (kept in exports as a remap) avoids error spam for files that don't exist.
	if FileAccess.file_exists(path + ".import") or ResourceLoader.exists(path):
		return load(path)
	return null


static func _load_raw(path: String, ext: String) -> Resource:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	match ext:
		"png":
			var img := Image.new()
			if img.load_png_from_buffer(bytes) != OK:
				push_warning("art: can't read %s (not a PNG?)" % path)
				return null
			var tex := ImageTexture.create_from_image(img)
			tex.set_meta("source_path", path)   # for messages; raw textures have no resource_path
			return tex
		"wav":
			return AudioStreamWAV.load_from_buffer(bytes)
		"ogg":
			return AudioStreamOggVorbis.load_from_buffer(bytes)
	return null
