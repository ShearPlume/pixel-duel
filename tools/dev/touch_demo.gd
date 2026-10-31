extends Node
## Dev-only: handheld shell layout without a touchscreen present, for screenshots.

const BrawlScene = preload("res://scenes/brawl.tscn")
const TouchControls = preload("res://scripts/ui/touch_controls.gd")

func _ready() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(640, 216)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	view.add_child(BrawlScene.instantiate())
	var screen := TextureRect.new()
	screen.texture = view.get_texture()
	screen.size = Vector2(640.0, 216.0)
	screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	screen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)
	add_child(TouchControls.new())
