extends RefCounted
## Icon sheet for pickup items, written by tools/items/props.py. The game works
## without it (flat colour blocks), so a missing sheet never blocks a run.

const ATLAS_PATH := "res://art/items/atlas.json"
## Desktop keeps the lossless PNG, the web build only carries the WebP twin.
const IMAGE_PATH := "res://art/items/spritesheet.png"
const FALLBACK_IMAGE := "res://art/items/spritesheet.webp"

static var _cell := Vector2(72.0, 72.0)
static var _entries := {}
static var _texture: Texture2D = null
static var _frames := {}
static var _loaded := false


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var image_path := IMAGE_PATH
	if not ResourceLoader.exists(image_path):
		image_path = FALLBACK_IMAGE
	if not FileAccess.file_exists(ATLAS_PATH) or not ResourceLoader.exists(image_path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ATLAS_PATH))
	if not parsed is Dictionary:
		return
	var data: Dictionary = parsed
	_texture = load(image_path)
	if _texture == null:
		return
	var cell: Array = data.get("cell", [72, 72])
	_cell = Vector2(float(cell[0]), float(cell[1]))
	_entries = data.get("items", {})


static func available() -> bool:
	_ensure()
	return _texture != null


static func cell() -> Vector2:
	_ensure()
	return _cell


static func size_for(kind: String) -> Vector2:
	_ensure()
	if not _entries.has(kind):
		return _cell
	var entry: Dictionary = _entries[kind]
	return Vector2(float(entry.get("w", _cell.x)), float(entry.get("h", _cell.y)))


static func texture_for(kind: String) -> AtlasTexture:
	_ensure()
	if _texture == null or not _entries.has(kind):
		return null
	if _frames.has(kind):
		return _frames[kind]
	var entry: Dictionary = _entries[kind]
	var frame := AtlasTexture.new()
	frame.atlas = _texture
	frame.region = Rect2(float(entry.get("col", 0)) * _cell.x, 0.0, _cell.x, _cell.y)
	_frames[kind] = frame
	return frame



