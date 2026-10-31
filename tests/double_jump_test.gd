extends SceneTree
## Double jump at the character level. The `jump` field of a command means
## "a new press happened this tick"; holding must not produce extra jumps.
##   godot --headless --path . --script tests/double_jump_test.gd

const Brawler = preload("res://scripts/brawl/brawler.gd")
const Stage = preload("res://scripts/brawl/stage_data.gd")
const DT := 1.0 / 60.0

var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		print("FAIL: ", label)
		failures += 1

func grounded() -> Node2D:
	var b := Brawler.new()
	b.position = Vector2(0.0, -100.0)
	b.on_ground = false
	for index in range(40):
		b.step(DT, {}, Stage.PLATFORMS)
	return b

func _initialize() -> void:
	# Horizontal input must not interfere with either jump.
	for move in [0, -1, 1]:
		var b := grounded()
		b.step(DT, {"jump": true, "move": move}, Stage.PLATFORMS)
		check(b.vel.y < -500.0, "move %d: ground jump is full strength" % move)
		for index in range(6):
			b.step(DT, {"move": move}, Stage.PLATFORMS)
		b.step(DT, {"jump": true, "move": move}, Stage.PLATFORMS)
		check(b.jumps_left == 0, "move %d: second press consumes the air jump" % move)
		check(b.vel.y < -430.0, "move %d: second press re-launches upward (%.0f)" % [move, b.vel.y])

	# Holding does not produce a second jump: no new press is delivered.
	var holder := grounded()
	holder.step(DT, {"jump": true}, Stage.PLATFORMS)
	for index in range(10):
		holder.step(DT, {"move": 0}, Stage.PLATFORMS)
	check(holder.jumps_left == 1, "without a new press the air jump stays available")

	# A press after the air jump is already spent does nothing.
	holder.step(DT, {"jump": true}, Stage.PLATFORMS)
	check(holder.jumps_left == 0, "air jump is spent")
	var spent: float = holder.vel.y
	holder.step(DT, {"jump": true}, Stage.PLATFORMS)
	check(holder.vel.y > spent, "third press cannot launch again")

	print("Double jump checks: failures: %d" % failures)
	quit(0 if failures == 0 else 1)
