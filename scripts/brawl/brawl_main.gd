extends Node2D
## Brawl mode: 2-5 brawlers on a multi-platform stage, percent damage, KO by
## leaving the blast zone, camera follows everyone and zooms out as they spread.

const Brawler = preload("res://scripts/brawl/brawler.gd")
const Stage = preload("res://scripts/brawl/stage_data.gd")
const BrawlHit = preload("res://scripts/brawl/brawl_hit.gd")
const Knockback = preload("res://scripts/brawl/knockback.gd")
const Pushbox = preload("res://scripts/brawl/pushbox.gd")
const Items = preload("res://scripts/brawl/items.gd")
const ItemArt = preload("res://scripts/brawl/item_art.gd")
const MatchConfig = preload("res://scripts/match_config.gd")
const ShotVisual = preload("res://scripts/brawl/shot_visual.gd")
const BurstEffect = preload("res://scripts/brawl/burst_effect.gd")
const SlashEffect = preload("res://scripts/brawl/slash_effect.gd")
const HeartPickup = preload("res://scripts/brawl/heart_pickup.gd")
const Sfx = preload("res://scripts/audio/sfx.gd")
const NetClient = preload("res://scripts/net/net_client.gd")
const TouchControls = preload("res://scripts/ui/touch_controls.gd")

const VIEW_W := 640.0
const VIEW_H := 360.0
## Item ids are internal; the HUD shows these instead.
const ITEM_NAMES := {
	"pistol": "玩具枪",
	"bat": "吉他",
	"grenade": "蛋糕", 
	"cannon": "泡泡炮",
}
const FIXED_HZ := 60
const FIXED_DT := 1.0 / float(FIXED_HZ)
const MAX_STEPS_PER_FRAME := 5
const RESPAWN_DELAY := 1.1
## Grenade charge: a tap lobs it short, a one second hold throws it far.
const CHARGE_START := 0.15
const CHARGE_FULL := 1.15
const HEART_INTERVAL := 7.0
## LAN button bits, mirrored in scripts/net/net_client and the lobby.
const NET_LEFT := 1
const NET_RIGHT := 2
const NET_JUMP := 4
const NET_ATTACK := 8
const NET_USE := 16
const NET_RELEASE := 32
const NET_CROUCH := 64
## 60 Hz simulation, 20 Hz snapshots.
const SNAPSHOT_EVERY := 2
const HEART_MAX := 2
const HEART_HEAL := 45.0
const ZOOM_MIN := 0.42
const ZOOM_MAX := 1.0

const COLORS := [
	Color("8ccff3"), Color("ffb365"), Color("a6e3a1"), Color("f5a7b6"), Color("c9a7ff"),
]
const CHARACTERS := ["res://art/yoru", "res://art/nayu", "res://art/hanami", "res://art/kana", "res://art/mosaki"]

var brawlers: Array = []
var player_count := 2
var selection := PackedStringArray()
var camera: Camera2D
var hud: Label
var status: Label
var _hud_text := ""

var accumulator := 0.0
var ticks := 0
var match_over := false
var _jump_latch: Array = []
var _attack_latch: Array = []
var _respawn: Array = []
var _item_latch: Array = []
var _crouch_latch: Array = []
var _charge: Array = []
var items: Array = []
var hearts: Array = []
var bullets: Array = []
var effects: Array = []
var spawn_clock := 3.0
var heart_clock := 5.0
var _sfx: Node
var _touch := false
## Touch builds reserve the bottom band for controls, so the camera and zoom fit
## the playfield above it instead of the whole window.
const TOUCH_BAND := 136.0
var _play_height := VIEW_H
var _bot_clock := 0.0
var _bot_attack_clock := 0.0
var _bot_move := 0.0
var _bot_jump := false
var _bot_attack := false
var _bot_item := false
var _background: Sprite2D = null
var _platform_texture: Texture2D = null
var _hazards: Array = []
var _conveyors: Array = []
var _bouncers: Array = []
var _clock := 0.0
## LAN session: role, own slot, remote button bits, latest snapshot.
var lan_role := ""
var lan_slot := 0
var _remote_bits := {}
var _remote_prev := {}
var _snapshot := {}
## Bullets a guest replays for itself: the host owns the hits, the guest only has
## to draw the same thing in the same place.
var _guest_bullets: Array = []
## End-of-match panel, parented to the window so it works on phones too (the
## match itself may run inside a SubViewport that does not take input).
var _end_layer: CanvasLayer = null
var _end_title: Label = null
var _lan_pickups: Array = []
var _lan_pickup_state := ""
var _result_reported := false
var net: Node = null

func _ready() -> void:
	_sfx = Sfx.new()
	add_child(_sfx)
	# Touch builds drive P1 from the on-screen stick and give P2 a simple CPU,
	# since a phone has only one player's worth of controls.
	if TouchControls.is_touch_device():
		_touch = true
		# Inside the handheld shell the controls live in their own bottom panel,
		# so the camera keeps the full viewport height.
		if not (get_parent() is SubViewport):
			_play_height = VIEW_H - TOUCH_BAND
			add_child(TouchControls.new())
	_build_stage()
	_build_camera()
	_build_hud()
	selection = MatchConfig.characters
	var count := selection.size() if selection.size() >= 2 else 2
	lan_role = MatchConfig.lan_role
	lan_slot = MatchConfig.lan_slot
	if MatchConfig.is_lan():
		count = clampi(MatchConfig.lan_players, 2, Stage.MAX_PLAYERS)
	spawn_players(count)
	if MatchConfig.is_lan():
		_setup_lan()

func spawn_players(count: int) -> void:
	player_count = clampi(count, 2, Stage.MAX_PLAYERS)
	for brawler: Node2D in brawlers:
		brawler.visible = false
		brawler.alive = false
	brawlers.clear()
	_jump_latch.clear()
	_attack_latch.clear()
	_respawn.clear()
	_item_latch.clear()
	_crouch_latch.clear()
	_charge.clear()
	for item: Dictionary in items:
		item.node.queue_free()
	items.clear()
	for heart: Dictionary in hearts:
		heart.node.queue_free()
	hearts.clear()
	heart_clock = 5.0
	for bullet: Dictionary in bullets:
		bullet.node.queue_free()
	bullets.clear()
	spawn_clock = 3.0
	for index in range(player_count):
		var brawler: Node2D = Brawler.new()
		brawler.player_index = index
		brawler.attack_prefix = "p%d_" % (index + 1)
		brawler.atlas_dir = selection[index] if index < selection.size() else CHARACTERS[index % CHARACTERS.size()]
		if String(brawler.atlas_dir).begins_with("res://art/placeholder"):
			brawler.tint = COLORS[index % COLORS.size()]
		brawler.stocks = Stage.STOCKS
		add_child(brawler)
		brawler.spawn(Stage.SPAWNS[index % Stage.SPAWNS.size()])
		brawler.facing = 1 if brawler.position.x < 0.0 else -1
		brawler.jumped.connect(_on_jumped.bind(brawler))
		brawler.landed.connect(_on_landed.bind(brawler))
		brawler.struck.connect(_on_struck.bind(brawler))
		brawlers.append(brawler)
		_jump_latch.append(false)
		_attack_latch.append(false)
		_respawn.append(0.0)
		_item_latch.append(false)
		_crouch_latch.append(false)
		_charge.append(0.0)
	match_over = false

func _build_stage() -> void:
	if Stage.BACKGROUND == "" or not ResourceLoader.exists(Stage.BACKGROUND):
		var sky := ColorRect.new()
		sky.color = Color("0b0913")
		sky.position = Vector2(-2000.0, -2000.0)
		sky.size = Vector2(4000.0, 4000.0)
		sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(sky)
	_build_background()
	if Stage.PLATFORM_IMAGE != "" and ResourceLoader.exists(Stage.PLATFORM_IMAGE):
		_platform_texture = load(Stage.PLATFORM_IMAGE)
	for index in range(Stage.PLATFORMS.size()):
		_build_platform(index, Stage.PLATFORMS[index])
	for index in range(Stage.HAZARDS.size()):
		_build_hazard(Stage.HAZARDS[index])
	for index in range(Stage.PLATFORMS.size()):
		match String(Stage.KINDS[index]):
			"conveyor":
				_build_conveyor(Stage.PLATFORMS[index], float(Stage.SPEEDS[index]))
			"bouncer":
				_build_bouncer(Stage.PLATFORMS[index])

func _build_background() -> void:
	if Stage.BACKGROUND == "" or not ResourceLoader.exists(Stage.BACKGROUND):
		return
	_background = Sprite2D.new()
	_background.texture = load(Stage.BACKGROUND)
	_background.z_index = -20
	add_child(_background)

## A ledge is a left cap, a repeated middle and a right cap, so a 200 px and a
## 1040 px platform share the same art instead of stretching it.
func _build_platform(index: int, platform: Rect2) -> void:
	if _platform_texture == null or Stage.PLATFORM_PIECES.size() < 3:
		var slab := ColorRect.new()
		slab.color = Color("3a2b4d")
		slab.position = platform.position
		slab.size = platform.size
		slab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(slab)
		var lip := ColorRect.new()
		lip.color = Color("6f4f8f")
		lip.position = platform.position
		lip.size = Vector2(platform.size.x, 2.0)
		lip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(lip)
		return
	var cap_left: Rect2 = Stage.PLATFORM_PIECES[0]
	var cap_right: Rect2 = Stage.PLATFORM_PIECES[2]
	var middle: Rect2 = Stage.PLATFORM_PIECES[1]
	var ratio := platform.size.y / maxf(1.0, cap_left.size.y)
	var cap_left_width := cap_left.size.x * ratio
	var cap_right_width := cap_right.size.x * ratio
	var middle_width := maxf(1.0, middle.size.x * ratio)
	var left := platform.position.x
	var right := platform.end.x
	_add_piece(cap_left, Vector2(left, platform.position.y), ratio)
	var cursor := left + cap_left_width
	var guard := 0
	while cursor < right - cap_right_width - 1.0 and guard < 400:
		var piece := middle
		var width := middle_width
		if cursor + width > right - cap_right_width:
			width = right - cap_right_width - cursor
			piece = Rect2(middle.position, Vector2(middle.size.x * width / middle_width, middle.size.y))
		_add_piece(piece, Vector2(cursor, platform.position.y), ratio)
		cursor += width
		guard += 1
	_add_piece(cap_right, Vector2(right - cap_right_width, platform.position.y), ratio)

func _add_piece(piece: Rect2, at: Vector2, ratio: float) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = _platform_texture
	sprite.region_enabled = true
	sprite.region_rect = piece
	sprite.centered = false
	sprite.scale = Vector2(ratio, ratio)
	sprite.position = at.round()
	add_child(sprite)

func _build_hazard(rect: Rect2) -> void:
	var node := ColorRect.new()
	node.color = Color(1.0, 0.24, 0.28, 0.30)
	node.position = rect.position
	node.size = rect.size
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(node)
	var warning := ColorRect.new()
	warning.color = Color(1.0, 0.85, 0.35, 0.75)
	warning.position = rect.position
	warning.size = Vector2(rect.size.x, 2.0)
	warning.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(warning)
	_hazards.append(node)

## Chevrons scroll along the belt so its direction reads at a glance.
func _build_conveyor(rect: Rect2, speed: float) -> void:
	var mark := Label.new()
	mark.text = ">>>" if speed > 0.0 else "<<<"
	mark.add_theme_font_size_override("font_size", 10)
	mark.add_theme_color_override("font_color", Color(0.55, 0.95, 1.0, 0.75))
	mark.position = Vector2(rect.position.x + 6.0, rect.position.y - 16.0)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(mark)
	_conveyors.append({"node": mark, "speed": speed, "left": rect.position.x,
		"width": rect.size.x})

func _build_bouncer(rect: Rect2) -> void:
	var pad := ColorRect.new()
	pad.color = Color(1.0, 0.72, 0.30, 0.95)
	pad.position = rect.position
	pad.size = rect.size
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pad)
	var lip := ColorRect.new()
	lip.color = Color(1.0, 0.95, 0.65)
	lip.position = rect.position
	lip.size = Vector2(rect.size.x, 3.0)
	lip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lip)
	_bouncers.append({"node": pad, "lip": lip, "height": rect.size.y})

func _build_camera() -> void:
	camera = Camera2D.new()
	camera.zoom = Vector2.ONE
	add_child(camera)
	camera.make_current()

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(8.0, 6.0)
	hud.add_theme_font_size_override("font_size", 11)
	hud.add_theme_color_override("font_color", Color("cfc3e0"))
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)
	status = Label.new()
	status.position = Vector2(8.0, 340.0)
	status.add_theme_font_size_override("font_size", 9)
	status.add_theme_color_override("font_color", Color("8f7fa8"))
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(status)

func _process(delta: float) -> void:
	accumulator += minf(delta, FIXED_DT * float(MAX_STEPS_PER_FRAME))
	while accumulator >= FIXED_DT:
		_step_fixed()
		accumulator -= FIXED_DT
	_update_camera(delta)
	_animate_stage(delta)
	_update_hud()

## Stage gimmicks need motion to read: hazard vents throb, belts scroll their
## chevrons, bounce pads breathe.
func _animate_stage(delta: float) -> void:
	_clock += delta
	for node: ColorRect in _hazards:
		node.color.a = 0.22 + 0.10 * absf(sin(_clock * 5.0))
	for belt: Dictionary in _conveyors:
		var mark: Label = belt.node
		var span := float(belt.width) - 26.0
		var travel := fposmod(_clock * absf(float(belt.speed)) * 0.4, span)
		mark.position.x = float(belt.left) + 6.0 + (travel if float(belt.speed) > 0.0 else span - travel)
	for pad: Dictionary in _bouncers:
		var glow := 0.65 + 0.35 * absf(sin(_clock * 4.0))
		(pad["node"] as ColorRect).color.a = glow
		(pad["lip"] as ColorRect).color.a = glow

func _step_fixed() -> void:
	ticks += 1
	# Guests do not simulate anything: they forward their input and replay the
	# host's snapshots.
	if lan_role == "guest":
		_guest_tick()
		return
	if not match_over:
		for index in range(brawlers.size()):
			var brawler: Node2D = brawlers[index]
			if not brawler.alive:
				_tick_respawn(index, brawler)
				continue
			var command: Dictionary = _command(index)
			_apply_gimmicks(brawler)
			brawler.step(FIXED_DT, command, Stage.PLATFORMS)
			_bounce(brawler)
			_update_item_charge(index, brawler, command)
		_separate_bodies()
		_update_items()
		_update_hearts()
		_update_bullets()
		_resolve_hits()
		_check_blast_zones()
		_check_match_end()
	else:
		for brawler: Node2D in brawlers:
			if brawler.alive:
				brawler.step(FIXED_DT, {}, Stage.PLATFORMS)
	if lan_role == "host" and net != null and ticks % SNAPSHOT_EVERY == 0:
		_send_snapshot()

## Keep every screen identical: whatever the host spawns or plays is mirrored
## to the guests, which replay it without simulating damage.
func _send_fx(event: Dictionary) -> void:
	if lan_role != "host" or net == null:
		return
	event["t"] = "fx"
	net.send_data(event)


func _play_sfx(key: String, at: Vector2) -> void:
	_sfx.play(key, at)
	_send_fx({"k": "sfx", "n": key, "x": at.x, "y": at.y})


func _apply_fx(event: Dictionary) -> void:
	if lan_role != "guest":
		return
	var at := Vector2(float(event.get("x", 0.0)), float(event.get("y", 0.0)))
	match String(event.get("k", "")):
		"sfx":
			_sfx.play(String(event.get("n", "")), at)
		"slash":
			var slash := SlashEffect.new()
			slash.radius = float(event.get("r", 86.0))
			slash.inner = float(event.get("i", 22.0))
			slash.facing = int(event.get("f", 1))
			slash.total = float(event.get("d", 0.2))
			slash.color = Color(String(event.get("c", "efe4ff")))
			slash.position = at
			add_child(slash)
		"burst":
			var burst := BurstEffect.new()
			burst.color = Color(String(event.get("c", "ffd166")))
			burst.radius = float(event.get("r", 60.0))
			burst.total = float(event.get("d", 0.24))
			burst.filled = bool(event.get("fl", true))
			burst.position = at
			add_child(burst)
		"shot":
			var node := ShotVisual.new()
			node.kind = String(event.get("s", "bullet"))
			node.radius = float(event.get("r", 4.0))
			node.hue = Color(String(event.get("c", "ffe066")))
			node.position = at
			add_child(node)
			_guest_bullets.append({
				"node": node,
				"x": at.x,
				"y": at.y,
				"vx": float(event.get("vx", 0.0)),
				"vy": float(event.get("vy", 0.0)),
				"g": float(event.get("g", 0.0)),
				"b": float(event.get("b", 0.0)),
				"w": float(event.get("w", 0.0)),
				"wr": float(event.get("wr", 6.0)),
				"life": float(event.get("l", 1.1)),
				"age": 0.0,
			})
		_:
			pass


## Guest-side bullet motion, mirroring the host's step so the pictures match.
func _update_guest_bullets() -> void:
	for shot: Dictionary in _guest_bullets.duplicate():
		shot.life = float(shot.life) - FIXED_DT
		shot.age = float(shot.age) + FIXED_DT
		var previous_y := float(shot.y)
		shot.vy = float(shot.vy) + float(shot.g) * FIXED_DT
		shot.x = float(shot.x) + float(shot.vx) * FIXED_DT
		shot.y = float(shot.y) + float(shot.vy) * FIXED_DT
		if float(shot.w) != 0.0:
			shot.y = float(shot.y) + sin(float(shot.age) * float(shot.wr)) * float(shot.w) * FIXED_DT
		if float(shot.b) > 0.0 and float(shot.vy) >= 0.0:
			for platform: Rect2 in Stage.PLATFORMS:
				if float(shot.x) < platform.position.x - 6.0 or float(shot.x) > platform.end.x + 6.0:
					continue
				if previous_y <= platform.position.y and float(shot.y) >= platform.position.y:
					shot.y = platform.position.y - 5.0
					shot.vy = -absf(float(shot.vy)) * float(shot.b)
		var node: Node2D = shot["node"]
		node.position = Vector2(float(shot.x), float(shot.y)).round()
		if float(shot.life) <= 0.0 or float(shot.y) > 420.0:
			node.queue_free()
			_guest_bullets.erase(shot)


func _setup_lan() -> void:
	net = MatchConfig.net
	if net == null:
		push_warning("LAN match without a socket, falling back to local play")
		return
	net.data_received.connect(_on_net_data)
	net.peer_left.connect(_on_lan_peer_left)
	net.closed.connect(_on_lan_closed)
	_snapshot = {}

func _on_net_data(from_slot: int, payload: Dictionary) -> void:
	match String(payload.get("t", "")):
		"in":
			if lan_role == "host":
				_remote_bits[from_slot] = int(payload.get("b", 0))
		"s":
			if lan_role == "guest":
				_snapshot = payload
		"fx":
			_apply_fx(payload)
		"rematch":
			if lan_role == "guest":
				_hide_end_panel()
				get_tree().reload_current_scene()
		"rematch_req":
			if lan_role == "host":
				_rematch()
		_:
			pass

func _on_lan_peer_left(_reason: String) -> void:
	status.text = "有玩家离开了房间"

func _on_lan_closed(reason: String) -> void:
	status.text = "连接断开：%s（按 F5 返回房间）" % reason


## Own input as a bit field. Touch controls and the keyboard both land on p1_,
## so every device reads its local player the same way.
func _local_bits() -> int:
	var prefix := "p1_"
	var bits := 0
	if Input.is_action_pressed(prefix + "left"):
		bits |= NET_LEFT
	if Input.is_action_pressed(prefix + "right"):
		bits |= NET_RIGHT
	if Input.is_action_pressed(prefix + "jump"):
		bits |= NET_JUMP
	if Input.is_action_pressed(prefix + "light"):
		bits |= NET_ATTACK
	var use := Input.is_action_pressed(prefix + "ranged")
	if use:
		bits |= NET_USE
	elif bool(_item_latch[lan_slot] if lan_slot < _item_latch.size() else false):
		bits |= NET_RELEASE
	if Input.is_action_pressed(prefix + "crouch"):
		bits |= NET_CROUCH
	return bits


## Host side: turn a guest's bit field into a command, with edge detection so
## "pressed this tick" stays a one-shot like the local latches.
func _remote_command(index: int) -> Dictionary:
	var bits := int(_remote_bits.get(index, 0))
	var previous := int(_remote_prev.get(index, 0))
	_remote_prev[index] = bits
	return {
		"move": int(bool(bits & NET_RIGHT)) - int(bool(bits & NET_LEFT)),
		"jump": bool(bits & NET_JUMP) and not bool(previous & NET_JUMP),
		"attack": bool(bits & NET_ATTACK) and not bool(previous & NET_ATTACK),
		"use_item": bool(bits & NET_USE) and not bool(previous & NET_USE),
		"item_release": bool(bits & NET_RELEASE),
		"crouch": bool(bits & NET_CROUCH),
		"crouch_press": bool(bits & NET_CROUCH) and not bool(previous & NET_CROUCH),
	}


func _send_snapshot() -> void:
	var players: Array = []
	for index in range(brawlers.size()):
		var brawler: Node2D = brawlers[index]
		players.append([
			index,
			snappedf(brawler.position.x, 0.1), snappedf(brawler.position.y, 0.1),
			snappedf(brawler.vel.x, 1.0), snappedf(brawler.vel.y, 1.0),
			int(brawler.facing), 1 if brawler.on_ground else 0,
			snappedf(brawler.hp, 0.5), brawler.stocks, 1 if brawler.alive else 0,
			String(brawler.attack), String(brawler.item),
			1 if brawler.hitstun > 0.0 else 0, 1 if brawler.invuln > 0.0 else 0,
			1 if brawler.crouching_now() else 0, 1 if brawler.swinging() else 0,
		])
	var pickups: Array = []
	for pickup: Dictionary in items:
		var at: Vector2 = pickup.position
		pickups.append([String(pickup.kind), snappedf(at.x, 0.1), snappedf(at.y, 0.1)])
	net.send_data({"t": "s", "p": players, "i": pickups, "o": match_over})


func _guest_tick() -> void:
	if net != null:
		net.send_data({"t": "in", "b": _local_bits()})
		if lan_slot < _item_latch.size():
			_item_latch[lan_slot] = Input.is_action_pressed("p1_ranged")
	# Predict the local fighter so the input response is immediate; the host's
	# snapshot then pulls it back into sync.
	_predict_local()
	_apply_snapshot()
	_update_guest_bullets()


## Guests run only their own fighter; everything else comes from snapshots.
func _predict_local() -> void:
	if lan_slot < 0 or lan_slot >= brawlers.size():
		return
	var brawler: Node2D = brawlers[lan_slot]
	if not brawler.alive:
		return
	var command: Dictionary = _command(lan_slot)
	_apply_gimmicks(brawler)
	brawler.step(FIXED_DT, command, Stage.PLATFORMS)
	_bounce(brawler)


func _apply_snapshot() -> void:
	if _snapshot.is_empty():
		return
	var blend := clampf(FIXED_DT * 14.0, 0.0, 1.0)
	for entry: Array in _snapshot.get("p", []):
		var index := int(entry[0])
		if index < 0 or index >= brawlers.size():
			continue
		var brawler: Node2D = brawlers[index]
		var target := Vector2(float(entry[1]), float(entry[2]))
		if index == lan_slot:
			# Running locally: only correct the drift, keep the predicted velocity.
			if brawler.position.distance_to(target) > 70.0:
				brawler.position = target
			else:
				brawler.position += (target - brawler.position) * 0.10
		else:
			brawler.position = brawler.position.lerp(target, blend)
			brawler.vel = Vector2(float(entry[3]), float(entry[4]))
		brawler.facing = int(entry[5])
		brawler.on_ground = bool(entry[6])
		brawler.hp = float(entry[7])
		brawler.stocks = int(entry[8])
		var alive := bool(entry[9])
		brawler.alive = alive
		brawler.visible = alive
		brawler.attack = String(entry[10])
		brawler.item = String(entry[11])
		brawler.hitstun = 1.0 if bool(entry[12]) else 0.0
		brawler.invuln = 1.0 if bool(entry[13]) else 0.0
		var crouching := entry.size() > 14 and bool(entry[14])
		if entry.size() > 15 and bool(entry[15]):
			brawler.swing_clock = maxf(brawler.swing_clock, 0.12)
			brawler.swing_total = maxf(brawler.swing_total, 0.22)
		brawler._update_visuals({"crouch": crouching})
	match_over = bool(_snapshot.get("o", false))
	_sync_lan_pickups(_snapshot.get("i", []))


## Rebuild the guest's view of the field items only when it actually changes.
func _sync_lan_pickups(entries: Array) -> void:
	var key := ""
	for entry: Array in entries:
		key += "%s:%d:%d;" % [String(entry[0]), int(float(entry[1])), int(float(entry[2]))]
	if key == _lan_pickup_state:
		return
	_lan_pickup_state = key
	for node: Node in _lan_pickups:
		node.queue_free()
	_lan_pickups.clear()
	for entry: Array in entries:
		var kind := String(entry[0])
		var icon: AtlasTexture = ItemArt.texture_for(kind)
		if icon == null:
			continue
		var sprite := Sprite2D.new()
		sprite.texture = icon
		sprite.scale = Vector2(0.62, 0.62)
		sprite.position = Vector2(float(entry[1]), float(entry[2]))
		add_child(sprite)
		_lan_pickups.append(sprite)

## Conveyor drag and hazard burn, both looked up from the stage layout.
func _apply_gimmicks(brawler: Node2D) -> void:
	var support := -1
	if brawler.on_ground:
		support = Stage.support_index(brawler.position.x, brawler.position.y)
	brawler.ground_push = Stage.conveyor_speed(support)
	var dps := Stage.hazard_dps(Vector2(brawler.position.x, brawler.position.y - 12.0))
	if dps > 0.0:
		brawler.take_hazard_damage(dps * FIXED_DT)

## A bouncer fires as soon as a fighter lands on it.
func _bounce(brawler: Node2D) -> void:
	if not brawler.on_ground:
		return
	var power := Stage.bounce_power(Stage.support_index(brawler.position.x, brawler.position.y))
	if power <= 0.0:
		return
	brawler.vel.y = -power
	brawler.on_ground = false
	brawler.ground_soft = false

func _command(index: int) -> Dictionary:
	if lan_role == "host" and index != lan_slot:
		return _remote_command(index)
	if _touch and not MatchConfig.is_lan() and index > 0:
		return _bot_command(index)
	var prefix := "p%d_" % (index + 1)
	# Every device drives its own slot with p1_*, whatever slot number it got.
	if MatchConfig.is_lan() and index == lan_slot:
		prefix = "p1_"
	var jump_down := Input.is_action_pressed(prefix + "jump")
	var attack_down := Input.is_action_pressed(prefix + "light")
	var item_down := Input.is_action_pressed(prefix + "ranged")
	var crouch_down := Input.is_action_pressed(prefix + "crouch")
	var command := {
		"move": int(Input.get_axis(prefix + "left", prefix + "right")),
		"jump": jump_down and not bool(_jump_latch[index]),
		"attack": attack_down and not bool(_attack_latch[index]),
		"use_item": item_down and not bool(_item_latch[index]),
		"item_release": not item_down and bool(_item_latch[index]),
		"crouch": crouch_down,
		"crouch_press": crouch_down and not bool(_crouch_latch[index]),
	}
	_jump_latch[index] = jump_down
	_attack_latch[index] = attack_down
	_item_latch[index] = item_down
	_crouch_latch[index] = crouch_down
	return command

## Sound hooks: one handler per brawler signal, all positional.
func _on_jumped(double_jump: bool, brawler: Node2D) -> void:
	_play_sfx("jump_double" if double_jump else "jump", brawler.position)

func _on_landed(brawler: Node2D) -> void:
	_play_sfx("land", brawler.position)

func _on_struck(damage: float, brawler: Node2D) -> void:
	_play_sfx("hit_heavy" if damage >= 10.0 else "hit_light", brawler.body_rect().get_center())


## Minimal opponent for touch play: close the gap, jump when the target is
## above, swing in range, throw an item now and then. Deliberately simple -
## it exists so a phone match has someone to fight, not to be a real AI.
func _bot_command(index: int) -> Dictionary:
	_bot_clock = maxf(0.0, _bot_clock - FIXED_DT)
	_bot_attack_clock = maxf(0.0, _bot_attack_clock - FIXED_DT)
	var brawler: Node2D = brawlers[index]
	var target: Node2D = _nearest_target(index, brawler.position)
	if target == null:
		return {}
	var dx: float = target.position.x - brawler.position.x
	var dy: float = target.position.y - brawler.position.y
	var reach := 62.0
	var move := 0.0
	if absf(dx) > reach:
		move = signf(dx)
	var jump: bool = dy < -46.0 and brawler.on_ground
	var attack: bool = absf(dx) <= reach + 6.0 and absf(dy) < 90.0 and _bot_attack_clock <= 0.0
	if attack:
		_bot_attack_clock = randf_range(0.30, 0.48)
	var item: bool = brawler.item != "" and absf(dx) < 320.0 and randf() < 0.012
	if _bot_clock <= 0.0:
		_bot_clock = randf_range(0.18, 0.42)
		if randf() < 0.25:
			jump = true
	if brawler.facing != int(signf(dx)) and absf(dx) > 4.0:
		move = signf(dx)
	return {
		"move": int(move),
		"jump": jump,
		"attack": attack,
		"use_item": item,
		"item_release": false,
		"crouch": false,
		"crouch_press": false,
	}


func _separate_bodies() -> void:
	for i in range(brawlers.size()):
		for j in range(i + 1, brawlers.size()):
			var a: Node2D = brawlers[i]
			var b: Node2D = brawlers[j]
			if not a.alive or not b.alive:
				continue
			var corrected := Pushbox.separate(a.position.x, a.position.y, b.position.x, b.position.y)
			if corrected.is_empty():
				continue
			a.position.x = corrected[0]
			b.position.x = corrected[1]

func _update_items() -> void:
	if items.size() < Items.MAX_ON_FIELD:
		spawn_clock = maxf(0.0, spawn_clock - FIXED_DT)
		if spawn_clock <= 0.0:
			spawn_clock = Items.SPAWN_INTERVAL
			var platform: Rect2 = Stage.PLATFORMS[randi() % Stage.PLATFORMS.size()]
			var at := Vector2(
				randf_range(platform.position.x + 30.0, platform.end.x - 30.0),
				platform.position.y - 10.0
			)
			_spawn_item(String(Items.kinds().pick_random()), at)
	for item: Dictionary in items.duplicate():
		for index in range(brawlers.size()):
			var brawler: Node2D = brawlers[index]
			if not brawler.alive or brawler.item != "":
				continue
			if not Items.can_pick_up(String(item.kind), item.position.x, item.position.y,
					brawler.position.x, brawler.position.y - 30.0):
				continue
			brawler.give_item(String(item.kind), int(Items.config(String(item.kind))["rounds"]))
			_play_sfx("pickup", brawler.position)
			item.node.queue_free()
			items.erase(item)
			break

func _update_hearts() -> void:
	if hearts.size() < HEART_MAX:
		heart_clock = maxf(0.0, heart_clock - FIXED_DT)
		if heart_clock <= 0.0:
			heart_clock = HEART_INTERVAL
			_spawn_heart()
	for heart: Dictionary in hearts.duplicate():
		for index in range(brawlers.size()):
			var brawler: Node2D = brawlers[index]
			if not brawler.alive or brawler.hp >= brawler.MAX_HP:
				continue
			var centre: Vector2 = brawler.body_rect().get_center()
			if centre.distance_to(heart.position) > 46.0:
				continue
			brawler.heal(HEART_HEAL)
			_play_sfx("heart", heart.position)
			_burst(heart.position, Color("ff6f91"), 26.0, 0.22)
			heart.node.queue_free()
			hearts.erase(heart)
			break


func _spawn_heart() -> void:
	var spots: Array = []
	for platform: Rect2 in Stage.PLATFORMS:
		if Stage.hazard_dps(Vector2(platform.position.x + platform.size.x * 0.5, platform.position.y - 12.0)) > 0.0:
			continue
		if platform.size.x < 90.0:
			continue
		spots.append(platform)
	if spots.is_empty():
		return
	var platform: Rect2 = spots.pick_random()
	var at := Vector2(
		randf_range(platform.position.x + 34.0, platform.end.x - 34.0),
		platform.position.y - 26.0)
	var node := HeartPickup.new()
	node.position = at
	add_child(node)
	hearts.append({"position": at, "node": node})


func _spawn_item(kind: String, at: Vector2) -> void:
	var config: Dictionary = Items.config(kind)
	var icon: AtlasTexture = ItemArt.texture_for(kind)
	if icon != null:
		var sprite := Sprite2D.new()
		sprite.texture = icon
		sprite.scale = Vector2(0.62, 0.62)
		sprite.position = at
		add_child(sprite)
		items.append({"kind": kind, "position": at, "node": sprite})
		return
	var node := ColorRect.new()
	node.color = config["color"]
	node.size = config["size"]
	node.position = (at - (config["size"] as Vector2) * 0.5).round()
	add_child(node)
	items.append({"kind": kind, "position": at, "node": node})

## Grenades wind up while the item key is held: holding throws further, tapping
## is the short lob. Every other item fires on press.
func _update_item_charge(index: int, brawler: Node2D, command: Dictionary) -> void:
	var kind := String(brawler.item)
	if bool(command.get("use_item", false)) and kind == "grenade":
		_charge[index] = CHARGE_START
	elif bool(command.get("use_item", false)):
		_use_item(index)
	if float(_charge[index]) > 0.0 and kind == "grenade":
		_charge[index] = minf(CHARGE_FULL, float(_charge[index]) + FIXED_DT)
		brawler.charge_ratio = float(_charge[index]) / CHARGE_FULL
	if bool(command.get("item_release", false)) and float(_charge[index]) > 0.0:
		var ratio := float(_charge[index]) / CHARGE_FULL
		_charge[index] = 0.0
		brawler.charge_ratio = 0.0
		if kind == "grenade" and brawler.consume_ammo():
			_throw_grenade(index, Items.config("grenade"), ratio)
	if kind != "grenade":
		_charge[index] = 0.0
		brawler.charge_ratio = 0.0

func _use_item(index: int) -> void:
	var brawler: Node2D = brawlers[index]
	var kind: String = String(brawler.item)
	if kind == "" or not Items.has_item(kind):
		return
	var config: Dictionary = Items.config(kind)
	if not brawler.consume_ammo():
		return
	match String(config["type"]):
		"melee":
			_melee_swing(index, config)
			_play_sfx("guitar_swing", brawler.position)
		"grenade":
			_throw_grenade(index, config)
			_play_sfx("cake_throw", brawler.muzzle_point())
		"homing":
			_spawn_shot(index, config, "homing")
			_play_sfx("bubble_fire", brawler.muzzle_point())
		_:
			_spawn_shot(index, config, "projectile")
			_play_sfx("pistol", brawler.muzzle_point())

func _melee_swing(index: int, config: Dictionary) -> void:
	var brawler: Node2D = brawlers[index]
	var facing := int(brawler.facing)
	var duration := float(config.get("slash_total", 0.20))
	brawler.play_item_swing(duration)
	var slash := SlashEffect.new()
	slash.radius = float(config["reach"])
	slash.inner = float(config.get("slash_inner", 20.0))
	slash.facing = facing
	slash.color = config["color"]
	slash.total = duration
	slash.position = brawler.position + Vector2(0.0, -52.0)
	add_child(slash)
	_send_fx({"k": "slash", "x": slash.position.x, "y": slash.position.y,
		"r": slash.radius, "i": slash.inner, "f": slash.facing, "d": duration,
		"c": Color(slash.color).to_html()})
	# The swing sweeps a wide arc, so it hits everyone inside it, not just the
	# closest target.
	var zone := Rect2(
		brawler.position.x if facing > 0 else brawler.position.x - float(config["reach"]),
		brawler.position.y - float(config["height"]),
		float(config["reach"]), float(config["height"]) + 12.0)
	var sounded := false
	for other in range(brawlers.size()):
		if other == index:
			continue
		var target: Node2D = brawlers[other]
		if not target.alive:
			continue
		if not zone.intersects(target.body_rect()):
			continue
		target.take_hit(float(config["damage"]), float(config["kb_base"]),
			float(config["kb_scale"]), float(config["angle"]), facing)
		# The string chord sits on the first thing the guitar connects with,
		# while the cleave itself still hits everybody in the arc.
		if not sounded:
			_play_sfx("guitar_hit", target.body_rect().get_center())
			sounded = true

func _throw_grenade(index: int, config: Dictionary, ratio: float = 0.0) -> void:
	var brawler: Node2D = brawlers[index]
	var icon: AtlasTexture = ItemArt.texture_for("grenade")
	var node: CanvasItem
	if icon != null:
		var sprite := Sprite2D.new()
		sprite.texture = icon
		sprite.scale = Vector2(0.5, 0.5)
		node = sprite
	else:
		var block := ColorRect.new()
		block.color = config["color"]
		block.size = config["size"]
		node = block
	add_child(node)
	var from: Vector2 = brawler.muzzle_point()
	bullets.append({
		"type": "grenade",
		"node": node,
		"x": from.x,
		"y": from.y,
		"vx": float(brawler.facing) * float(config["speed"]) * (1.0 + 1.1 * ratio),
		"vy": float(config["throw_vy"]) * (1.0 + 0.5 * ratio),
		"owner": index,
		"config": config,
		"fuse": float(config["fuse"]),
	})

func _spawn_shot(index: int, config: Dictionary, type: String) -> void:
	var brawler: Node2D = brawlers[index]
	var from: Vector2 = brawler.muzzle_point()
	var node := ShotVisual.new()
	node.kind = String(config.get("shot", "bullet"))
	node.radius = float(config.get("shot_radius", 4.0))
	node.hue = config["color"]
	node.position = from
	add_child(node)
	_send_fx({"k": "shot", "x": from.x, "y": from.y,
		"vx": float(brawler.facing) * float(config["speed"]), "vy": 0.0,
		"s": node.kind, "r": node.radius, "c": Color(node.hue).to_html(),
		"g": float(config.get("gravity", 0.0)), "b": float(config.get("bounce", 0.0)),
		"w": float(config.get("wobble", 0.0)), "wr": float(config.get("wobble_rate", 6.0)),
		"l": float(config.get("life", 1.1))})
	_spawn_muzzle_flash(from, config)
	bullets.append({
		"type": type,
		"node": node,
		"x": from.x,
		"y": from.y,
		"vx": float(brawler.facing) * float(config["speed"]),
		"vy": 0.0,
		"owner": index,
		"config": config,
		"life": float(config.get("life", 1.1)),
		"age": 0.0,
	})

func _spawn_muzzle_flash(at: Vector2, config: Dictionary) -> void:
	_burst(at, config["color"], 13.0, 0.10, false)

func _update_bullets() -> void:
	for shot: Dictionary in bullets.duplicate():
		match String(shot.type):
			"grenade":
				_step_grenade(shot)
			"homing":
				_step_homing(shot)
			_:
				_step_straight(shot)
	for effect: Dictionary in effects.duplicate():
		effect.life -= FIXED_DT
		var node: ColorRect = effect.node
		node.modulate.a = clampf(float(effect.life) / float(effect.total), 0.0, 1.0)
		if float(effect.life) <= 0.0:
			node.queue_free()
			effects.erase(effect)

func _step_straight(shot: Dictionary) -> void:
	shot.x += float(shot.vx) * FIXED_DT
	shot.life -= FIXED_DT
	shot.node.position = Vector2(shot.x, shot.y).round()
	if _shot_contact(shot) or float(shot.life) <= 0.0:
		_remove_shot(shot)

func _step_homing(shot: Dictionary) -> void:
	var config: Dictionary = shot.config
	var target: Node2D = _nearest_target(int(shot.owner), Vector2(shot.x, shot.y))
	if target != null:
		var goal: Vector2 = target.body_rect().get_center()
		if goal.distance_to(Vector2(shot.x, shot.y)) > float(config.get("lock_range", 70.0)):
			var desired: Vector2 = (goal - Vector2(shot.x, shot.y)).normalized() * float(config["speed"])
			var current := Vector2(shot.vx, shot.vy)
			current = current.move_toward(desired, float(config["turn"]) * float(config["speed"]) * FIXED_DT)
			shot.vx = current.x
			shot.vy = current.y
	# Bubbles drift up and down so they read as light and floaty.
	var wobble := float(config.get("wobble", 0.0))
	if wobble != 0.0:
		shot.age = float(shot.get("age", 0.0)) + FIXED_DT
		shot.y += sin(float(shot.age) * float(config.get("wobble_rate", 6.0))) * wobble * FIXED_DT
	shot.x += float(shot.vx) * FIXED_DT
	shot.y += float(shot.vy) * FIXED_DT
	shot.life -= FIXED_DT
	shot.node.position = Vector2(shot.x, shot.y).round()
	if _shot_contact(shot):
		if String(config.get("shot", "bullet")) == "bubble":
			_pop_bubble(shot)
		_remove_shot(shot)
	elif float(shot.life) <= 0.0 or shot.y > 420.0 or shot.y < -1100.0:
		if String(config.get("shot", "bullet")) == "bubble":
			_pop_bubble(shot)
		_remove_shot(shot)

## A bubble bursts into a short splash instead of just vanishing.
func _pop_bubble(shot: Dictionary) -> void:
	var config: Dictionary = shot.config
	var radius := float(config.get("pop_radius", 54.0))
	var at := Vector2(float(shot.x), float(shot.y))
	_burst(at, config["color"], radius, 0.24)
	_play_sfx("bubble_pop", at)
	for index in range(brawlers.size()):
		if index == int(shot.owner):
			continue
		var target: Node2D = brawlers[index]
		if not target.alive:
			continue
		var delta: Vector2 = target.body_rect().get_center() - at
		var distance := delta.length()
		if distance > radius:
			continue
		var falloff := 1.0 - distance / radius
		target.take_hit(float(config.get("pop_damage", 6.0)) * (0.5 + 0.5 * falloff),
			float(config.get("pop_kb_base", 120.0)), float(config.get("pop_kb_scale", 2.6)),
			40.0, 1 if delta.x >= 0.0 else -1)

func _step_grenade(shot: Dictionary) -> void:
	var config: Dictionary = shot.config
	var previous_y := float(shot.y)
	shot.vy += float(config["gravity"]) * FIXED_DT
	shot.x += float(shot.vx) * FIXED_DT
	shot.y += float(shot.vy) * FIXED_DT
	shot.fuse -= FIXED_DT
	# A cake that lands on somebody blows up right away; otherwise it keeps
	# bouncing and fuses down as before.
	if bool(config.get("contact_explode", false)) and _shot_contact(shot, false):
		_explode(float(shot.x), float(shot.y), config, int(shot.owner))
		_remove_shot(shot)
		return
	# Bounce off platform tops instead of blowing up on the first touch.
	if float(shot.vy) >= 0.0:
		for platform: Rect2 in Stage.PLATFORMS:
			if float(shot.x) < platform.position.x - 6.0 or float(shot.x) > platform.end.x + 6.0:
				continue
			if previous_y <= platform.position.y and float(shot.y) >= platform.position.y:
				shot.y = platform.position.y - 5.0
				shot.vy = -absf(float(shot.vy)) * float(config["bounce"])
				shot.vx *= float(config["friction"])
				if absf(float(shot.vy)) < 70.0:
					shot.vy = 0.0
				break
	if float(shot.vy) == 0.0 and absf(float(shot.vx)) < 12.0:
		shot.vx = 0.0
	shot.node.position = Vector2(shot.x, shot.y).round()
	var remaining := float(shot.fuse)
	if remaining < 0.5 and int(remaining * 16.0) % 2 == 0:
		shot.node.modulate.a = 0.45
	else:
		shot.node.modulate.a = 1.0
	if remaining <= 0.0 or shot.y > 520.0:
		_explode(float(shot.x), float(shot.y), config, int(shot.owner))
		_remove_shot(shot)

func _explode(at_x: float, at_y: float, config: Dictionary, owner: int) -> void:
	var radius := float(config["radius"])
	_burst(Vector2(at_x, at_y), Color("ffd166"), radius, 0.30)
	_play_sfx("explosion", Vector2(at_x, at_y))
	for index in range(brawlers.size()):
		if index == owner:
			continue
		var target: Node2D = brawlers[index]
		if not target.alive:
			continue
		var delta: Vector2 = target.body_rect().get_center() - Vector2(at_x, at_y)
		var distance := delta.length()
		if distance > radius:
			continue
		var falloff := 1.0 - distance / radius
		target.take_hit(float(config["damage"]) * (0.55 + 0.45 * falloff), float(config["kb_base"]),
			float(config["kb_scale"]), float(config["angle"]), 1 if delta.x >= 0.0 else -1)

func _burst(at: Vector2, color: Color, radius: float, total: float, filled: bool = true) -> void:
	var burst := BurstEffect.new()
	burst.color = color
	burst.radius = radius
	burst.total = total
	burst.filled = filled
	burst.position = at
	add_child(burst)
	_send_fx({"k": "burst", "x": at.x, "y": at.y, "c": color.to_html(), "r": radius,
		"d": total, "fl": filled})

func _nearest_target(owner: int, from: Vector2) -> Node2D:
	var best: Node2D = null
	var best_distance := INF
	for index in range(brawlers.size()):
		if index == owner:
			continue
		var candidate: Node2D = brawlers[index]
		if not candidate.alive:
			continue
		var distance: float = from.distance_to(candidate.body_rect().get_center())
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best

## Point test against the whole silhouette: a shot that hits the head, the
## outstretched arm or a boot counts, not only the torso centre.
func _shot_contact(shot: Dictionary, damage: bool = true) -> bool:
	var config: Dictionary = shot.config
	var point := Vector2(float(shot.x), float(shot.y))
	var radius := float(config.get("shot_radius", 4.0))
	for index in range(brawlers.size()):
		if index == int(shot.owner):
			continue
		var target: Node2D = brawlers[index]
		if not target.alive:
			continue
		if not target.body_rect().grow(radius + 2.0).has_point(point):
			continue
		if not damage:
			return true
		target.take_hit(float(config["damage"]), float(config["kb_base"]),
			float(config["kb_scale"]), float(config["angle"]), 1 if float(shot.vx) > 0.0 else -1)
		return true
	return false

func _remove_shot(shot: Dictionary) -> void:
	shot.node.queue_free()
	bullets.erase(shot)

func _resolve_hits() -> void:
	for i in range(brawlers.size()):
		for j in range(brawlers.size()):
			if i == j:
				continue
			var attacker: Node2D = brawlers[i]
			var target: Node2D = brawlers[j]
			if not attacker.alive or not target.alive:
				continue
			BrawlHit.resolve(attacker, target)

func _check_blast_zones() -> void:
	for index in range(brawlers.size()):
		var brawler: Node2D = brawlers[index]
		if not brawler.alive:
			continue
		# Two ways to lose a stock: leave the blast zone, or run out of health.
		if not Knockback.outside_blast(brawler.position) and brawler.hp > 0.0:
			continue
		brawler.alive = false
		brawler.visible = false
		brawler.stocks -= 1
		_play_sfx("ko", brawler.position)
		_respawn[index] = RESPAWN_DELAY

func _tick_respawn(index: int, brawler: Node2D) -> void:
	if brawler.stocks <= 0:
		return
	_respawn[index] = maxf(0.0, float(_respawn[index]) - FIXED_DT)
	if float(_respawn[index]) <= 0.0:
		brawler.spawn(Stage.SPAWNS[index % Stage.SPAWNS.size()])
		_play_sfx("respawn", brawler.position)

func _check_match_end() -> void:
	var standing := 0
	for brawler: Node2D in brawlers:
		if brawler.stocks > 0:
			standing += 1
	if standing <= 1:
		if not match_over:
			_show_end_panel()
		match_over = true
		if lan_role == "host" and net != null and not _result_reported:
			_result_reported = true
			var winner := 0
			for brawler: Node2D in brawlers:
				if brawler.stocks > 0:
					winner = brawler.player_index
			net.report_result(winner)

func _update_camera(delta: float) -> void:
	var alive: Array = []
	for brawler: Node2D in brawlers:
		if brawler.alive:
			alive.append(brawler)
	if alive.is_empty():
		return
	var minimum: Vector2 = alive[0].position
	var maximum: Vector2 = alive[0].position
	for brawler: Node2D in alive:
		minimum = minimum.min(brawler.position)
		maximum = maximum.max(brawler.position)
	var centre: Vector2 = (minimum + maximum) * 0.5
	var spread: Vector2 = maximum - minimum
	var needed: Vector2 = Vector2(maxf(260.0, spread.x + 300.0), maxf(200.0, spread.y + 260.0))
	var zoom: float = clampf(minf(VIEW_W / needed.x, _play_height / needed.y), ZOOM_MIN, ZOOM_MAX)
	var blend := clampf(delta * 6.0, 0.0, 1.0)
	camera.position = camera.position.lerp(centre, blend)
	camera.zoom = camera.zoom.lerp(Vector2(zoom, zoom), blend)
	# Push the world into the upper band so the controls own the bottom strip.
	camera.offset = Vector2(0.0, -(VIEW_H - _play_height) * 0.5) if _touch else Vector2.ZERO
	if _background != null:
		# The backdrop is a world object drawn at 1:1, so it keeps its pixel size
		# while zoom changes; only the pan is damped for parallax.
		_background.position = Stage.BACKGROUND_ANCHOR + camera.position * (1.0 - Stage.PARALLAX)


func _update_hud() -> void:
	var text := ""
	for brawler: Node2D in brawlers:
		var gear := ""
		if String(brawler.item) != "":
			gear = "  [%s x%d]" % [ITEM_NAMES.get(String(brawler.item), String(brawler.item)), brawler.ammo]
		text += "P%d %s  血量 %d/%d  命 %d%s\n" % [brawler.player_index + 1,
			"存活" if brawler.alive else "出局", roundi(brawler.hp), roundi(brawler.MAX_HP),
			brawler.stocks, gear]
	# Text shaping is the most expensive thing the HUD does on a phone, so only
	# touch it when something actually changed.
	if text != _hud_text:
		_hud_text = text
		hud.text = text
	if match_over:
		var winner: Node2D = null
		for brawler: Node2D in brawlers:
			if brawler.stocks > 0:
				winner = brawler
		var where := "房间" if MatchConfig.is_lan() else "选人"
		status.text = "胜者：P%d　（按 F5 返回%s）" % [winner.player_index + 1, where] if winner != null else "平局"
	elif MatchConfig.is_lan():
		var role_text := "房主" if MatchConfig.lan_role == "host" else "客机"
		status.text = "联机 %s　第 %d 位　房号 %s　-　按 F5 离开" % [
			role_text, lan_slot + 1, MatchConfig.lan_code]
	else:
		status.text = "P1/P2 键盘　-　P3-P5 手柄　-　按 F5 重新选人"

## Winner screen: a rematch or a way back to the lobby, both big enough to tap.
func _show_end_panel() -> void:
	if _end_layer != null:
		return
	var winner: Node2D = null
	for brawler: Node2D in brawlers:
		if brawler.stocks > 0:
			winner = brawler

	var layer := CanvasLayer.new()
	layer.layer = 40
	get_tree().root.add_child(layer)
	_end_layer = layer

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.05, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(centre)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	centre.add_child(column)

	_end_title = Label.new()
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_title.add_theme_font_size_override("font_size", 34)
	_end_title.add_theme_color_override("font_color", Color("f2e9ff"))
	_end_title.text = _winner_text(winner)
	column.add_child(_end_title)

	var detail := Label.new()
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_theme_font_size_override("font_size", 16)
	detail.add_theme_color_override("font_color", Color("a99cc4"))
	detail.text = "联机对局" if MatchConfig.is_lan() else "本地对局"
	column.add_child(detail)

	var again := Button.new()
	again.text = "再战一局"
	again.custom_minimum_size = Vector2(240.0, 56.0)
	again.add_theme_font_size_override("font_size", 20)
	again.pressed.connect(_rematch)
	column.add_child(again)

	var back := Button.new()
	back.text = "返回大厅" if MatchConfig.is_lan() else "重新选人"
	back.custom_minimum_size = Vector2(240.0, 56.0)
	back.add_theme_font_size_override("font_size", 20)
	back.pressed.connect(_leave_match)
	column.add_child(back)

	if MatchConfig.is_lan() and MatchConfig.lan_role == "guest":
		var note := Label.new()
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.add_theme_font_size_override("font_size", 14)
		note.add_theme_color_override("font_color", Color("8f7fac"))
		note.text = "点「再战一局」会请房主重开"
		column.add_child(note)


func _winner_text(winner: Node2D) -> String:
	if winner == null:
		return "平局"
	var slot: int = winner.player_index
	var names := ["Yoru", "Nayu", "Hanami", "Kana", "Mosaki"]
	var character: String = names[slot % names.size()]
	if MatchConfig.characters.size() > slot:
		var path := String(MatchConfig.characters[slot])
		character = path.get_file().capitalize()
	return "P%d 获胜
%s" % [slot + 1, character]


func _hide_end_panel() -> void:
	if _end_layer == null:
		return
	_end_layer.queue_free()
	_end_layer = null
	_end_title = null


func _rematch() -> void:
	if lan_role == "guest":
		if net != null:
			net.send_data({"t": "rematch_req"})
		return
	if lan_role == "host" and net != null:
		net.send_data({"t": "rematch"})
	_hide_end_panel()
	get_tree().reload_current_scene()


func _leave_match() -> void:
	_hide_end_panel()
	if MatchConfig.is_lan():
		MatchConfig.clear_lan()
		get_tree().change_scene_to_file("res://scenes/lan.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/select.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if match_over and (event as InputEventKey).physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			_rematch()
			return
		if match_over and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			_leave_match()
			return
		if (event as InputEventKey).physical_keycode == KEY_F5:
			if MatchConfig.is_lan():
				MatchConfig.clear_lan()
				get_tree().change_scene_to_file("res://scenes/lan.tscn")
			else:
				get_tree().change_scene_to_file("res://scenes/select.tscn")

























