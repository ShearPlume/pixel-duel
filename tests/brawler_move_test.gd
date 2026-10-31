extends SceneTree
## Platformer movement: run, double jump, fast fall, one-way platforms.
##   godot --headless --path . --script tests/brawler_move_test.gd

const Brawler = preload("res://scripts/brawl/brawler.gd")
const Stage = preload("res://scripts/brawl/stage_data.gd")
const DT := 1.0 / 60.0
## A plain fall from rest needs ~95 px/s per 5 frames; anything past this would
## mean the old instant fast-fall came back.
const FAST_FALL_LIMIT := 400.0

var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		print("FAIL: ", label)
		failures += 1

func make(at_x: float) -> Node2D:
	var b := Brawler.new()
	b.position = Vector2(at_x, -100.0)
	return b

func step(b: Node2D, frames: int, command: Dictionary = {}) -> void:
	for index in range(frames):
		b.step(DT, command, Stage.PLATFORMS)

func _initialize() -> void:
	# Falling lands on the floor and refills jumps.
	var a := make(0.0)
	step(a, 40)
	check(a.on_ground and absf(a.position.y) < 0.001, "fighter falls onto the main floor")
	check(a.jumps_left == Brawler.MAX_JUMPS, "landing refills double jump")

	# Ground jump then air jump, and no third jump.
	a.step(DT, {"jump": true}, Stage.PLATFORMS)
	check(a.vel.y < 0.0 and not a.on_ground, "ground jump leaves the floor")
	a.step(DT, {"jump": true}, Stage.PLATFORMS)
	check(a.jumps_left == 0, "air jump consumes the last jump")
	var before: float = a.vel.y
	a.step(DT, {"jump": true}, Stage.PLATFORMS)
	check(a.vel.y > before, "no triple jump: gravity keeps pulling")

	# Holding crouch in the air no longer speeds the fall up.
	var faller := make(0.0)
	step(faller, 4, {"fast_fall": true})
	check(faller.vel.y < FAST_FALL_LIMIT, "crouch in the air keeps a normal fall speed")
	check(not faller.on_ground, "crouch in the air does not teleport the fighter down")
	var normal := make(0.0)
	normal.on_ground = false
	var frames := 0
	while not normal.on_ground and frames < 60:
		normal.step(DT, {}, Stage.PLATFORMS)
		frames += 1
	check(frames > 0, "normal fall needs gravity frames")

	# One-way platform: rising through it does not snap to the top.
	var under := make(0.0)
	under.position = Vector2(0.0, -120.0)
	under.vel = Vector2(0.0, -600.0)
	for index in range(6):
		under.step(DT, {}, Stage.PLATFORMS)
	check(under.position.y < -150.0, "rising through a platform is not blocked (%.0f)" % under.position.y)

	# Walking off an edge starts a fall.
	var walker := make(0.0)
	step(walker, 40)
	var ground_y := walker.position.y
	step(walker, 40, {"move": 1})
	check(absf(walker.position.y - ground_y) < 0.001, "running along the floor stays on it")
	walker.position.x = 560.0
	step(walker, 20)
	check(walker.position.y > ground_y, "walking past the stage edge falls off")

	# Knockback removes ground control.
	var victim := make(0.0)
	step(victim, 40)
	victim.take_hit(10.0, 150.0, 3.5, 40.0, -1)
	check(victim.hitstun > 0.0 and not victim.on_ground, "taking a hit launches and stuns")
	var stun: float = victim.hitstun
	step(victim, 3, {"move": 1})
	check(victim.hitstun < stun, "hitstun ticks down")

	# Double jump must reach the first platform tier (170 px above the floor).
	var climber := make(-360.0)
	step(climber, 40)
	check(climber.on_ground, "climber starts on the floor")
	climber.step(DT, {"jump": true}, Stage.PLATFORMS)
	for index in range(18):
		climber.step(DT, {}, Stage.PLATFORMS)
	climber.step(DT, {"jump": true}, Stage.PLATFORMS)
	for index in range(60):
		climber.step(DT, {}, Stage.PLATFORMS)
	check(climber.on_ground and absf(climber.position.y + 170.0) < 1.0, "double jump lands on the left conveyor (y=%.0f)" % climber.position.y)

	# A single jump alone must not reach it.
	var single := make(-360.0)
	step(single, 40)
	single.step(DT, {"jump": true}, Stage.PLATFORMS)
	var peak: float = 0.0
	for index in range(60):
		single.step(DT, {}, Stage.PLATFORMS)
		peak = minf(peak, single.position.y)
	check(peak > -170.0, "single jump stays below the platform (peak %.0f)" % peak)

	print("Brawler movement checks: failures: %d" % failures)
	quit(0 if failures == 0 else 1)

