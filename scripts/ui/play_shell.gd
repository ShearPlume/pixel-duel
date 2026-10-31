extends Node
## Scene wrapper for a match.
##
## Touch devices get the handheld split: the brawl renders into a SubViewport
## that fills the top half of the portrait screen, and the bottom half is the
## control panel. Keyboard builds just show the match full screen.

const BrawlScene = preload("res://scenes/brawl.tscn")
const TouchControls = preload("res://scripts/ui/touch_controls.gd")


func _ready() -> void:
	if not TouchControls.is_touch_device():
		add_child(BrawlScene.instantiate())
		return

	var vp := get_viewport().get_visible_rect().size
	var screen_h := floorf(vp.y * 0.5)

	var view := SubViewport.new()
	view.size = Vector2i(int(vp.x), int(screen_h))
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.handle_input_locally = false
	view.gui_disable_input = true
	add_child(view)
	view.add_child(BrawlScene.instantiate())

	var screen := TextureRect.new()
	screen.texture = view.get_texture()
	screen.position = Vector2.ZERO
	screen.size = Vector2(vp.x, screen_h)
	screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	screen.stretch_mode = TextureRect.STRETCH_SCALE
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(screen)

	var controls := TouchControls.new()
	add_child(controls)
	controls.use_band(screen_h, vp.y - screen_h)
