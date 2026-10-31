extends SceneTree
## Dev probe: holds walk and crouch, then prints what clip the brawler plays.

var _brawl: Node
var _frames := 0
var _fail := 0

func _initialize() -> void:
	change_scene_to_file("res://scenes/brawl.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 5:
		_brawl = current_scene
		Input.action_press("p1_right")
	if _frames in [20, 25, 30]:
		_report("walk")
	if _frames == 34:
		Input.action_release("p1_right")
		Input.action_press("p1_crouch")
	if _frames in [45, 50, 55]:
		_report("crouch")
	return false

func _report(tag: String) -> void:
	var player: Node2D = _brawl.brawlers[0]
	var sprite: AnimatedSprite2D = player._sprite
	print("%s f=%d x=%d clip=%s frame=%d vel=%d" % [tag, _frames, roundi(player.position.x), sprite.animation, sprite.frame, roundi(player.vel.x)])
