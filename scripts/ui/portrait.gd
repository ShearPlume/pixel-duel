extends RefCounted
## Shared portrait layout helper.
##
## Godot keeps a fixed design resolution, so on a portrait phone a landscape
## design turns into a thin strip at the top with dead space below. This makes
## the design canvas match the window aspect (width fixed at 640): a 640x360
## page then sits in the top half and the touch panel owns the bottom half.

const DESIGN_HEIGHT := 360.0
const PAGE := Vector2(640.0, 360.0)


## Returns the design size now in effect and applies content scaling.
static func fit_viewport(width: float = 640.0) -> Vector2:
	var window := Engine.get_main_loop().root as Window
	if window == null:
		return Vector2(width, DESIGN_HEIGHT)
	var size := window.size
	if size.x <= 0 or size.y <= 0:
		return Vector2(width, DESIGN_HEIGHT)
	var height := roundf(width * float(size.y) / float(size.x))
	window.content_scale_size = Vector2i(int(width), int(height))
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	return Vector2(width, height)


## Vertical offset that centres the classic 640x360 page inside a taller canvas.
static func page_offset(design: Vector2) -> float:
	return maxf(0.0, (design.y - DESIGN_HEIGHT) * 0.5)


## Menus keep the page inside the top half so the control panel never covers it.
static func menu_offset(design: Vector2) -> float:
	var top_area := design.y * 0.5
	return maxf(0.0, (top_area - DESIGN_HEIGHT) * 0.5)


## Fills the whole (possibly tall) canvas with the page colour, behind whatever
## the scene draws, so no bare window background shows above or below the page.
static func backdrop(owner: Node, design: Vector2) -> void:
	# A CanvasLayer at layer -1 is guaranteed to sit behind the page's own
	# CanvasItems, whatever order the scene built them in.
	var layer := CanvasLayer.new()
	layer.layer = -1
	owner.add_child(layer)
	var fill := ColorRect.new()
	fill.color = Color("0b0913")
	fill.size = design
	fill.position = Vector2.ZERO
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fill)
