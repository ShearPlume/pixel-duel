extends RefCounted
## Builds a SpriteFrames from the atlas produced by tools/frames/extract.py.
## Metadata stays in atlas.json so re-running the pipeline needs no Godot edits.

static var CACHE := {}

## The desktop tree keeps the lossless PNG; the web export ships only the WebP
## twin. Trying PNG first means both builds pick the right file with no flags.
static func sheet_path(dir: String) -> String:
	var png := dir.path_join("spritesheet.png")
	if ResourceLoader.exists(png):
		return png
	return dir.path_join("spritesheet.webp")


static func load_atlas(dir: String) -> Dictionary:
	if CACHE.has(dir):
		return CACHE[dir]
	var meta_path := dir.path_join("atlas.json")
	var sheet_path := sheet_path(dir)
	if not FileAccess.file_exists(meta_path) or not ResourceLoader.exists(sheet_path):
		return {}
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
	if not meta is Dictionary:
		return {}
	var sheet: Texture2D = load(sheet_path)
	var cell := Vector2(float(meta.cell[0]), float(meta.cell[1]))
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for state: Dictionary in meta.states:
		var name := String(state.name)
		frames.add_animation(name)
		frames.set_animation_speed(name, float(state.fps))
		frames.set_animation_loop(name, String(state.name) in ["idle", "walk", "walk-back", "crouch"])
		for index in range(int(state.frames)):
			var region := AtlasTexture.new()
			region.atlas = sheet
			region.region = Rect2(float(index) * cell.x, float(state.row) * cell.y, cell.x, cell.y)
			frames.add_frame(name, region)
	var result := {
		"frames": frames,
		"cell": cell,
		"height": float(meta.get("height", 0)),
		"anchor": Vector2(float(meta.anchor[0]), float(meta.anchor[1])),
	}
	CACHE[dir] = result
	return result

