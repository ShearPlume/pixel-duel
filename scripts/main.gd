extends Node2D
## M0 skeleton: 640x360 pixel canvas + a fixed 60 Hz logic step + local 2P input.
## Rendering only mirrors logic state, so later combat code stays deterministic.

const Fighter = preload("res://scripts/fighter.gd")
const HitResolve = preload("res://scripts/hit_resolve.gd")

const SFX := {
	"hit_light": preload("res://art/audio/hit_light.wav"),
	"hit_heavy": preload("res://art/audio/hit_heavy.wav"),
	"hurt": preload("res://art/audio/hit_heavy.wav"),
	"whiff": preload("res://art/audio/guitar_swing.wav"),
	"jump": preload("res://art/audio/jump.wav"),
	"land": preload("res://art/audio/land.wav"),
}
const SFX_GAIN := {"hurt": -7.0, "whiff": -6.0, "jump": -8.0, "land": -5.0}
const SFX_VOICES := 8

const ARENA_WIDTH := 640.0
const ARENA_HEIGHT := 360.0
const GROUND_Y := 300.0
const LEFT_WALL := 0.0
const RIGHT_WALL := 640.0
const FIXED_HZ := 60
const FIXED_DT := 1.0 / float(FIXED_HZ)
## Avoid a spiral of death after a hitch; drop time instead of stalling.
const MAX_STEPS_PER_FRAME := 5

const PROJECTILE_SPEED := 300.0
const PROJECTILE_LIFE := 1.0
const PROJECTILE_HEIGHT := 52.0
const PROJECTILE_HALF_W := 8.0
const PROJECTILE_HALF_H := 46.0

var player1: Node2D
var player2: Node2D
var debug_label: Label
var projectiles: Array = []

var accumulator := 0.0
var ticks := 0
var fps := 0.0

var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_cursor := 0
var _was_grounded := [true, true]
var _last_attack := ["", ""]
var _bars: Array = []
var _fills: Array = []

func _ready() -> void:
	_build_stage()
	_build_actors()
	_build_hud()
	_build_audio()

func _build_stage() -> void:
	var sky := ColorRect.new()
	sky.color = Color("0b0913")
	sky.size = Vector2(ARENA_WIDTH, ARENA_HEIGHT)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sky)

	var floor_band := ColorRect.new()
	floor_band.color = Color("241a33")
	floor_band.position = Vector2(0.0, GROUND_Y)
	floor_band.size = Vector2(ARENA_WIDTH, ARENA_HEIGHT - GROUND_Y)
	floor_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(floor_band)

	var line := ColorRect.new()
	line.color = Color("4a365d")
	line.position = Vector2(0.0, GROUND_Y)
	line.size = Vector2(ARENA_WIDTH, 2.0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(line)

func _build_actors() -> void:
	player1 = Fighter.new()
	player1.attack_prefix = "p1_"
	player1.facing = 1
	add_child(player1)
	player1.place(240.0, GROUND_Y)

	player2 = Fighter.new()
	player2.attack_prefix = "p2_"
	player2.facing = -1
	player2.tint = Color("ffb365")
	add_child(player2)
	player2.place(400.0, GROUND_Y)

func _build_hud() -> void:
	debug_label = Label.new()
	debug_label.position = Vector2(8.0, 6.0)
	debug_label.add_theme_font_size_override("font_size", 9)
	debug_label.add_theme_color_override("font_color", Color("9d8fb0"))
	debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(debug_label)
	for index in range(2):
		var background := ColorRect.new()
		background.color = Color("30273c")
		background.position = Vector2(8.0 if index == 0 else 512.0, 338.0)
		background.size = Vector2(120.0, 6.0)
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(background)
		var fill := ColorRect.new()
		fill.color = player1.tint if index == 0 else player2.tint
		fill.position = background.position
		fill.size = Vector2(120.0, 6.0)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(fill)
		_bars.append(background)
		_fills.append(fill)

func _build_audio() -> void:
	for index in range(SFX_VOICES):
		var player := AudioStreamPlayer.new()
		add_child(player)
		_sfx_players.append(player)

func _process(delta: float) -> void:
	accumulator += minf(delta, FIXED_DT * float(MAX_STEPS_PER_FRAME))
	while accumulator >= FIXED_DT:
		_step_fixed()
		accumulator -= FIXED_DT
	_render(delta)

func _step_fixed() -> void:
	ticks += 1
	player1.facing = 1 if player2.x >= player1.x else -1
	player2.facing = 1 if player1.x >= player2.x else -1
	_step_player(player1, "p1_")
	_step_player(player2, "p2_")
	_resolve_combat()
	_update_projectiles()

func _step_player(fighter: Node2D, prefix: String) -> void:
	var move := int(Input.get_axis(prefix + "left", prefix + "right"))
	fighter.step_fixed(
		FIXED_DT,
		move,
		Input.is_action_pressed(prefix + "jump"),
		Input.is_action_pressed(prefix + "crouch"),
		LEFT_WALL,
		RIGHT_WALL
	)

func _resolve_combat() -> void:
	var fighters := [player1, player2]
	for index in range(2):
		var attacker: Node2D = fighters[index]
		var target: Node2D = fighters[1 - index]
		var result := HitResolve.resolve(attacker, target)
		if not result.is_empty():
			_play_sfx("hit_heavy" if String(result.kind) in ["attack-heavy", "kick"] else "hit_light")
			_play_sfx("hurt")
			attacker.add_energy(Fighter.GAIN_HIT)
			target.add_energy(Fighter.GAIN_TAKEN)
		if attacker.wants_projectile:
			attacker.wants_projectile = false
			_spawn_projectile(index)
		_play_motion_cues(index, attacker)

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
	node.color = fighter.tint
	node.size = Vector2(12.0, 5.0)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(node)
	projectiles.append({
		"node": node,
		"x": fighter.x + float(fighter.facing) * 26.0,
		"y": GROUND_Y - fighter.height - PROJECTILE_HEIGHT,
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
		projectile.life -= FIXED_DT
		var node: ColorRect = projectile.node
		node.position = Vector2(projectile.x, projectile.y).round()
		var target: Node2D = fighters[1 - int(projectile.owner)]
		var vertical: float = GROUND_Y - float(target.height) - PROJECTILE_HEIGHT
		var hit: bool = absf(float(projectile.x) - float(target.x)) <= PROJECTILE_HALF_W + 14.0 \
			and absf(vertical - float(projectile.y)) <= PROJECTILE_HALF_H \
			and target.invuln_clock <= 0.0
		if hit:
			target.take_hit(4.0 * signf(float(projectile.vx)), 0.20, 0.0)
			target.combo = mini(target.combo + 1, HitResolve.MAX_COMBO)
			target.combo_clock = HitResolve.COMBO_WINDOW
			fighters[int(projectile.owner)].add_energy(Fighter.GAIN_HIT)
			target.add_energy(Fighter.GAIN_TAKEN)
			_play_sfx("hit_light")
			_play_sfx("hurt")
		if hit or projectile.life <= 0.0 or projectile.x < -20.0 or projectile.x > ARENA_WIDTH + 20.0:
			node.queue_free()
			continue
		remaining.append(projectile)
	projectiles = remaining

func _render(delta: float) -> void:
	player1.render_sync()
	player2.render_sync()
	for index in range(2):
		var fighter: Node2D = player1 if index == 0 else player2
		var width := 120.0 * clampf(fighter.energy / Fighter.MAX_ENERGY, 0.0, 1.0)
		var fill: ColorRect = _fills[index]
		fill.size = Vector2(width, 6.0)
		fill.position.x = 8.0 if index == 0 else 632.0 - width
	if delta > 0.0001:
		fps = lerpf(fps, 1.0 / delta, 0.1)
	debug_label.text = "FPS %d  fixed %d  tick %d\nP1 x%.0f h%.0f 气%.0f combo%d     P2 x%.0f h%.0f 气%.0f combo%d\nP1: WASD J普攻 K跳 L瞬步 U远攻 I放招 O灵替    P2: 方向键 小键盘1/2/3/4/5/6" % [
		roundi(fps), FIXED_HZ, ticks,
		player1.x, player1.height, player1.energy, player1.combo,
		player2.x, player2.height, player2.energy, player2.combo
	]

func _play_sfx(cue: String) -> void:
	if not SFX.has(cue):
		return
	var player: AudioStreamPlayer = null
	for candidate in _sfx_players:
		if not candidate.playing:
			player = candidate
			break
	if player == null:
		player = _sfx_players[_sfx_cursor % _sfx_players.size()]
		_sfx_cursor += 1
	player.stream = SFX[cue]
	player.volume_db = float(SFX_GAIN.get(cue, 0.0))
	player.play()

