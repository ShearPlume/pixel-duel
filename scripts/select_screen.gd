extends Node2D
## Classic 1v1 Character Select Screen.
## Supports 3 modes via Tab:
##   1. "training" — 木桩调试模式（无限时间、自动回血、招式/帧数据/判定盒可视化、独立试招键）
##   2. "cpu"      — 单人街机 1P vs CPU
##   3. "versus"   — 本地双人 1P vs 2P

const MatchConfig = preload("res://scripts/match_config.gd")
const Atlas = preload("res://scripts/sprite_atlas.gd")

const SFX := {
	"move": preload("res://art/audio/select_move.wav"),
	"confirm": preload("res://art/audio/select_confirm.wav"),
}

const MODES := ["training", "cpu", "versus"]
const CARD_W := 96.0
const CARD_H := 152.0
const GAP := 8.0
const TOP := 86.0
const PORTRAIT_HEIGHT := 98.0
const PORTRAIT_FEET := 12.0

var _p1_idx := 0
var _p2_idx := 1
var _p1_locked := false
var _p2_locked := false
var _mode := "training"
var _start_timer := -1.0

var _cards: Array[Dictionary] = []
var _mode_label: Label
var _title_label: Label
var _sub_label: Label
var _p1_tag: Label
var _p2_tag: Label
var _sfx_player: AudioStreamPlayer

func _ready() -> void:
	_p1_idx = MatchConfig.p1_index
	_p2_idx = MatchConfig.p2_index
	_mode = MatchConfig.mode
	_sfx_player = AudioStreamPlayer.new()
	add_child(_sfx_player)
	_build_ui()
	_refresh()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("0d0a18")
	bg.size = Vector2(640.0, 360.0)
	add_child(bg)

	var top_bar := ColorRect.new()
	top_bar.color = Color("19132b")
	top_bar.size = Vector2(640.0, 56.0)
	add_child(top_bar)

	_title_label = _make_label("IDOL FIGHTER · 经典格斗 1V1", Vector2(0.0, 8.0), 18, Color("ffdf9e"))
	_title_label.size = Vector2(640.0, 26.0)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title_label)

	_mode_label = _make_label("", Vector2(0.0, 34.0), 11, Color("7bed9f"))
	_mode_label.size = Vector2(640.0, 18.0)
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_mode_label)

	var count := MatchConfig.ROSTER.size()
	var total_w := float(count) * CARD_W + float(count - 1) * GAP
	var start_x := (640.0 - total_w) * 0.5

	for i in range(count):
		var entry: Dictionary = MatchConfig.ROSTER[i]
		var x := start_x + float(i) * (CARD_W + GAP)

		var border := ColorRect.new()
		border.color = Color("32294d")
		border.position = Vector2(x - 2.0, TOP - 2.0)
		border.size = Vector2(CARD_W + 4.0, CARD_H + 4.0)
		add_child(border)

		var card := ColorRect.new()
		card.color = Color("181326")
		card.position = Vector2(x, TOP)
		card.size = Vector2(CARD_W, CARD_H)
		add_child(card)

		var data := Atlas.load_atlas(String(entry["dir"]))
		var sprite := AnimatedSprite2D.new()
		if not data.is_empty():
			var content_h := maxf(80.0, float(data.get("height", 140.0)))
			var factor := PORTRAIT_HEIGHT / content_h
			sprite.sprite_frames = data["frames"]
			sprite.centered = false
			sprite.offset = -data["anchor"]
			sprite.scale = Vector2(factor, factor)
			sprite.position = Vector2(x + CARD_W * 0.5, TOP + CARD_H - PORTRAIT_FEET)
			sprite.play("idle")
			add_child(sprite)

		var name_lbl := _make_label(String(entry["name"]), Vector2(x, TOP + CARD_H + 6.0), 11, Color("f4effa"))
		name_lbl.size = Vector2(CARD_W, 16.0)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(name_lbl)

		var tag_lbl := _make_label(String(entry["tag"]), Vector2(x - 6.0, TOP + CARD_H + 22.0), 8, Color(entry["color"]))
		tag_lbl.size = Vector2(CARD_W + 12.0, 14.0)
		tag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(tag_lbl)

		_cards.append({"border": border, "card": card, "sprite": sprite})

	_p1_tag = _make_label("P1", Vector2.ZERO, 12, Color("ff9f43"))
	add_child(_p1_tag)
	_p2_tag = _make_label("木桩", Vector2.ZERO, 12, Color("8ccff3"))
	add_child(_p2_tag)

	_sub_label = _make_label(
		"P1: A/D 选人  J 确认  S 取消   |   Tab: 切换【木桩调试 / 1P vs CPU / 2P 对战】   |   P2: ←/→ 选人  Enter/1 确认",
		Vector2(0.0, 330.0), 10, Color("9d8fb0")
	)
	_sub_label.size = Vector2(640.0, 20.0)
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_sub_label)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).physical_keycode
		if key == KEY_TAB:
			var cur := MODES.find(_mode)
			_mode = MODES[(cur + 1) % MODES.size()]
			_p1_locked = false
			_p2_locked = false
			_play_ui("move")
			_refresh()

func _process(delta: float) -> void:
	if _start_timer >= 0.0:
		_start_timer += delta
		if _start_timer >= 0.45:
			MatchConfig.p1_index = _p1_idx
			MatchConfig.p2_index = _p2_idx
			MatchConfig.mode = _mode
			MatchConfig.vs_cpu = (_mode != "versus")
			get_tree().change_scene_to_file("res://scenes/main.tscn")
		return

	var count := MatchConfig.ROSTER.size()
	var changed := false

	if _mode in ["training", "cpu"]:
		if not _p1_locked:
			if Input.is_action_just_pressed("p1_left"):
				_p1_idx = (_p1_idx + count - 1) % count
				_play_ui("move")
				changed = true
			elif Input.is_action_just_pressed("p1_right"):
				_p1_idx = (_p1_idx + 1) % count
				_play_ui("move")
				changed = true
			elif Input.is_action_just_pressed("p1_light"):
				_p1_locked = true
				_play_ui("confirm")
				changed = true
		elif not _p2_locked:
			if Input.is_action_just_pressed("p1_left") or Input.is_action_just_pressed("p2_left"):
				_p2_idx = (_p2_idx + count - 1) % count
				_play_ui("move")
				changed = true
			elif Input.is_action_just_pressed("p1_right") or Input.is_action_just_pressed("p2_right"):
				_p2_idx = (_p2_idx + 1) % count
				_play_ui("move")
				changed = true
			elif Input.is_action_just_pressed("p1_light") or Input.is_action_just_pressed("p2_light"):
				_p2_locked = true
				_play_ui("confirm")
				_start_timer = 0.0
				changed = true
			elif Input.is_action_just_pressed("p1_crouch"):
				_p1_locked = false
				_play_ui("move")
				changed = true
	else:
		if not _p1_locked:
			if Input.is_action_just_pressed("p1_left"):
				_p1_idx = (_p1_idx + count - 1) % count
				_play_ui("move")
				changed = true
			elif Input.is_action_just_pressed("p1_right"):
				_p1_idx = (_p1_idx + 1) % count
				_play_ui("move")
				changed = true
			elif Input.is_action_just_pressed("p1_light"):
				_p1_locked = true
				_play_ui("confirm")
				changed = true
		elif Input.is_action_just_pressed("p1_crouch"):
			_p1_locked = false
			_play_ui("move")
			changed = true

		if not _p2_locked:
			if Input.is_action_just_pressed("p2_left"):
				_p2_idx = (_p2_idx + count - 1) % count
				_play_ui("move")
				changed = true
			elif Input.is_action_just_pressed("p2_right"):
				_p2_idx = (_p2_idx + 1) % count
				_play_ui("move")
				changed = true
			elif Input.is_action_just_pressed("p2_light"):
				_p2_locked = true
				_play_ui("confirm")
				changed = true
		elif Input.is_action_just_pressed("p2_crouch"):
			_p2_locked = false
			_play_ui("move")
			changed = true

		if _p1_locked and _p2_locked:
			_start_timer = 0.0

	if changed:
		_refresh()

func _refresh() -> void:
	var count := MatchConfig.ROSTER.size()
	var total_w := float(count) * CARD_W + float(count - 1) * GAP
	var start_x := (640.0 - total_w) * 0.5

	match _mode:
		"training":
			_mode_label.text = "当前模式：【木桩训练调试】（按 Tab 切换模式） — " + ("请选择你的角色" if not _p1_locked else "请选择木桩角色")
			_mode_label.add_theme_color_override("font_color", Color("7bed9f"))
		"cpu":
			_mode_label.text = "当前模式：【单人街机 1P vs CPU】（按 Tab 切换模式） — " + ("请选择你的角色" if not _p1_locked else "请选择 CPU 对手")
			_mode_label.add_theme_color_override("font_color", Color("c4b5fd"))
		"versus":
			_mode_label.text = "当前模式：【本地双人 1P vs 2P】（按 Tab 切换模式）"
			_mode_label.add_theme_color_override("font_color", Color("ff9ff3"))

	for i in range(count):
		var border: ColorRect = _cards[i]["border"]
		var card: ColorRect = _cards[i]["card"]
		var col: Color = MatchConfig.ROSTER[i]["color"]
		if i == _p1_idx or i == _p2_idx:
			border.color = col if i == _p1_idx else Color("8ccff3")
			card.color = Color("271f3d")
		else:
			border.color = Color("32294d")
			card.color = Color("181326")

	var p1_x := start_x + float(_p1_idx) * (CARD_W + GAP)
	var p2_x := start_x + float(_p2_idx) * (CARD_W + GAP)
	_p1_tag.text = "P1 已就绪" if _p1_locked else "▼ P1"
	_p1_tag.position = Vector2(p1_x + 4.0, TOP - 20.0)
	var p2_name := "木桩" if _mode == "training" else ("CPU" if _mode == "cpu" else "P2")
	_p2_tag.text = ("%s 已就绪" % p2_name) if _p2_locked else ("▼ %s" % p2_name)
	_p2_tag.position = Vector2(p2_x + CARD_W - 44.0, TOP - 20.0)

func _play_ui(cue: String) -> void:
	if SFX.has(cue):
		_sfx_player.stream = SFX[cue]
		_sfx_player.play()

func _make_label(text: String, pos: Vector2, size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = pos
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	return lbl
