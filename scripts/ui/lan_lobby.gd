extends Control
## LAN room lobby: create or join a relay room (server/room_server.js), watch the
## slots fill up, and start a host-authoritative match for up to five players.
##
## The page is one scrollable column so the same build works on a phone in
## portrait (tall canvas) and on a desktop (640x360). Fields are ordinary
## LineEdits, so tapping one on a phone brings up the native keyboard.

const NetClient = preload("res://scripts/net/net_client.gd")
const MatchConfig = preload("res://scripts/match_config.gd")
const Sfx = preload("res://scripts/audio/sfx.gd")
const Portrait = preload("res://scripts/ui/portrait.gd")
const TouchControls = preload("res://scripts/ui/touch_controls.gd")

const CHARACTER_NAMES := ["Yoru", "Nayu", "Hanami", "Kana", "Mosaki"]
const CHARACTERS := ["res://art/yoru", "res://art/nayu", "res://art/hanami", "res://art/kana", "res://art/mosaki"]
const MAX_SLOTS := 5
const MIN_PLAYERS := 2
const OPEN_SLOT := "空位"

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
var _logged_in := false
var _pending_name := ""
var _login_box: VBoxContainer
var _name_edit: LineEdit
var _question_edit: LineEdit
var _answer_edit: LineEdit
var _create_account_button: Button
var _pick_label: Label
var _my_pick := 0
## slot -> character index, filled by the host from everyone's pick.
var _picks := {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Portrait phones get a tall canvas so the column can breathe.
	_portrait = TouchControls.is_touch_device()
	var design := Portrait.fit_viewport() if _portrait else Vector2(640.0, 360.0)
	_build()
	if _portrait:
		# Menus do not own the bottom half: this page is one scrolling column.
		position = Vector2.ZERO
		size = design
		Portrait.backdrop(self, design)
	_connect_relay(NetClient.default_url())


var _portrait := false


func _build() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 24)
	scroll.add_child(margin)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var title := Label.new()
	title.text = "联机房间"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("f2e9ff"))
	column.add_child(title)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 16)
	_status.add_theme_color_override("font_color", Color("8f7fac"))
	_status.text = "连接中…"
	column.add_child(_status)

	_url_edit = LineEdit.new()
	_url_edit.text = NetClient.default_url()
	_url_edit.custom_minimum_size = Vector2(0.0, 34.0)
	_url_edit.add_theme_font_size_override("font_size", 12)
	_url_edit.placeholder_text = "中继服务器地址"
	column.add_child(_url_edit)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	_menu_buttons.append(_add_button(row, "创建房间", _on_create))
	_menu_buttons.append(_add_button(row, "刷新", _on_refresh))
	_menu_buttons.append(_add_button(row, "返回", _on_back))
	for button: Button in _menu_buttons:
		button.visible = false

	_login_box = VBoxContainer.new()
	_login_box.add_theme_constant_override("separation", 8)
	column.add_child(_login_box)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "昵称（2-16 个字符）"
	_name_edit.custom_minimum_size = Vector2(0.0, 44.0)
	_name_edit.add_theme_font_size_override("font_size", 18)
	_login_box.add_child(_name_edit)

	var login_row := HBoxContainer.new()
	login_row.add_theme_constant_override("separation", 8)
	_login_box.add_child(login_row)
	_add_button(login_row, "登录", _on_login)
	_create_account_button = _add_button(login_row, "注册新账号", _on_show_register)

	_question_edit = LineEdit.new()
	_question_edit.placeholder_text = "密保问题（找回账号用）"
	_question_edit.custom_minimum_size = Vector2(0.0, 40.0)
	_question_edit.add_theme_font_size_override("font_size", 15)
	_question_edit.visible = false
	_login_box.add_child(_question_edit)

	_answer_edit = LineEdit.new()
	_answer_edit.placeholder_text = "问题答案"
	_answer_edit.custom_minimum_size = Vector2(0.0, 40.0)
	_answer_edit.add_theme_font_size_override("font_size", 15)
	_answer_edit.visible = false
	_login_box.add_child(_answer_edit)

	_rooms_box = VBoxContainer.new()
	_rooms_box.add_theme_constant_override("separation", 6)
	_rooms_box.visible = false
	column.add_child(_rooms_box)

	_room_box = VBoxContainer.new()
	_room_box.add_theme_constant_override("separation", 6)
	_room_box.visible = false
	column.add_child(_room_box)

	_code_label = Label.new()
	_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_label.add_theme_font_size_override("font_size", 34)
	_code_label.add_theme_color_override("font_color", Color("a6e3a1"))
	_room_box.add_child(_code_label)

	for slot in range(MAX_SLOTS):
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 17)
		label.add_theme_color_override("font_color", Color("cbb9e8"))
		label.text = OPEN_SLOT
		_room_box.add_child(label)
		_slot_labels.append(label)

	var pick_row := HBoxContainer.new()
	pick_row.add_theme_constant_override("separation", 8)
	_room_box.add_child(pick_row)
	var previous_pick := _arrow_button("<")
	previous_pick.pressed.connect(func() -> void: _pick(-1))
	pick_row.add_child(previous_pick)
	_pick_label = Label.new()
	_pick_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pick_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pick_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pick_label.add_theme_font_size_override("font_size", 18)
	_pick_label.text = "角色：%s" % CHARACTER_NAMES[0]
	pick_row.add_child(_pick_label)
	var next_pick := _arrow_button(">")
	next_pick.pressed.connect(func() -> void: _pick(1))
	pick_row.add_child(next_pick)

	_start_button = Button.new()
	_start_button.text = "开始对战"
	_start_button.disabled = true
	_start_button.custom_minimum_size = Vector2(0.0, 46.0)
	_start_button.add_theme_font_size_override("font_size", 18)
	_start_button.pressed.connect(_on_start)
	_room_box.add_child(_start_button)

	var leave := Button.new()
	leave.text = "离开房间"
	leave.custom_minimum_size = Vector2(0.0, 40.0)
	leave.add_theme_font_size_override("font_size", 16)
	leave.pressed.connect(_on_leave)
	_room_box.add_child(leave)



func _arrow_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(46.0, 46.0)
	button.add_theme_font_size_override("font_size", 20)
	return button


func _add_button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 16)
	button.custom_minimum_size = Vector2(0.0, 40.0)
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
	net.auth_question.connect(_on_auth_question)
	net.auth_unknown.connect(_on_auth_unknown)
	net.auth_ok.connect(_on_auth_ok)
	net.auth_error.connect(_on_auth_error)
	net.leaderboard_changed.connect(_on_leaderboard)
	net.joined_room.connect(_on_joined)
	net.room_changed.connect(_on_room_state)
	net.data_received.connect(_on_data)
	net.closed.connect(_on_closed)
	net.failed.connect(_on_failed)
	net.peer_left.connect(func(_reason: String) -> void: _status.text = "有玩家离开了")
	net.connect_to(url, "P1")


func _on_connected() -> void:
	_status.text = "已连接，请输入昵称登录"
	_show_login()


func _show_login() -> void:
	_logged_in = false
	_login_box.visible = true
	_room_box.visible = false
	_rooms_box.visible = false
	for button: Button in _menu_buttons:
		button.visible = false


func _on_login() -> void:
	if _pending_name != "":
		net.answer(_pending_name, _answer_edit.text)
		return
	_pending_name = _name_edit.text.strip_edges()
	if _pending_name.length() < 2:
		_status.text = "昵称至少要 2 个字符"
		return
	net.login(_pending_name)


func _on_show_register() -> void:
	_pending_name = ""
	_question_edit.visible = true
	_answer_edit.visible = true
	_create_account_button.text = "创建账号"
	_create_account_button.pressed.disconnect(_on_show_register)
	_create_account_button.pressed.connect(_on_register)
	_status.text = "填写昵称、密保问题和答案即可注册"


func _on_register() -> void:
	net.register(_name_edit.text.strip_edges(), _question_edit.text.strip_edges(), _answer_edit.text.strip_edges())


func _on_auth_question(name: String, question: String) -> void:
	_pending_name = name
	_question_edit.visible = false
	_answer_edit.visible = true
	_status.text = "密保问题：%s" % question
	_answer_edit.grab_focus()


func _on_auth_unknown(name: String) -> void:
	_pending_name = ""
	_name_edit.text = name
	_question_edit.visible = true
	_answer_edit.visible = true
	_create_account_button.text = "创建账号"
	_status.text = "没有叫「%s」的账号，回答问题即可创建" % name


func _on_auth_ok(name: String, wins: int, losses: int) -> void:
	_logged_in = true
	_pending_name = ""
	_login_box.visible = false
	_status.text = "已登录：%s　战绩 %d 胜 %d 负" % [name, wins, losses]
	_show_menu()
	net.list_rooms()


func _on_auth_error(reason: String) -> void:
	_status.text = reason


func _on_leaderboard(entries: Array) -> void:
	if entries.is_empty():
		return
	var parts: Array = []
	for entry: Dictionary in entries.slice(0, 3):
		parts.append("%s %d 胜" % [String(entry.get("name", "?")), int(entry.get("wins", 0))])
	var top := "、".join(parts)
	if _logged_in:
		_status.text = "已登录：%s　|　排行：%s" % [net.account, top]
	else:
		_status.text = "排行：%s" % top


func _on_failed(reason: String) -> void:
	_status.text = reason


func _on_closed(reason: String) -> void:
	if not _in_room:
		return
	_in_room = false
	_show_menu()
	_status.text = "已离开房间（%s）" % reason


func _on_rooms(rooms: Array) -> void:
	for child: Node in _rooms_box.get_children():
		child.queue_free()
	if rooms.is_empty():
		var empty := Label.new()
		empty.text = "暂时没有空房间，创建一个吧"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 16)
		empty.add_theme_color_override("font_color", Color("6f6486"))
		_rooms_box.add_child(empty)
		return
	for room: Dictionary in rooms:
		var button := Button.new()
		button.text = "房号 %s　房主 %s　%d/%d 人" % [
			String(room.get("code", "??????")), String(room.get("host", "?")),
			int(room.get("players", 0)), int(room.get("max", MAX_SLOTS))]
		button.custom_minimum_size = Vector2(0.0, 42.0)
		button.add_theme_font_size_override("font_size", 16)
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
	_status.text = "你是 P%d，把房号 %s 发给朋友" % [slot + 1, code]
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
			var tag := "　← 你" if index == mine else ""
			var host_tag := "（房主）" if index == 0 else ""
			label.text = "P%d　%s%s%s" % [index + 1, String(entry.get("name", "?")), host_tag, tag]
			label.add_theme_color_override("font_color", Color("f2e9ff") if index == mine else Color("cbb9e8"))
		else:
			label.text = OPEN_SLOT
			label.add_theme_color_override("font_color", Color("5a5270"))
	_start_button.visible = mine == 0
	_start_button.disabled = slots.size() < MIN_PLAYERS


## Each player picks a fighter inside the room; the host collects the picks and
## ships them with the start packet so every client builds the same roster.
func _pick(delta: int) -> void:
	_my_pick = wrapi(_my_pick + delta, 0, CHARACTER_NAMES.size())
	_pick_label.text = "角色：%s" % CHARACTER_NAMES[_my_pick]
	_picks[MatchConfig.lan_slot] = _my_pick
	if net != null:
		net.send_data({"t": "pick", "c": _my_pick})


func _on_start() -> void:
	if MatchConfig.lan_slot != 0 or net == null:
		return
	net.send_data({"t": "start", "picks": _picks})
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
	_status.text = "正在开始…"
	get_tree().change_scene_to_file("res://scenes/play.tscn")


func _filled_slots() -> int:
	var count := 0
	for label: Label in _slot_labels:
		if label.text != OPEN_SLOT:
			count += 1
	return count


func _on_create() -> void:
	_status.text = "正在创建房间…"
	net.create_room("P1")


func _on_refresh() -> void:
	net.list_rooms()


func _on_leave() -> void:
	_in_room = false
	_show_menu()
	_connect_relay(_url_edit.text)


func _show_menu() -> void:
	_login_box.visible = false
	_room_box.visible = false
	_rooms_box.visible = true
	for button: Button in _menu_buttons:
		button.visible = true
	_status.text = "选一个房间，或者自己创建"


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
