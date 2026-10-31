extends SceneTree
## Stage gimmicks: the map JSON drives colliders, conveyors, bounce pads and
## hazard zones.   godot --headless --path . --script tests/stage_test.gd

const Brawler = preload("res://scripts/brawl/brawler.gd")
const Stage = preload("res://scripts/brawl/stage_data.gd")
const ItemArt = preload("res://scripts/brawl/item_art.gd")

const DT := 1.0 / 60.0

var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		print("FAIL: ", label)
		failures += 1

func _initialize() -> void:
	check(Stage.PLATFORMS.size() >= 5, "map provides a full platform layout")
	check(Stage.SPAWNS.size() >= 5, "map provides five spawn points")
	check(Stage.BACKGROUND != "", "map provides a backdrop")
	check(Stage.PLATFORM_PIECES.size() == 3, "platform art has cap/middle/cap pieces")
	check(ResourceLoader.exists(Stage.BACKGROUND), "backdrop file exists")
	check(ResourceLoader.exists(Stage.PLATFORM_IMAGE), "platform sheet exists")
	check(Stage.BACKGROUND_ANCHOR != Vector2.ZERO, "backdrop has a placement anchor")

	# Item icons come from their own sheet, one cell per kind.
	check(ItemArt.available(), "item icon sheet loads")
	for kind: String in ["pistol", "bat", "grenade", "cannon"]:
		var icon: AtlasTexture = ItemArt.texture_for(kind)
		check(icon != null, "item icon exists for %s" % kind)
		if icon != null:
			check(icon.region.size == ItemArt.cell(), "item icon %s fills one cell" % kind)

	# Kind lookups: index 1 is the left conveyor in the shipped layout.
	var left := -1
	var pad := -1
	for index in range(Stage.PLATFORMS.size()):
		if String(Stage.KINDS[index]) == "conveyor" and left < 0:
			left = index
		if String(Stage.KINDS[index]) == "bouncer" and pad < 0:
			pad = index
	check(left >= 0, "a conveyor exists")
	check(pad >= 0, "a bounce pad exists")
	check(Stage.conveyor_speed(left) != 0.0, "conveyor has a belt speed")
	check(Stage.bounce_power(left) == 0.0, "a conveyor is not a bounce pad")
	check(Stage.bounce_power(pad) > 0.0, "bounce pad has launch power")
	check(Stage.conveyor_speed(-1) == 0.0, "no support means no belt")
	check(Stage.HAZARDS.size() > 0, "the map has hazard zones")
	check(Stage.hazard_dps(Stage.HAZARDS[0].get_center()) > 0.0, "hazard zone burns")
	check(Stage.hazard_dps(Vector2(0.0, -300.0)) == 0.0, "open air is safe")

	# Standing still on the belt must still drag the fighter.
	var belt: Rect2 = Stage.PLATFORMS[left]
	var speed := Stage.conveyor_speed(left)
	var b := Brawler.new()
	b.spawn(Vector2(belt.position.x + belt.size.x * 0.5, belt.position.y))
	b.on_ground = true
	b.ground_push = speed
	var start: float = b.position.x
	for index in range(30):
		b.ground_push = speed
		b.step(DT, {}, Stage.PLATFORMS)
	check((b.position.x - start) * signf(speed) > 20.0,
		"belt drags a idle fighter (%.1f px in 0.5 s)" % (b.position.x - start))

	# Someone standing on the pad gets launched upward.
	var pad_rect: Rect2 = Stage.PLATFORMS[pad]
	var jumper := Brawler.new()
	jumper.spawn(Vector2(pad_rect.position.x + pad_rect.size.x * 0.5, pad_rect.position.y))
	jumper.on_ground = true
	var power := Stage.bounce_power(pad)
	jumper.vel.y = -power
	check(jumper.vel.y < Brawler.JUMP_VELOCITY, "pad launch is stronger than a jump")
	for index in range(10):
		jumper.step(DT, {}, Stage.PLATFORMS)
	check(jumper.position.y < pad_rect.position.y - 40.0, "pad throws the fighter up")

	# Hazard damage never stuns, so a player can walk out of it.
	var burned := Brawler.new()
	burned.spawn(Vector2(0.0, -40.0))
	burned.invuln = 0.0
	burned.take_hazard_damage(12.0)
	check(is_equal_approx(burned.damage_percent, 12.0), "hazard raises the damage percent")
	check(burned.hitstun == 0.0, "hazard damage does not stun")
	burned.invuln = 0.5
	burned.take_hazard_damage(12.0)
	check(is_equal_approx(burned.damage_percent, 12.0), "invulnerability blocks hazard damage")

	print("Stage checks: failures: %d" % failures)
	quit(0 if failures == 0 else 1)
