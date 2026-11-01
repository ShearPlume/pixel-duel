extends Node2D
## Placeholder fighter. Logic state (x, height, vy, facing, action, energy) is the
## only source of truth; the sprite only mirrors it.

const Atlas = preload("res://scripts/sprite_atlas.gd")

const HALF_WIDTH := 24.0
const EDGE_MARGIN := 24.0
const GRAVITY := 900.0
const JUMP_VELOCITY := 330.0
## Atlas cells are 192x208; 0.5 keeps the fighter near 95 px tall on a
## 640x360 canvas while staying an integer pixel scale.
const SPRITE_SCALE := 0.5

const ATTACK_DURATION := {
	"attack-light": 4.0 / 30.0,
	"attack-heavy": 4.0 / 24.0,
	"kick": 4.0 / 24.0,
	"ranged": 4.0 / 30.0,
}
const ATTACK_CLIP := {
	"attack-light": "attack-light",
	"attack-heavy": "attack-heavy",
	"kick": "kick",
	"ranged": "attack-light",
}
## J taps walk this chain: light -> heavy -> kick, then back to light.
const CHAIN := ["attack-light", "attack-heavy", "kick"]
const CHAIN_WINDOW := 0.45

const MAX_ENERGY := 100.0
const GAIN_HIT := 8.0
const GAIN_TAKEN := 5.0
const COST_SPECIAL := 40.0
const COST_ASSIST := 30.0

const DASH_SPEED := 430.0
const DASH_TIME := 0.16
const DASH_INVULN := 0.14
const ASSIST_INVULN := 0.40
const RANGED_CLOCK := 0.05
const RANGED_COOLDOWN := 0.45

@export var atlas_dir := "res://art/placeholder/stickman"
@export var tint := Color("8ccff3")
@export var attack_prefix := "p1_"

var x := 0.0
var height := 0.0
var vy := 0.0
var move_speed := 120.0
var grounded := true
var crouching := false
var facing := 1
var jump_held := false

var attack := ""
var attack_clock := 0.0
var hit_done := false
var super_hit := false
var ranged_spawned := false
var wants_projectile := false
var ranged_cooldown := 0.0

var hurt_clock := 0.0
var invuln_clock := 0.0
var dash_clock := 0.0
var dash_dir := 0.0
var combo := 0
var combo_clock := 0.0
var chain_index := 0
var chain_clock := 0.0
var energy := 100.0
var tick := 0

var _baseline_y := 0.0
var _sprite: AnimatedSprite2D
var _cell := Vector2(192.0, 208.0)
var _held := {}

func _ready() -> void:
	_ensure_sprite()

func place(at_x: float, ground_y: float) -> void:
	x = at_x
	_baseline_y = ground_y
	height = 0.0
	vy = 0.0
	grounded = true
	render_sync()

func _ensure_sprite() -> void:
	if _sprite != null:
		return
	var atlas := Atlas.load_atlas(atlas_dir)
	if atlas.is_empty():
		var body := ColorRect.new()
		body.color = tint
		body.size = Vector2(HALF_WIDTH * 2.0, 64.0)
		body.position = Vector2(-HALF_WIDTH, -64.0)
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(body)
		return
	_cell = atlas.cell
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = atlas.frames
	_sprite.centered = false
	# Put the feet anchor on the node origin so the root stays on the floor.
	_sprite.offset = -atlas.anchor
	_sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	_sprite.modulate = tint
	add_child(_sprite)
	_sprite.play("idle")

func step_fixed(dt: float, move: int, jump_down: bool, crouch_down: bool, arena_left: float, arena_right: float) -> void:
	tick += 1
	var jump_pressed := jump_down and not jump_held
	jump_held = jump_down

	invuln_clock = maxf(0.0, invuln_clock - dt)
	ranged_cooldown = maxf(0.0, ranged_cooldown - dt)
	chain_clock = maxf(0.0, chain_clock - dt)
	if chain_clock <= 0.0:
		chain_index = 0
	combo_clock = maxf(0.0, combo_clock - dt)
	if combo_clock <= 0.0:
		combo = 0

	# 灵替 (assist) is the one action allowed out of hitstun: it costs meter.
	if _pressed("assist") and energy >= COST_ASSIST:
		_use_assist()

	if hurt_clock > 0.0:
		hurt_clock = maxf(0.0, hurt_clock - dt)
	elif attack != "":
		attack_clock += dt
		if attack == "ranged" and not ranged_spawned and attack_clock >= RANGED_CLOCK:
			ranged_spawned = true
			wants_projectile = true
		if attack_clock >= float(ATTACK_DURATION.get(attack, 0.16)):
			attack = ""
			attack_clock = 0.0
			super_hit = false

	if dash_clock > 0.0:
		dash_clock = maxf(0.0, dash_clock - dt)
		x = clampf(x + dash_dir * DASH_SPEED * dt, arena_left + EDGE_MARGIN, arena_right - EDGE_MARGIN)
	if attack == "" and hurt_clock <= 0.0 and dash_clock <= 0.0:
		_try_start_actions(move)

	var free_now := attack == "" and hurt_clock <= 0.0 and dash_clock <= 0.0
	crouching = crouch_down and grounded and free_now
	if jump_pressed and grounded and free_now:
		crouching = false
		vy = JUMP_VELOCITY
		grounded = false
	if free_now and not crouching:
		x = clampf(x + float(move) * move_speed * dt, arena_left + EDGE_MARGIN, arena_right - EDGE_MARGIN)
	if not grounded:
		height += vy * dt
		vy -= GRAVITY * dt
		if height <= 0.0:
			height = 0.0
			vy = 0.0
			grounded = true
			# Landing ends the juggle: the next hit starts a fresh combo.
			combo = 0
			combo_clock = 0.0
	crouching = crouching and grounded
	_update_animation(move)

func _try_start_actions(move: int) -> void:
	if _pressed("special") and energy >= COST_SPECIAL:
		energy -= COST_SPECIAL
		_start_attack("attack-heavy", true)
	elif _pressed("ranged") and ranged_cooldown <= 0.0:
		ranged_cooldown = RANGED_COOLDOWN
		_start_attack("ranged", false)
	elif _pressed("light"):
		var kind: String = CHAIN[chain_index]
		chain_index = (chain_index + 1) % CHAIN.size()
		chain_clock = CHAIN_WINDOW
		_start_attack(kind, false)
	elif _pressed("flash") and grounded:
		dash_dir = float(facing) if move == 0 else float(signi(move))
		dash_clock = DASH_TIME
		invuln_clock = maxf(invuln_clock, DASH_INVULN)

func _start_attack(kind: String, powered: bool) -> void:
	attack = kind
	attack_clock = 0.0
	hit_done = false
	super_hit = powered
	ranged_spawned = false
	crouching = false

func _use_assist() -> void:
	energy = maxf(0.0, energy - COST_ASSIST)
	hurt_clock = 0.0
	attack = ""
	attack_clock = 0.0
	invuln_clock = maxf(invuln_clock, ASSIST_INVULN)
	x = clampf(x - facing * 26.0, EDGE_MARGIN, 640.0 - EDGE_MARGIN)

func add_energy(amount: float) -> void:
	energy = clampf(energy + amount, 0.0, MAX_ENERGY)

## Applies hitstun plus an optional upward launch. A target already in hitstun
## can be hit again on purpose: that is what makes air juggles possible.
func take_hit(push: float, stun: float, launch: float) -> void:
	attack = ""
	attack_clock = 0.0
	hit_done = false
	super_hit = false
	hurt_clock = maxf(hurt_clock, stun)
	x = clampf(x + push, EDGE_MARGIN, 640.0 - EDGE_MARGIN)
	if launch > 0.0:
		vy = maxf(vy, launch) if not grounded else launch
		height = maxf(height, 1.0)
		grounded = false

func _pressed(action: String) -> bool:
	var full := attack_prefix + action
	var down := Input.is_action_pressed(full)
	var was := bool(_held.get(full, false))
	_held[full] = down
	return down and not was

func _update_animation(move: int) -> void:
	if _sprite == null:
		return
	var clip := "idle"
	if hurt_clock > 0.0:
		clip = "hurt"
	elif attack != "":
		clip = String(ATTACK_CLIP.get(attack, "attack-light"))
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

func render_sync() -> void:
	position = Vector2(x, _baseline_y - height).round()
