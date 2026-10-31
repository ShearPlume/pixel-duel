extends SceneTree
## Dev probe: crouch, then jump, so a movie capture shows both clips.

var _frames := 0

func _initialize() -> void:
	change_scene_to_file("res://scenes/brawl.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 6:
		Input.action_press("p1_crouch")
	if _frames == 22:
		Input.action_release("p1_crouch")
		Input.action_press("p1_jump")
	if _frames == 24:
		Input.action_release("p1_jump")
	return false
