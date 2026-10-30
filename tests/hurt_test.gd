extends SceneTree
## Placeholder hit windows + hurt reaction.
##   godot --headless --path . --script tests/hurt_test.gd

const Fighter = preload("res://scripts/fighter.gd")
const HitResolve = preload("res://scripts/hit_resolve.gd")

var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		print("FAIL: ", label)
		failures += 1

func fighter(at_x: float, facing: int) -> Node2D:
	var f := Fighter.new()
	f.facing = facing
	f.place(at_x, 300.0)
	return f

func attack(f: Node2D, kind: String, clock: float) -> void:
	f.attack = kind
	f.attack_clock = clock
	f.hit_done = false

func _initialize() -> void:
	var attacker := fighter(200.0, 1)
	var target := fighter(250.0, -1)

	attack(attacker, "attack-light", 0.0)
	check(HitResolve.resolve(attacker, target).is_empty(), "startup frame cannot hit")
	check(target.hurt_clock == 0.0, "no reaction during startup")

	attack(attacker, "attack-light", 0.08)
	check(not HitResolve.resolve(attacker, target).is_empty(), "active frame hits in range")
	check(target.hurt_clock > 0.0, "target plays hurt")
	check(target.attack == "", "target attack is interrupted")
	check(absf(target.x - 255.0) < 0.001, "target is pushed away from the attacker")
	check(HitResolve.resolve(attacker, target).is_empty(), "one hit per swing")

	var far_target := fighter(320.0, -1)
	attack(attacker, "kick", 0.09)
	check(HitResolve.resolve(attacker, far_target).is_empty(), "out of reach misses")

	var behind := fighter(150.0, -1)
	attack(attacker, "attack-heavy", 0.09)
	check(HitResolve.resolve(attacker, behind).is_empty(), "cannot hit behind the attacker")

	target.hurt_clock = 0.0
	attack(attacker, "kick", 0.09)
	check(not HitResolve.resolve(attacker, target).is_empty(), "kick hits again after recovery")
	target.step_fixed(1.0 / 60.0, 0, false, false, 0.0, 640.0)
	check(target.attack == "" and not target.crouching, "hurt blocks new actions")

	print("Hurt checks: failures: %d" % failures)
	quit(0 if failures == 0 else 1)
