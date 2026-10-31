extends SceneTree
## Weapon feel: whole-body hit boxes, guitar cleave, cake contact detonation and
## bubble splash.   godot --headless --path . --script tests/weapon_test.gd

const Items = preload("res://scripts/brawl/items.gd")

var failures := 0
var brawl: Node2D

func check(ok: bool, label: String) -> void:
	if not ok:
		print("FAIL: ", label)
		failures += 1

func place(index: int, at: Vector2, facing: int = 1) -> Node2D:
	var brawler: Node2D = brawl.brawlers[index]
	brawler.spawn(at)
	brawler.invuln = 0.0
	brawler.on_ground = true
	brawler.facing = facing
	return brawler

func advance(ticks: int) -> void:
	for index in range(ticks):
		brawl._step_fixed()

func _initialize() -> void:
	brawl = (load("res://scenes/brawl.tscn") as PackedScene).instantiate()
	root.add_child(brawl)
	await process_frame
	brawl.spawn_players(3)
	await process_frame

	# Projectiles use the whole silhouette, not the torso centre.
	var body: Node2D = place(0, Vector2(0.0, 0.0))
	var box: Rect2 = body.body_rect()
	check(box.has_point(body.position + Vector2(0.0, -100.0)), "hit box covers the head")
	check(box.has_point(body.position + Vector2(0.0, -8.0)), "hit box covers the feet")
	check(box.has_point(body.position + Vector2(14.0, -50.0)), "hit box covers the side")
	check(not box.has_point(body.position + Vector2(0.0, 30.0)), "hit box stops above the floor")

	# The guitar cleaves everyone inside the arc on a single swing.
	var attacker: Node2D = place(0, Vector2(-200.0, 0.0), 1)
	var near: Node2D = place(1, Vector2(-150.0, 0.0), -1)
	var far: Node2D = place(2, Vector2(-130.0, 0.0), -1)
	var behind: Node2D = place(0, Vector2(-200.0, 0.0), 1)
	attacker.give_item("bat", 3)
	brawl._use_item(0)
	check(near.damage_percent > 0.0, "guitar hits the first target")
	check(far.damage_percent > 0.0, "guitar cleaves the second target")
	check(attacker.damage_percent == 0.0 and behind == attacker, "guitar leaves the swinger alone")

	# Cake explodes on contact, long before its fuse would run out.
	for index in range(3):
		var brawler: Node2D = place(index, Vector2(-200.0 + 120.0 * index, 0.0), -1)
		brawler.damage_percent = 0.0
	var thrower: Node2D = place(0, Vector2(-200.0, 0.0), 1)
	place(1, Vector2(-120.0, 0.0), -1)
	place(2, Vector2(-1000.0, 0.0), -1)
	thrower.give_item("grenade", 1)
	brawl._use_item(0)
	advance(20)
	var target: Node2D = brawl.brawlers[1]
	check(target.damage_percent > 0.0, "cake detonates on contact")
	check(brawl.bullets.is_empty(), "contact explosion removes the cake")

	# Bubble pop splashes a bystander standing in the burst.
	var pop_config: Dictionary = Items.config("cannon")
	var bystander: Node2D = place(2, Vector2(0.0, 0.0), -1)
	bystander.damage_percent = 0.0
	place(0, Vector2(-400.0, 0.0), 1)
	place(1, Vector2(-400.0, 0.0), 1)
	brawl._pop_bubble({"x": 20.0, "y": -50.0, "owner": 0, "config": pop_config})
	check(bystander.damage_percent > 0.0, "bubble burst damages a nearby fighter")

	print("Weapon checks: failures: %d" % failures)
	quit(0 if failures == 0 else 1)



