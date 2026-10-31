extends SceneTree
## Pickup items: spawn data, pickup range, ammo and cooldown.
##   godot --headless --path . --script tests/item_test.gd

const Items = preload("res://scripts/brawl/items.gd")
const Brawler = preload("res://scripts/brawl/brawler.gd")

var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		print("FAIL: ", label)
		failures += 1

func _initialize() -> void:
	check(Items.has_item("pistol"), "pistol is registered")
	var pistol: Dictionary = Items.config("pistol")
	check(pistol.has_all(["damage", "speed", "kb_base", "kb_scale", "angle", "rounds"]),
		"pistol carries a full firing profile")
	check(int(pistol["rounds"]) > 0 and float(pistol["speed"]) > 0.0, "pistol has rounds and speed")

	# Pickup range.
	check(Items.can_pick_up("pistol", 0.0, -150.0, 10.0, -160.0), "stands close enough to grab it")
	check(not Items.can_pick_up("pistol", 0.0, -150.0, 200.0, -160.0), "far away cannot grab it")
	check(not Items.can_pick_up("pistol", 0.0, -150.0, 0.0, 200.0), "below a platform cannot grab it")
	check(not Items.can_pick_up("nope", 0.0, 0.0, 0.0, 0.0), "unknown item cannot be grabbed")

	# Every item carries the data its behaviour needs.
	check(Items.has_item("bat") and String(Items.config("bat")["type"]) == "melee", "bat is a melee item")
	check(Items.has_item("grenade") and String(Items.config("grenade")["type"]) == "grenade", "grenade throws")
	check(Items.has_item("cannon") and String(Items.config("cannon")["type"]) == "homing", "cannon homes")
	for kind: String in Items.kinds():
		var config: Dictionary = Items.config(kind)
		check(config.has_all(["type", "rounds", "cooldown", "damage", "kb_base", "kb_scale", "angle"]),
			"%s has a complete profile" % kind)

	# Ammo: the configured number of shots, then the item is gone.
	var brawler := Brawler.new()
	var rounds: int = int(pistol["rounds"])
	brawler.give_item("pistol", rounds)
	check(brawler.item == "pistol" and brawler.ammo == rounds, "picking up fills ammo")
	check(brawler.consume_ammo(), "first shot fires")
	check(brawler.ammo == rounds - 1, "one round is consumed")
	check(not brawler.consume_ammo(), "cannot fire again during the cooldown")
	for shot in range(rounds - 1):
		brawler.item_cooldown = 0.0
		check(brawler.consume_ammo(), "shot %d fires" % (shot + 2))
	check(brawler.ammo == 0 and brawler.item == "", "empty item is dropped")
	brawler.item_cooldown = 0.0
	check(not brawler.consume_ammo(), "empty hands cannot fire")

	# Respawn clears the item.
	brawler.give_item("pistol", 3)
	brawler.spawn(Vector2(0.0, -40.0))
	check(brawler.item == "" and brawler.ammo == 0, "respawn drops the item")

	# A pistol hit moves the target and adds percent.
	var shooter := Brawler.new()
	shooter.position = Vector2(0.0, -40.0)
	shooter.facing = 1
	var victim := Brawler.new()
	victim.position = Vector2(40.0, -40.0)
	var speed := victim.take_hit(float(pistol["damage"]), float(pistol["kb_base"]),
		float(pistol["kb_scale"]), float(pistol["angle"]), 1)
	check(victim.damage_percent == float(pistol["damage"]), "bullet adds its damage")
	check(speed > 0.0 and victim.vel.x > 0.0, "bullet pushes the target away")
	check(victim.hitstun > 0.0, "bullet applies hitstun")

	print("Item checks: failures: %d" % failures)
	quit(0 if failures == 0 else 1)
