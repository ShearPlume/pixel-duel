extends Node2D
## Classic 2D 1v1 Fighting Game Arena + Training Dummy Mode + Street Fighter-style Super Art ("漫天糖果雨").
## Press [I] (or [5] in Training Mode) to unleash Tangtang's Super Art:
##   1. 0.55s Super Flash Freeze: darkened stage, radial golden burst, slide-in pixel Cut-in banner ("超必杀 · 漫天糖果雨!")
##   2. 8-frame Star Wand Summon animation (`super-cast`)
##   3. Meteor Candy Barrage: 26 lollipops, star-sugars, and wrapped candies rain from the sky with multi-hit juggles!

const Fighter = preload("res://scripts/fighter.gd")
const HitResolve = preload("res://scripts/hit_resolve.gd")
const MatchConfig = preload("res://scripts/match_config.gd")

const SFX := {
	"hit_light": preload("res://art/audio/hit_light.wav"),
	"hit_heavy": preload("res://art/audio/hit_heavy.wav"),
	"hurt": preload("res://art/audio/hit_heavy.wav"),
	"whiff": preload("res://art/audio/guitar_swing.wav"),
	"jump": preload("res://art/audio/jump.wav"),
	"land": preload("res://art/audio/land.wav"),
	"ko": preload("res://art/audio/ko.wav"),
	"confirm": preload("res://art/audio/select_confirm.wav"),
	"super_start": preload("res://art/audio/pickup.wav"),
	"candy_pop": preload("res://art/audio/bubble_pop.wav"),
	"explosion": preload("res://art/audio/explosion.wav"),
}
const SFX_GAIN := {"hurt": -7.0, "whiff": -6.0, "jump": -8.0, "land": -5.0, "candy_pop": -4.0}
const SFX_VOICES := 12

const ARENA_WIDTH := 640.0
const ARENA_HEIGHT := 360.0
const GROUND_Y := 312.0
const LEFT_WALL := 0.0
const RIGHT_WALL := 640.0
const FIXED_HZ := 60
const FIXED_DT := 1.0 / float(FIXED_HZ)
const MAX_STEPS_PER_FRAME := 5

const PROJECTILE_SPEED := 320.0
const PROJECTILE_LIFE := 1.2
const PROJECTILE_HEIGHT := 54.0
const PROJECTILE_HALF_W := 10.0
const PROJECTILE_HALF_H := 44.0

const DUMMY_STATES := ["idle", "guard", "crouch", "jump", "cpu"]
const DUMMY_NAMES := {
	"idle": "站立木桩（不还手）",
	"guard": "防御木桩（全程格挡）",
	"crouch": "下蹲木桩",
	"jump": "跳跃木桩",
	"cpu": "AI 实战对打",
}

const CANDY_PALETTE := [
	Color("ff6b9d"), Color("ff9f43"), Color("ffd166"),
	Color("7bed9f"), Color("70a1ff"), Color("e056fd"),
]

var world_root: Node2D
var super_fx_node: Node2D
var debug_draw_node: Node2D
var player1: Node2D
var player2: Node2D
var projectiles: Array = []
var candies: Array = []
var candy_bursts: Array = []
var effects: Array = []

var accumulator := 0.0
var ticks := 0
var hitstop_clock := 0.0
var shake_clock := 0.0
var shake_strength := 0.0

# Street Fighter Super Art cinematic + Candy Rain state
var super_freeze_clock := 0.0
var super_Freeze_total := 0.58
var super_caster_idx := -1
var super_caster_pos := Vector2.ZERO
var candy_rain_clock := 0.0
var candy_spawn_accum := 0.0
var _cutin_texture: Texture2D
var _cutin_band: Control
var _cutin_sprite: Sprite2D
var _cutin_title: Label
var _stage_dim: ColorRect

var is_training := false
var dummy_behavior := "idle"
var show_hitboxes := true
var slow_motion := false
var _pending_force_attack := ""
var _regen_clock := 0.0
var _last_hit_damage := 0.0
var _total_combo_damage := 0.0

var round_number := 1
var p1_wins := 0
var p2_wins := 0
var round_timer := 99.0
var state := "intro" # intro | fight | ko | match_over
var state_clock := 1.4

# CPU AI timers
var _ai_clock := 0.0
var _ai_move := 0
var _ai_crouch := false

# HUD elements
var _hp_fills: Array[ColorRect] = []
var _hp_delays: Array[ColorRect] = []
var _energy_fills: Array[ColorRect] = []
var _round_dots_p1: Array[ColorRect] = []
var _round_dots_p2: Array[ColorRect] = []
var _timer_label: Label
var _banner_label: Label
var _sub_banner_label: Label
var _combo_labels: Array[Label] = []
var _hint_label: Label
var _training_panel: ColorRect
var _training_label: Label

var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_cursor := 0
var _was_grounded := [true, true]
var _last_attack := ["", ""]

class SuperFxOverlay extends Node2D:
	var arena: Node2D
	func _draw() -> void:
		if arena == null:
			return
		# 1. Super Freeze starburst rays behind caster
		if arena.super_freeze_clock > 0.0:
			var center: Vector2 = arena.super_caster_pos
			var phase: float = (arena.super_Freeze_total - arena.super_freeze_clock) * 14.0
			for i in range(20):
				var angle := float(i) * TAU / 20.0 + phase * 0.25
				var len_r := 380.0 if (i % 2 == 0) else 220.0
				var p1 := center + Vector2(cos(angle), sin(angle)) * 18.0
				var p2 := center + Vector2(cos(angle - 0.045), sin(angle - 0.045)) * len_r
				var p3 := center + Vector2(cos(angle + 0.045), sin(angle + 0.045)) * len_r
				var col := Color(1.0, 0.85, 0.32, 0.55) if (i % 2 == 0) else Color(1.0, 0.45, 0.68, 0.40)
				draw_colored_polygon(PackedVector2Array([p1, p2, p3]), col)
			draw_circle(center, 34.0 + sin(phase * 2.0) * 8.0, Color(1.0, 0.95, 0.65, 0.65))

		# 2. Falling candies (lollipop, star sugar, wrapped candy)
		for c: Dictionary in arena.candies:
			var pos := Vector2(float(c.x), float(c.y))
			var col: Color = c.color
			var kind := int(c.kind)
			var rot := float(c.rot)
			# Trail sparkles
			draw_circle(pos - Vector2(float(c.vx), float(c.vy)) * 0.025, 3.5, Color(1.0, 0.96, 0.8, 0.55))
			draw_circle(pos - Vector2(float(c.vx), float(c.vy)) * 0.05, 2.0, Color(col.r, col.g, col.b, 0.40))
			if kind == 0:
				# Swirl Lollipop: white stick + candy disc + spiral highlight
				var stick_dir := Vector2(cos(rot + 1.2), sin(rot + 1.2))
				draw_line(pos, pos + stick_dir * 16.0, Color("fff8e7"), 2.5)
				draw_circle(pos, 9.5, Color("2d1b36"))
				draw_circle(pos, 8.0, col)
				draw_arc(pos, 4.8, rot, rot + 4.2, 12, Color.WHITE, 2.0)
				draw_circle(pos + Vector2(-2.5, -2.5), 2.0, Color.WHITE)
			elif kind == 1:
				# Konpeito Star Candy (5-pointed star)
				var pts := PackedVector2Array()
				for k in range(10):
					var a := rot + float(k) * PI / 5.0
					var r := 10.5 if (k % 2 == 0) else 4.8
					pts.append(pos + Vector2(cos(a) * r, sin(a) * r))
				draw_colored_polygon(pts, col)
				draw_polyline(pts, Color.WHITE, 1.2, true)
			else:
				# Wrapped Sweet Candy (central round + two bow triangles)
				var ax := Vector2(cos(rot), sin(rot))
				var perp := Vector2(-ax.y, ax.x)
				var left_bow := PackedVector2Array([
					pos - ax * 5.0,
					pos - ax * 12.0 + perp * 6.0,
					pos - ax * 12.0 - perp * 6.0,
				])
				var right_bow := PackedVector2Array([
					pos + ax * 5.0,
					pos + ax * 12.0 + perp * 6.0,
					pos + ax * 12.0 - perp * 6.0,
				])
				draw_colored_polygon(left_bow, col.lightened(0.22))
				draw_colored_polygon(right_bow, col.lightened(0.22))
				draw_circle(pos, 7.5, Color("2d1b36"))
				draw_circle(pos, 6.2, col)
				draw_line(pos - perp * 4.0, pos + perp * 4.0, Color.WHITE, 1.6)

		# 3. Candy impact bursts (expanding star/sugar rings)
		for b: Dictionary in arena.candy_bursts:
			var t := 1.0 - clampf(float(b.life) / float(b.total), 0.0, 1.0)
			var bpos: Vector2 = b.pos
			var bcol: Color = b.color
			bcol.a = 1.0 - t
			var rad := lerpf(6.0, float(b.radius), t)
			draw_arc(bpos, rad, 0.0, TAU, 20, bcol, 2.5)
			for s in range(6):
				var sa := float(s) * TAU / 6.0 + t * 2.2
				var sp := bpos + Vector2(cos(sa), sin(sa)) * rad * 0.85
				draw_circle(sp, 3.0 * (1.0 - t), Color(1.0, 0.96, 0.78, 1.0 - t))

class BoxOverlay extends Node2D:
	var arena: Node2D
	func _draw() -> void:
		if arena == null or not arena.show_hitboxes:
			return
		var g_y: float = arena.GROUND_Y
		for idx in range(2):
			var f: Node2D = arena.player1 if idx == 0 else arena.player2
			if f == null:
				continue
			var body_h := 66.0 if f.crouching else 96.0
			var hurt_rect := Rect2(float(f.x) - 20.0, g_y - float(f.height) - body_h, 40.0, body_h)
			var hurt_col := Color(0.25, 0.75, 1.0, 0.25) if f.guarding else Color(0.2, 0.95, 0.45, 0.22)
			draw_rect(hurt_rect, hurt_col, true)
			draw_rect(hurt_rect, hurt_col.lightened(0.35), false, 1.0)
			var foot := Vector2(float(f.x), g_y - float(f.height))
			draw_line(foot + Vector2(-6, 0), foot + Vector2(6, 0), Color.YELLOW, 1.5)
			draw_line(foot + Vector2(0, -6), foot + Vector2(0, 6), Color.YELLOW, 1.5)

			if String(f.attack) != "" and HitResolve.ATTACKS.has(String(f.attack)):
				var reach: float = float(HitResolve.ATTACKS[String(f.attack)]["reach"])
				var active: bool = HitResolve.is_active(f)
				var hx: float = float(f.x) if int(f.facing) > 0 else float(f.x) - reach
				var hit_rect := Rect2(hx, g_y - float(f.height) - 82.0, reach, 54.0)
				var hcol := Color(1.0, 0.2, 0.25, 0.42) if active else Color(1.0, 0.85, 0.2, 0.20)
				draw_rect(hit_rect, hcol, true)
				draw_rect(hit_rect, Color(1.0, 0.3, 0.3, 0.95) if active else Color(1.0, 0.85, 0.2, 0.7), false, 1.5)

func _ready() -> void:
	is_training = (MatchConfig.mode == "training")
	show_hitboxes = is_training
	if ResourceLoader.exists("res://art/tangtang/super_cutin.png"):
		_cutin_texture = load("res://art/tangtang/super_cutin.png")
	elif ResourceLoader.exists("res://art/tangtang/super_cutin.webp"):
		_cutin_texture = load("res://art/tangtang/super_cutin.webp")
	world_root = Node2D.new()
	add_child(world_root)
	_build_stage()
	_build_actors()
	super_fx_node = SuperFxOverlay.new()
	super_fx_node.arena = self
	super_fx_node.z_index = 15
	world_root.add_child(super_fx_node)
	debug_draw_node = BoxOverlay.new()
	debug_draw_node.arena = self
	debug_draw_node.z_index = 20
	world_root.add_child(debug_draw_node)
	_build_hud()
	_build_audio()
	_start_round(true)

func _build_stage() -> void:
	var sky := ColorRect.new()
	sky.color = Color("0d0a1a")
	sky.size = Vector2(ARENA_WIDTH, ARENA_HEIGHT)
	world_root.add_child(sky)

	var bg_path := "res://art/map/yggdrasil/background.png"
	if not ResourceLoader.exists(bg_path):
		bg_path = "res://art/map/yggdrasil/background.webp"
	if ResourceLoader.exists(bg_path):
		var bg := Sprite2D.new()
		bg.texture = load(bg_path)
		bg.position = Vector2(ARENA_WIDTH * 0.5, ARENA_HEIGHT * 0.45)
		bg.scale = Vector2(0.45, 0.45)
		bg.modulate = Color(0.75, 0.72, 0.88, 0.85)
		world_root.add_child(bg)

	var floor_band := ColorRect.new()
	floor_band.color = Color("1e162e")
	floor_band.position = Vector2(0.0, GROUND_Y)
	floor_band.size = Vector2(ARENA_WIDTH, ARENA_HEIGHT - GROUND_Y)
	world_root.add_child(floor_band)

	var line := ColorRect.new()
	line.color = Color("ff9f43")
	line.position = Vector2(0.0, GROUND_Y)
	line.size = Vector2(ARENA_WIDTH, 2.0)
	world_root.add_child(line)

	# Dark overlay used during Super Art freeze & Candy Rain sky darkening
	_stage_dim = ColorRect.new()
	_stage_dim.color = Color(0.04, 0.01, 0.09, 0.0)
	_stage_dim.position = Vector2(-40.0, -40.0)
	_stage_dim.size = Vector2(ARENA_WIDTH + 80.0, ARENA_HEIGHT + 80.0)
	_stage_dim.z_index = 5
	world_root.add_child(_stage_dim)

func _build_actors() -> void:
	var p1_info: Dictionary = MatchConfig.ROSTER[MatchConfig.p1_index % MatchConfig.ROSTER.size()]
	var p2_info: Dictionary = MatchConfig.ROSTER[MatchConfig.p2_index % MatchConfig.ROSTER.size()]

	player1 = Fighter.new()
	player1.attack_prefix = "p1_"
	player1.atlas_dir = String(p1_info["dir"])
	player1.accent_color = p1_info["color"]
	player1.facing = 1
	player1.z_index = 10
	world_root.add_child(player1)
	player1._ensure_sprite()
	player1.place(220.0, GROUND_Y)

	player2 = Fighter.new()
	player2.attack_prefix = "p2_"
	player2.atlas_dir = String(p2_info["dir"])
	player2.accent_color = p2_info["color"]
	if MatchConfig.p1_index == MatchConfig.p2_index:
		player2.tint = Color(0.82, 0.90, 1.0, 1.0)
	player2.facing = -1
	player2.z_index = 10
	world_root.add_child(player2)
	player2._ensure_sprite()
	player2.place(380.0, GROUND_Y)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var p1_info: Dictionary = MatchConfig.ROSTER[MatchConfig.p1_index % MatchConfig.ROSTER.size()]
	var p2_info: Dictionary = MatchConfig.ROSTER[MatchConfig.p2_index % MatchConfig.ROSTER.size()]

	for i in range(2):
		var bar_x := 18.0 if i == 0 else 362.0
		var border := ColorRect.new()
		border.color = Color("3d315b")
		border.position = Vector2(bar_x - 2.0, 14.0)
		border.size = Vector2(264.0, 18.0)
		layer.add_child(border)

		var bg := ColorRect.new()
		bg.color = Color("181224")
		bg.position = Vector2(bar_x, 16.0)
		bg.size = Vector2(260.0, 14.0)
		layer.add_child(bg)

		var delay_bar := ColorRect.new()
		delay_bar.color = Color("ff4757")
		delay_bar.position = Vector2(bar_x, 16.0)
		delay_bar.size = Vector2(260.0, 14.0)
		layer.add_child(delay_bar)
		_hp_delays.append(delay_bar)

		var fill := ColorRect.new()
		fill.color = Color("2ed573") if i == 0 else Color("ffa502")
		fill.position = Vector2(bar_x, 16.0)
		fill.size = Vector2(260.0, 14.0)
		layer.add_child(fill)
		_hp_fills.append(fill)

		var role_suffix := " [木桩]" if is_training else (" [CPU]" if MatchConfig.vs_cpu else "")
		var name_text := String(p1_info["name"]) if i == 0 else (String(p2_info["name"]) + role_suffix)
		var name_lbl := _make_label(name_text, Vector2(bar_x, 33.0), 10, Color("f2e9ff"))
		name_lbl.size = Vector2(260.0, 14.0)
		if i == 1:
			name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		layer.add_child(name_lbl)

		for r in range(MatchConfig.rounds_to_win):
			var dot := ColorRect.new()
			dot.size = Vector2(8.0, 8.0)
			var dx := (bar_x + 252.0 - float(r) * 12.0) if i == 0 else (bar_x + float(r) * 12.0)
			dot.position = Vector2(dx, 35.0)
			dot.color = Color("32284a")
			dot.visible = not is_training
			layer.add_child(dot)
			if i == 0:
				_round_dots_p1.append(dot)
			else:
				_round_dots_p2.append(dot)

		var e_x := 18.0 if i == 0 else 442.0
		var e_bg := ColorRect.new()
		e_bg.color = Color("221a35")
		e_bg.position = Vector2(e_x, 332.0)
		e_bg.size = Vector2(180.0, 8.0)
		layer.add_child(e_bg)

		var e_fill := ColorRect.new()
		e_fill.color = Color("00d2d3") if i == 0 else Color("ff9ff3")
		e_fill.position = Vector2(e_x, 332.0)
		e_fill.size = Vector2(90.0, 8.0)
		layer.add_child(e_fill)
		_energy_fills.append(e_fill)

		var combo_lbl := _make_label("", Vector2(20.0 if i == 0 else 480.0, 102.0), 15, Color("ffd166"))
		combo_lbl.size = Vector2(140.0, 24.0)
		if i == 1:
			combo_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		layer.add_child(combo_lbl)
		_combo_labels.append(combo_lbl)

	var timer_box := ColorRect.new()
	timer_box.color = Color("2b2142")
	timer_box.position = Vector2(294.0, 10.0)
	timer_box.size = Vector2(52.0, 30.0)
	layer.add_child(timer_box)

	_timer_label = _make_label("∞" if is_training else "99", Vector2(294.0, 12.0), 18, Color("fff4dc"))
	_timer_label.size = Vector2(52.0, 28.0)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(_timer_label)

	_training_panel = ColorRect.new()
	_training_panel.color = Color(0.08, 0.06, 0.14, 0.78)
	_training_panel.position = Vector2(16.0, 48.0)
	_training_panel.size = Vector2(608.0, 48.0)
	_training_panel.visible = is_training
	layer.add_child(_training_panel)

	_training_label = _make_label("", Vector2(22.0, 50.0), 9, Color("a3f7bf"))
	_training_label.size = Vector2(596.0, 44.0)
	_training_label.visible = is_training
	layer.add_child(_training_label)

	# Street Fighter Super Art Cut-in Banner Band
	_cutin_band = Control.new()
	_cutin_band.position = Vector2(0.0, 96.0)
	_cutin_band.size = Vector2(640.0, 156.0)
	_cutin_band.clip_contents = true
	_cutin_band.visible = false
	layer.add_child(_cutin_band)

	var band_bg := ColorRect.new()
	band_bg.color = Color(0.16, 0.03, 0.22, 0.92)
	band_bg.size = Vector2(640.0, 156.0)
	_cutin_band.add_child(band_bg)

	if _cutin_texture != null:
		_cutin_sprite = Sprite2D.new()
		_cutin_sprite.texture = _cutin_texture
		_cutin_sprite.scale = Vector2(0.50, 0.50)
		_cutin_sprite.position = Vector2(320.0, 78.0)
		_cutin_band.add_child(_cutin_sprite)

	var top_gold := ColorRect.new()
	top_gold.color = Color("ffd166")
	top_gold.size = Vector2(640.0, 4.0)
	_cutin_band.add_child(top_gold)

	var bot_gold := ColorRect.new()
	bot_gold.color = Color("ffd166")
	bot_gold.position = Vector2(0.0, 152.0)
	bot_gold.size = Vector2(640.0, 4.0)
	_cutin_band.add_child(bot_gold)

	var title_plate := ColorRect.new()
	title_plate.color = Color(0.08, 0.02, 0.14, 0.82)
	title_plate.position = Vector2(0.0, 114.0)
	title_plate.size = Vector2(640.0, 38.0)
	_cutin_band.add_child(title_plate)

	_cutin_title = _make_label("★ SUPER ART · 漫天糖果雨 ★", Vector2(16.0, 118.0), 22, Color("fff4dc"))
	_cutin_title.size = Vector2(608.0, 32.0)
	_cutin_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cutin_band.add_child(_cutin_title)

	_banner_label = _make_label("", Vector2(0.0, 128.0), 32, Color("ffd166"))
	_banner_label.size = Vector2(640.0, 44.0)
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(_banner_label)

	_sub_banner_label = _make_label("", Vector2(0.0, 174.0), 13, Color("f2e9ff"))
	_sub_banner_label.size = Vector2(640.0, 24.0)
	_sub_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(_sub_banner_label)

	var hint_str := (
		"【木桩调试】1:轻拳 2:重拳 3:踢腿 4:受击 5/I:大招[漫天糖果雨] | F1:木桩状态 F2:判定框 F3:慢放 R:重置 F5:选人"
		if is_training else
		"P1: WASD移动/跳/蹲  J连段  L瞬步  U远攻波  I超必杀[漫天糖果雨](40气)  O灵替(30气)  |  F5重选角色"
	)
	_hint_label = _make_label(hint_str, Vector2(0.0, 344.0), 8, Color("8f7fac"))
	_hint_label.size = Vector2(640.0, 14.0)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(_hint_label)

func _build_audio() -> void:
	for i in range(SFX_VOICES):
		var player := AudioStreamPlayer.new()
		add_child(player)
		_sfx_players.append(player)

func _start_round(reset_all: bool = false) -> void:
	if reset_all:
		round_number = 1
		p1_wins = 0
		p2_wins = 0
		player1.energy = Fighter.MAX_ENERGY if is_training else 50.0
		player2.energy = Fighter.MAX_ENERGY if is_training else 50.0
	player1.reset_for_round(220.0 if is_training else 200.0, GROUND_Y)
	player2.reset_for_round(380.0 if is_training else 440.0, GROUND_Y)
	if is_training:
		player1.energy = Fighter.MAX_ENERGY
		player2.energy = Fighter.MAX_ENERGY
	for p: Dictionary in projectiles:
		p.node.queue_free()
	projectiles.clear()
	candies.clear()
	candy_bursts.clear()
	super_freeze_clock = 0.0
	candy_rain_clock = 0.0
	if _cutin_band != null:
		_cutin_band.visible = false
	round_timer = 99.0
	if is_training:
		state = "fight"
		_banner_label.text = ""
		_sub_banner_label.text = ""
	else:
		state = "intro"
		state_clock = 1.3
		_banner_label.text = "ROUND %d" % round_number
		_sub_banner_label.text = "READY..."

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).physical_keycode
		if key == KEY_F5 or key == KEY_ESCAPE:
			Engine.time_scale = 1.0
			get_tree().change_scene_to_file("res://scenes/select.tscn")
			return
		if is_training:
			match key:
				KEY_1:
					_pending_force_attack = "attack-light"
				KEY_2:
					_pending_force_attack = "attack-heavy"
				KEY_3:
					_pending_force_attack = "kick"
				KEY_4:
					player1.take_hit(0.0, -8.0 * float(player1.facing), 0.40, 0.0, false)
				KEY_5:
					_pending_force_attack = "super-cast"
				KEY_F1:
					var idx := DUMMY_STATES.find(dummy_behavior)
					dummy_behavior = DUMMY_STATES[(idx + 1) % DUMMY_STATES.size()]
				KEY_F2:
					show_hitboxes = not show_hitboxes
					debug_draw_node.queue_redraw()
				KEY_F3:
					slow_motion = not slow_motion
					Engine.time_scale = 0.25 if slow_motion else 1.0
				KEY_R:
					_start_round(true)
		elif state == "match_over" and key in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_J]:
			_play_sfx("confirm")
			_start_round(true)

func _process(delta: float) -> void:
	# Street Fighter Super Art freeze pauses the simulation while animating the Cut-in!
	if super_freeze_clock > 0.0:
		super_freeze_clock = maxf(0.0, super_freeze_clock - delta)
		var progress := 1.0 - (super_freeze_clock / super_Freeze_total)
		if _cutin_band != null:
			_cutin_band.visible = super_freeze_clock > 0.0
			if _cutin_sprite != null:
				# Fast slide-in from left, hold in center, then slight zoom
				var slide := clampf(progress * 4.5, 0.0, 1.0)
				_cutin_sprite.position.x = lerpf(-120.0, 320.0, slide)
				var s := lerpf(0.54, 0.50, clampf(progress * 2.0, 0.0, 1.0))
				_cutin_sprite.scale = Vector2(s, s)
		if super_freeze_clock <= 0.0:
			if _cutin_band != null:
				_cutin_band.visible = false
			candy_rain_clock = 1.95
			candy_spawn_accum = 0.0
			shake_clock = 0.25
			shake_strength = 4.5
			_play_sfx("explosion")
		_render(delta)
		return

	if hitstop_clock > 0.0:
		hitstop_clock = maxf(0.0, hitstop_clock - delta)
	else:
		accumulator += minf(delta, FIXED_DT * float(MAX_STEPS_PER_FRAME))
		while accumulator >= FIXED_DT:
			_step_fixed()
			accumulator -= FIXED_DT
	_render(delta)

func _start_super_art(caster_idx: int) -> void:
	var caster: Node2D = player1 if caster_idx == 0 else player2
	super_caster_idx = caster_idx
	super_caster_pos = Vector2(float(caster.x), GROUND_Y - float(caster.height) - 64.0)
	super_freeze_clock = super_Freeze_total
	if _cutin_band != null:
		_cutin_band.visible = true
	_play_sfx("confirm")
	_play_sfx("super_start")

func _step_fixed() -> void:
	ticks += 1
	player1.facing = 1 if float(player2.x) >= float(player1.x) else -1
	player2.facing = 1 if float(player1.x) >= float(player2.x) else -1

	if state == "intro":
		state_clock -= FIXED_DT
		if state_clock <= 0.45:
			_banner_label.text = "FIGHT!"
			_sub_banner_label.text = ""
		if state_clock <= 0.0:
			state = "fight"
			_banner_label.text = ""
		player1.step_fixed(FIXED_DT, {}, LEFT_WALL, RIGHT_WALL)
		player2.step_fixed(FIXED_DT, {}, LEFT_WALL, RIGHT_WALL)
		return

	if state == "ko":
		state_clock -= FIXED_DT
		player1.step_fixed(FIXED_DT, {}, LEFT_WALL, RIGHT_WALL)
		player2.step_fixed(FIXED_DT, {}, LEFT_WALL, RIGHT_WALL)
		_update_candies()
		if state_clock <= 0.0:
			if p1_wins >= MatchConfig.rounds_to_win or p2_wins >= MatchConfig.rounds_to_win:
				state = "match_over"
				var winner_name := String(MatchConfig.ROSTER[MatchConfig.p1_index]["name"]) if p1_wins > p2_wins else String(MatchConfig.ROSTER[MatchConfig.p2_index]["name"])
				_banner_label.text = "%s 获胜!" % winner_name
				_sub_banner_label.text = "按 J / Enter 再战一局　|　按 F5 / Esc 返回选人"
			else:
				round_number += 1
				_start_round(false)
		return

	if state == "match_over":
		player1.step_fixed(FIXED_DT, {}, LEFT_WALL, RIGHT_WALL)
		player2.step_fixed(FIXED_DT, {}, LEFT_WALL, RIGHT_WALL)
		return

	if not is_training:
		round_timer = maxf(0.0, round_timer - FIXED_DT)
	else:
		player1.energy = Fighter.MAX_ENERGY
		player2.energy = Fighter.MAX_ENERGY
		if player2.hurt_clock <= 0.0 and player2.block_clock <= 0.0 and player2.grounded and candy_rain_clock <= 0.0 and player2.hp < Fighter.MAX_HP:
			_regen_clock += FIXED_DT
			if _regen_clock >= 0.9:
				player2.hp = minf(Fighter.MAX_HP, player2.hp + 90.0 * FIXED_DT)
				if player2.hp >= Fighter.MAX_HP:
					_total_combo_damage = 0.0
		else:
			_regen_clock = 0.0
		if player1.hp < Fighter.MAX_HP and player1.hurt_clock <= 0.0:
			player1.hp = minf(Fighter.MAX_HP, player1.hp + 90.0 * FIXED_DT)

	var cmd1: Dictionary = player1.poll_input_command()
	if _pending_force_attack != "":
		cmd1["force_attack"] = _pending_force_attack
		_pending_force_attack = ""

	var cmd2: Dictionary
	if is_training:
		cmd2 = _dummy_command()
	elif MatchConfig.vs_cpu:
		cmd2 = _cpu_command()
	else:
		cmd2 = player2.poll_input_command()

	player1.step_fixed(FIXED_DT, cmd1, LEFT_WALL, RIGHT_WALL)
	player2.step_fixed(FIXED_DT, cmd2, LEFT_WALL, RIGHT_WALL)
	_separate_fighters()
	_resolve_combat()
	_update_projectiles()
	_update_candies()
	if is_training:
		player1.hp = maxf(1.0, player1.hp)
		player2.hp = maxf(1.0, player2.hp)
	else:
		_check_round_end()

func _update_candies() -> void:
	var fighters := [player1, player2]
	if candy_rain_clock > 0.0:
		candy_rain_clock = maxf(0.0, candy_rain_clock - FIXED_DT)
		candy_spawn_accum += FIXED_DT
		# Spawn a dense wave of colorful candies across the arena sky (biased slightly toward opponent)
		while candy_spawn_accum >= 0.065:
			candy_spawn_accum -= 0.065
			var target_f: Node2D = fighters[1 - maxi(0, super_caster_idx)]
			var caster_f: Node2D = fighters[maxi(0, super_caster_idx)]
			var aim_target := randf() < 0.55
			var spawn_x := (
				float(target_f.x) + randf_range(-110.0, 110.0)
				if aim_target else randf_range(36.0, ARENA_WIDTH - 36.0)
			)
			spawn_x = clampf(spawn_x, 28.0, ARENA_WIDTH - 28.0)
			candies.append({
				"x": spawn_x - float(caster_f.facing) * 32.0,
				"y": randf_range(-48.0, -12.0),
				"vx": float(caster_f.facing) * randf_range(28.0, 78.0) + randf_range(-20.0, 20.0),
				"vy": randf_range(290.0, 410.0),
				"rot": randf() * TAU,
				"vrot": randf_range(-9.0, 9.0),
				"kind": randi() % 3,
				"color": CANDY_PALETTE[randi() % CANDY_PALETTE.size()],
				"owner": maxi(0, super_caster_idx),
			})

	var remaining: Array = []
	for c: Dictionary in candies:
		c.x = float(c.x) + float(c.vx) * FIXED_DT
		c.y = float(c.y) + float(c.vy) * FIXED_DT
		c.vy = float(c.vy) + 340.0 * FIXED_DT
		c.rot = float(c.rot) + float(c.vrot) * FIXED_DT

		var target: Node2D = fighters[1 - int(c.owner)]
		var body_h := 66.0 if target.crouching else 96.0
		var target_top := GROUND_Y - float(target.height) - body_h
		var target_bot := GROUND_Y - float(target.height)
		var hit: bool = absf(float(c.x) - float(target.x)) <= 28.0 \
			and float(c.y) >= target_top - 10.0 and float(c.y) <= target_bot + 6.0 \
			and target.invuln_clock <= 0.0 and target.hp > 0.0

		if hit:
			var blocked: bool = target.guarding and target.grounded and target.hurt_clock <= 0.0
			var push_dir := 1.0 if float(c.x) <= float(target.x) else -1.0
			var dmg := 2.8
			target.take_hit(dmg, 3.0 * push_dir, 0.24, 155.0 if not blocked else 0.0, blocked)
			if not blocked:
				target.combo = mini(target.combo + 1, 99)
				target.combo_clock = HitResolve.COMBO_WINDOW
			if int(c.owner) == 0:
				_last_hit_damage = dmg * (0.2 if blocked else 1.0)
				_total_combo_damage = (_total_combo_damage + _last_hit_damage) if target.combo > 1 else _last_hit_damage
			_play_sfx("candy_pop")
			shake_clock = maxf(shake_clock, 0.08)
			shake_strength = maxf(shake_strength, 2.8)
			candy_bursts.append({
				"pos": Vector2(float(c.x), float(c.y)),
				"color": c.color,
				"radius": 26.0,
				"life": 0.20,
				"total": 0.20,
			})
			continue

		if float(c.y) >= GROUND_Y:
			candy_bursts.append({
				"pos": Vector2(float(c.x), GROUND_Y),
				"color": c.color,
				"radius": 18.0,
				"life": 0.16,
				"total": 0.16,
			})
			continue

		remaining.append(c)
	candies = remaining

func _dummy_command() -> Dictionary:
	match dummy_behavior:
		"guard":
			return {"move": -int(player2.facing), "force_guard": true}
		"crouch":
			return {"crouch": true}
		"jump":
			return {"jump": player2.grounded}
		"cpu":
			return _cpu_command()
		_:
			return {}

func _separate_fighters() -> void:
	if absf(float(player1.height) - float(player2.height)) > 52.0:
		return
	var min_dist := 34.0
	var dx: float = float(player2.x) - float(player1.x)
	if absf(dx) < min_dist:
		var push := (min_dist - absf(dx)) * 0.5
		var dir := 1.0 if dx >= 0.0 else -1.0
		player1.x = clampf(float(player1.x) - dir * push, LEFT_WALL + Fighter.EDGE_MARGIN, RIGHT_WALL - Fighter.EDGE_MARGIN)
		player2.x = clampf(float(player2.x) + dir * push, LEFT_WALL + Fighter.EDGE_MARGIN, RIGHT_WALL - Fighter.EDGE_MARGIN)

func _cpu_command() -> Dictionary:
	_ai_clock -= FIXED_DT
	var dx: float = float(player1.x) - float(player2.x)
	var dist := absf(dx)
	var dir_to_p1 := int(signf(dx))
	var cmd := {
		"move": _ai_move,
		"jump": false,
		"crouch": _ai_crouch,
		"light": false,
		"ranged": false,
		"special": false,
		"flash": false,
		"assist": false,
	}
	if player2.hurt_clock > 0.0 and player2.combo >= 4 and player2.energy >= Fighter.COST_ASSIST and randf() < 0.04:
		cmd["assist"] = true
		return cmd

	if _ai_clock <= 0.0:
		_ai_clock = randf_range(0.14, 0.28)
		_ai_crouch = false
		if player1.attack != "" and dist < 95.0 and randf() < 0.48:
			_ai_move = -dir_to_p1
		elif dist > 110.0:
			_ai_move = dir_to_p1
			if dist > 180.0 and randf() < 0.28:
				cmd["ranged"] = true
			elif dist > 160.0 and randf() < 0.18:
				cmd["flash"] = true
		elif dist <= 78.0:
			_ai_move = 0 if randf() < 0.5 else dir_to_p1
			if player2.energy >= Fighter.COST_SPECIAL and randf() < 0.22:
				cmd["special"] = true
			else:
				cmd["light"] = true
		else:
			_ai_move = dir_to_p1
		if player1.height > 40.0 and player2.grounded and randf() < 0.25:
			cmd["jump"] = true
		cmd["move"] = _ai_move
	elif dist <= 72.0 and player2.chain_clock > 0.0 and randf() < 0.15:
		cmd["light"] = true
	return cmd

func _resolve_combat() -> void:
	var fighters := [player1, player2]
	for index in range(2):
		var attacker: Node2D = fighters[index]
		var target: Node2D = fighters[1 - index]
		if attacker.wants_super:
			attacker.wants_super = false
			_start_super_art(index)
		var result := HitResolve.resolve(attacker, target)
		if not result.is_empty():
			var blocked := bool(result.get("blocked", false))
			var heavy := String(result.kind) in ["attack-heavy", "kick"]
			var dmg := float(result.get("damage", 0.0))
			if index == 0:
				_last_hit_damage = dmg
				_total_combo_damage = (_total_combo_damage + dmg) if target.combo > 1 else dmg
			_play_sfx("hit_light" if blocked else ("hit_heavy" if heavy else "hit_light"))
			if not blocked:
				_play_sfx("hurt")
			attacker.add_energy(Fighter.GAIN_HIT * (0.4 if blocked else 1.0))
			target.add_energy(Fighter.GAIN_TAKEN)
			hitstop_clock = 0.045 if not heavy else 0.075
			shake_clock = 0.12 if not heavy else 0.18
			shake_strength = 2.5 if blocked else (6.0 if heavy else 3.5)
			_spawn_hit_spark(
				Vector2((float(attacker.x) + float(target.x)) * 0.5, GROUND_Y - float(target.height) - 54.0),
				Color("70a1ff") if blocked else (Color("ff6b81") if heavy else Color("ffd166")),
				18.0 if blocked else (28.0 if heavy else 20.0)
			)
		if attacker.wants_projectile:
			attacker.wants_projectile = false
			_spawn_projectile(index)
		_play_motion_cues(index, attacker)

func _spawn_hit_spark(at: Vector2, color: Color, radius: float) -> void:
	var spark := ColorRect.new()
	spark.color = color
	spark.size = Vector2(radius, radius)
	spark.position = at - spark.size * 0.5
	spark.rotation = deg_to_rad(45.0)
	world_root.add_child(spark)
	effects.append({"node": spark, "life": 0.14, "total": 0.14})

func _play_motion_cues(index: int, fighter: Node2D) -> void:
	if fighter.attack != "" and _last_attack[index] == "":
		_play_sfx("whiff")
	_last_attack[index] = fighter.attack
	var grounded: bool = fighter.grounded
	if not _was_grounded[index] and grounded:
		_play_sfx("land")
	elif _was_grounded[index] and not grounded:
		_play_sfx("jump")
	_was_grounded[index] = grounded

func _spawn_projectile(index: int) -> void:
	var fighter: Node2D = player1 if index == 0 else player2
	var node := ColorRect.new()
	node.color = fighter.accent_color
	node.size = Vector2(18.0, 10.0)
	world_root.add_child(node)
	projectiles.append({
		"node": node,
		"x": float(fighter.x) + float(fighter.facing) * 32.0,
		"y": GROUND_Y - float(fighter.height) - PROJECTILE_HEIGHT,
		"vx": float(fighter.facing) * PROJECTILE_SPEED,
		"owner": index,
		"life": PROJECTILE_LIFE,
	})
	_play_sfx("whiff")

func _update_projectiles() -> void:
	var fighters := [player1, player2]
	var remaining: Array = []
	for projectile: Dictionary in projectiles:
		projectile.x += float(projectile.vx) * FIXED_DT
		projectile.y += float(projectile.get("vy", 0.0)) * FIXED_DT
		projectile.life -= FIXED_DT
		var node: ColorRect = projectile.node
		node.position = Vector2(projectile.x - 9.0, projectile.y - 5.0).round()
		var target: Node2D = fighters[1 - int(projectile.owner)]
		var vertical: float = GROUND_Y - float(target.height) - PROJECTILE_HEIGHT
		var is_super_drop := bool(projectile.get("super_drop", false))
		var crouch_dodge: bool = (not is_super_drop) and target.crouching and target.grounded
		var hit: bool = not crouch_dodge \
			and absf(float(projectile.x) - float(target.x)) <= PROJECTILE_HALF_W + (28.0 if is_super_drop else 16.0) \
			and absf(vertical - float(projectile.y)) <= PROJECTILE_HALF_H \
			and target.invuln_clock <= 0.0 and target.hp > 0.0
		if hit:
			var blocked: bool = target.guarding and target.grounded and target.hurt_clock <= 0.0
			var dmg := 6.0 if is_super_drop else 7.0
			var launch := 190.0 if is_super_drop else 0.0
			target.take_hit(dmg, 6.0 * signf(float(projectile.vx)), 0.26, launch, blocked)
			if not blocked:
				target.combo = mini(target.combo + 1, HitResolve.MAX_COMBO)
				target.combo_clock = HitResolve.COMBO_WINDOW
			if int(projectile.owner) == 0:
				_last_hit_damage = dmg * (0.2 if blocked else 1.0)
				_total_combo_damage = (_total_combo_damage + _last_hit_damage) if target.combo > 1 else _last_hit_damage
			fighters[int(projectile.owner)].add_energy(Fighter.GAIN_HIT * (0.3 if is_super_drop else 1.0))
			target.add_energy(Fighter.GAIN_TAKEN)
			_play_sfx("hit_heavy" if is_super_drop else "hit_light")
			_spawn_hit_spark(Vector2(projectile.x, projectile.y), Color("70a1ff") if blocked else Color("ffd166"), 22.0 if is_super_drop else 18.0)
		if hit or projectile.life <= 0.0 or projectile.x < -20.0 or projectile.x > ARENA_WIDTH + 20.0 or projectile.y > GROUND_Y + 12.0:
			node.queue_free()
			continue
		remaining.append(projectile)
	projectiles = remaining

func _check_round_end() -> void:
	if player1.hp > 0.0 and player2.hp > 0.0 and round_timer > 0.0:
		return
	state = "ko"
	state_clock = 2.0
	_play_sfx("ko")
	if player1.hp <= 0.0 and player2.hp <= 0.0:
		_banner_label.text = "DOUBLE KO!"
	elif player1.hp >= player2.hp:
		p1_wins += 1
		_banner_label.text = "K.O.!" if player2.hp <= 0.0 else "TIME OVER!"
		_sub_banner_label.text = "P1 拿下本局"
	else:
		p2_wins += 1
		_banner_label.text = "K.O.!" if player1.hp <= 0.0 else "TIME OVER!"
		_sub_banner_label.text = ("CPU" if MatchConfig.vs_cpu else "P2") + " 拿下本局"

func _render(delta: float) -> void:
	player1.render_sync()
	player2.render_sync()

	# Update candy bursts
	for b: Dictionary in candy_bursts.duplicate():
		b.life = float(b.life) - delta
		if float(b.life) <= 0.0:
			candy_bursts.erase(b)

	if _stage_dim != null:
		var target_dim := 0.72 if super_freeze_clock > 0.0 else (0.38 if candy_rain_clock > 0.0 else 0.0)
		_stage_dim.color.a = lerpf(_stage_dim.color.a, target_dim, clampf(delta * 12.0, 0.0, 1.0))

	if super_fx_node != null:
		super_fx_node.queue_redraw()
	if debug_draw_node != null and show_hitboxes:
		debug_draw_node.queue_redraw()

	if shake_clock > 0.0:
		shake_clock = maxf(0.0, shake_clock - delta)
		world_root.position = Vector2(
			randf_range(-shake_strength, shake_strength),
			randf_range(-shake_strength, shake_strength)
		).round()
	else:
		world_root.position = Vector2.ZERO

	for fx: Dictionary in effects.duplicate():
		fx.life = float(fx.life) - delta
		var n: ColorRect = fx.node
		n.modulate.a = clampf(float(fx.life) / float(fx.total), 0.0, 1.0)
		if float(fx.life) <= 0.0:
			n.queue_free()
			effects.erase(fx)

	for i in range(2):
		var f: Node2D = player1 if i == 0 else player2
		var hp_ratio := clampf(f.hp / Fighter.MAX_HP, 0.0, 1.0)
		var target_w := 260.0 * hp_ratio
		var fill: ColorRect = _hp_fills[i]
		var delay_bar: ColorRect = _hp_delays[i]
		fill.size.x = target_w
		delay_bar.size.x = lerpf(delay_bar.size.x, target_w, clampf(delta * 6.0, 0.0, 1.0))
		if i == 0:
			fill.position.x = 18.0 + (260.0 - fill.size.x)
			delay_bar.position.x = 18.0 + (260.0 - delay_bar.size.x)

		var e_w := 180.0 * clampf(f.energy / Fighter.MAX_ENERGY, 0.0, 1.0)
		var e_fill: ColorRect = _energy_fills[i]
		e_fill.size.x = e_w
		if i == 1:
			e_fill.position.x = 442.0 + (180.0 - e_w)

	for r in range(_round_dots_p1.size()):
		_round_dots_p1[r].color = Color("ffd166") if r < p1_wins else Color("32284a")
		_round_dots_p2[r].color = Color("ffd166") if r < p2_wins else Color("32284a")

	_timer_label.text = "∞" if is_training else ("%02d" % ceili(round_timer))
	_combo_labels[0].text = ("%d HIT COMBO!" % player2.combo) if player2.combo >= 2 else ""
	_combo_labels[1].text = ("%d HIT COMBO!" % player1.combo) if player1.combo >= 2 else ""

	if is_training and _training_label != null:
		var dist := absf(float(player2.x) - float(player1.x))
		_training_label.text = (
			"P1 动画: %-18s  招式: %-12s  坐标: (%.0f, 高%.0f)   |   间距: %.0fpx   |   单次伤害: %.1f  连段累计: %.1f  (%d Hit)\n"
			+ "木桩(F1): %-18s  木桩动画: %-16s  受击硬直: %.2fs   |   判定框(F2): %s   |   速度(F3): %s"
		) % [
			player1.current_anim_status(),
			player1.attack if player1.attack != "" else "idle",
			player1.x, player1.height,
			dist,
			_last_hit_damage, _total_combo_damage, player2.combo,
			DUMMY_NAMES.get(dummy_behavior, dummy_behavior),
			player2.current_anim_status(),
			player2.hurt_clock,
			"开启" if show_hitboxes else "关闭",
			"0.25x 慢放" if slow_motion else "1.0x 正常",
		]

func _play_sfx(cue: String) -> void:
	if not SFX.has(cue) or not is_inside_tree():
		return
	var player: AudioStreamPlayer = null
	for candidate in _sfx_players:
		if not candidate.playing:
			player = candidate
			break
	if player == null:
		player = _sfx_players[_sfx_cursor % _sfx_players.size()]
		_sfx_cursor += 1
	if player.is_inside_tree():
		player.stream = SFX[cue]
		player.volume_db = float(SFX_GAIN.get(cue, 0.0))
		player.play()

func _make_label(text: String, pos: Vector2, size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = pos
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	return lbl
