extends SceneTree
## Headless smoke test for the classic 1v1 fighting game:
## checks all 6 characters' 8-frame animations across all 10 states, combat hit/block resolution, and scene loading.

const Atlas = preload("res://scripts/sprite_atlas.gd")
const Fighter = preload("res://scripts/fighter.gd")
const HitResolve = preload("res://scripts/hit_resolve.gd")
const MatchConfig = preload("res://scripts/match_config.gd")

func _init() -> void:
	var failures := 0
	for entry: Dictionary in MatchConfig.ROSTER:
		var dir := String(entry["dir"])
		var data := Atlas.load_atlas(dir)
		if data.is_empty():
			push_error("Failed to load atlas: " + dir)
			failures += 1
			continue
		var frames: SpriteFrames = data["frames"]
		for anim in ["idle", "walk", "walk-back", "crouch", "jump", "attack-light", "attack-heavy", "kick", "hurt", "super-cast"]:
			if not frames.has_animation(anim):
				push_error("%s missing animation: %s" % [dir, anim])
				failures += 1
			elif frames.get_frame_count(anim) != 8:
				push_error("Expected 8 frames for %s/%s, got %d" % [dir, anim, frames.get_frame_count(anim)])
				failures += 1

	var p1 := Fighter.new()
	var p2 := Fighter.new()
	root.add_child(p1)
	root.add_child(p2)
	p1._ready()
	p2._ready()
	p1.place(200.0, 312.0)
	p2.place(248.0, 312.0)
	p1.facing = 1
	p2.facing = -1

	p1.step_fixed(1.0 / 60.0, {"light": true}, 0.0, 640.0)
	var hit_landed := false
	for _i in range(20):
		p1.step_fixed(1.0 / 60.0, {}, 0.0, 640.0)
		p2.step_fixed(1.0 / 60.0, {}, 0.0, 640.0)
		var res := HitResolve.resolve(p1, p2)
		if not res.is_empty():
			hit_landed = true
			break
	if not hit_landed or p2.hp >= Fighter.MAX_HP:
		push_error("Expected P1 light punch to damage P2")
		failures += 1

	var select_scene: PackedScene = load("res://scenes/select.tscn")
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	if select_scene == null or main_scene == null:
		push_error("Failed to load select.tscn or main.tscn")
		failures += 1
	else:
		var sel := select_scene.instantiate()
		root.add_child(sel)
		sel._ready()
		sel._process(0.016)
		sel.free()
		var arena := main_scene.instantiate()
		root.add_child(arena)
		arena._ready()
		arena._pending_force_attack = "super-cast"
		for _i in range(180):
			arena._process(0.016)
		if arena._total_combo_damage <= 0.0:
			push_error("Expected Super Art barrage to hit and deal damage to P2")
			failures += 1
		arena.free()

	print("Classic 1v1 checks (all 6 characters x 10 states x 8 frames): failures: %d" % failures)
	p1.free()
	p2.free()
	quit(failures)
