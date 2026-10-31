extends RefCounted
## Builds a SpriteFrames from the atlas produced by tools/frames/extract.py.

static var CACHE := {}

static func sheet_path(dir: String) -> String:
	var png := dir.path_join("spritesheet.png")
	if ResourceLoader.exists(png):
		return png
	return dir.path_join("spritesheet.webp")

static func load_atlas(dir: String) -> Dictionary:
	if CACHE.has(dir):
		return CACHE[dir]
	var meta_path := dir.path_join("atlas.json")
	var sheet_file := sheet_path(dir)
	if not FileAccess.file_exists(meta_path) or not ResourceLoader.exists(sheet_file):
		return {}
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
	if not meta is Dictionary:
		return {}
	var sheet: Texture2D = load(sheet_file)
	var cell := Vector2(float(meta.cell[0]), float(meta.cell[1]))
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var state_frames := {}
	for state: Dictionary in meta.states:
		var name := String(state.name)
		var count := int(state.frames)
		var fps := float(state.fps)
		state_frames[name] = {"frames": count, "fps": fps, "duration": float(count) / maxf(1.0, fps)}
		frames.add_animation(name)
		frames.set_animation_speed(name, fps)
		frames.set_animation_loop(name, name in ["idle", "walk", "walk-back", "crouch"])
		for index in range(count):
			var region := AtlasTexture.new()
			region.atlas = sheet
			region.region = Rect2(float(index) * cell.x, float(state.row) * cell.y, cell.x, cell.y)
			frames.add_frame(name, region)
	var result := {
		"frames": frames,
		"cell": cell,
		"height": float(meta.get("height", 140.0)),
		"anchor": Vector2(float(meta.anchor[0]), float(meta.anchor[1])),
		"state_info": state_frames,
	}
	CACHE[dir] = result
	return result
