extends SceneTree
## One-shot bootstrap: writes the BvN-style two-player input map into project.godot.
## Run with:
##   godot --headless --path . --script tools/setup_input.gd

const LAYOUT := {
	"p1_left": [KEY_A],
	"p1_right": [KEY_D],
	"p1_jump": [KEY_W, KEY_K],
	"p1_crouch": [KEY_S],
	"p1_light": [KEY_J],
	"p1_flash": [KEY_L],
	"p1_ranged": [KEY_U],
	"p1_special": [KEY_I],
	"p1_assist": [KEY_O],
	"p2_left": [KEY_LEFT],
	"p2_right": [KEY_RIGHT],
	"p2_jump": [KEY_UP, KEY_KP_2],
	"p2_crouch": [KEY_DOWN],
	"p2_light": [KEY_KP_1],
	"p2_flash": [KEY_KP_3],
	"p2_ranged": [KEY_KP_4],
	"p2_special": [KEY_KP_5],
	"p2_assist": [KEY_KP_6],
}

const REMOVED := ["p1_heavy", "p1_kick", "p2_heavy", "p2_kick"]

func _initialize() -> void:
	for stale: String in REMOVED:
		if ProjectSettings.has_setting("input/" + stale):
			ProjectSettings.set_setting("input/" + stale, null)
			print("input/", stale, " removed")
	for action: String in LAYOUT:
		var events: Array = []
		for key: int in LAYOUT[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			events.append(event)
		ProjectSettings.set_setting("input/" + action, {"deadzone": 0.5, "events": events})
		print("input/", action, " -> ", events.size(), " key(s)")
	var error := ProjectSettings.save()
	print("save result: ", error)
	quit(0 if error == OK else 1)
