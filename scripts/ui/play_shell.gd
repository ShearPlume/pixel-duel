extends Node
## Scene wrapper for a match.
##
## On portrait phones the design canvas is switched to a tall portrait size, the
## brawl renders into a 16:9 SubViewport that fills the top half, and the bottom
## half is the control panel (handheld split). Keyboard builds just show the
## match full screen.

const BrawlScene = preload("res://scenes/brawl.tscn")
const TouchControls = preload("res://scripts/ui/touch_controls.gd")
const Portrait = preload("res://scripts/ui/portrait.gd")

const DESIGN_WIDTH := 640.0
const SCREEN_RATIO := 9.0 / 16.0


func _ready() -> void:
	if not TouchControls.is_touch_device():
		add_child(BrawlScene.instantiate())
		return

	var design := Portrait.fit_viewport(DESIGN_WIDTH)
	var screen_height := floorf(design.x * SCREEN_RATIO)
	var top_area := floorf(design.y * 0.5)
	var screen_y := floorf((top_area - screen_height) * 0.5)

	var view := SubViewport.new()
	view.size = Vector2i(int(design.x), int(screen_height))
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.handle_input_locally = false
	view.gui_disable_input = true
	add_child(view)
	view.add_child(BrawlScene.instantiate())

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.02, 0.05)
	backdrop.size = design
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var screen := TextureRect.new()
	screen.texture = view.get_texture()
	screen.position = Vector2(0.0, screen_y)
	screen.size = Vector2(design.x, screen_height)
	screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	screen.stretch_mode = TextureRect.STRETCH_SCALE
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(screen)

	var controls := TouchControls.new()
	add_child(controls)
	controls.use_band(top_area, design.y - top_area)
