extends CanvasLayer
## Handheld style on-screen controls: the game screen occupies the top half of
## the viewport and this panel owns the bottom half, so buttons never sit on top
## of the playfield. Positions are derived from the real viewport size, which is
## portrait on phones (stretch aspect "expand" grows the design height).
##
## It drives the same p1_* actions the keyboard uses.

const PREFIX := "p1_"
const STICK_ACTIONS := ["left", "right", "crouch"]
const DEAD_ENTER := 0.26
const DEAD_EXIT := 0.18

## action, label, anchor (0..1 inside the band), radius factor of band unit
const BUTTONS := [
	{"action": "jump", "label": "A", "anchor": Vector2(0.80, 0.56), "r": 0.095},
	{"action": "light", "label": "B", "anchor": Vector2(0.62, 0.74), "r": 0.080},
	{"action": "flash", "label": "瞬步", "anchor": Vector2(0.50, 0.24), "r": 0.060},
	{"action": "special", "label": "技能", "anchor": Vector2(0.67, 0.17), "r": 0.060},
	{"action": "ranged", "label": "道具", "anchor": Vector2(0.84, 0.21), "r": 0.060},
	{"action": "assist", "label": "替身", "anchor": Vector2(0.93, 0.80), "r": 0.055},
	{"action": "crouch", "label": "蹲下", "anchor": Vector2(0.40, 0.66), "r": 0.060},
]

const FILL := Color(0.09, 0.07, 0.14, 0.42)
const STROKE := Color(0.85, 0.80, 0.95, 0.55)
const HELD := Color(0.95, 0.85, 1.0, 0.55)
const PANEL := Color(0.05, 0.04, 0.09, 1.0)
const PANEL_EDGE := Color(0.35, 0.30, 0.46, 0.9)

var _view: Control
var _touches := {}
var _counts := {}
var _dir_actions: Array = []
var _stick := Vector2.ZERO

var _size := Vector2(640.0, 360.0)
var _band_top := 180.0
var _band_h := 180.0
var _band_locked := false
var _stick_center := Vector2(78.0, 288.0)
var _stick_radius := 46.0
var _slots := {}


static func is_touch_device() -> bool:
	# PIXEL_TOUCH=1 forces the handheld layout on a desktop for screenshots.
	if OS.get_environment("PIXEL_TOUCH") == "1":
		return true
	return OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()


func _ready() -> void:
	layer = 20
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.draw.connect(_paint)
	add_child(_view)
	get_viewport().size_changed.connect(_layout)
	_layout()


## Called by the shell: reserve the bottom `height` pixels for the panel.
func use_band(top: float, height: float) -> void:
	_band_locked = true
	_band_top = top
	_band_h = height
	_layout()


func _layout() -> void:
	_size = get_viewport().get_visible_rect().size
	if not _band_locked:
		_band_top = floorf(_size.y * 0.5)
		_band_h = _size.y - _band_top

	# Size everything from the smaller of band width/height so a tall portrait
	# panel does not blow the buttons up to half the screen.
	var unit := minf(_size.x, _band_h)
	var stick_r := maxf(24.0, unit * 0.18)
	_stick_radius = stick_r
	_stick_center = Vector2(stick_r + unit * 0.05, _band_top + _band_h * 0.55)

	_slots = {}
	for button: Dictionary in BUTTONS:
		var anchor: Vector2 = button["anchor"]
		var radius := maxf(14.0, float(button["r"]) * unit)
		_slots[button["action"]] = {
			"at": Vector2(anchor.x * _size.x, _band_top + anchor.y * _band_h),
			"r": radius,
		}
	_view.queue_redraw()


func _process(_delta: float) -> void:
	# The portrait canvas may be applied after this node's first layout, so keep
	# watching the design size instead of relying on size_changed alone.
	if not get_viewport().get_visible_rect().size.is_equal_approx(_size):
		_layout()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_drag(event as InputEventScreenDrag)


func _touch(event: InputEventScreenTouch) -> void:
	if event.pressed and not event.canceled:
		if _touches.has(event.index):
			_end(event.index, false)
		var at := event.position
		if at.y >= _band_top and at.distance_to(_stick_center) <= _stick_radius * 1.7 \
				and not _stick_owner_taken():
			_touches[event.index] = {"kind": "stick"}
			_move_stick(at)
			return
		var action := _button_at(at)
		if action != "":
			_touches[event.index] = {"kind": "button", "action": action}
			_press(action)
			_view.queue_redraw()
	elif _touches.has(event.index):
		_end(event.index, not event.canceled)


func _drag(event: InputEventScreenDrag) -> void:
	if not _touches.has(event.index):
		return
	if String(_touches[event.index]["kind"]) == "stick":
		_move_stick(event.position)


func _end(index: int, released: bool) -> void:
	var contact: Dictionary = _touches.get(index, {})
	_touches.erase(index)
	if String(contact.get("kind", "")) == "stick":
		_stick = Vector2.ZERO
		_set_directions([])
	elif released:
		_release(String(contact.get("action", "")))
	_view.queue_redraw()


func _stick_owner_taken() -> bool:
	for contact: Dictionary in _touches.values():
		if String(contact["kind"]) == "stick":
			return true
	return false


func _move_stick(at: Vector2) -> void:
	_stick = ((at - _stick_center) / _stick_radius).limit_length(1.0)
	var actions: Array = []
	if _stick.length() >= (DEAD_ENTER if _dir_actions.is_empty() else DEAD_EXIT):
		var threshold := 0.42 if _dir_actions.is_empty() else 0.30
		if _stick.x < -threshold:
			actions.append("left")
		elif _stick.x > threshold:
			actions.append("right")
		if _stick.y > 0.42:
			actions.append("crouch")
	_set_directions(actions)
	_view.queue_redraw()


func _set_directions(actions: Array) -> void:
	if actions == _dir_actions:
		return
	var previous := _dir_actions
	_dir_actions = actions.duplicate()
	for action: String in STICK_ACTIONS:
		var was := action in previous
		var now := action in actions
		if was and not now:
			_release(action)
		elif now and not was:
			_press(action)


func _press(action: String) -> void:
	if action.is_empty():
		return
	_counts[action] = int(_counts.get(action, 0)) + 1
	if int(_counts[action]) == 1:
		Input.action_press(PREFIX + action)


func _release(action: String) -> void:
	if action.is_empty() or not _counts.has(action):
		return
	_counts[action] = maxi(0, int(_counts.get(action, 0)) - 1)
	if int(_counts[action]) == 0:
		Input.action_release(PREFIX + action)


func _is_held(action: String) -> bool:
	return int(_counts.get(action, 0)) > 0


func _button_at(at: Vector2) -> String:
	for action: String in _slots:
		var slot: Dictionary = _slots[action]
		if at.distance_to(slot["at"]) <= float(slot["r"]) * 1.3:
			return action
	return ""


func _paint() -> void:
	# The bottom half is a panel: nothing from the game shows through it.
	_view.draw_rect(Rect2(0.0, _band_top, _size.x, _size.y - _band_top), PANEL)
	_view.draw_line(Vector2(0.0, _band_top), Vector2(_size.x, _band_top), PANEL_EDGE, 2.0)

	var nub_r := _stick_radius * 0.42
	_view.draw_circle(_stick_center, _stick_radius, FILL)
	_view.draw_arc(_stick_center, _stick_radius, 0.0, TAU, 44, STROKE, 2.0)
	var nub := _stick_center + _stick * (_stick_radius - nub_r)
	_view.draw_circle(nub, nub_r, Color(0.85, 0.78, 0.95, 0.35 if _stick.length() < DEAD_ENTER else 0.6))
	_view.draw_arc(nub, nub_r, 0.0, TAU, 28, STROKE, 1.5)

	var font := ThemeDB.fallback_font
	for button: Dictionary in BUTTONS:
		var action := String(button["action"])
		var slot: Dictionary = _slots.get(action, {})
		if slot.is_empty():
			continue
		var at: Vector2 = slot["at"]
		var radius := float(slot["r"])
		var down := _is_held(action)
		_view.draw_circle(at, radius, HELD if down else FILL)
		_view.draw_arc(at, radius, 0.0, TAU, 36, Color("f2e9ff") if down else STROKE, 2.0)
		var font_size := int(clampf(radius * 0.62, 11.0, 20.0))
		_view.draw_string(font, at + Vector2(-radius, font_size * 0.36), String(button["label"]),
			HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, font_size,
			Color(0.98, 0.95, 1.0, 0.94))


