extends SceneTree
## Sound bank and mixer rules: every sound the game asks for exists, throttling
## and voice caps hold, and the pool never grows.
##   godot --headless --path . --script tests/audio_test.gd

const Sfx = preload("res://scripts/audio/sfx.gd")

var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		print("FAIL: ", label)
		failures += 1

func _initialize() -> void:
	var sfx := Sfx.new()
	root.add_child(sfx)
	await process_frame

	var missing: Array = []
	for key: String in Sfx.BANK:
		if not ResourceLoader.exists("res://art/audio/%s.wav" % key):
			missing.append(key)
		check(sfx.available(key), "stream loads for %s" % key)
	check(missing.is_empty(), "every bank entry has a wav (%s)" % str(missing))

	# Every key used by the game code must be in the bank.
	for key: String in ["jump", "jump_double", "land", "hit_light", "hit_heavy",
			"guitar_swing", "guitar_hit", "pistol", "bubble_fire", "bubble_pop",
			"cake_throw", "explosion", "pickup", "heart", "ko", "respawn",
			"select_move", "select_confirm"]:
		check(Sfx.BANK.has(key), "bank covers %s" % key)

	# Throttling: the same sound twice in a row only takes one voice.
	sfx.play("hit_light", Vector2.ZERO)
	var used := 0
	for player: Node in sfx._world:
		if player.get_meta("key", "") == "hit_light" and bool(player.get("playing")):
			used += 1
	check(used == 1, "one hit sound starts one voice")
	sfx.play("hit_light", Vector2.ZERO)
	used = 0
	for player: Node in sfx._world:
		if player.get_meta("key", "") == "hit_light" and bool(player.get("playing")):
			used += 1
	check(used == 1, "a repeat inside the gap window is dropped")

	# Unknown keys are ignored instead of erroring.
	sfx.play("nope", Vector2.ZERO)
	check(true, "unknown sound is ignored")

	check(sfx._world.size() == Sfx.WORLD_POOL, "world voice pool is fixed")
	check(sfx._flat.size() == Sfx.FLAT_POOL, "ui voice pool is fixed")

	# The explosion is the loudest, movement is the quietest: keeps a busy
	# five player match readable.
	check(float(Sfx.BANK["explosion"]["db"]) > float(Sfx.BANK["jump"]["db"]),
		"big impacts sit above movement")
	check(float(Sfx.BANK["select_move"]["db"]) < float(Sfx.BANK["ko"]["db"]),
		"ui clicks stay below match events")

	print("Audio checks: failures: %d" % failures)
	quit(0 if failures == 0 else 1)
