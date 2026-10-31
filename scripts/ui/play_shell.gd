extends Node
## Scene wrapper for a match. On touch devices it renders the brawl into a
## SubViewport on the top of the screen and puts the controls in a dedicated
## bottom panel, the way a handheld does it. On keyboard setups the match just
## fills the screen.

const BrawlScene = preload("res://scenes/brawl.tscn")
const TouchControls = preload("res://scripts/ui/touch_controls.gd")

const SCREEN_HEIGHT := 216


func _ready() -> void:
	if not TouchControls.is_touch_device():
		add_child(BrawlScene.instantiate())
		return

	var view := SubViewport.new()
	view.size = Vector2i(640, SCREEN_HEIGHT)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.handle_input_locally = false
	view.gui_disable_input = true
	add_child(view)
	view.add_child(BrawlScene.instantiate())

	var screen := TextureRect.new()
	screen.texture = view.get_texture()
	screen.position = Vector2.ZERO
	screen.size = Vector2(640.0, float(SCREEN_HEIGHT))
	screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	screen.stretch_mode = TextureRect.STRETCH_SCALE
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(screen)

	add_child(TouchControls.new())
