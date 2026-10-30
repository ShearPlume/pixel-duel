extends SceneTree
## Section-1 moves: meter costs, dash i-frames, ranged flag, assist escape.
##   godot --headless --path . --script tests/ability_test.gd

const Fighter = preload("res://scripts/fighter.gd")
const HitResolve = preload("res://scripts/hit_resolve.gd")
const DT := 1.0 / 60.0

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

func tap(action: String, f: Node2D) -> void:
	Input.action_press(action)
	f.step_fixed(DT, 0, false, false, 0.0, 640.0)
	Input.action_release(action)
	f.step_fixed(DT, 0, false, false, 0.0, 640.0)

func _initialize() -> void:
	# 鏀炬嫑 I: costs 40 meter and becomes a powered heavy.
	var p1 := fighter(200.0, 1)
	tap("p1_special", p1)
	check(p1.attack == "attack-heavy" and p1.super_hit, "I starts the powered heavy")
	check(absf(p1.energy - 60.0) < 0.001, "I spends 40 meter, got %.0f" % p1.energy)

	# Not enough meter -> nothing happens.
	p1.energy = 10.0
	p1.attack = ""
	tap("p1_special", p1)
	check(p1.attack == "" and absf(p1.energy - 10.0) < 0.001, "I is rejected below the meter cost")

	# 杩滄敾 U: fires once and goes on cooldown.
	var p2 := fighter(300.0, 1)
	p2.energy = 0.0
	Input.action_press("p1_ranged")
	p2.step_fixed(DT, 0, false, false, 0.0, 640.0)
	Input.action_release("p1_ranged")
	check(p2.attack == "ranged", "U starts the ranged attack")
	var fired := false
	for step in range(6):
		p2.step_fixed(DT, 0, false, false, 0.0, 640.0)
		fired = fired or p2.wants_projectile
	check(fired, "ranged attack requests a projectile at the release frame")
	check(p2.ranged_cooldown > 0.0, "ranged attack goes on cooldown")
	p2.attack = ""
	p2.wants_projectile = false
	tap("p1_ranged", p2)
	check(p2.attack == "", "ranged attack cannot spam during cooldown")

	# 鐬 L: dash with i-frames and real displacement.
	var dasher := fighter(200.0, 1)
	var start_x: float = dasher.x
	tap("p1_flash", dasher)
	check(dasher.dash_clock > 0.0, "L starts a dash")
	check(dasher.invuln_clock > 0.0, "dash grants i-frames")
	for step in range(8):
		dasher.step_fixed(DT, 0, false, false, 0.0, 640.0)
	check(dasher.x > start_x + 40.0, "dash actually moves the fighter (%.1f -> %.1f)" % [start_x, dasher.x])

	# 鐏垫浛 O: escapes hitstun and costs 30 meter.
	var victim := fighter(300.0, 1)
	victim.hurt_clock = 0.30
	victim.energy = 100.0
	var before: float = victim.x
	tap("p1_assist", victim)
	check(victim.hurt_clock == 0.0, "O cancels hitstun")
	check(victim.invuln_clock >= 0.3, "O grants a long invulnerability window")
	check(absf(victim.energy - 70.0) < 0.001, "O spends 30 meter, got %.0f" % victim.energy)
	check(victim.x < before, "O steps the fighter backwards")

	# Invulnerable targets cannot be hit.
	var attacker := fighter(200.0, 1)
	var guarded := fighter(240.0, -1)
	guarded.invuln_clock = 0.2
	attacker.attack = "attack-light"
	attacker.attack_clock = 0.09
	attacker.hit_done = false
	check(HitResolve.resolve(attacker, guarded).is_empty(), "i-frames make the target untouchable")

	print("Ability checks: failures: %d" % failures)
	quit(0 if failures == 0 else 1)
