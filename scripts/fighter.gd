extends Node2D
## Classic 1v1 fighting character with normalized sprite height, guarding,
## light/heavy/kick combo chain, projectiles, Street Fighter-style Super Art ("super-cast"),
## and burst escape.

const Atlas = preload("res://scripts/sprite_atlas.gd")

const HALF_WIDTH := 22.0
const EDGE_MARGIN := 32.0
const GRAVITY := 920.0
const JUMP_VELOCITY := 355.0
const TARGET_HEIGHT := 112.0

const DEFAULT_ATTACK_DURATION := {
	"attack-light": 0.26,
	"attack-heavy": 0.34,
	"kick": 0.34,
	"ranged": 0.28,
	"super-cast": 1.15,
}
const ATTACK_CLIP := {
	"attack-light": "attack-light",
	"attack-heavy": "attack-heavy",
	"kick": "kick",
	"ranged": "attack-light",
	"super-cast": "super-cast",
}
const CHAIN := ["attack-light", "attack-heavy", "kick"]
const CHAIN_WINDOW := 0.50

const MAX_HP := 100.0
const MAX_ENERGY := 100.0
const GAIN_HIT := 10.0
const GAIN_TAKEN := 7.0
const COST_SPECIAL := 40.0
const COST_ASSIST := 30.0

const DASH_SPEED := 440.0
const DASH_TIME := 0.16
const DASH_INVULN := 0.14
const ASSIST_INVULN := 0.42
const RANGED_CLOCK := 0.08
const RANGED_COOLDOWN := 0.50

@export var atlas_dir := "res://art/tangtang"
@export var tint := Color.WHITE
@export var accent_color := Color("ff9f43")
@export var attack_prefix := "p1_"

var x := 0.0
var height := 0.0
var vy := 0.0
var move_speed := 155.0
var grounded := true
var crouching := false
var guarding := false
var facing := 1
var jump_held := false

var hp := MAX_HP
var energy := 50.0

var attack := ""
var attack_clock := 0.0
var attack_total := 0.26
var hit_done := false
var super_hit := false
var ranged_spawned := false
var wants_projectile := false
var wants_super := false
var ranged_cooldown := 0.0

var hurt_clock := 0.0
var block_clock := 0.0
var invuln_clock := 0.0
var dash_clock := 0.0
var dash_dir := 0.0
var combo := 0
var combo_clock := 0.0
var chain_index := 0
var chain_clock := 0.0
var tick := 0

var _baseline_y := 0.0
var _sprite: AnimatedSprite2D
var _state_info := {}
var _base_scale := 0.55
var _held := {}
var _shadow: Polygon2D
var _guard_aura: ColorRect

func _ready() -> void:
	_build_shadow()
	_ensure_sprite()
	_build_guard_aura()

func _build_shadow() -> void:
	_shadow = Polygon2D.new()
	var pts := PackedVector2Array()
	for i in range(16):
		var a := float(i) * TAU / 16.0
		pts.append(Vector2(cos(a) * 26.0, sin(a) * 5.0))
	_shadow.polygon = pts
	_shadow.color = Color(0.0, 0.0, 0.0, 0.38)
	_shadow.z_index = -1
	add_child(_shadow)

func _build_guard_aura() -> void:
	_guard_aura = ColorRect.new()
	_guard_aura.color = Color(0.45, 0.82, 1.0, 0.28)
	_guard_aura.size = Vector2(54.0, 96.0)
	_guard_aura.position = Vector2(-27.0, -96.0)
	_guard_aura.visible = false
	_guard_aura.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_guard_aura)

func place(at_x: float, ground_y: float) -> void:
	x = at_x
	_baseline_y = ground_y
	height = 0.0
	vy = 0.0
	grounded = true
	attack = ""
	attack_clock = 0.0
	hurt_clock = 0.0
	block_clock = 0.0
	dash_clock = 0.0
	invuln_clock = 0.0
	combo = 0
	combo_clock = 0.0
	wants_super = false
	wants_projectile = false
	render_sync()

func reset_for_round(at_x: float, ground_y: float) -> void:
	hp = MAX_HP
	energy = clampf(energy + 25.0, 50.0, MAX_ENERGY)
	place(at_x, ground_y)

func has_candy_super() -> bool:
	return _state_info.has("super-cast")

func _ensure_sprite() -> void:
	if _sprite != null:
		return
	var atlas := Atlas.load_atlas(atlas_dir)
	if atlas.is_empty():
		var body := ColorRect.new()
		body.color = accent_color
		body.size = Vector2(HALF_WIDTH * 2.0, 88.0)
		body.position = Vector2(-HALF_WIDTH, -88.0)
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(body)
		return
	_state_info = atlas.get("state_info", {})
	var content_h := maxf(80.0, float(atlas.get("height", 140.0)))
	_base_scale = TARGET_HEIGHT / content_h
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = atlas.frames
	_sprite.centered = false
	_sprite.offset = -atlas.anchor
	_sprite.scale = Vector2(_base_scale, _base_scale)
	_sprite.modulate = tint
	add_child(_sprite)
	_sprite.play("idle")

func step_fixed(dt: float, cmd: Dictionary, arena_left: float, arena_right: float) -> void:
	tick += 1
	var move := int(cmd.get("move", 0))
	var jump_down := bool(cmd.get("jump", false))
	var crouch_down := bool(cmd.get("crouch", false))
	var jump_pressed := jump_down and not jump_held
	jump_held = jump_down

	invuln_clock = maxf(0.0, invuln_clock - dt)
	ranged_cooldown = maxf(0.0, ranged_cooldown - dt)
	block_clock = maxf(0.0, block_clock - dt)
	chain_clock = maxf(0.0, chain_clock - dt)
	if chain_clock <= 0.0:
		chain_index = 0
	combo_clock = maxf(0.0, combo_clock - dt)
	if combo_clock <= 0.0:
		combo = 0

	# 灵替 (assist/burst) breaks out of hitstun at the cost of 30 energy.
	if bool(cmd.get("assist", false)) and energy >= COST_ASSIST and hp > 0.0:
		_use_assist(arena_left, arena_right)

	if hurt_clock > 0.0:
		hurt_clock = maxf(0.0, hurt_clock - dt)
	elif attack != "":
		attack_clock += dt
		if attack == "ranged" and not ranged_spawned and attack_clock >= RANGED_CLOCK:
			ranged_spawned = true
			wants_projectile = true
		if attack_clock >= attack_total:
			attack = ""
			attack_clock = 0.0
			super_hit = false

	if dash_clock > 0.0:
		dash_clock = maxf(0.0, dash_clock - dt)
		x = clampf(x + dash_dir * DASH_SPEED * dt, arena_left + EDGE_MARGIN, arena_right - EDGE_MARGIN)
	if attack == "" and hurt_clock <= 0.0 and block_clock <= 0.0 and dash_clock <= 0.0 and hp > 0.0:
		_try_start_actions(move, cmd)

	var free_now := attack == "" and hurt_clock <= 0.0 and block_clock <= 0.0 and dash_clock <= 0.0 and hp > 0.0
	crouching = crouch_down and grounded and free_now
	var holding_back := (move * facing) < 0
	guarding = (free_now or block_clock > 0.0) and grounded and (holding_back or crouch_down or bool(cmd.get("force_guard", false)))

	if jump_pressed and grounded and free_now:
		crouching = false
		guarding = false
		vy = JUMP_VELOCITY
		grounded = false
	if free_now and not crouching:
		var speed_mult := 0.78 if holding_back else 1.0
		x = clampf(x + float(move) * move_speed * speed_mult * dt, arena_left + EDGE_MARGIN, arena_right - EDGE_MARGIN)
	if not grounded:
		height += vy * dt
		vy -= GRAVITY * dt
		if height <= 0.0:
			height = 0.0
			vy = 0.0
			grounded = true
			combo = 0
			combo_clock = 0.0
	crouching = crouching and grounded
	_update_animation(move)

func _try_start_actions(move: int, cmd: Dictionary) -> void:
	var forced_attack := String(cmd.get("force_attack", ""))
	if forced_attack == "super-cast":
		_trigger_super()
		return
	elif forced_attack != "":
		_start_attack(forced_attack, false)
		return

	if bool(cmd.get("special", false)) and energy >= COST_SPECIAL:
		energy -= COST_SPECIAL
		if has_candy_super():
			_trigger_super()
		else:
			_start_attack("attack-heavy", true)
	elif bool(cmd.get("ranged", false)) and ranged_cooldown <= 0.0:
		ranged_cooldown = RANGED_COOLDOWN
		_start_attack("ranged", false)
	elif bool(cmd.get("light", false)):
		var kind: String = CHAIN[chain_index]
		chain_index = (chain_index + 1) % CHAIN.size()
		chain_clock = CHAIN_WINDOW
		_start_attack(kind, false)
	elif bool(cmd.get("flash", false)) and grounded:
		dash_dir = float(facing) if move == 0 else float(signi(move))
		dash_clock = DASH_TIME
		invuln_clock = maxf(invuln_clock, DASH_INVULN)

func _trigger_super() -> void:
	if has_candy_super():
		_start_attack("super-cast", true)
		attack_total = 1.15
		invuln_clock = maxf(invuln_clock, 1.25)
		wants_super = true
	else:
		_start_attack("attack-heavy", true)

func _start_attack(kind: String, powered: bool) -> void:
	attack = kind
	attack_clock = 0.0
	var clip := String(ATTACK_CLIP.get(kind, "attack-light"))
	if _sprite != null and _sprite.sprite_frames != null and not _sprite.sprite_frames.has_animation(clip):
		clip = "attack-heavy"
	var default_dur := float(DEFAULT_ATTACK_DURATION.get(kind, 0.28))
	if kind == "super-cast":
		attack_total = 1.15
	elif _state_info.has(clip):
		attack_total = clampf(float(_state_info[clip]["duration"]), 0.20, 0.40)
	else:
		attack_total = default_dur
	hit_done = false
	super_hit = powered
	ranged_spawned = false
	crouching = false
	guarding = false
	if _sprite != null:
		_sprite.stop()
		_sprite.play(clip)

func _use_assist(arena_left: float, arena_right: float) -> void:
	energy = maxf(0.0, energy - COST_ASSIST)
	hurt_clock = 0.0
	block_clock = 0.0
	attack = ""
	attack_clock = 0.0
	invuln_clock = maxf(invuln_clock, ASSIST_INVULN)
	x = clampf(x - float(facing) * 44.0, arena_left + EDGE_MARGIN, arena_right - EDGE_MARGIN)

func add_energy(amount: float) -> void:
	energy = clampf(energy + amount, 0.0, MAX_ENERGY)

func take_hit(damage: float, push: float, stun: float, launch: float, blocked: bool = false) -> void:
	attack = ""
	attack_clock = 0.0
	hit_done = false
	super_hit = false
	if blocked:
		hp = maxf(1.0, hp - damage * 0.20)
		block_clock = maxf(block_clock, stun * 0.55)
		x = clampf(x + push * 0.65, EDGE_MARGIN, 640.0 - EDGE_MARGIN)
		return
	hp = maxf(0.0, hp - damage)
	hurt_clock = maxf(hurt_clock, stun)
	x = clampf(x + push, EDGE_MARGIN, 640.0 - EDGE_MARGIN)
	if launch > 0.0:
		vy = maxf(vy, launch) if not grounded else launch
		height = maxf(height, 1.0)
		grounded = false
	if _sprite != null:
		_sprite.stop()
		_sprite.play("hurt")

func poll_input_command() -> Dictionary:
	return {
		"move": int(Input.get_axis(attack_prefix + "left", attack_prefix + "right")),
		"jump": Input.is_action_pressed(attack_prefix + "jump"),
		"crouch": Input.is_action_pressed(attack_prefix + "crouch"),
		"light": _pressed("light"),
		"ranged": _pressed("ranged"),
		"special": _pressed("special"),
		"flash": _pressed("flash"),
		"assist": _pressed("assist"),
	}

func _pressed(action: String) -> bool:
	var full := attack_prefix + action
	var down := Input.is_action_pressed(full)
	var was := bool(_held.get(full, false))
	_held[full] = down
	return down and not was

func current_anim_status() -> String:
	if _sprite == null or _sprite.sprite_frames == null:
		return "none"
	var anim := String(_sprite.animation)
	var total := _sprite.sprite_frames.get_frame_count(anim)
	return "%s [%d/%d]" % [anim, _sprite.frame + 1, total]

func _update_animation(move: int) -> void:
	if _guard_aura != null:
		_guard_aura.visible = block_clock > 0.0 or (guarding and (crouching or move * facing < 0))
	if _sprite == null:
		return
	var clip := "idle"
	if hp <= 0.0 or hurt_clock > 0.0:
		clip = "hurt"
	elif block_clock > 0.0:
		clip = "crouch"
	elif attack != "":
		clip = String(ATTACK_CLIP.get(attack, "attack-light"))
		if _sprite.sprite_frames != null and not _sprite.sprite_frames.has_animation(clip):
			clip = "attack-heavy"
	elif not grounded:
		clip = "jump"
	elif crouching:
		clip = "crouch"
	elif dash_clock > 0.0:
		clip = "walk"
	elif move != 0:
		clip = "walk" if move * facing > 0 else "walk-back"
	_sprite.flip_h = facing < 0
	if _sprite.animation != clip:
		_sprite.play(clip)
	if attack == "super-cast":
		_sprite.modulate = Color(1.18, 1.08, 0.96, 1.0)
	elif invuln_clock > 0.0 and (tick % 4 < 2):
		_sprite.modulate = Color(1.4, 1.4, 1.6, 0.78)
	elif super_hit:
		_sprite.modulate = Color(1.35, 1.05, 0.65, 1.0)
	else:
		_sprite.modulate = tint

func render_sync() -> void:
	position = Vector2(x, _baseline_y - height).round()
	if _shadow != null:
		_shadow.position = Vector2(0.0, height)
		var s := clampf(1.0 - height / 260.0, 0.45, 1.0)
		_shadow.scale = Vector2(s, s)
