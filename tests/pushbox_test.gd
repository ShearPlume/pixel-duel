extends SceneTree
## Body pushboxes and the air attack launcher.
##   godot --headless --path . --script tests/pushbox_test.gd

const Brawler = preload("res://scripts/brawl/brawler.gd")
const BrawlHit = preload("res://scripts/brawl/brawl_hit.gd")
const Pushbox = preload("res://scripts/brawl/pushbox.gd")

var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		print("FAIL: ", label)
		failures += 1

func _initialize() -> void:
	# Bodies separate when they overlap on roughly the same height.
	var overlap := Pushbox.separate(0.0, -40.0, 10.0, -40.0)
	check(overlap.size() == 2, "overlapping brawlers are separated")
	if overlap.size() == 2:
		check(absf(overlap[1] - overlap[0]) >= Pushbox.MIN_GAP - 0.001,
			"separated gap is at least a body width (%.1f)" % (overlap[1] - overlap[0]))
		check(overlap[0] < 0.0 and overlap[1] > 10.0, "both are pushed apart evenly")

	# Exact touch and clear gaps stay untouched.
	check(Pushbox.separate(0.0, -40.0, 28.0, -40.0).is_empty(), "touching bodies need no push")
	check(Pushbox.separate(0.0, -40.0, 60.0, -40.0).is_empty(), "apart bodies need no push")

	# One standing on a higher platform does not shove the one below.
	check(Pushbox.separate(0.0, 0.0, 10.0, -150.0).is_empty(), "different heights do not push")

	# Air attack launches nearly straight up.
	var attacker := Brawler.new()
	attacker.position = Vector2(0.0, -120.0)
	attacker.on_ground = false
	attacker.attack = "air"
	attacker.attack_clock = 0.09
	attacker.hit_done = false
	var target := Brawler.new()
	target.position = Vector2(30.0, -120.0)
	var result := BrawlHit.resolve(attacker, target)
	check(not result.is_empty(), "air attack connects")
	check(target.vel.y < 0.0, "air attack sends the target upward")
	check(absf(target.vel.y) > absf(target.vel.x) * 4.0, "air attack is close to vertical")
	check(target.hitstun > 0.0 and not target.on_ground, "target is popped up for a juggle")
	check(attacker.attack == "", "air attack can be followed up")

	# Repeat hits keep the target rising: vertical launch is re-applied.
	var before := target.vel.y
	target.hitstun = 0.0
	attacker.attack = "air"
	attacker.attack_clock = 0.09
	attacker.hit_done = false
	BrawlHit.resolve(attacker, target)
	check(target.vel.y <= before + 1.0, "a second air hit re-launches the target upward")

	print("Pushbox checks: failures: %d" % failures)
	quit(0 if failures == 0 else 1)
