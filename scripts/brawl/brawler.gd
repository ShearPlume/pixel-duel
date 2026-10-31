extends Node2D
## Platform-brawler character: percent damage, knockback, double jump, one-way
## platforms. Logic only; the sprite mirrors it.

const Atlas = preload("res://scripts/sprite_atlas.gd")
const Knockback = preload("res://scripts/brawl/knockback.gd")
const Items = preload("res://scripts/brawl/items.gd")
const ItemArt = preload("res://scripts/brawl/item_art.gd")

## Emitted for the sound layer, so the brawler stays pure logic.
signal jumped(double_jump: bool)
signal landed
signal struck(damage: float)

const HALF_W := 14.0
const SPRITE_SCALE := 0.65
## Standing height in screen pixels every character is scaled to.
const TARGET_HEIGHT := 167.0
## Held item icon scale, shared with the muzzle maths.
const GEAR_SCALE := 0.62

const RUN_SPEED := 210.0
const GROUND_ACCEL := 1800.0
const AIR_ACCEL := 1100.0
const FRICTION := 1600.0
const GRAVITY := 1150.0
const MAX_FALL := 950.0
## Launched victims float: lower gravity plus a slower terminal fall keeps them
## inside the attacker's jump arc long enough to combo.
const HITSTUN_GRAVITY := 0.62
const HITSTUN_FALL_CAP := 0.55
const JUMP_VELOCITY := -520.0
const DOUBLE_JUMP_VELOCITY := -470.0
const MAX_JUMPS := 2
## Short grace period where a ground jump still counts after leaving a ledge.
const COYOTE_TIME := 0.08
## Crouching. A second crouch tap inside the window falls through a soft platform.
const CROUCH_SPEED := 0.3
const CROUCH_TAP_WINDOW := 0.3
const DROP_TIME := 0.22

const ATTACKS := {
	"attack-light": {"duration": 4.0 / 30.0, "active": Vector2(0.067, 0.100), "reach": 46.0,
		"damage": 4.0, "kb_base": 140.0, "kb_scale": 3.2, "angle": 46.0},
	"attack-heavy": {"duration": 4.0 / 24.0, "active": Vector2(0.083, 0.125), "reach": 52.0,
		"damage": 8.0, "kb_base": 170.0, "kb_scale": 4.0, "angle": 52.0},
	"kick": {"duration": 4.0 / 24.0, "active": Vector2(0.083, 0.125), "reach": 58.0,
		"damage": 7.0, "kb_base": 160.0, "kb_scale": 3.8, "angle": 40.0},
	## Air attack: nearly vertical launch, the juggle starter.
	"air": {"duration": 4.0 / 24.0, "active": Vector2(0.083, 0.125), "reach": 44.0,
		"damage": 6.0, "kb_base": 120.0, "kb_scale": 2.6, "angle": 82.0},
}
const CHAIN := ["attack-light", "attack-heavy", "kick"]
const CHAIN_WINDOW := 0.45
const ATTACK_CLIP := {"attack-light": "attack-light", "attack-heavy": "attack-heavy", "kick": "kick", "air": "kick"}
const HIT_HEIGHT := 92.0
## Direct health: percent damage still drives knockback, but a fighter also
## dies when this runs out, so matches are not only about ring-outs.
const MAX_HP := 160.0

@export var atlas_dir := "res://art/fighter"
@export var tint := Color.WHITE
@export var attack_prefix := "p1_"

var player_index := 0
var vel := Vector2.ZERO
var facing := 1
var on_ground := true
var jumps_left := MAX_JUMPS
var coyote := 0.0
var damage_percent := 0.0
var hp := MAX_HP
var stocks := 3
var invuln := 0.0
var hitstun := 0.0
var attack := ""
var attack_clock := 0.0
var hit_done := false
var chain_index := 0
var chain_clock := 0.0
var respawn_clock := 0.0
var land_clock := 0.0
var item := ""
var ammo := 0
var item_cooldown := 0.0
var combo := 0
var combo_clock := 0.0
var alive := true

var _sprite: AnimatedSprite2D
var _hp_bar: ColorRect
var _hp_fill: ColorRect
var _gear: Sprite2D
## Fallback block used while the item icon sheet does not exist yet.
var _gear_block: ColorRect
var swing_clock := 0.0
var swing_total := 0.0
## Last crouch state the visuals used, so a host can tell its guests about it.
var crouch_pose := false
var charge_ratio := 0.0
var drop_clock := 0.0
var ground_soft := false
## Horizontal speed a conveyor under the feet adds while standing on it.
var ground_push := 0.0
var _crouch_tap := 0.0

func _ready() -> void:
	_ensure_visuals()

func spawn(at: Vector2) -> void:
	position = at
	vel = Vector2.ZERO
	damage_percent = 0.0
	hp = MAX_HP
	hitstun = 0.0
	attack = ""
	attack_clock = 0.0
	hit_done = false
	item = ""
	ammo = 0
	invuln = 1.2
	alive = true
	on_ground = false
	jumps_left = MAX_JUMPS
	visible = true
	render_sync()

func _ensure_visuals() -> void:
	if _sprite != null:
		return
	var atlas := Atlas.load_atlas(atlas_dir)
	if not atlas.is_empty():
		_sprite = AnimatedSprite2D.new()
		_sprite.sprite_frames = atlas.frames
		_sprite.centered = false
		_sprite.offset = -atlas.anchor
		var height := float(atlas.get("height", 0.0))
		var scale := SPRITE_SCALE if height <= 0.0 else SPRITE_SCALE * TARGET_HEIGHT / height
		_sprite.scale = Vector2(scale, scale)
		_sprite.modulate = tint
		add_child(_sprite)
		_sprite.play("idle")
	if ItemArt.available():
		_gear = Sprite2D.new()
		_gear.visible = false
		add_child(_gear)
	else:
		_gear_block = ColorRect.new()
		_gear_block.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_gear_block.visible = false
		add_child(_gear_block)
	_hp_bar = ColorRect.new()
	_hp_bar.position = Vector2(-27.0, -166.0)
	_hp_bar.size = Vector2(54.0, 9.0)
	_hp_bar.color = Color(0.06, 0.05, 0.10, 0.85)
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hp_bar)
	_hp_fill = ColorRect.new()
	_hp_fill.position = Vector2(-25.0, -164.0)
	_hp_fill.size = Vector2(50.0, 5.0)
	_hp_fill.color = Color(0.45, 0.9, 0.5)
	_hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hp_fill)

func step(dt: float, command: Dictionary, platforms: Array) -> void:
	invuln = maxf(0.0, invuln - dt)
	item_cooldown = maxf(0.0, item_cooldown - dt)
	land_clock = maxf(0.0, land_clock - dt)
	swing_clock = maxf(0.0, swing_clock - dt)
	combo_clock = maxf(0.0, combo_clock - dt)
	if combo_clock <= 0.0:
		combo = 0
	chain_clock = maxf(0.0, chain_clock - dt)
	if chain_clock <= 0.0:
		chain_index = 0

	if hitstun > 0.0:
		hitstun = maxf(0.0, hitstun - dt)
	else:
		_control(dt, command)
	if attack != "":
		attack_clock += dt
		if attack_clock >= float(ATTACKS[attack]["duration"]):
			attack = ""
			attack_clock = 0.0

	_integrate(dt, platforms)
	_update_visuals(command)

func _control(dt: float, command: Dictionary) -> void:
	var move := float(command.get("move", 0))
	var crouching := bool(command.get("crouch", false)) and on_ground
	var target := move * RUN_SPEED * (CROUCH_SPEED if crouching else 1.0)
	var accel := GROUND_ACCEL if on_ground else AIR_ACCEL
	if absf(move) < 0.01 and on_ground:
		vel.x = move_toward(vel.x, 0.0, FRICTION * dt)
	else:
		vel.x = move_toward(vel.x, target, accel * dt)

	coyote = COYOTE_TIME if on_ground else maxf(0.0, coyote - dt)
	_crouch_tap = maxf(0.0, _crouch_tap - dt)
	if bool(command.get("crouch_press", false)) and on_ground:
		if _crouch_tap > 0.0 and ground_soft:
			_crouch_tap = 0.0
			drop_clock = DROP_TIME
			on_ground = false
			ground_soft = false
			position.y += 4.0
			vel.y = 0.0
		else:
			_crouch_tap = CROUCH_TAP_WINDOW
	if bool(command.get("jump", false)):
		if on_ground or coyote > 0.0:
			vel.y = JUMP_VELOCITY
			on_ground = false
			coyote = 0.0
			jumps_left = MAX_JUMPS - 1
			jumped.emit(false)
		elif jumps_left > 0:
			vel.y = DOUBLE_JUMP_VELOCITY
			jumps_left -= 1
			jumped.emit(true)

	if bool(command.get("attack", false)) and attack == "":
		var kind: String
		if not on_ground:
			# Air attack always launches upward so the target can be juggled.
			kind = "air"
		else:
			kind = CHAIN[chain_index]
			chain_index = (chain_index + 1) % CHAIN.size()
			chain_clock = CHAIN_WINDOW
		attack = kind
		attack_clock = 0.0
		hit_done = false

func _integrate(dt: float, platforms: Array) -> void:
	var was_ground := on_ground
	drop_clock = maxf(0.0, drop_clock - dt)
	# A launched fighter hangs in the air: floaty gravity during hitstun is what
	# makes air juggles possible, otherwise the victim drops out of reach before
	# the attacker's jump peaks.
	var launched := hitstun > 0.0 and not on_ground
	var gravity := GRAVITY * (HITSTUN_GRAVITY if launched else 1.0)
	var fall_cap := MAX_FALL * (HITSTUN_FALL_CAP if launched else 1.0)
	# A conveyor drags whoever stands on it, before gravity moves anything.
	if on_ground and ground_push != 0.0:
		position.x += ground_push * dt
	vel.y = minf(fall_cap, vel.y + gravity * dt)
	var previous_y := position.y
	position += vel * dt
	on_ground = false
	if vel.y <= 0.0:
		return
	for index in range(platforms.size()):
		# Only the first slab is solid; the rest are one-way and can be dropped
		# through right after a double crouch tap.
		if index > 0 and drop_clock > 0.0:
			continue
		var platform: Rect2 = platforms[index]
		if position.x < platform.position.x - HALF_W or position.x > platform.end.x + HALF_W:
			continue
		if previous_y <= platform.position.y + 1.0 and position.y >= platform.position.y:
			position.y = platform.position.y
			vel.y = 0.0
			on_ground = true
			ground_soft = index > 0
			jumps_left = MAX_JUMPS
			# Re-landing is reported every frame while standing still, so the
			# landing clip must only fire on the transition from the air.
			if not was_ground:
				land_clock = 0.12
				landed.emit()
			return
	# Stepping off a ledge still costs the ground jump, unless coyote time is up.
	if was_ground and coyote <= 0.0:
		jumps_left = mini(jumps_left, MAX_JUMPS - 1)

func give_item(kind: String, rounds: int) -> void:
	item = kind
	ammo = rounds
	# A fresh pickup is ready to fire: the previous item's cooldown must not leak.
	item_cooldown = 0.0
	swing_clock = 0.0
	swing_total = 0.0

## Full body box used by projectiles: a shot that grazes the head, the guitar
## arm or a boot still counts as a hit.
func body_rect() -> Rect2:
	return Rect2(position.x - 16.0, position.y - 104.0, 32.0, 106.0)

## Local item offset to world space, mirrored by facing.
func item_point(offset: Vector2) -> Vector2:
	return position + Vector2(offset.x * float(facing), offset.y)

## World position of the barrel / cake release point. Derived from the same grip
## and icon size the sprite uses, so shots leave the muzzle instead of the chest.
func muzzle_point() -> Vector2:
	var config: Dictionary = Items.config(item)
	if config.is_empty():
		return position
	var hand: Vector2 = config.get("hand", Vector2(8.0, -56.0))
	var art: Vector2 = ItemArt.size_for(item)
	var facing_f := float(facing)
	var reach := art.x * GEAR_SCALE * 0.5 + 2.0
	var barrel := Vector2(facing_f * reach, 0.0).rotated(
		float(config.get("tilt", 0.0)) * facing_f)
	return position + Vector2(hand.x * facing_f, hand.y) + barrel

## Stage hazard damage: percent goes up, but there is no hitstun or knockback,
## so the player can still walk out of the fire.
func take_hazard_damage(amount: float) -> void:
	if amount <= 0.0 or invuln > 0.0 or not alive:
		return
	damage_percent = minf(999.0, damage_percent + amount)
	hp = maxf(0.0, hp - amount)

## Heart pickup: returns how much was actually restored.
func heal(amount: float) -> float:
	if not alive or amount <= 0.0:
		return 0.0
	var before := hp
	hp = minf(MAX_HP, hp + amount)
	return hp - before

## Visual-only swing so a melee item reads differently from a punch.
func play_item_swing(duration: float = 0.22) -> void:
	swing_clock = maxf(swing_clock, duration)
	swing_total = maxf(swing_total, duration)


## What the last frame drew, so the host can replay it on the guests.
func crouching_now() -> bool:
	return crouch_pose


func swinging() -> bool:
	return swing_clock > 0.0

## Returns false when the item cannot fire right now.
func consume_ammo() -> bool:
	if item == "" or ammo <= 0 or item_cooldown > 0.0:
		return false
	ammo -= 1
	item_cooldown = float(Items.config(item).get("cooldown", 0.35))
	if ammo <= 0:
		item = ""
		ammo = 0
	return true

## Returns the launch speed applied, or 0 when the hit is ignored.
func take_hit(damage: float, kb_base: float, kb_scale: float, angle: float, from_facing: int) -> float:
	if invuln > 0.0 or not alive:
		return 0.0
	damage_percent = minf(999.0, damage_percent + damage)
	hp = maxf(0.0, hp - damage)
	var speed := Knockback.launch_speed(damage_percent, kb_base, kb_scale)
	vel = Knockback.launch_velocity(speed, angle, from_facing)
	hitstun = Knockback.hitstun_for(speed)
	attack = ""
	attack_clock = 0.0
	hit_done = false
	on_ground = false
	jumps_left = 0
	combo += 1
	combo_clock = 1.0
	struck.emit(damage)
	return speed

func _update_visuals(command: Dictionary) -> void:
	if _hp_fill != null:
		var ratio := clampf(hp / MAX_HP, 0.0, 1.0)
		_hp_fill.size = Vector2(50.0 * ratio, 5.0)
		_hp_fill.color = Color(0.45, 0.9, 0.5).lerp(Color(0.95, 0.25, 0.30), 1.0 - ratio)
		var faded := invuln > 0.0 and int(invuln * 18.0) % 2 == 0
		_hp_bar.visible = not faded
		_hp_fill.visible = not faded
	if _sprite == null:
		return
	# Respawn / blast-zone invulnerability reads as a fast blink, the usual
	# platform-fighter cue that hits cannot connect yet.
	_sprite.modulate.a = 0.25 if invuln > 0.0 and int(invuln * 18.0) % 2 == 0 else 1.0
	var move := float(command.get("move", 0))
	# Standing on a conveyor counts as walking even without input.
	var drift := vel.x + (ground_push if on_ground else 0.0)
	var clip := "idle"
	crouch_pose = on_ground and bool(command.get("crouch", false)) and attack == ""
	if hitstun > 0.0:
		clip = "hurt-air" if not on_ground else "hurt"
	elif attack != "":
		clip = String(ATTACK_CLIP.get(attack, "attack-light"))
	elif swing_clock > 0.0:
		clip = "item-swing"
	elif not on_ground:
		clip = "jump" if vel.y < 0.0 else "jump-fall"
	elif land_clock > 0.0:
		clip = "land"
	elif crouch_pose:
		clip = "crouch"
	elif _sprite.sprite_frames.has_animation("item-hold") and item != "" and absf(move) <= 0.1:
		clip = "item-hold"
	elif absf(move) > 0.1 or (on_ground and absf(drift) > 40.0):
		clip = "walk" if (move if absf(move) > 0.1 else drift) * float(facing) > 0.0 else "walk-back"
	if absf(move) > 0.1 and hitstun <= 0.0:
		facing = 1 if move > 0.0 else -1
	if absf(vel.x) > 1.0 and hitstun <= 0.0:
		facing = 1 if vel.x > 0.0 else -1
	_sprite.flip_h = facing < 0
	if _gear != null:
		var icon: AtlasTexture = ItemArt.texture_for(item) if item != "" else null
		_gear.visible = icon != null
		if icon != null:
			var config: Dictionary = Items.config(item)
			var hold := String(config.get("hold", "gun"))
			var hand: Vector2 = config.get("hand", Vector2(8.0, -56.0))
			var art: Vector2 = ItemArt.size_for(item)
			var gear_scale := GEAR_SCALE * (1.0 + 0.28 * charge_ratio)
			var angle := 0.0
			var lift := Vector2.ZERO
			match hold:
				"melee":
					if swing_clock > 0.0 and swing_total > 0.0:
						# Sweep down through the arc while the slash effect plays.
						var progress := clampf(1.0 - swing_clock / swing_total, 0.0, 1.0)
						# The icon stands upright, so it is laid over the shoulder and
						# swept forward through the arc.
						angle = lerpf(1.45, 0.05, ease(progress, 2.0))
					else:
						angle = 0.78
				"throw":
					# Raising the cake over the head reads as a wind-up.
					lift = Vector2(0.0, -10.0 * charge_ratio)
					angle = -0.9 * charge_ratio
			# The icon is centred on the hand so it reads as gripped, and the
			# muzzle then sits at its far edge (see muzzle_point()).
			_gear.texture = icon
			_gear.scale = Vector2(float(facing) * gear_scale, gear_scale)
			_gear.rotation = (angle + float(config.get("tilt", 0.0))) * float(facing)
			_gear.position = Vector2(hand.x * float(facing), hand.y) + lift
	if _gear_block != null:
		_gear_block.visible = item != ""
		if item != "":
			var config: Dictionary = Items.config(item)
			var gear_size: Vector2 = config["size"] * 0.8 * (1.0 + 0.7 * charge_ratio)
			_gear_block.color = config["color"]
			_gear_block.size = gear_size
			_gear_block.position = Vector2(float(facing) * 18.0 - gear_size.x * 0.5, -54.0)
	# Art may only cover a few states while it is being generated: fall back to
	# idle instead of asking for a missing animation.
	if not _sprite.sprite_frames.has_animation(clip):
		clip = "idle"
	# Walk frames slide when the cycle speed does not match ground speed, so the
	# cycle is scaled with the actual velocity.
	if clip == "walk" or clip == "walk-back":
		_sprite.speed_scale = clampf(absf(drift) / RUN_SPEED, 0.6, 1.4)
	else:
		_sprite.speed_scale = 1.0
	if _sprite.sprite_frames.has_animation(clip) and _sprite.animation != clip:
		_sprite.play(clip)

func render_sync() -> void:
	position = position.round()












