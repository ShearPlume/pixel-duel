extends SceneTree
## Smoke test for the BvN-style input map.
##   godot --headless --path . --script tests/input_map_test.gd

const EXPECTED := {
	"p1_left": KEY_A, "p1_right": KEY_D, "p1_jump": KEY_K, "p1_crouch": KEY_S,
	"p1_light": KEY_J, "p1_flash": KEY_L, "p1_ranged": KEY_U,
	"p1_special": KEY_I, "p1_assist": KEY_O,
	"p2_left": KEY_LEFT, "p2_right": KEY_RIGHT, "p2_jump": KEY_KP_2, "p2_crouch": KEY_DOWN,
	"p2_light": KEY_KP_1, "p2_flash": KEY_KP_3, "p2_ranged": KEY_KP_4,
	"p2_special": KEY_KP_5, "p2_assist": KEY_KP_6,
}

var failures := 0

func _initialize() -> void:
	for action: String in EXPECTED:
		if not InputMap.has_action(action):
			print("FAIL: missing action ", action)
			failures += 1
			continue
		var found := false
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventKey and (event as InputEventKey).physical_keycode == EXPECTED[action]:
				found = true
		if not found:
			print("FAIL: ", action, " is not bound to ", OS.get_keycode_string(EXPECTED[action]))
			failures += 1
	print("Input map checks: %d; failures: %d" % [EXPECTED.size(), failures])
	quit(0 if failures == 0 else 1)
