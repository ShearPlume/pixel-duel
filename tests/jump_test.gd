extends SceneTree
## M0 regression: jump arc, single jump per press, crouch height.
##   godot --headless --path . --script tests/jump_test.gd

const Fighter = preload("res://scripts/fighter.gd")
const DT := 1.0 / 60.0

var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		print("FAIL: ", label)
		failures += 1

func spawn() -> Node2D:
	var fighter := Fighter.new()
	root.add_child(fighter)
	fighter.place(240.0, 300.0)
	return fighter

func _initialize() -> void:
	var fighter := spawn()
	var peak := 0.0
	var landed_at := -1
	fighter.step_fixed(DT, 0, true, false, 0.0, 640.0)
	check(fighter.height > 0.0 and not fighter.grounded, "press starts the jump")
	for frame in range(120):
		fighter.step_fixed(DT, 0, true, false, 0.0, 640.0)
		peak = maxf(peak, fighter.height)
		if fighter.grounded and landed_at < 0:
			landed_at = frame
	check(peak > 55.0 and peak < 66.0, "apex is about 60 px, got %.1f" % peak)
	check(landed_at >= 40 and landed_at <= 48, "airtime is about 0.73 s, landed at frame %d" % landed_at)
	check(fighter.grounded and fighter.height == 0.0, "holding jump through landing does not bunny hop")
	check(absf(fighter.position.y - 300.0) < 0.0001, "render keeps the fighter feet on the floor line")

	fighter.step_fixed(DT, 0, false, false, 0.0, 640.0)
	fighter.step_fixed(DT, 0, true, false, 0.0, 640.0)
	check(fighter.height > 0.0, "release then fresh press jumps again")

	var other := spawn()
	other.step_fixed(DT, 0, false, true, 0.0, 640.0)
	check(other.crouching and other.height == 0.0, "crouch stays grounded")
	other.step_fixed(DT, 0, true, true, 0.0, 640.0)
	check(not other.crouching and other.height > 0.0, "jump from crouch leaves the ground")

	print("Jump checks: failures: %d" % failures)
	quit(0 if failures == 0 else 1)
