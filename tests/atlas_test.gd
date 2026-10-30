extends SceneTree
## Smoke test: the atlas pipeline output can be loaded and sliced.
##   godot --headless --path . --script tests/atlas_test.gd

const Atlas = preload("res://scripts/sprite_atlas.gd")
const DIR := "res://art/placeholder/stickman"

var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		print("FAIL: ", label)
		failures += 1

func _initialize() -> void:
	var atlas := Atlas.load_atlas(DIR)
	check(not atlas.is_empty(), "atlas loads")
	if atlas.is_empty():
		print("Atlas checks: failures: 1")
		quit(1)
		return
	check(atlas.cell == Vector2(192.0, 208.0), "cell is 192x208")
	check(atlas.anchor == Vector2(96.0, 196.0), "feet anchor is the cell bottom centre")
	var frames: SpriteFrames = atlas.frames
	for name in ["idle", "walk", "walk-back", "crouch", "jump", "attack-light", "attack-heavy", "kick", "hurt"]:
		check(frames.has_animation(name), "animation %s exists" % name)
		check(frames.get_frame_count(name) > 0, "animation %s has frames" % name)
	check(frames.get_animation_loop("idle"), "idle loops")
	check(not frames.get_animation_loop("attack-light"), "attacks do not loop")
	check(frames.get_animation_speed("attack-light") > frames.get_animation_speed("idle"), "attacks play faster than idle")
	print("Atlas checks: failures: %d" % failures)
	quit(0 if failures == 0 else 1)
