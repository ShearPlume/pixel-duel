extends Control
## On-screen keyboard for touch devices. Browser virtual keyboards are unreliable
## inside a canvas game, so the lobby shows its own keypad.

signal submitted(text: String)
signal cancelled

const ROWS := ["ABCDEFGHIJ", "KLMNOPQRST", "UVWXYZ0123", "456789 -_."]
const FONT := 14

var value := ""
var title := ""

var _label: Label
var _buttons: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.86)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := ColorRect.new()
	panel.color = Color("1b1626")
	panel.position = Vector2(40.0, 40.0)
	panel.size = Vector2(560.0, 280.0)
	add_child(panel)

	var heading := Label.new()
	heading.position = Vector2(40.0, 8.0)
	heading.size = Vector2(560.0, 18.0)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 11)
	heading.add_theme_color_override("font_color", Color("8f7fac"))
	heading.text = title
	add_child(heading)

	_label = Label.new()
	_label.position = Vector2(56.0, 50.0)
	_label.size = Vector2(528.0, 26.0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color("f2e9ff"))
	add_child(_label)

	var grid := GridContainer.new()
	grid.columns = 10
	grid.position = Vector2(56.0, 84.0)
	grid.size = Vector2(528.0, 150.0)
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	add_child(grid)

	for row in ROWS:
		for character in row:
			var button := Button.new()
			button.text = character
			button.custom_minimum_size = Vector2(48.0, 32.0)
			button.add_theme_font_size_override("font_size", FONT)
			var key: String = String(character).strip_edges()
			button.pressed.connect(func() -> void: _tap(key))
			grid.add_child(button)
			_buttons.append(button)

	var actions := HBoxContainer.new()
	actions.position = Vector2(56.0, 244.0)
	actions.size = Vector2(528.0, 44.0)
	actions.add_theme_constant_override("separation", 6)
	add_child(actions)
	_action_button(actions, "DEL", _backspace)
	_action_button(actions, "SPACE", func() -> void: _tap(" "))
	_action_button(actions, "CANCEL", func() -> void: cancelled.emit())
	_action_button(actions, "OK", func() -> void: submitted.emit(value))

	_refresh()


func setup(initial: String, heading: String) -> void:
	value = initial
	title = heading
	if _label != null:
		var heading_label: Label = get_child(2)
		if heading_label is Label:
			heading_label.text = heading
		_refresh()


func _action_button(parent: Node, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 34.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 11)
	button.pressed.connect(callback)
	parent.add_child(button)


func _tap(character: String) -> void:
	if value.length() >= 32:
		return
	value += character
	_refresh()


func _backspace() -> void:
	if value.length() > 0:
		value = value.left(value.length() - 1)
		_refresh()


func _refresh() -> void:
	if _label != null:
		_label.text = value if value != "" else "_"

