extends CanvasLayer
## On-screen controls for touch devices (phones, tablets, touch laptops, web).
##
## It drives the same p1_* actions the keyboard uses, so nothing in the match or
## the character select needs to know that a finger is pressing instead of a key.
## Left thumb: fixed-base stick (left/right to move, down to crouch). Right hand:
## jump, attack, item, dash, special and assist buttons.

const PREFIX := "p1_"
## The bottom band is reserved for controls; the game is drawn above it, the
## same split the reference project uses on phones.
const BAND_HEIGHT := 136.0
const JOY_CENTER := Vector2(76.0, 292.0)
const JOY_RADIUS := 46.0
## Wider than the visual base so a thumb can grab slightly outside it.
const JOY_GRAB := 72.0
const DEAD_ENTER := 0.26
const DEAD_EXIT := 0.18
const STICK_ACTIONS := ["left", "right", "crouch"]

const BUTTONS := [
	{"action": "jump", "label": "JUMP", "at": Vector2(524.0, 308.0), "r": 28.0},
	{"action": "light", "label": "HIT", "at": Vector2(452.0, 312.0), "r": 24.0},
	{"action": "flash", "label": "DASH", "at": Vector2(430.0, 246.0), "r": 20.0},
	{"action": "special", "label": "SKILL", "at": Vector2(490.0, 242.0), "r": 20.0},
	{"action": "ranged", "label": "ITEM", "at": Vector2(550.0, 244.0), "r": 20.0},
	{"action": "assist", "label": "TAG", "at": Vector2(600.0, 306.0), "r": 18.0},
]

const FILL := Color(0.09, 0.07, 0.14, 0.42)
const STROKE := Color(0.85, 0.80, 0.95, 0.55)
const HELD := Color(0.95, 0.85, 1.0, 0.55)

var _view: Control
var _touches := {}
var _counts := {}
var _dir_actions: Array = []
var _stick := Vector2.ZERO


static func is_touch_device() -> bool:
	return OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()


func _ready() -> void:
	layer = 20
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.draw.connect(_paint)
	add_child(_view)
	_view.queue_redraw()


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
		if at.distance_to(JOY_CENTER) <= JOY_GRAB and not _stick_owner_taken():
			_touches[event.index] = {"kind": "stick"}
			_move_stick(at)
			return
		var button := _button_at(at)
		if not button.is_empty():
			_touches[event.index] = {"kind": "button", "action": String(button["action"])}
			_press(String(button["action"]))
			_view.queue_redraw()
	elif _touches.has(event.index):
		_end(event.index, not event.canceled)


func _drag(event: InputEventScreenDrag) -> void:
	if not _touches.has(event.index):
		return
	var contact: Dictionary = _touches[event.index]
	if String(contact["kind"]) == "stick":
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


## Stick to discrete directions with hysteresis: a diagonal cannot flicker and a
## held direction only releases after leaving the smaller exit radius.
func _move_stick(at: Vector2) -> void:
	_stick = ((at - JOY_CENTER) / JOY_RADIUS).limit_length(1.0)
	var actions: Array = []
	if _stick.length() >= (DEAD_ENTER if _dir_actions.is_empty() else DEAD_EXIT):
		var threshold := 0.42 if _dir_actions.is_empty() else 0.30
		if _stick.x < -threshold:
			actions.append("left")
		elif _stick.x > threshold:
			actions.append("right")
		if _stick.y > 0.5:
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


func _button_at(at: Vector2) -> Dictionary:
	for button: Dictionary in BUTTONS:
		if at.distance_to(button["at"]) <= float(button["r"]) * 1.25:
			return button
	return {}


func _paint() -> void:
	# Opaque band, so the playfield above it reads as its own screen area.
	var band_top := 360.0 - BAND_HEIGHT
	_view.draw_rect(Rect2(0.0, band_top, 640.0, BAND_HEIGHT), Color(0.04, 0.03, 0.07, 0.96))
	_view.draw_line(Vector2(0.0, band_top), Vector2(640.0, band_top), Color(0.35, 0.30, 0.46, 0.9), 1.0)
	# Stick base plus a nub that saturates at the rim.
	_view.draw_circle(JOY_CENTER, JOY_RADIUS, FILL)
	_view.draw_arc(JOY_CENTER, JOY_RADIUS, 0.0, TAU, 40, STROKE, 2.0)
	var nub := JOY_CENTER + _stick * (JOY_RADIUS - 18.0)
	_view.draw_circle(nub, 18.0, Color(0.85, 0.78, 0.95, 0.35 if _stick.length() < DEAD_ENTER else 0.6))
	_view.draw_arc(nub, 18.0, 0.0, TAU, 24, STROKE, 1.5)

	var font := ThemeDB.fallback_font
	for button: Dictionary in BUTTONS:
		var action := String(button["action"])
		var at: Vector2 = button["at"]
		var radius := float(button["r"])
		var down := _is_held(action)
		_view.draw_circle(at, radius, HELD if down else FILL)
		_view.draw_arc(at, radius, 0.0, TAU, 32, Color("f2e9ff") if down else STROKE, 2.0)
		var size := 11 if radius < 26.0 else 12
		_view.draw_string(font, at + Vector2(-radius, size * 0.36), String(button["label"]),
			HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, size,
			Color(0.98, 0.95, 1.0, 0.92))

