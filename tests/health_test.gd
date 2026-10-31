extends SceneTree
## Health, deaths and hearts: a fighter dies when HP runs out, not only when it
## leaves the blast zone, and hearts top it back up.
##   godot --headless --path . --script tests/health_test.gd

const Brawler = preload("res://scripts/brawl/brawler.gd")
const Items = preload("res://scripts/brawl/items.gd")

var failures := 0
var brawl: Node2D

func check(ok: bool, label: String) -> void:
	if not ok:
		print("FAIL: ", label)
		failures += 1

func _initialize() -> void:
	# Plain brawler: damage, healing and the ceiling.
	var b := Brawler.new()
	b.spawn(Vector2(0.0, 0.0))
	check(is_equal_approx(b.hp, Brawler.MAX_HP), "a fresh fighter starts at full health")
	b.invuln = 0.0
	b.take_hit(30.0, 100.0, 2.0, 40.0, 1)
	check(is_equal_approx(b.hp, Brawler.MAX_HP - 30.0), "a hit costs health as well as adding percent")
	check(is_equal_approx(b.damage_percent, 30.0), "percent still rises for knockback")
	b.invuln = 0.0
	var healed: float = b.heal(12.0)
	check(is_equal_approx(healed, 12.0), "heal returns the amount restored")
	b.heal(999.0)
	check(is_equal_approx(b.hp, Brawler.MAX_HP), "healing never overshoots max health")

	# Hazard burn drains health too, without stun.
	b.invuln = 0.0
	b.hitstun = 0.0
	b.take_hazard_damage(9.0)
	check(is_equal_approx(b.hp, Brawler.MAX_HP - 9.0), "hazard burn costs health")
	check(b.hitstun == 0.0, "hazard burn still does not stun")

	# In the real loop, zero health costs a stock and schedules a respawn.
	brawl = (load("res://scenes/brawl.tscn") as PackedScene).instantiate()
	root.add_child(brawl)
	await process_frame
	brawl.spawn_players(2)
	await process_frame
	var victim: Node2D = brawl.brawlers[0]
	victim.position = Vector2(-100.0, 0.0)
	victim.on_ground = true
	victim.invuln = 0.0
	victim.hp = 0.0
	var stocks_before: int = victim.stocks
	brawl._check_blast_zones()
	check(not victim.alive, "empty health knocks the fighter out")
	check(victim.stocks == stocks_before - 1, "empty health costs a stock")

	# A heart spawns on a safe platform and heals whoever touches it.
	brawl.hearts.clear()
	victim.spawn(Vector2(-100.0, 0.0))
	victim.invuln = 0.0
	victim.hp = 40.0
	brawl._spawn_heart()
	check(brawl.hearts.size() == 1, "a heart can spawn")
	var heart: Dictionary = brawl.hearts[0]
	heart.position = victim.body_rect().get_center()
	heart.node.position = heart.position
	brawl._update_hearts()
	check(victim.hp > 40.0, "walking into a heart heals")
	check(brawl.hearts.is_empty(), "a collected heart is removed")

	# Grenade keeps its wide blast, cannon splash stays smaller.
	var grenade: Dictionary = Items.config("grenade")
	var cannon: Dictionary = Items.config("cannon")
	check(float(grenade["radius"]) > float(cannon["pop_radius"]) * 2.0,
		"cake blast is far wider than the bubble splash")

	print("Health checks: failures: %d" % failures)
	quit(0 if failures == 0 else 1)

