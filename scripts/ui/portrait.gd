extends RefCounted
## Shared portrait layout helper.
##
## Godot keeps a fixed design resolution, so on a portrait phone a landscape
## design turns into a thin strip at the top with dead space below. This makes
## the design canvas match the window aspect (width fixed at 640), and menu pages
## keep their 640x360 layout inside a SubViewport shown in the top half.

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


## Re-hosts the 2D children `owner` built so far inside a fixed 640x360
## SubViewport placed in the top half. A menu page is authored for landscape, so
## this keeps its exact desktop layout on a phone without reflowing it.
## CanvasLayers (the touch panel) and plain Nodes (audio) stay where they are.
static func wrap_page(owner: Node, design: Vector2) -> SubViewport:
	var moving: Array[Node] = []
	for child in owner.get_children():
		if child is CanvasItem:
			moving.append(child)

	var backdrop := ColorRect.new()
	backdrop.color = Color("0b0913")
	backdrop.size = design
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	owner.add_child(backdrop)

	var view := SubViewport.new()
	view.size = Vector2i(int(PAGE.x), int(PAGE.y))
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.handle_input_locally = true

	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.size = PAGE
	holder.position = Vector2(0.0, menu_offset(design))
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	owner.add_child(holder)
	holder.add_child(view)

	for child in moving:
		owner.remove_child(child)
		view.add_child(child)
	return view
