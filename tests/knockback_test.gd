extends SceneTree
## Knockback model + blast zone rules.
##   godot --headless --path . --script tests/knockback_test.gd

const Knockback = preload("res://scripts/brawl/knockback.gd")
const Brawler = preload("res://scripts/brawl/brawler.gd")
const BrawlHit = preload("res://scripts/brawl/brawl_hit.gd")

var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		print("FAIL: ", label)
		failures += 1

func brawler(at: Vector2, facing: int, index: int) -> Node2D:
	var b := Brawler.new()
	b.player_index = index
	b.facing = facing
	b.position = at
	return b

func _initialize() -> void:
	# Higher percent must mean more knockback.
	var low := Knockback.launch_speed(20.0, 140.0, 3.2)
	var high := Knockback.launch_speed(120.0, 140.0, 3.2)
	check(high > low * 1.8, "knockback grows with damage (%.0f -> %.0f)" % [low, high])
	check(Knockback.launch_speed(0.0, 140.0, 3.2) == 140.0, "base knockback applies at 0%")
	check(Knockback.hitstun_for(1500.0) <= 1.30, "hitstun is clamped")
	check(Knockback.hitstun_for(100.0) >= 0.18, "hitstun never drops to zero")

	# Launch direction follows the attacker's facing and goes upward.
	var right := Knockback.launch_velocity(500.0, 40.0, 1)
	var left := Knockback.launch_velocity(500.0, 40.0, -1)
	check(right.x > 0.0 and right.y < 0.0, "facing right launches up-right")
	check(left.x < 0.0 and left.y < 0.0, "facing left launches up-left")

	# Blast zone.
	check(not Knockback.outside_blast(Vector2(0.0, -100.0)), "stage is inside the blast zone")
	check(Knockback.outside_blast(Vector2(-900.0, 0.0)), "far left is KO")
	check(Knockback.outside_blast(Vector2(0.0, -1200.0)), "above the stage is KO")
	check(Knockback.outside_blast(Vector2(0.0, 500.0)), "below the stage is KO")

	# Hit application: damage accumulates, speed scales, hitstun locks control.
	var attacker := brawler(Vector2(0.0, -40.0), 1, 0)
	var target := brawler(Vector2(30.0, -40.0), -1, 1)
	attacker.attack = "attack-light"
	attacker.attack_clock = 0.08
	attacker.hit_done = false
	var first := BrawlHit.resolve(attacker, target)
	check(not first.is_empty(), "light attack connects")
	check(target.damage_percent == 4.0, "damage percent increases by the hit damage")
	check(target.vel.x > 0.0 and target.vel.y < 0.0, "target is launched away and up")
	check(target.hitstun > 0.0, "target is in hitstun")
	check(attacker.attack == "", "attacker can chain after a hit")

	# Same attack at high percent launches far harder.
	target.position = Vector2(30.0, -40.0)
	target.hitstun = 0.0
	target.damage_percent = 120.0
	var before: Vector2 = target.vel
	attacker.attack = "attack-light"
	attacker.attack_clock = 0.08
	attacker.hit_done = false
	BrawlHit.resolve(attacker, target)
	check(target.vel.length() > 400.0, "high percent produces a big launch (%.0f)" % target.vel.length())
	check(absf(target.vel.x) > absf(before.x) * 0.5, "launch replaces the previous velocity")

	# Invulnerable targets ignore everything.
	var fresh := brawler(Vector2(30.0, -40.0), -1, 1)
	fresh.invuln = 1.0
	attacker.attack = "attack-heavy"
	attacker.attack_clock = 0.10
	attacker.hit_done = false
	check(BrawlHit.resolve(attacker, fresh).is_empty(), "respawn invulnerability blocks hits")
	check(fresh.damage_percent == 0.0, "blocked hit deals no damage")

	print("Knockback checks: failures: %d" % failures)
	quit(0 if failures == 0 else 1)
