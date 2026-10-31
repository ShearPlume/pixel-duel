extends SceneTree
## Dev probe: holds walk and reports the clip over time.

var _brawl: Node
var _frames := 0

func _initialize() -> void:
	change_scene_to_file("res://scenes/brawl.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 5:
		_brawl = current_scene
		Input.action_press("p1_right")
	if _frames >= 20 and _frames % 6 == 0:
		var player: Node2D = _brawl.brawlers[0]
		var sprite: AnimatedSprite2D = player._sprite
		print("f=%d x=%d ground=%s clip=%s frame=%d vel=%d" % [_frames, roundi(player.position.x),
			player.on_ground, sprite.animation, sprite.frame, roundi(player.vel.x)])
	return _frames > 62
