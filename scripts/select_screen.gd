extends Node2D
## Character select for 2-5 local players. Each joined player moves a cursor and
## locks a fighter; the match starts as soon as everybody joined is ready.

const MatchConfig = preload("res://scripts/match_config.gd")
const Atlas = preload("res://scripts/sprite_atlas.gd")

const CHARACTERS := [
	"res://art/yoru", "res://art/nayu", "res://art/hanami", "res://art/kana", "res://art/mosaki",
]
const NAMES := ["Yoru", "Nayu", "Hanami", "Kana", "Mosaki"]
const COLORS := [
	Color("8ccff3"), Color("ffb365"), Color("a6e3a1"), Color("f5a7b6"), Color("c9a7ff"),
]
const CARD_W := 116.0
const CARD_H := 158.0
const GAP := 6.0
const TOP := 84.0
## Every portrait is drawn at this content height, so all five read as the same
## size even though their atlas sheets differ slightly.
const PORTRAIT_HEIGHT := 96.0
const PORTRAIT_FEET := 10.0
const MIN_PLAYERS := 2
const MAX_PLAYERS := 5
const START_DELAY := 0.7

var _slots: Array[Dictionary] = []
var _cards: Array[Dictionary] = []
var _tags: Array[Label] = []
var _states: Array[Label] = []
var _start_clock := -1.0
var _starting := false

const Sfx = preload("res://scripts/audio/sfx.gd")
const TouchControls = preload("res://scripts/ui/touch_controls.gd")
const Portrait = preload("res://scripts/ui/portrait.gd")

var _sfx: Node
var _touch := false
## Single player is two steps: pick yourself, then pick the CPU opponent.
var _picking_enemy := false
var _title: Label
var _hint: Label

func _ready() -> void:
	_sfx = Sfx.new()
	add_child(_sfx)
	# A phone can drive only P1, so P2 joins ready and fights as the CPU.
	var design := Vector2(640.0, 360.0)
	if TouchControls.is_touch_device():
		design = Portrait.fit_viewport()
		add_child(TouchControls.new())
		_touch = true
	_build()
	if _touch:
		Portrait.backdrop(self, design)
		position.y = Portrait.menu_offset(design)
	for i in range(MAX_PLAYERS):
		_slots.append({
			"joined": i < MIN_PLAYERS,
			"index": i % CHARACTERS.size(),
			"ready": false,
			"cpu": false,
		})
	_refresh()
	_update_prompt()

func _build() -> void:
	var sky := ColorRect.new()
	sky.color = Color("0b0913")
	sky.size = Vector2(640.0, 360.0)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sky)

	_title = _label("选择你的角色", Vector2(0.0, 20.0), 22, Color("f2e9ff"))
	_title.size = Vector2(640.0, 30.0)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title)

	var total := float(CHARACTERS.size()) * CARD_W + float(CHARACTERS.size() - 1) * GAP
	var start_x := (640.0 - total) * 0.5
	for i in range(CHARACTERS.size()):
		var x := start_x + float(i) * (CARD_W + GAP)
		var border := ColorRect.new()
		border.color = Color("2f2742")
		border.position = Vector2(x - 2.0, TOP - 2.0)
		border.size = Vector2(CARD_W + 4.0, CARD_H + 4.0)
		border.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(border)

		var frame := ColorRect.new()
		frame.color = Color("1b1626")
		frame.position = Vector2(x, TOP)
		frame.size = Vector2(CARD_W, CARD_H)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(frame)

		var portrait := Sprite2D.new()
		# Straight from the game atlas: the idle frame, scaled so every fighter
		# stands the same height on the card. Works on web too, where only the
		# WebP twin of the sheet is shipped.
		var data := Atlas.load_atlas(CHARACTERS[i])
		if not data.is_empty():
			var frames: SpriteFrames = data["frames"]
			var anchor: Vector2 = data["anchor"]
			var content := float(data.get("height", 0.0))
			var factor := PORTRAIT_HEIGHT / maxf(1.0, content)
			portrait.texture = frames.get_frame_texture("idle", 0)
			portrait.centered = false
			portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			portrait.scale = Vector2(factor, factor)
			# Anchored by the feet, exactly like the in-game sprite.
			var feet_y := TOP + CARD_H - PORTRAIT_FEET
			portrait.position = Vector2(
				x + CARD_W * 0.5 - anchor.x * factor,
				feet_y - anchor.y * factor)
			portrait.z_index = 1
			add_child(portrait)

		var name_label := _label(NAMES[i], Vector2(x, TOP + CARD_H + 6.0), 12, Color("cbb9e8"))
		name_label.size = Vector2(CARD_W, 16.0)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(name_label)

		_cards.append({"frame": frame, "border": border})

	_tags.clear()
	_states.clear()
	for p in range(MAX_PLAYERS):
		var tag := _label("P%d" % (p + 1), Vector2.ZERO, 11, COLORS[p])
		add_child(tag)
		_tags.append(tag)
		var state := _label("", Vector2.ZERO, 10, Color("f2e9ff"))
		state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		state.size = Vector2(60.0, 14.0)
		add_child(state)
		_states.append(state)

	_hint = _label("", Vector2(0.0, 328.0), 11, Color("8f7fac"))
	_hint.size = Vector2(640.0, 18.0)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint)

	var lan_button := Button.new()
	lan_button.text = "联机"
	lan_button.position = Vector2(10.0, 8.0)
	lan_button.size = Vector2(88.0, 34.0 if _touch else 24.0)
	lan_button.add_theme_font_size_override("font_size", 15 if _touch else 12)
	lan_button.pressed.connect(_open_lan)
	add_child(lan_button)


func _open_lan() -> void:
	MatchConfig.clear_lan()
	get_tree().change_scene_to_file("res://scenes/lan.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).physical_keycode == KEY_L:
			_open_lan()
			get_viewport().set_input_as_handled()

func _label(text: String, at: Vector2, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _process(delta: float) -> void:
	if _starting:
		return
	# Step 2 of single player: the enemy has been picked, only confirm is left.
	if _picking_enemy:
		var enemy: Dictionary = _slots[1]
		if Input.is_action_just_pressed("p1_left"):
			enemy["index"] = (int(enemy["index"]) + CHARACTERS.size() - 1) % CHARACTERS.size()
			_sfx.play_ui("select_move")
			_refresh()
		if Input.is_action_just_pressed("p1_right"):
			enemy["index"] = (int(enemy["index"]) + 1) % CHARACTERS.size()
			_sfx.play_ui("select_move")
			_refresh()
		if Input.is_action_just_pressed("p1_light"):
			enemy["joined"] = true
			enemy["ready"] = true
			enemy["cpu"] = true
			_slots[0]["ready"] = true
			_picking_enemy = false
			_sfx.play_ui("select_confirm")
			_refresh()
		elif Input.is_action_just_pressed("p1_crouch"):
			_picking_enemy = false
			_slots[0]["ready"] = false
			_sfx.play_ui("select_move")
			_refresh()
		_update_start(delta)
		return
	var changed := false
	for p in range(MAX_PLAYERS):
		var slot: Dictionary = _slots[p]
		var prefix := "p%d_" % (p + 1)
		if not bool(slot["joined"]):
			if Input.is_action_just_pressed(prefix + "jump"):
				slot["joined"] = true
				changed = true
			continue
		if Input.is_action_just_pressed(prefix + "left"):
			slot["index"] = (int(slot["index"]) + CHARACTERS.size() - 1) % CHARACTERS.size()
			slot["ready"] = false
			_sfx.play_ui("select_move")
			changed = true
		if Input.is_action_just_pressed(prefix + "right"):
			slot["index"] = (int(slot["index"]) + 1) % CHARACTERS.size()
			slot["ready"] = false
			_sfx.play_ui("select_move")
			changed = true
		if Input.is_action_just_pressed(prefix + "light"):
			slot["ready"] = not bool(slot["ready"])
			_sfx.play_ui("select_confirm")
			# Nobody else joined: pick a CPU opponent next instead of waiting.
			if p == 0 and bool(slot["ready"]) and _human_players() == 1:
				_picking_enemy = true
				_update_prompt()
			changed = true
		if Input.is_action_just_pressed(prefix + "crouch"):
			if bool(slot["ready"]):
				slot["ready"] = false
				changed = true
			elif p >= MIN_PLAYERS:
				slot["joined"] = false
				changed = true
	if changed:
		_refresh()
	_update_start(delta)


## How many slots are driven by a human right now; the CPU opponent does not
## count, so a single player gets to choose it.
func _human_players() -> int:
	var count := 0
	for slot: Dictionary in _slots:
		if bool(slot["joined"]):
			count += 1
	return count

## Keeps the title / hint in step with the two-step flow.
func _update_prompt() -> void:
	if _title == null or _hint == null:
		return
	if _picking_enemy:
		_title.text = "选择对手"
		_hint.text = ("摇杆挑对手，点 B 开始对局" if _touch else
			"←/→ 挑对手　J 开始对局　S 返回上一步")
		return
	_title.text = "选择你的角色"
	_hint.text = ("摇杆挑角色，点 B 确认" if _touch else
		"P1  A/D 挑角色  J 确认　　P2  ←/→ 挑角色  Enter 确认　　P3-P5  按跳跃键加入")


func _refresh() -> void:
	var ready_cards := {}
	for p in range(MAX_PLAYERS):
		var slot: Dictionary = _slots[p]
		var tag: Label = _tags[p]
		var state: Label = _states[p]
		tag.visible = bool(slot["joined"])
		state.visible = bool(slot["joined"])
		if not bool(slot["joined"]):
			continue
		var x := _card_x(int(slot["index"]))
		tag.text = "对手" if bool(slot.get("cpu", false)) else "P%d" % (p + 1)
		tag.position = Vector2(x + 4.0, TOP - 18.0)
		state.position = Vector2(x + CARD_W * 0.5 - 30.0, TOP - 18.0)
		state.text = "已就绪" if bool(slot["ready"]) else ""
		if bool(slot["ready"]):
			ready_cards[int(slot["index"])] = true
	for i in range(_cards.size()):
		var frame: ColorRect = _cards[i]["frame"]
		var border: ColorRect = _cards[i]["border"]
		if ready_cards.has(i):
			frame.color = Color("2a2440")
			border.color = Color("f2e9ff")
		else:
			frame.color = Color("1b1626")
			border.color = Color("2f2742")

func _card_x(index: int) -> float:
	var total := float(CHARACTERS.size()) * CARD_W + float(CHARACTERS.size() - 1) * GAP
	return (640.0 - total) * 0.5 + float(index) * (CARD_W + GAP)

func _update_start(delta: float) -> void:
	var joined := 0
	var ready := 0
	for slot: Dictionary in _slots:
		if bool(slot["joined"]):
			joined += 1
			if bool(slot["ready"]):
				ready += 1
	if joined >= MIN_PLAYERS and ready == joined:
		if _start_clock < 0.0:
			_start_clock = 0.0
		_start_clock += delta
		if _start_clock >= START_DELAY:
			_start_match()
	else:
		_start_clock = -1.0

func _start_match() -> void:
	_starting = true
	MatchConfig.characters = PackedStringArray()
	for slot: Dictionary in _slots:
		if bool(slot["joined"]):
			MatchConfig.characters.append(CHARACTERS[int(slot["index"])])
	get_tree().change_scene_to_file("res://scenes/play.tscn")
