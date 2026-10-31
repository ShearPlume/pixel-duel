extends Control
## LAN room lobby: create or join a relay room (server/room_server.js), watch the
## slots fill up, and start a host-authoritative match for up to five players.
##
## Mouse, touch and keyboard all work: the buttons are ordinary Controls, so a
## phone can tap them and the keyboard can focus them with the arrow keys.

const NetClient = preload("res://scripts/net/net_client.gd")
const MatchConfig = preload("res://scripts/match_config.gd")
const Sfx = preload("res://scripts/audio/sfx.gd")

const CHARACTERS := ["res://art/yoru", "res://art/nayu", "res://art/hanami", "res://art/kana", "res://art/mosaki"]
const MAX_SLOTS := 5
const MIN_PLAYERS := 2

var net: Node = null
var _status: Label
var _url_edit: LineEdit
var _rooms_box: VBoxContainer
var _room_box: VBoxContainer
var _code_label: Label
var _slot_labels: Array = []
var _start_button: Button
var _menu_buttons: Array = []
var _in_room := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	_connect_relay(NetClient.default_url())


func _build() -> void:
	var sky := ColorRect.new()
	sky.color = Color("0b0913")
	sky.size = Vector2(640.0, 360.0)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sky)

	var title := Label.new()
	title.text = "LAN ROOM"
	title.position = Vector2(0.0, 18.0)
	title.size = Vector2(640.0, 30.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("f2e9ff"))
	add_child(title)

	_url_edit = LineEdit.new()
	_url_edit.text = NetClient.default_url()
	_url_edit.position = Vector2(120.0, 56.0)
	_url_edit.size = Vector2(400.0, 24.0)
	_url_edit.add_theme_font_size_override("font_size", 11)
	_url_edit.placeholder_text = "relay address"
	add_child(_url_edit)

	_status = Label.new()
	_status.position = Vector2(120.0, 86.0)
	_status.size = Vector2(400.0, 20.0)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 11)
	_status.add_theme_color_override("font_color", Color("8f7fac"))
	_status.text = "connecting..."
	add_child(_status)

	_rooms_box = VBoxContainer.new()
	_rooms_box.position = Vector2(150.0, 120.0)
	_rooms_box.size = Vector2(340.0, 120.0)
	_rooms_box.add_theme_constant_override("separation", 4)
	add_child(_rooms_box)

	var row := HBoxContainer.new()
	row.position = Vector2(150.0, 100.0)
	row.size = Vector2(340.0, 22.0)
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	_menu_buttons.append(_add_button(row, "CREATE ROOM", _on_create))
	_menu_buttons.append(_add_button(row, "REFRESH", _on_refresh))
	_menu_buttons.append(_add_button(row, "BACK", _on_back))

	_room_box = VBoxContainer.new()
	_room_box.position = Vector2(220.0, 120.0)
	_room_box.size = Vector2(200.0, 190.0)
	_room_box.add_theme_constant_override("separation", 3)
	_room_box.visible = false
	add_child(_room_box)

	_code_label = Label.new()
	_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_label.add_theme_font_size_override("font_size", 26)
	_code_label.add_theme_color_override("font_color", Color("a6e3a1"))
	_room_box.add_child(_code_label)

	for slot in range(MAX_SLOTS):
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color("cbb9e8"))
		label.text = "open"
		_room_box.add_child(label)
		_slot_labels.append(label)

	_start_button = Button.new()
	_start_button.text = "START MATCH"
	_start_button.disabled = true
	_start_button.add_theme_font_size_override("font_size", 12)
	_start_button.pressed.connect(_on_start)
	_room_box.add_child(_start_button)

	var leave := Button.new()
	leave.text = "LEAVE ROOM"
	leave.add_theme_font_size_override("font_size", 11)
	leave.pressed.connect(_on_leave)
	_room_box.add_child(leave)

	var hint := Label.new()
	hint.text = "Same Wi-Fi: host runs the relay (see server/room_server.js). Web: wss://mirugumi.space/idolbrawl-signal"
	hint.position = Vector2(0.0, 330.0)
	hint.size = Vector2(640.0, 16.0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 9)
	hint.add_theme_color_override("font_color", Color("6f6486"))
	add_child(hint)


func _add_button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 11)
	button.custom_minimum_size = Vector2(0.0, 24.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _connect_relay(url: String) -> void:
	if net != null:
		net.queue_free()
	net = NetClient.new()
	MatchConfig.net = net
	get_tree().root.add_child.call_deferred(net)
	net.connected.connect(_on_connected)
	net.rooms_changed.connect(_on_rooms)
	net.joined_room.connect(_on_joined)
	net.room_changed.connect(_on_room_state)
	net.data_received.connect(_on_data)
	net.closed.connect(_on_closed)
	net.failed.connect(_on_failed)
	net.peer_left.connect(func(_reason: String) -> void: _status.text = "a player left")
	net.connect_to(url, "P1")


func _on_connected() -> void:
	_status.text = "connected, looking for rooms"
	net.list_rooms()


func _on_failed(reason: String) -> void:
	_status.text = reason


func _on_closed(reason: String) -> void:
	if not _in_room:
		return
	_in_room = false
	_show_menu()
	_status.text = "left the room (%s)" % reason


func _on_rooms(rooms: Array) -> void:
	for child: Node in _rooms_box.get_children():
		child.queue_free()
	if rooms.is_empty():
		var empty := Label.new()
		empty.text = "no open rooms, create one"
		empty.add_theme_font_size_override("font_size", 11)
		empty.add_theme_color_override("font_color", Color("6f6486"))
		_rooms_box.add_child(empty)
		return
	for room: Dictionary in rooms:
		var button := Button.new()
		button.text = "%s   %s   %d/%d" % [
			String(room.get("code", "??????")), String(room.get("host", "?")),
			int(room.get("players", 0)), int(room.get("max", MAX_SLOTS))]
		button.add_theme_font_size_override("font_size", 11)
		button.disabled = not bool(room.get("open", true))
		var code := String(room.get("code", ""))
		button.pressed.connect(func() -> void: net.join_room(code, "P1"))
		_rooms_box.add_child(button)


func _on_joined(code: String, slot: int) -> void:
	_in_room = true
	MatchConfig.lan_slot = slot
	MatchConfig.lan_code = code
	_code_label.text = code
	_rooms_box.visible = false
	_room_box.visible = true
	for button: Button in _menu_buttons:
		button.visible = false
	_status.text = "you are P%d - share the code %s" % [slot + 1, code]
	net.set_ready(true)


func _on_room_state(state: Dictionary) -> void:
	if not _in_room:
		return
	var slots: Array = state.get("slots", [])
	var mine := MatchConfig.lan_slot
	for index in range(MAX_SLOTS):
		var label: Label = _slot_labels[index]
		if index < slots.size():
			var entry: Dictionary = slots[index]
			var tag := "  <you>" if index == mine else ""
			var host_tag := " (host)" if index == 0 else ""
			label.text = "P%d  %s%s%s" % [index + 1, String(entry.get("name", "?")), host_tag, tag]
			label.add_theme_color_override("font_color", Color("f2e9ff") if index == mine else Color("cbb9e8"))
		else:
			label.text = "open"
			label.add_theme_color_override("font_color", Color("5a5270"))
	_start_button.visible = mine == 0
	_start_button.disabled = slots.size() < MIN_PLAYERS


func _on_start() -> void:
	if MatchConfig.lan_slot != 0 or net == null:
		return
	net.send_data({"t": "start"})
	_begin(0)


func _on_data(from_slot: int, payload: Dictionary) -> void:
	if String(payload.get("t", "")) == "start":
		_begin(from_slot)


## Everyone builds the roster from the same rule, so slots line up without any
## extra negotiation: slot N plays CHARACTERS[N % 5].
func _begin(_from: int) -> void:
	MatchConfig.lan_role = "host" if MatchConfig.lan_slot == 0 else "guest"
	MatchConfig.lan_url = _url_edit.text
	MatchConfig.lan_players = MAX_SLOTS
	MatchConfig.characters = PackedStringArray()
	for index in range(MAX_SLOTS):
		MatchConfig.characters.append(CHARACTERS[index % CHARACTERS.size()])
	# The lobby knows how many players actually joined; fill from the room state.
	MatchConfig.lan_players = clampi(_filled_slots(), MIN_PLAYERS, MAX_SLOTS)
	_status.text = "starting..."
	get_tree().change_scene_to_file("res://scenes/brawl.tscn")


func _filled_slots() -> int:
	var count := 0
	for label: Label in _slot_labels:
		if label.text != "open":
			count += 1
	return count


func _on_create() -> void:
	_status.text = "creating room..."
	net.create_room("P1")


func _on_refresh() -> void:
	net.list_rooms()


func _on_leave() -> void:
	_in_room = false
	_show_menu()
	_connect_relay(_url_edit.text)


func _show_menu() -> void:
	_room_box.visible = false
	_rooms_box.visible = true
	for button: Button in _menu_buttons:
		button.visible = true
	_status.text = "pick a room or create one"


func _on_back() -> void:
	MatchConfig.clear_lan()
	get_tree().change_scene_to_file("res://scenes/select.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).physical_keycode
		if key == KEY_ESCAPE:
			if _in_room:
				_on_leave()
			else:
				_on_back()

