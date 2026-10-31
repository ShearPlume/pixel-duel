extends SceneTree
## One-shot bootstrap: writes the platform-brawler input map into project.godot.
## Run with:
##   godot --headless --path . --script tools/setup_input.gd

const LAYOUT := {
	"p1_left": [KEY_A],
	"p1_right": [KEY_D],
	"p1_jump": [KEY_W, KEY_SPACE],
	"p1_crouch": [KEY_S],
	"p1_light": [KEY_J],
	"p1_ranged": [KEY_K],
	"p1_flash": [KEY_L],
	"p1_special": [KEY_U],
	"p1_assist": [KEY_I],
	"p2_left": [KEY_LEFT],
	"p2_right": [KEY_RIGHT],
	"p2_jump": [KEY_UP, KEY_KP_0],
	"p2_crouch": [KEY_DOWN],
	"p2_light": [KEY_ENTER, KEY_KP_1],
	"p2_ranged": [KEY_KP_2],
	"p2_flash": [KEY_KP_3],
	"p2_special": [KEY_KP_4],
	"p2_assist": [KEY_KP_5],
}

const REMOVED := ["p1_heavy", "p1_kick", "p2_heavy", "p2_kick"]

## Players 3-5 are gamepad only: device 2/3/4 (0-based), same button layout.
const PAD_BUTTONS := {
	"jump": JOY_BUTTON_A,
	"light": JOY_BUTTON_X,
	"ranged": JOY_BUTTON_Y,
	"crouch": JOY_BUTTON_DPAD_DOWN,
	"left": JOY_BUTTON_DPAD_LEFT,
	"right": JOY_BUTTON_DPAD_RIGHT,
}
const PAD_MAX := 5

func _pad_events(action: String, device: int) -> Array:
	var events: Array = []
	if PAD_BUTTONS.has(action):
		var button := InputEventJoypadButton.new()
		button.device = device
		button.button_index = PAD_BUTTONS[action]
		events.append(button)
	if action in ["left", "right", "crouch"]:
		var motion := InputEventJoypadMotion.new()
		motion.device = device
		motion.axis = 0 if action != "crouch" else 1
		motion.axis_value = -1.0 if action == "left" else 1.0
		events.append(motion)
	return events

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
	for player in range(3, PAD_MAX + 1):
		for action: String in PAD_BUTTONS:
			var name := "p%d_%s" % [player, action]
			var events := _pad_events(action, player - 1)
			ProjectSettings.set_setting("input/" + name, {"deadzone": 0.5, "events": events})
			print("input/", name, " -> gamepad ", player - 1)
	var error := ProjectSettings.save()
	print("save result: ", error)
	quit(0 if error == OK else 1)
