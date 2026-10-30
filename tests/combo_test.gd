extends SceneTree
## Combo / juggle rules: launchers, air hits, chaining and scaling.
##   godot --headless --path . --script tests/combo_test.gd

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

func swing(f: Node2D, kind: String) -> void:
	f.attack = kind
	f.attack_clock = 0.09
	f.hit_done = false

func _initialize() -> void:
	var attacker := fighter(200.0, 1)
	var target := fighter(250.0, -1)

	# Ground heavy is a launcher.
	swing(attacker, "attack-heavy")
	var hit := HitResolve.resolve(attacker, target)
	check(not hit.is_empty(), "heavy launcher connects")
	check(target.vy > 0.0 and not target.grounded, "heavy lifts the target off the ground")
	check(target.combo == 1, "first hit starts combo 1")
	target.step_fixed(DT, 0, false, false, 0.0, 640.0)
	check(target.height > 0.0, "launched target rises")
	check(attacker.attack == "", "attacker recovery is cancelled so the combo can continue")

	# The attacker can immediately throw the next hit and it counts as a combo.
	swing(attacker, "attack-light")
	var second := HitResolve.resolve(attacker, target)
	check(not second.is_empty(), "follow-up hits a target that is already in hitstun")
	check(target.combo == 2, "combo counter increments")
	check(float(second.stun) < 0.20, "later hits apply shorter hitstun (%.3f)" % float(second.stun))

	# Air hits keep the target airborne instead of dropping it.
	var jumper := fighter(200.0, 1)
	var victim := fighter(240.0, -1)
	jumper.height = 60.0
	jumper.grounded = false
	jumper.vy = 0.0
	victim.height = 70.0
	victim.grounded = false
	victim.vy = -400.0
	swing(jumper, "attack-light")
	var air_hit := HitResolve.resolve(jumper, victim)
	check(not air_hit.is_empty(), "air attack connects while both are airborne")
	check(float(air_hit.launch) >= 150.0, "air hit pops the target back up")
	check(victim.vy > 0.0, "falling target's velocity is reversed by the air hit")

	# Juggle scaling floors out and the combo is capped.
	victim.combo = HitResolve.MAX_COMBO - 1
	swing(jumper, "attack-heavy")
	var capped := HitResolve.resolve(jumper, victim)
	check(not capped.is_empty(), "hit still connects at the combo cap")
	check(victim.combo == HitResolve.MAX_COMBO, "combo never exceeds the cap")
	swing(jumper, "attack-heavy")
	var beyond := HitResolve.resolve(jumper, victim)
	check(beyond.is_empty() or victim.combo == HitResolve.MAX_COMBO, "combo stays capped")

	# Landing ends the combo.
	var landing := fighter(300.0, 1)
	landing.combo = 3
	landing.height = 2.0
	landing.grounded = false
	landing.vy = -20.0
	for step in range(30):
		landing.step_fixed(DT, 0, false, false, 0.0, 640.0)
	check(landing.grounded and landing.combo == 0, "landing resets the combo counter")

	# Combo expires when the window runs out.
	var idle_target := fighter(300.0, 1)
	idle_target.combo = 4
	idle_target.combo_clock = 1.0
	for step in range(70):
		idle_target.step_fixed(DT, 0, false, false, 0.0, 640.0)
	check(idle_target.combo == 0, "combo expires after the window")

	print("Combo checks: failures: %d" % failures)
	quit(0 if failures == 0 else 1)
