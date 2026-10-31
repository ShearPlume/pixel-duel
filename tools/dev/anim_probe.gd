extends SceneTree
## Dev probe: advances the walk clip and prints the frame index.

const Atlas = preload("res://scripts/sprite_atlas.gd")

var _sprite: AnimatedSprite2D
var _frames := 0

func _initialize() -> void:
	var root := Node2D.new()
	get_root().add_child(root)
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = Atlas.load_atlas("res://art/yoru").frames
	root.add_child(_sprite)
	_sprite.play("walk")
	print("anims: ", _sprite.sprite_frames.get_animation_names())

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames % 6 == 0:
		print("frame=", _sprite.frame, " anim=", _sprite.animation, " speed=", _sprite.sprite_frames.get_animation_speed("walk"), " loop=", _sprite.sprite_frames.get_animation_loop("walk"))
	return _frames > 36
