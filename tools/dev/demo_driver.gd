extends Node
## Dev-only driver: spawns the brawl scene, hands out items and fires them so the
## visuals can be captured without touching the keyboard.
##   godot --path . scenes/demo.tscn --write-movie shots/f.png --quit-after 120

const BrawlScene = preload("res://scenes/brawl.tscn")

var brawl: Node2D
var _clock := 0.0
var _done := {}


func _ready() -> void:
	brawl = BrawlScene.instantiate()
	add_child(brawl)
	await get_tree().process_frame
	brawl.spawn_players(2)
	var left: Node2D = brawl.brawlers[0]
	var right: Node2D = brawl.brawlers[1]
	left.position = Vector2(-160.0, 0.0)
	left.on_ground = true
	left.facing = 1
	right.position = Vector2(60.0, 0.0)
	right.on_ground = true
	right.facing = -1
	left.give_item("bat", 6)
	right.give_item("cannon", 2)


func _process(delta: float) -> void:
	_clock += delta
	for moment in [0.6, 1.6, 2.6, 3.6]:
		var key := "at_%s" % moment
		if _clock >= moment and not _done.has(key):
			_done[key] = true
			_fire(moment)


func _fire(moment: float) -> void:
	var left: Node2D = brawl.brawlers[0]
	var right: Node2D = brawl.brawlers[1]
	match moment:
		0.6:
			brawl._use_item(0)
		1.6:
			brawl._use_item(1)
		2.6:
			left.give_item("pistol", 4)
			brawl._use_item(0)
		3.6:
			right.give_item("grenade", 2)
			brawl._use_item(1)
